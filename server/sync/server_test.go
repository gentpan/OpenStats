package main

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
)

// fakeProvider 不联网：把授权码当 subject 用
type fakeProvider struct{}

func (fakeProvider) Name() string { return "fake" }
func (fakeProvider) AuthURL(state, redirect string) string {
	return "https://example.com/authorize?state=" + state + "&redirect_uri=" + url.QueryEscape(redirect)
}
func (fakeProvider) Exchange(_ context.Context, code, _ string, form url.Values) (Identity, error) {
	return Identity{Provider: "fake", Subject: code, Email: code + "@example.com", EmailVerified: true, Name: form.Get("name")}, nil
}

func newTestServer(t *testing.T) *Server {
	t.Helper()
	store, err := OpenStore(t.TempDir() + "/sync.db")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { store.Close() })
	cfg := Config{BaseURL: "https://sync.test", Providers: map[string]Provider{"fake": fakeProvider{}}}
	return NewServer(cfg, store)
}

func do(t *testing.T, srv http.Handler, method, path, token string, body any) *httptest.ResponseRecorder {
	t.Helper()
	var reader *strings.Reader
	if body != nil {
		raw, _ := json.Marshal(body)
		reader = strings.NewReader(string(raw))
	} else {
		reader = strings.NewReader("")
	}
	req := httptest.NewRequest(method, path, reader)
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	return rec
}

