#!/bin/bash
# 发布已公证的版本：DMG 与在线升级包上传到官网 /download/，最后更新版本清单 appcast.json（已安装的应用据此提示升级），
# cask 提交到 gentpan/homebrew-tap，并校验线上文件。
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
ZIP="dist/OpenStats-${VERSION}.zip"
APPCAST="dist/appcast.json"
CASK="dist/openstats.rb"
SSH=(ssh -i "$KEY" -o BatchMode=yes "$HOST")

for file in "$DMG" "$ZIP" "$APPCAST" "$CASK"; do
  [ -f "$file" ] || { echo "缺少 $file，先运行 ./Scripts/release.sh" >&2; exit 1; }
done
python3 - "$APPCAST" "$VERSION" "$ZIP" <<'PY' || { echo "$APPCAST 与 $ZIP 不一致" >&2; exit 1; }
import hashlib, json, sys
feed = json.load(open(sys.argv[1]))
digest = hashlib.sha256(open(sys.argv[3], "rb").read()).hexdigest()
assert feed["version"] == sys.argv[2] and feed["sha256"] == digest and feed["notes"], feed
PY
grep -q "version \"${VERSION}\"" "$CASK" || { echo "$CASK 的版本不是 ${VERSION}" >&2; exit 1; }
xcrun stapler validate "$DMG" >/dev/null || { echo "$DMG 没有装订公证票据" >&2; exit 1; }
SHA="$(shasum -a 256 "$DMG" | cut -d' ' -f1)"
grep -q "$SHA" "$CASK" || { echo "$CASK 里的 sha256 与 DMG 不一致" >&2; exit 1; }

# 上传：先传临时名再改名，下载中途不会拿到半个文件
"${SSH[@]}" "sudo install -d -o \$(id -un) -m 755 $ROOT/download"
upload() {
  local name
  name="$(basename "$1")"
  scp -i "$KEY" -o BatchMode=yes "$1" "$HOST:$ROOT/download/.${name}.part"
  "${SSH[@]}" "mv -f $ROOT/download/.${name}.part $ROOT/download/${name} && chmod 644 $ROOT/download/${name}"
  local online
  online="$(curl -fsSL --max-time 300 "https://getopenstats.com/download/${name}" | shasum -a 256 | cut -d' ' -f1)"
  [ "$online" = "$(shasum -a 256 "$1" | cut -d' ' -f1)" ] || { echo "线上 ${name} 校验不一致：$online" >&2; exit 1; }
  echo "✅ https://getopenstats.com/download/${name}"
}
upload "$DMG"
upload "$ZIP"
# 版本清单最后发布：安装包都已就位后，已安装的应用才会看到新版本
upload "$APPCAST"

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
