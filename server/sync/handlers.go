package main

import (
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"log"
	"net"
	"net/http"
	"net/url"
	"regexp"
	"strings"
	"sync"
	"time"
)

// 应用注册的回调 scheme：登录完成后浏览器跳到 openstats://auth/callback?code=…，由 ASWebAuthenticationSession 接住
const appCallback = "openstats://auth/callback"

// 设置文档上限：实际文档不到 2 KB，留足余量
const maxDocumentBytes = 64 << 10

var challengePattern = regexp.MustCompile(`^[A-Za-z0-9_-]{43}$`)

type Server struct {
	cfg     Config
	store   *Store
	mux     *http.ServeMux
	limiter *limiter
}

func NewServer(cfg Config, store *Store) *Server {
	s := &Server{cfg: cfg, store: store, mux: http.NewServeMux(), limiter: newLimiter(30, time.Minute)}
	s.mux.HandleFunc("GET /api/v1/health", func(w http.ResponseWriter, _ *http.Request) { writeJSON(w, 200, map[string]string{"status": "ok"}) })
	s.mux.HandleFunc("GET /api/v1/auth/providers", s.providers)
	s.mux.HandleFunc("GET /api/v1/auth/{provider}/start", s.limited(s.start))
	s.mux.HandleFunc("GET /api/v1/auth/{provider}/callback", s.limited(s.callback))
	s.mux.HandleFunc("POST /api/v1/auth/{provider}/callback", s.limited(s.callback))
	s.mux.HandleFunc("POST /api/v1/auth/exchange", s.limited(s.exchange))
	s.mux.HandleFunc("POST /api/v1/auth/logout", s.authed(s.logout))
	s.mux.HandleFunc("GET /api/v1/me", s.authed(s.me))
	s.mux.HandleFunc("GET /api/v1/settings", s.authed(s.getSettings))
	s.mux.HandleFunc("PUT /api/v1/settings", s.authed(s.putSettings))
	s.mux.HandleFunc("DELETE /api/v1/account", s.authed(s.deleteAccount))
	return s
}

func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	s.mux.ServeHTTP(w, r)
}

func (s *Server) redirectURI(provider string) string {
	return strings.TrimRight(s.cfg.BaseURL, "/") + "/api/v1/auth/" + provider + "/callback"
}

// MARK: 登录

func (s *Server) providers(w http.ResponseWriter, _ *http.Request) {
	names := []string{}
	for _, name := range []string{"github", "google", "apple"} {
		if _, ok := s.cfg.Providers[name]; ok {
			names = append(names, name)
		}
	}
	writeJSON(w, 200, map[string]any{"providers": names})
}

// start 记下应用生成的 PKCE challenge，把浏览器送去第三方授权页
func (s *Server) start(w http.ResponseWriter, r *http.Request) {
	provider, ok := s.cfg.Providers[r.PathValue("provider")]
	if !ok {
		writeError(w, 404, "不支持的登录方式")
		return
	}
	challenge := r.URL.Query().Get("challenge")
	if !challengePattern.MatchString(challenge) {
		writeError(w, 400, "缺少 challenge")
		return
	}
	state, err := s.store.CreateLogin(provider.Name(), challenge)
	if err != nil {
		s.fail(w, err)
		return
	}
	http.Redirect(w, r, provider.AuthURL(state, s.redirectURI(provider.Name())), http.StatusFound)
}

// callback 校验 state，用授权码换身份，签发一次性换取码交回应用
func (s *Server) callback(w http.ResponseWriter, r *http.Request) {
	provider, ok := s.cfg.Providers[r.PathValue("provider")]
	if !ok {
		writeError(w, 404, "不支持的登录方式")
		return
	}
	if err := r.ParseForm(); err != nil {
		writeError(w, 400, "参数不正确")
		return
	}
	form := r.Form
	login, err := s.store.TakeLogin(form.Get("state"))
	if err != nil || login.Provider != provider.Name() {
		s.backToApp(w, r, "", "登录已过期，请重试")
		return
	}
	if reason := form.Get("error"); reason != "" {
		if reason == "user_cancelled_authorize" || reason == "access_denied" {
			s.backToApp(w, r, "", "cancelled")
		} else {
			s.backToApp(w, r, "", reason)
		}
		return
	}
	code := form.Get("code")
	if code == "" {
		s.backToApp(w, r, "", "未收到授权码")
		return
	}
	identity, err := provider.Exchange(r.Context(), code, s.redirectURI(provider.Name()), form)
	if err != nil {
		log.Printf("%s 换取身份失败：%v", provider.Name(), err)
		s.backToApp(w, r, "", "登录失败，请重试")
		return
	}
	user, err := s.store.UpsertUser(identity)
	if err != nil {
		s.fail(w, err)
		return
	}
	exchange, err := s.store.CreateExchange(user.ID, login.Challenge)
	if err != nil {
		s.fail(w, err)
		return
	}
	s.backToApp(w, r, exchange, "")
}

func (s *Server) backToApp(w http.ResponseWriter, r *http.Request, code, errorText string) {
	q := url.Values{}
	if code != "" {
		q.Set("code", code)
	} else {
		q.Set("error", errorText)
	}
	http.Redirect(w, r, appCallback+"?"+q.Encode(), http.StatusFound)
}

