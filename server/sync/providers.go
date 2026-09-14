package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

// Identity 是第三方登录返回的身份：同一 provider 下 subject 唯一
type Identity struct {
	Provider      string
	Subject       string
	Email         string
	EmailVerified bool
	Name          string
	Avatar        string
}

// Provider 封装一种登录方式：生成授权地址、用授权码换身份
type Provider interface {
	Name() string
	AuthURL(state, redirectURI string) string
	// form 是回调请求的全部参数；Apple 首次登录时在 user 字段里带姓名
	Exchange(ctx context.Context, code, redirectURI string, form url.Values) (Identity, error)
}

var httpClient = &http.Client{Timeout: 15 * time.Second}

// postForm 向令牌端点提交表单并解析 JSON
func postForm(ctx context.Context, endpoint string, form url.Values, out any) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, strings.NewReader(form.Encode()))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("Accept", "application/json")
	req.Header.Set("User-Agent", "openstats-sync")
	resp, err := httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return err
	}
	if resp.StatusCode/100 != 2 {
		return fmt.Errorf("%s 返回 %d：%s", endpoint, resp.StatusCode, trim(body))
	}
	return json.Unmarshal(body, out)
}

func getJSON(ctx context.Context, endpoint, bearer string, out any) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+bearer)
	req.Header.Set("Accept", "application/json")
	req.Header.Set("User-Agent", "openstats-sync")
	resp, err := httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return err
	}
	if resp.StatusCode/100 != 2 {
		return fmt.Errorf("%s 返回 %d：%s", endpoint, resp.StatusCode, trim(body))
	}
	return json.Unmarshal(body, out)
}

func trim(body []byte) string {
	s := strings.TrimSpace(string(body))
	if len(s) > 200 {
		s = s[:200] + "…"
	}
	return s
}

// MARK: GitHub

type gitHub struct{ id, secret string }

func NewGitHub(id, secret string) Provider { return &gitHub{id: id, secret: secret} }

func (g *gitHub) Name() string { return "github" }

func (g *gitHub) AuthURL(state, redirectURI string) string {
	q := url.Values{
		"client_id":    {g.id},
		"redirect_uri": {redirectURI},
		"scope":        {"read:user user:email"},
		"state":        {state},
	}
	return "https://github.com/login/oauth/authorize?" + q.Encode()
}

func (g *gitHub) Exchange(ctx context.Context, code, redirectURI string, _ url.Values) (Identity, error) {
	var token struct {
		AccessToken string `json:"access_token"`
		Error       string `json:"error_description"`
	}
	if err := postForm(ctx, "https://github.com/login/oauth/access_token", url.Values{
		"client_id": {g.id}, "client_secret": {g.secret}, "code": {code}, "redirect_uri": {redirectURI},
	}, &token); err != nil {
		return Identity{}, err
	}
	if token.AccessToken == "" {
		return Identity{}, errors.New("GitHub 未返回令牌：" + token.Error)
	}
	var user struct {
		ID     int64  `json:"id"`
		Login  string `json:"login"`
		Name   string `json:"name"`
		Avatar string `json:"avatar_url"`
	}
	if err := getJSON(ctx, "https://api.github.com/user", token.AccessToken, &user); err != nil {
		return Identity{}, err
	}
	identity := Identity{Provider: "github", Subject: strconv.FormatInt(user.ID, 10), Name: user.Name, Avatar: user.Avatar}
	if identity.Name == "" {
		identity.Name = user.Login
	}
	var emails []struct {
		Email    string `json:"email"`
		Primary  bool   `json:"primary"`
		Verified bool   `json:"verified"`
	}
	if err := getJSON(ctx, "https://api.github.com/user/emails", token.AccessToken, &emails); err == nil {
		for _, e := range emails {
			if e.Primary && e.Verified {
				identity.Email, identity.EmailVerified = e.Email, true
				break
			}
		}
	}
	return identity, nil
}

// MARK: Google

type google struct{ id, secret string }

func NewGoogle(id, secret string) Provider { return &google{id: id, secret: secret} }

func (g *google) Name() string { return "google" }

func (g *google) AuthURL(state, redirectURI string) string {
	q := url.Values{
		"client_id":     {g.id},
		"redirect_uri":  {redirectURI},
		"response_type": {"code"},
		"scope":         {"openid email profile"},
		"state":         {state},
		"prompt":        {"select_account"},
	}
	return "https://accounts.google.com/o/oauth2/v2/auth?" + q.Encode()
}

func (g *google) Exchange(ctx context.Context, code, redirectURI string, _ url.Values) (Identity, error) {
	var token struct {
		AccessToken string `json:"access_token"`
	}
	if err := postForm(ctx, "https://oauth2.googleapis.com/token", url.Values{
		"client_id": {g.id}, "client_secret": {g.secret}, "code": {code},
		"redirect_uri": {redirectURI}, "grant_type": {"authorization_code"},
	}, &token); err != nil {
		return Identity{}, err
	}
	if token.AccessToken == "" {
		return Identity{}, errors.New("Google 未返回令牌")
	}
	var info struct {
		Sub           string `json:"sub"`
		Email         string `json:"email"`
		EmailVerified bool   `json:"email_verified"`
		Name          string `json:"name"`
		Picture       string `json:"picture"`
	}
	if err := getJSON(ctx, "https://openidconnect.googleapis.com/v1/userinfo", token.AccessToken, &info); err != nil {
		return Identity{}, err
	}
	if info.Sub == "" {
		return Identity{}, errors.New("Google 未返回用户标识")
	}
	return Identity{Provider: "google", Subject: info.Sub, Email: info.Email, EmailVerified: info.EmailVerified,
		Name: info.Name, Avatar: info.Picture}, nil
}
