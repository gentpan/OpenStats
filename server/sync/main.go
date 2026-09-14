// OpenStats 账号与设置同步服务：GitHub / Google / Apple 登录，按用户保存一份设置文档。
//
// 部署在官网服务器上，由 Caddy 把 /api/ 反代到这里（见 install.sh）。配置全部来自环境变量：
//
//	SYNC_LISTEN            监听地址，默认 127.0.0.1:8787
//	SYNC_BASE_URL          对外地址，默认 https://getopenstats.com（回调地址由此拼出）
//	SYNC_DB                SQLite 文件路径，默认 ./sync.db
//	GITHUB_CLIENT_ID / GITHUB_CLIENT_SECRET
//	GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET
//	APPLE_CLIENT_ID        Services ID（例如 com.openstats.web）
//	APPLE_TEAM_ID / APPLE_KEY_ID / APPLE_PRIVATE_KEY_FILE（.p8 文件路径）
//
// 没有配置的登录方式不会出现在 /auth/providers 里，应用据此隐藏对应按钮。
package main

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

func main() {
	cfg, err := loadConfig()
	if err != nil {
		log.Fatalf("配置错误：%v", err)
	}
	store, err := OpenStore(cfg.DBPath)
	if err != nil {
		log.Fatalf("打开数据库失败：%v", err)
	}
	defer store.Close()

	srv := NewServer(cfg, store)
	httpServer := &http.Server{
		Addr:              cfg.Listen,
		Handler:           srv,
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	go store.Housekeeping(ctx)

	go func() {
		<-ctx.Done()
		shutdown, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		_ = httpServer.Shutdown(shutdown)
	}()

	names := make([]string, 0, len(cfg.Providers))
	for name := range cfg.Providers {
		names = append(names, name)
	}
	log.Printf("openstats-sync 监听 %s，登录方式：%v", cfg.Listen, names)
	if err := httpServer.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatalf("服务退出：%v", err)
	}
}

// Config 来自环境变量
type Config struct {
	Listen    string
	BaseURL   string
	DBPath    string
	Providers map[string]Provider
}

func loadConfig() (Config, error) {
	cfg := Config{
		Listen:    env("SYNC_LISTEN", "127.0.0.1:8787"),
		BaseURL:   env("SYNC_BASE_URL", "https://getopenstats.com"),
		DBPath:    env("SYNC_DB", "sync.db"),
		Providers: map[string]Provider{},
	}
	if id, secret := os.Getenv("GITHUB_CLIENT_ID"), os.Getenv("GITHUB_CLIENT_SECRET"); id != "" && secret != "" {
		cfg.Providers["github"] = NewGitHub(id, secret)
	}
	if id, secret := os.Getenv("GOOGLE_CLIENT_ID"), os.Getenv("GOOGLE_CLIENT_SECRET"); id != "" && secret != "" {
		cfg.Providers["google"] = NewGoogle(id, secret)
	}
	if id := os.Getenv("APPLE_CLIENT_ID"); id != "" {
		keyFile := os.Getenv("APPLE_PRIVATE_KEY_FILE")
		pem, err := os.ReadFile(keyFile)
		if err != nil {
			return cfg, errors.New("APPLE_PRIVATE_KEY_FILE 无法读取：" + err.Error())
		}
		apple, err := NewApple(id, os.Getenv("APPLE_TEAM_ID"), os.Getenv("APPLE_KEY_ID"), pem)
		if err != nil {
			return cfg, err
		}
		cfg.Providers["apple"] = apple
	}
	if len(cfg.Providers) == 0 {
		log.Printf("警告：没有配置任何登录方式，登录接口会返回 404")
	}
	return cfg, nil
}

func env(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}