// exchange 应用拿换取码与 PKCE verifier 换长期令牌
func (s *Server) exchange(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Code     string `json:"code"`
		Verifier string `json:"verifier"`
		Device   string `json:"device"`
	}
	if err := readJSON(r, &body, 4<<10); err != nil {
		writeError(w, 400, "参数不正确")
		return
	}
	ex, err := s.store.TakeExchange(body.Code)
	if err != nil {
		writeError(w, 400, "换取码无效或已过期")
		return
	}
	if pkceChallenge(body.Verifier) != ex.Challenge {
		writeError(w, 400, "verifier 不匹配")
		return
	}
	token, err := s.store.CreateSession(ex.UserID, clip(body.Device, 80))
	if err != nil {
		s.fail(w, err)
		return
	}
	user, err := s.store.GetUser(ex.UserID)
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, 200, map[string]any{"token": token, "user": user})
}

func pkceChallenge(verifier string) string {
	sum := sha256.Sum256([]byte(verifier))
	return base64.RawURLEncoding.EncodeToString(sum[:])
}

// MARK: 需要登录的接口

type contextKey int

const (
	userKey contextKey = iota
	tokenKey
)

func (s *Server) authed(next func(http.ResponseWriter, *http.Request, User, string)) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		header := r.Header.Get("Authorization")
		token, ok := strings.CutPrefix(header, "Bearer ")
		if !ok || token == "" {
			writeError(w, 401, "需要登录")
			return
		}
		user, err := s.store.UserForToken(token)
		if errors.Is(err, ErrNotFound) {
			writeError(w, 401, "登录已失效")
			return
		}
		if err != nil {
			s.fail(w, err)
			return
		}
		next(w, r, user, token)
	}
}

func (s *Server) me(w http.ResponseWriter, _ *http.Request, user User, _ string) {
	writeJSON(w, 200, user)
}

func (s *Server) logout(w http.ResponseWriter, _ *http.Request, _ User, token string) {
	if err := s.store.DeleteSession(token); err != nil {
		s.fail(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) deleteAccount(w http.ResponseWriter, _ *http.Request, user User, _ string) {
	if err := s.store.DeleteUser(user.ID); err != nil {
		s.fail(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) getSettings(w http.ResponseWriter, _ *http.Request, user User, _ string) {
	st, err := s.store.GetSettings(user.ID)
	if errors.Is(err, ErrNotFound) {
		writeError(w, 404, "还没有保存过设置")
		return
	}
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, 200, map[string]any{
		"version":   st.Version,
		"updatedAt": st.UpdatedAt.UTC().Format(time.RFC3339),
		"device":    st.Device,
		"document":  json.RawMessage(st.Document),
	})
}

func (s *Server) putSettings(w http.ResponseWriter, r *http.Request, user User, _ string) {
	var body struct {
		Document json.RawMessage `json:"document"`
		Device   string          `json:"device"`
	}
	if err := readJSON(r, &body, maxDocumentBytes); err != nil {
		writeError(w, 400, "参数不正确或文档过大")
		return
	}
	// 只接受 JSON 对象，原样保存，服务端不解释字段
	var object map[string]json.RawMessage
	if err := json.Unmarshal(body.Document, &object); err != nil || object == nil {
		writeError(w, 400, "document 必须是 JSON 对象")
		return
	}
	st, err := s.store.PutSettings(user.ID, body.Document, clip(body.Device, 80))
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, 200, map[string]any{"version": st.Version, "updatedAt": st.UpdatedAt.UTC().Format(time.RFC3339)})
}

// MARK: 工具

func (s *Server) fail(w http.ResponseWriter, err error) {
	log.Printf("内部错误：%v", err)
	writeError(w, 500, "服务器内部错误")
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func writeError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, map[string]string{"error": message})
}

func readJSON(r *http.Request, out any, limit int64) error {
	body, err := io.ReadAll(io.LimitReader(r.Body, limit+1))
	if err != nil {
		return err
	}
	if int64(len(body)) > limit {
		return errors.New("body too large")
	}
	return json.Unmarshal(body, out)
}

func clip(s string, max int) string {
	if len(s) > max {
		return s[:max]
	}
	return s
}

// limiter 是按来源 IP 的简单滑动窗口限流，只用在登录相关接口
type limiter struct {
	mu     sync.Mutex
	hits   map[string][]time.Time
	limit  int
	window time.Duration
}

func newLimiter(limit int, window time.Duration) *limiter {
	return &limiter{hits: map[string][]time.Time{}, limit: limit, window: window}
}

func (l *limiter) allow(key string) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	now := time.Now()
	recent := l.hits[key][:0]
	for _, t := range l.hits[key] {
		if now.Sub(t) < l.window {
			recent = append(recent, t)
		}
	}
	if len(recent) >= l.limit {
		l.hits[key] = recent
		return false
	}
	l.hits[key] = append(recent, now)
	if len(l.hits) > 10000 {
		// 极端情况下直接清空，避免无限增长
		l.hits = map[string][]time.Time{}
	}
	return true
}

func (s *Server) limited(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !s.limiter.allow(clientIP(r)) {
			writeError(w, 429, "请求过于频繁，请稍后再试")
			return
		}
		next(w, r)
	}
}

// clientIP 依次看 Cloudflare、反向代理头，最后才是连接地址
func clientIP(r *http.Request) string {
	if ip := r.Header.Get("CF-Connecting-IP"); ip != "" {
		return ip
	}
	if forwarded := r.Header.Get("X-Forwarded-For"); forwarded != "" {
		return strings.TrimSpace(strings.Split(forwarded, ",")[0])
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}
