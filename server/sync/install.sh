#!/bin/bash
# 把同步服务装到官网服务器：交叉编译、安装二进制与 systemd 单元、建专用用户，
# 并在 Caddy 的站点块里把 /api/ 反代到本服务。第三方登录的 Client ID / Secret 不进仓库，
# 放在服务器的 /etc/openstats/sync.env（模板见 sync.env.example，用 configure.sh 填写）。
#
#   ./server/sync/install.sh
set -euo pipefail
cd "$(dirname "$0")"
HOST="${SITE_HOST:-debian@51.38.126.148}"
KEY="${SITE_KEY:-$HOME/.ssh/gentpan.pem}"
SSH=(ssh -i "$KEY" -o BatchMode=yes "$HOST")

# 目标架构按服务器实际情况
case "$("${SSH[@]}" uname -m)" in
  x86_64) GOARCH=amd64 ;;
  aarch64|arm64) GOARCH=arm64 ;;
  *) echo "未知架构" >&2; exit 1 ;;
esac

go test ./...
CGO_ENABLED=0 GOOS=linux GOARCH=$GOARCH go build -trimpath -ldflags="-s -w" -o /tmp/openstats-sync .
echo "已编译 linux/$GOARCH"

scp -i "$KEY" -o BatchMode=yes /tmp/openstats-sync openstats-sync.service sync.env.example openstats-sync.caddy "$HOST:/tmp/"
rm -f /tmp/openstats-sync

# 远端步骤通过标准输入交给 bash，引号不受本地 ssh 参数的限制
"${SSH[@]}" bash -s <<'REMOTE'
set -euo pipefail
id -u openstats-sync >/dev/null 2>&1 || sudo useradd --system --home /var/lib/openstats-sync --shell /usr/sbin/nologin openstats-sync
sudo install -m 755 /tmp/openstats-sync /usr/local/bin/openstats-sync
sudo install -m 644 /tmp/openstats-sync.service /etc/systemd/system/
sudo install -d -m 750 -o root -g openstats-sync /etc/openstats
if [ ! -f /etc/openstats/sync.env ]; then
  sudo install -m 640 -o root -g openstats-sync /tmp/sync.env.example /etc/openstats/sync.env
  echo "已创建 /etc/openstats/sync.env，请用 configure.sh 填入各登录方式的 Client ID / Secret"
fi
sudo chgrp openstats-sync /etc/openstats/sync.env && sudo chmod 640 /etc/openstats/sync.env
if [ -f /etc/openstats/apple-signin.p8 ]; then
  sudo chgrp openstats-sync /etc/openstats/apple-signin.p8 && sudo chmod 640 /etc/openstats/apple-signin.p8
fi

# Caddy：站点配置在 /etc/caddy/sites/getopenstats.com.caddy，在站点块开头插入 handle /api/*；已有则跳过。
# 改完用完整的 Caddyfile 校验，不通过就恢复原文件
SITE=/etc/caddy/sites/getopenstats.com.caddy
if sudo test -f "$SITE" && ! sudo grep -q openstats-sync "$SITE"; then
  BACKUP="$SITE.bak.$(date +%Y%m%d%H%M%S)"
  sudo cp -p "$SITE" "$BACKUP"
  sudo awk -v snippet="$(cat /tmp/openstats-sync.caddy)" '
    { print }
    !done && /^[^#]*getopenstats\.com[^{]*\{[[:space:]]*$/ { print snippet; done = 1 }
  ' "$BACKUP" | sudo tee "$SITE" >/dev/null
  if sudo grep -q openstats-sync "$SITE" && sudo caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null 2>&1; then
    sudo systemctl reload caddy
    sudo rm -f "$BACKUP"
    echo "Caddy 已加入 /api/ 反向代理"
  else
    sudo cp -p "$BACKUP" "$SITE" && sudo rm -f "$BACKUP"
    echo "没有自动改 Caddy 配置，请手动把下面这段放进 $SITE 的 getopenstats.com 站点块里，然后 systemctl reload caddy："
    cat /tmp/openstats-sync.caddy
  fi
elif ! sudo test -f "$SITE"; then
  echo "没找到 $SITE，请手动把下面这段放进官网的 Caddy 站点块里："
  cat /tmp/openstats-sync.caddy
fi
rm -f /tmp/openstats-sync /tmp/openstats-sync.service /tmp/sync.env.example /tmp/openstats-sync.caddy

sudo systemctl daemon-reload
sudo systemctl enable --now openstats-sync.service
sudo systemctl restart openstats-sync.service
sleep 1
systemctl --no-pager --lines=5 status openstats-sync.service || true
curl -s http://127.0.0.1:8787/api/v1/auth/providers || true
echo
REMOTE
