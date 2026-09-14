package main

import (
	"context"
	"crypto/ecdsa"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"net/url"
	"strings"
	"time"
)

// Apple 登录走网页授权（Sign in with Apple JS 的 OAuth 形式），不依赖应用的 entitlement：
// client_id 是 Services ID，client_secret 是用 .p8 私钥签的 ES256 JWT。
// 请求 name email 时 Apple 要求 response_mode=form_post，所以回调是 POST。
type apple struct {
	clientID string
	teamID   string
	keyID    string
	key      *ecdsa.PrivateKey
}

func NewApple(clientID, teamID, keyID string, pemBytes []byte) (Provider, error) {
	if teamID == "" || keyID == "" {
		return nil, errors.New("APPLE_TEAM_ID 与 APPLE_KEY_ID 必须同时提供")
	}
	block, _ := pem.Decode(pemBytes)
	if block == nil {
		return nil, errors.New("Apple 私钥不是 PEM 格式")
	}
	parsed, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("解析 Apple 私钥失败：%w", err)
	}
	key, ok := parsed.(*ecdsa.PrivateKey)
	if !ok {
		return nil, errors.New("Apple 私钥不是 EC 密钥")
	}
	return &apple{clientID: clientID, teamID: teamID, keyID: keyID, key: key}, nil
}

func (a *apple) Name() string { return "apple" }

func (a *apple) AuthURL(state, redirectURI string) string {
	q := url.Values{
		"client_id":     {a.clientID},
		"redirect_uri":  {redirectURI},
		"response_type": {"code"},
		"response_mode": {"form_post"},
		"scope":         {"name email"},
		"state":         {state},
	}
	return "https://appleid.apple.com/auth/authorize?" + q.Encode()
}

func (a *apple) Exchange(ctx context.Context, code, redirectURI string, form url.Values) (Identity, error) {
	secret, err := a.clientSecret(time.Now())
	if err != nil {
		return Identity{}, err
	}
	var token struct {
		IDToken string `json:"id_token"`
		Error   string `json:"error"`
	}
	if err := postForm(ctx, "https://appleid.apple.com/auth/token", url.Values{
		"client_id": {a.clientID}, "client_secret": {secret}, "code": {code},
		"grant_type": {"authorization_code"}, "redirect_uri": {redirectURI},
	}, &token); err != nil {
		return Identity{}, err
	}
	if token.IDToken == "" {
		return Identity{}, errors.New("Apple 未返回 id_token：" + token.Error)
	}
	// id_token 是刚从 Apple 的令牌端点经 TLS 直接取回的，来源可信，只核对声明不再验签
	claims, err := parseIDToken(token.IDToken)
	if err != nil {
		return Identity{}, err
	}
	if claims.Issuer != "https://appleid.apple.com" || claims.Audience != a.clientID {
		return Identity{}, errors.New("Apple id_token 的签发者或受众不符")
	}
	if time.Now().Unix() > claims.Expires {
		return Identity{}, errors.New("Apple id_token 已过期")
	}
	identity := Identity{Provider: "apple", Subject: claims.Subject, Email: claims.Email, EmailVerified: claims.emailVerified()}
	// 姓名只在用户第一次授权时随回调表单给出，之后 Apple 不再提供
	if raw := form.Get("user"); raw != "" {
		var user struct {
			Name struct {
				FirstName string `json:"firstName"`
				LastName  string `json:"lastName"`
			} `json:"name"`
		}
		if json.Unmarshal([]byte(raw), &user) == nil {
			identity.Name = strings.TrimSpace(user.Name.FirstName + " " + user.Name.LastName)
		}
	}
	return identity, nil
}

// clientSecret 按 Apple 要求签发 ES256 JWT；有效期取 1 小时，每次换取时现签
func (a *apple) clientSecret(now time.Time) (string, error) {
	header, _ := json.Marshal(map[string]string{"alg": "ES256", "kid": a.keyID})
	payload, _ := json.Marshal(map[string]any{
		"iss": a.teamID,
		"iat": now.Unix(),
		"exp": now.Add(time.Hour).Unix(),
		"aud": "https://appleid.apple.com",
		"sub": a.clientID,
	})
	signing := base64.RawURLEncoding.EncodeToString(header) + "." + base64.RawURLEncoding.EncodeToString(payload)
	digest := sha256.Sum256([]byte(signing))
	r, s, err := ecdsa.Sign(rand.Reader, a.key, digest[:])
	if err != nil {
		return "", err
	}
	// JWS 要求 r、s 各补齐到 32 字节后拼接，而不是 ASN.1
	size := (a.key.Curve.Params().BitSize + 7) / 8
	sig := make([]byte, 2*size)
	r.FillBytes(sig[:size])
	s.FillBytes(sig[size:])
	return signing + "." + base64.RawURLEncoding.EncodeToString(sig), nil
}

type idTokenClaims struct {
	Issuer   string `json:"iss"`
	Audience string `json:"aud"`
	Expires  int64  `json:"exp"`
	Subject  string `json:"sub"`
	Email    string `json:"email"`
	// Apple 有时给字符串 "true"，有时给布尔值
	EmailVerifiedRaw json.RawMessage `json:"email_verified"`
}

func (c idTokenClaims) emailVerified() bool {
	s := strings.Trim(string(c.EmailVerifiedRaw), `"`)
	return s == "true"
}

func parseIDToken(token string) (idTokenClaims, error) {
	var claims idTokenClaims
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		return claims, errors.New("id_token 格式不正确")
	}
	payload, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return claims, err
	}
	return claims, json.Unmarshal(payload, &claims)
}

// timeNow 便于测试替换
var timeNow = func() time.Time { return time.Now() }