// 完整走一遍：start → callback → exchange → 存取设置 → 退出
func TestLoginAndSettingsFlow(t *testing.T) {
	srv := newTestServer(t)
	verifier := "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
	challenge := "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"

	rec := do(t, srv, "GET", "/api/v1/auth/fake/start?challenge="+challenge, "", nil)
	if rec.Code != http.StatusFound {
		t.Fatalf("start 返回 %d：%s", rec.Code, rec.Body)
	}
	authorize, _ := url.Parse(rec.Header().Get("Location"))
	state := authorize.Query().Get("state")
	if state == "" || authorize.Query().Get("redirect_uri") != "https://sync.test/api/v1/auth/fake/callback" {
		t.Fatalf("授权地址不对：%s", authorize)
	}

	rec = do(t, srv, "GET", "/api/v1/auth/fake/callback?state="+state+"&code=alice", "", nil)
	if rec.Code != http.StatusFound {
		t.Fatalf("callback 返回 %d：%s", rec.Code, rec.Body)
	}
	back, _ := url.Parse(rec.Header().Get("Location"))
	if back.Scheme != "openstats" || back.Query().Get("code") == "" {
		t.Fatalf("没有跳回应用：%s", back)
	}
	// state 只能用一次
	if rec := do(t, srv, "GET", "/api/v1/auth/fake/callback?state="+state+"&code=alice", "", nil); !strings.Contains(rec.Header().Get("Location"), "error=") {
		t.Fatalf("重放 state 应该失败：%s", rec.Header().Get("Location"))
	}

	// verifier 错误
	rec = do(t, srv, "POST", "/api/v1/auth/exchange", "", map[string]string{"code": back.Query().Get("code"), "verifier": "wrong"})
	if rec.Code != 400 {
		t.Fatalf("错误的 verifier 应该被拒绝，得到 %d", rec.Code)
	}
	// 换取码被消耗后，正确的 verifier 也无法再用：重新走一遍
	rec = do(t, srv, "GET", "/api/v1/auth/fake/start?challenge="+challenge, "", nil)
	authorize, _ = url.Parse(rec.Header().Get("Location"))
	rec = do(t, srv, "GET", "/api/v1/auth/fake/callback?state="+authorize.Query().Get("state")+"&code=alice", "", nil)
	back, _ = url.Parse(rec.Header().Get("Location"))
	rec = do(t, srv, "POST", "/api/v1/auth/exchange", "", map[string]string{"code": back.Query().Get("code"), "verifier": verifier, "device": "MacBook"})
	if rec.Code != 200 {
		t.Fatalf("exchange 返回 %d：%s", rec.Code, rec.Body)
	}
	var session struct {
		Token string `json:"token"`
		User  User   `json:"user"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &session)
	if session.Token == "" || session.User.Email != "alice@example.com" || len(session.User.Providers) != 1 {
		t.Fatalf("会话不完整：%s", rec.Body)
	}

	if rec := do(t, srv, "GET", "/api/v1/settings", session.Token, nil); rec.Code != 404 {
		t.Fatalf("新用户应该没有设置，得到 %d", rec.Code)
	}
	rec = do(t, srv, "PUT", "/api/v1/settings", session.Token, map[string]any{"document": map[string]any{"refreshSeconds": 3}, "device": "MacBook"})
	if rec.Code != 200 {
		t.Fatalf("PUT 返回 %d：%s", rec.Code, rec.Body)
	}
	rec = do(t, srv, "PUT", "/api/v1/settings", session.Token, map[string]any{"document": map[string]any{"refreshSeconds": 5}})
	var receipt struct{ Version int64 }
	_ = json.Unmarshal(rec.Body.Bytes(), &receipt)
	if receipt.Version != 2 {
		t.Fatalf("第二次保存版本应为 2，得到 %d", receipt.Version)
	}
	rec = do(t, srv, "GET", "/api/v1/settings", session.Token, nil)
	var stored struct {
		Version  int64
		Document map[string]any
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &stored)
	if stored.Version != 2 || stored.Document["refreshSeconds"] != float64(5) {
		t.Fatalf("读回的设置不对：%s", rec.Body)
	}
	if rec := do(t, srv, "PUT", "/api/v1/settings", session.Token, map[string]any{"document": []int{1}}); rec.Code != 400 {
		t.Fatalf("数组文档应被拒绝，得到 %d", rec.Code)
	}

	// 同邮箱在另一种登录方式下登录，并入同一用户
	srv.cfg.Providers["other"] = otherProvider{}
	rec = do(t, srv, "GET", "/api/v1/auth/other/start?challenge="+challenge, "", nil)
	authorize, _ = url.Parse(rec.Header().Get("Location"))
	rec = do(t, srv, "GET", "/api/v1/auth/other/callback?state="+authorize.Query().Get("state")+"&code=alice", "", nil)
	back, _ = url.Parse(rec.Header().Get("Location"))
	rec = do(t, srv, "POST", "/api/v1/auth/exchange", "", map[string]string{"code": back.Query().Get("code"), "verifier": verifier})
	var second struct{ User User }
	_ = json.Unmarshal(rec.Body.Bytes(), &second)
	if second.User.ID != session.User.ID || len(second.User.Providers) != 2 {
		t.Fatalf("同邮箱应并入同一用户：%s", rec.Body)
	}

	if rec := do(t, srv, "POST", "/api/v1/auth/logout", session.Token, nil); rec.Code != 204 {
		t.Fatalf("logout 返回 %d", rec.Code)
	}
	if rec := do(t, srv, "GET", "/api/v1/me", session.Token, nil); rec.Code != 401 {
		t.Fatalf("退出后令牌应失效，得到 %d", rec.Code)
	}
}

type otherProvider struct{ fakeProvider }

func (otherProvider) Name() string { return "other" }
func (otherProvider) Exchange(_ context.Context, code, _ string, _ url.Values) (Identity, error) {
	return Identity{Provider: "other", Subject: "o-" + code, Email: code + "@example.com", EmailVerified: true}, nil
}

func TestDeleteAccountRemovesEverything(t *testing.T) {
	srv := newTestServer(t)
	user, err := srv.store.UpsertUser(Identity{Provider: "fake", Subject: "bob"})
	if err != nil {
		t.Fatal(err)
	}
	token, _ := srv.store.CreateSession(user.ID, "")
	_, _ = srv.store.PutSettings(user.ID, []byte(`{}`), "")
	if rec := do(t, srv, "DELETE", "/api/v1/account", token, nil); rec.Code != 204 {
		t.Fatalf("删除返回 %d", rec.Code)
	}
	if _, err := srv.store.GetUser(user.ID); err != ErrNotFound {
		t.Fatalf("用户应已删除：%v", err)
	}
	if _, err := srv.store.GetSettings(user.ID); err != ErrNotFound {
		t.Fatalf("设置应已删除：%v", err)
	}
}

func TestPKCE(t *testing.T) {
	// RFC 7636 附录 B 的示例
	if got := pkceChallenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"); got != "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM" {
		t.Fatalf("challenge 计算错误：%s", got)
	}
}

func TestAppleClientSecretIsES256(t *testing.T) {
	const pemKey = "-----BEGIN PRIVATE KEY-----\nMIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgevZzL1gdAFr88hb2\nOF/2NxApJCzGCEDdfSp6VQO30hyhRANCAAQRWz+jn65BtOMvdyHKcvjBeBSDZH2r\n1RTwjmYSi9R/zpBnuQ4EiMnCqfMPWiZqB4QdbAd0E7oH50VpuZ1P087G\n-----END PRIVATE KEY-----\n"
	p, err := NewApple("com.openstats.web", "TEAM123456", "KEY1234567", []byte(pemKey))
	if err != nil {
		t.Fatal(err)
	}
	secret, err := p.(*apple).clientSecret(timeNow())
	if err != nil {
		t.Fatal(err)
	}
	parts := strings.Split(secret, ".")
	if len(parts) != 3 {
		t.Fatalf("JWT 应有三段：%s", secret)
	}
	claims, err := parseIDToken(secret)
	if err != nil || claims.Issuer != "TEAM123456" || claims.Audience != "https://appleid.apple.com" || claims.Subject != "com.openstats.web" {
		t.Fatalf("声明不对：%+v %v", claims, err)
	}
}
