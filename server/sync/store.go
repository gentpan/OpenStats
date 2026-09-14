package main

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"log"
	"time"

	_ "modernc.org/sqlite"
)

// Store 是 SQLite 上的一层薄封装。每个用户一份设置文档，整份覆盖，版本号递增。
type Store struct {
	db *sql.DB
}

type User struct {
	ID        string   `json:"id"`
	Email     string   `json:"email,omitempty"`
	Name      string   `json:"name,omitempty"`
	Avatar    string   `json:"avatar,omitempty"`
	Providers []string `json:"providers"`
}

type Login struct {
	State     string
	Provider  string
	Challenge string
	CreatedAt time.Time
}

type Exchange struct {
	Code      string
	UserID    string
	Challenge string
	CreatedAt time.Time
}

type Settings struct {
	Version   int64
	Document  []byte
	Device    string
	UpdatedAt time.Time
}

var ErrNotFound = errors.New("not found")

const schema = `
CREATE TABLE IF NOT EXISTS users (
	id TEXT PRIMARY KEY,
	email TEXT,
	name TEXT,
	avatar TEXT,
	created_at INTEGER NOT NULL,
	last_seen_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS users_email ON users(email);
CREATE TABLE IF NOT EXISTS accounts (
	provider TEXT NOT NULL,
	subject TEXT NOT NULL,
	user_id TEXT NOT NULL,
	email TEXT,
	PRIMARY KEY (provider, subject)
);
CREATE INDEX IF NOT EXISTS accounts_user ON accounts(user_id);
CREATE TABLE IF NOT EXISTS logins (
	state TEXT PRIMARY KEY,
	provider TEXT NOT NULL,
	challenge TEXT NOT NULL,
	created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS exchanges (
	code TEXT PRIMARY KEY,
	user_id TEXT NOT NULL,
	challenge TEXT NOT NULL,
	created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS sessions (
	token_hash TEXT PRIMARY KEY,
	user_id TEXT NOT NULL,
	device TEXT,
	created_at INTEGER NOT NULL,
	last_used_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS sessions_user ON sessions(user_id);
CREATE TABLE IF NOT EXISTS settings (
	user_id TEXT PRIMARY KEY,
	version INTEGER NOT NULL,
	document TEXT NOT NULL,
	device TEXT,
	updated_at INTEGER NOT NULL
);
`

func OpenStore(path string) (*Store, error) {
	db, err := sql.Open("sqlite", path+"?_pragma=journal_mode(WAL)&_pragma=busy_timeout(5000)&_pragma=foreign_keys(ON)")
	if err != nil {
		return nil, err
	}
	// 纯 Go 的 SQLite 驱动在多个连接间共享内存库会出问题，单连接足够应付这里的流量
	db.SetMaxOpenConns(1)
	if _, err := db.Exec(schema); err != nil {
		db.Close()
		return nil, err
	}
	return &Store{db: db}, nil
}

func (s *Store) Close() error { return s.db.Close() }

