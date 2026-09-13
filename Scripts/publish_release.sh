#!/bin/bash
# 发布已公证的版本：DMG 上传到官网 /download/，cask 提交到 gentpan/homebrew-tap，并校验线上文件。
#
#   ./Scripts/release.sh          # 先打包、公证
#   ./Scripts/publish_release.sh  # 再发布
set -euo pipefail
cd "$(dirname "$0")/.."

HOST="${SITE_HOST:-debian@15.204.80.137}"
KEY="${SITE_KEY:-$HOME/.ssh/gentpan.pem}"
ROOT="${SITE_ROOT:-/var/www/getopenstats.com}"
TAP="${TAP:-gentpan/homebrew-tap}"
VERSION="$(sed -nE 's/^ *MARKETING_VERSION: *"?([0-9.]+)"?.*/\1/p' project.yml | head -1)"
DMG="dist/OpenStats-${VERSION}.dmg"
CASK="dist/openstats.rb"
SSH=(ssh -i "$KEY" -o BatchMode=yes "$HOST")

[ -f "$DMG" ] && [ -f "$CASK" ] || { echo "缺少 $DMG 或 $CASK，先运行 ./Scripts/release.sh" >&2; exit 1; }
grep -q "version \"${VERSION}\"" "$CASK" || { echo "$CASK 的版本不是 ${VERSION}" >&2; exit 1; }
xcrun stapler validate "$DMG" >/dev/null || { echo "$DMG 没有装订公证票据" >&2; exit 1; }
SHA="$(shasum -a 256 "$DMG" | cut -d' ' -f1)"
grep -q "$SHA" "$CASK" || { echo "$CASK 里的 sha256 与 DMG 不一致" >&2; exit 1; }

# 上传：先传临时名再改名，下载中途不会拿到半个文件
"${SSH[@]}" "sudo install -d -o \$(id -un) -m 755 $ROOT/download"
scp -i "$KEY" -o BatchMode=yes "$DMG" "$HOST:$ROOT/download/.OpenStats-${VERSION}.dmg.part"
"${SSH[@]}" "mv -f $ROOT/download/.OpenStats-${VERSION}.dmg.part $ROOT/download/OpenStats-${VERSION}.dmg && chmod 644 $ROOT/download/OpenStats-${VERSION}.dmg"

URL="https://getopenstats.com/download/OpenStats-${VERSION}.dmg"
ONLINE="$(curl -fsSL --max-time 300 "$URL" | shasum -a 256 | cut -d' ' -f1)"
[ "$ONLINE" = "$SHA" ] || { echo "线上 DMG 校验不一致：$ONLINE" >&2; exit 1; }
echo "✅ $URL"

# Homebrew tap
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
gh repo clone "$TAP" "$WORK/tap" -- --quiet
mkdir -p "$WORK/tap/Casks"
cp "$CASK" "$WORK/tap/Casks/openstats.rb"
if git -C "$WORK/tap" diff --quiet -- Casks/openstats.rb && git -C "$WORK/tap" ls-files --error-unmatch Casks/openstats.rb >/dev/null 2>&1; then
  echo "✅ $TAP 已是 ${VERSION}"
else
  git -C "$WORK/tap" add Casks/openstats.rb
  git -C "$WORK/tap" commit -q -m "openstats ${VERSION}"
  git -C "$WORK/tap" push -q
  echo "✅ 已提交 Casks/openstats.rb 到 $TAP"
fi
echo "安装：brew install --cask gentpan/tap/openstats"
