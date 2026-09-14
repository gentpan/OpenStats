# openstats-sync

OpenStats 的账号与设置同步服务，跑在官网服务器上，路径 `https://getopenstats.com/api/v1/`。
Go 标准库加纯 Go 的 SQLite，单个二进制，没有其他运行时依赖。

## 接口

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/auth/providers` | 已配置的登录方式，应用据此显示按钮 |
| GET | `/auth/{github,google,apple}/start?challenge=…` | 记下 PKCE challenge，跳转到第三方授权页 |
| GET/POST | `/auth/{provider}/callback` | 第三方回调；换到身份后跳回 `openstats://auth/callback?code=…` |
| POST | `/auth/exchange` | `{code, verifier, device}` → `{token, user}`，换取码 5 分钟内一次有效 |
| GET | `/me` | 当前用户 |
| GET | `/settings` | `{version, updatedAt, device, document}`，没有保存过返回 404 |
| PUT | `/settings` | `{document, device}` 整份覆盖，版本号加一 |
| POST | `/auth/logout` | 作废当前令牌 |
| DELETE | `/account` | 删除用户、所有登录方式、令牌与设置 |

需要登录的接口用 `Authorization: Bearer <token>`。令牌只在库里存 SHA-256。

登录流程和 PKCE 一样：应用生成 verifier，把 S256 challenge 交给 `start`；回调时服务器只把一次性换取码
交回应用，应用再用 verifier 换长期令牌。这样即使别的程序抢注了 `openstats://` scheme，拿到换取码也没有用。

同一个已验证邮箱在不同登录方式下登录会并入同一个用户。Apple 的姓名只在首次授权时给出。

## 部署

1. 在 GitHub、Google、Apple 各建一个 OAuth 应用，回调地址写 `https://getopenstats.com/api/v1/auth/<provider>/callback`（详见 `sync.env.example`）。
2. `./server/sync/install.sh`：交叉编译，安装到 `/usr/local/bin/openstats-sync`，建 `openstats-sync` 用户与 systemd 单元，
   在 `/etc/caddy/sites/getopenstats.com.caddy` 的站点块里加 `handle /api/*` 反向代理。首次安装会生成 `/etc/openstats/sync.env`。
3. 运行 `./server/sync/configure.sh`：它在你的终端里逐项询问 Client ID / Secret 与 .p8 路径，写到服务器的 `/etc/openstats/sync.env` 并重启服务；也可以自己编辑那个文件后 `sudo systemctl restart openstats-sync`。
4. `curl https://getopenstats.com/api/v1/auth/providers` 应列出已配置的登录方式。

数据库在 `/var/lib/openstats-sync/sync.db`，备份这个文件即可。

## 开发

```bash
cd server/sync
go test ./...
GITHUB_CLIENT_ID=… GITHUB_CLIENT_SECRET=… SYNC_BASE_URL=http://127.0.0.1:8787 go run .
```