// Housekeeping 每小时清掉过期的登录状态与一次性换取码
func (s *Store) Housekeeping(ctx context.Context) {
	ticker := time.NewTicker(time.Hour)
	defer ticker.Stop()
	for {
		s.expire()
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}

func (s *Store) expire() {
	cutoff := time.Now().Add(-15 * time.Minute).Unix()
	if _, err := s.db.Exec(`DELETE FROM logins WHERE created_at < ?`, cutoff); err != nil {
		log.Printf("清理 logins 失败：%v", err)
	}
	if _, err := s.db.Exec(`DELETE FROM exchanges WHERE created_at < ?`, cutoff); err != nil {
		log.Printf("清理 exchanges 失败：%v", err)
	}
}

// MARK: 登录流程

func (s *Store) CreateLogin(provider, challenge string) (string, error) {
	state := randomToken(24)
	_, err := s.db.Exec(`INSERT INTO logins(state, provider, challenge, created_at) VALUES(?,?,?,?)`,
		state, provider, challenge, time.Now().Unix())
	return state, err
}

// TakeLogin 取出并删除登录状态；不存在或超过 10 分钟返回 ErrNotFound
func (s *Store) TakeLogin(state string) (Login, error) {
	var login Login
	var created int64
	err := s.db.QueryRow(`DELETE FROM logins WHERE state = ? RETURNING state, provider, challenge, created_at`, state).
		Scan(&login.State, &login.Provider, &login.Challenge, &created)
	if errors.Is(err, sql.ErrNoRows) {
		return login, ErrNotFound
	}
	if err != nil {
		return login, err
	}
	login.CreatedAt = time.Unix(created, 0)
	if time.Since(login.CreatedAt) > 10*time.Minute {
		return login, ErrNotFound
	}
	return login, nil
}

func (s *Store) CreateExchange(userID, challenge string) (string, error) {
	code := randomToken(24)
	_, err := s.db.Exec(`INSERT INTO exchanges(code, user_id, challenge, created_at) VALUES(?,?,?,?)`,
		code, userID, challenge, time.Now().Unix())
	return code, err
}

func (s *Store) TakeExchange(code string) (Exchange, error) {
	var ex Exchange
	var created int64
	err := s.db.QueryRow(`DELETE FROM exchanges WHERE code = ? RETURNING code, user_id, challenge, created_at`, code).
		Scan(&ex.Code, &ex.UserID, &ex.Challenge, &created)
	if errors.Is(err, sql.ErrNoRows) {
		return ex, ErrNotFound
	}
	if err != nil {
		return ex, err
	}
	ex.CreatedAt = time.Unix(created, 0)
	if time.Since(ex.CreatedAt) > 5*time.Minute {
		return ex, ErrNotFound
	}
	return ex, nil
}

// MARK: 用户

// UpsertUser 按 (provider, subject) 找用户；找不到时，已验证的邮箱与现有用户相同就并入，否则新建
func (s *Store) UpsertUser(id Identity) (User, error) {
	tx, err := s.db.Begin()
	if err != nil {
		return User{}, err
	}
	defer tx.Rollback()

	now := time.Now().Unix()
	var userID string
	err = tx.QueryRow(`SELECT user_id FROM accounts WHERE provider = ? AND subject = ?`, id.Provider, id.Subject).Scan(&userID)
	switch {
	case errors.Is(err, sql.ErrNoRows):
		if id.Email != "" && id.EmailVerified {
			err = tx.QueryRow(`SELECT id FROM users WHERE email = ? LIMIT 1`, id.Email).Scan(&userID)
			if err != nil && !errors.Is(err, sql.ErrNoRows) {
				return User{}, err
			}
		}
		if userID == "" {
			userID = randomToken(12)
			if _, err := tx.Exec(`INSERT INTO users(id, email, name, avatar, created_at, last_seen_at) VALUES(?,?,?,?,?,?)`,
				userID, id.Email, id.Name, id.Avatar, now, now); err != nil {
				return User{}, err
			}
		}
		if _, err := tx.Exec(`INSERT INTO accounts(provider, subject, user_id, email) VALUES(?,?,?,?)`,
			id.Provider, id.Subject, userID, id.Email); err != nil {
			return User{}, err
		}
	case err != nil:
		return User{}, err
	}

	// 用最近一次登录拿到的资料补全空缺，不覆盖已有的
	if _, err := tx.Exec(`UPDATE users SET
			email = CASE WHEN email IS NULL OR email = '' THEN ? ELSE email END,
			name = CASE WHEN name IS NULL OR name = '' THEN ? ELSE name END,
			avatar = CASE WHEN ? != '' THEN ? ELSE avatar END,
			last_seen_at = ?
		WHERE id = ?`, id.Email, id.Name, id.Avatar, id.Avatar, now, userID); err != nil {
		return User{}, err
	}
	if err := tx.Commit(); err != nil {
		return User{}, err
	}
	return s.GetUser(userID)
}

func (s *Store) GetUser(id string) (User, error) {
	var u User
	var email, name, avatar sql.NullString
	err := s.db.QueryRow(`SELECT id, email, name, avatar FROM users WHERE id = ?`, id).Scan(&u.ID, &email, &name, &avatar)
	if errors.Is(err, sql.ErrNoRows) {
		return u, ErrNotFound
	}
	if err != nil {
		return u, err
	}
	u.Email, u.Name, u.Avatar = email.String, name.String, avatar.String
	rows, err := s.db.Query(`SELECT provider FROM accounts WHERE user_id = ? ORDER BY provider`, id)
	if err != nil {
		return u, err
	}
	defer rows.Close()
	u.Providers = []string{}
	for rows.Next() {
		var p string
		if err := rows.Scan(&p); err != nil {
			return u, err
		}
		u.Providers = append(u.Providers, p)
	}
	return u, rows.Err()
}

func (s *Store) DeleteUser(id string) error {
	tx, err := s.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	for _, q := range []string{
		`DELETE FROM settings WHERE user_id = ?`,
		`DELETE FROM sessions WHERE user_id = ?`,
		`DELETE FROM exchanges WHERE user_id = ?`,
		`DELETE FROM accounts WHERE user_id = ?`,
		`DELETE FROM users WHERE id = ?`,
	} {
		if _, err := tx.Exec(q, id); err != nil {
			return err
		}
	}
	return tx.Commit()
}

// MARK: 会话

// CreateSession 返回明文令牌；库里只存 SHA-256
func (s *Store) CreateSession(userID, device string) (string, error) {
	token := randomToken(32)
	now := time.Now().Unix()
	_, err := s.db.Exec(`INSERT INTO sessions(token_hash, user_id, device, created_at, last_used_at) VALUES(?,?,?,?,?)`,
		hashToken(token), userID, device, now, now)
	return token, err
}

func (s *Store) UserForToken(token string) (User, error) {
	var userID string
	var lastUsed int64
	err := s.db.QueryRow(`SELECT user_id, last_used_at FROM sessions WHERE token_hash = ?`, hashToken(token)).Scan(&userID, &lastUsed)
	if errors.Is(err, sql.ErrNoRows) {
		return User{}, ErrNotFound
	}
	if err != nil {
		return User{}, err
	}
	// 最近使用时间每小时至多写一次
	if now := time.Now().Unix(); now-lastUsed > 3600 {
		_, _ = s.db.Exec(`UPDATE sessions SET last_used_at = ? WHERE token_hash = ?`, now, hashToken(token))
	}
	return s.GetUser(userID)
}

func (s *Store) DeleteSession(token string) error {
	_, err := s.db.Exec(`DELETE FROM sessions WHERE token_hash = ?`, hashToken(token))
	return err
}

// MARK: 设置

func (s *Store) GetSettings(userID string) (Settings, error) {
	var st Settings
	var doc string
	var device sql.NullString
	var updated int64
	err := s.db.QueryRow(`SELECT version, document, device, updated_at FROM settings WHERE user_id = ?`, userID).
		Scan(&st.Version, &doc, &device, &updated)
	if errors.Is(err, sql.ErrNoRows) {
		return st, ErrNotFound
	}
	if err != nil {
		return st, err
	}
	st.Document = []byte(doc)
	st.Device = device.String
	st.UpdatedAt = time.Unix(updated, 0)
	return st, nil
}

// PutSettings 整份覆盖，版本号加一
func (s *Store) PutSettings(userID string, document []byte, device string) (Settings, error) {
	now := time.Now().Unix()
	var version int64
	err := s.db.QueryRow(`INSERT INTO settings(user_id, version, document, device, updated_at) VALUES(?,1,?,?,?)
		ON CONFLICT(user_id) DO UPDATE SET version = version + 1, document = excluded.document,
			device = excluded.device, updated_at = excluded.updated_at
		RETURNING version`, userID, string(document), device, now).Scan(&version)
	if err != nil {
		return Settings{}, err
	}
	return Settings{Version: version, Document: document, Device: device, UpdatedAt: time.Unix(now, 0)}, nil
}

// MARK: 工具

func randomToken(bytes int) string {
	buf := make([]byte, bytes)
	if _, err := rand.Read(buf); err != nil {
		panic(err)
	}
	return base64.RawURLEncoding.EncodeToString(buf)
}

func hashToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}
