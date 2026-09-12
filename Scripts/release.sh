#!/bin/bash
# 发布一个可分发的版本：Developer ID 签名 → 公证 → 装订 → DMG（签名、公证、装订）→ SHA-256 与 Homebrew cask。
#
#   ./Scripts/release.sh
#
# 需要钥匙串里的 Developer ID Application 证书和 notarytool 凭据。凭据按 Apple ID 与团队保存，
# 默认沿用 QuotaBar 的 “QuotaBar” 凭据；也可以单独保存一份：
#   xcrun notarytool store-credentials OpenStats --apple-id you@example.com --team-id <TEAM_ID>
#   NOTARY_PROFILE=OpenStats ./Scripts/release.sh
#
# SKIP_NOTARIZE=1 只生成未公证的 DMG 供本机测试——不要分发，别的 Mac 上 Gatekeeper 会拒绝打开。
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="${REPO:-gentpan/OpenStats}"
DIST="${DIST:-dist}"
NOTARY_PROFILE="${NOTARY_PROFILE:-QuotaBar}"
SIGN_ID="${SIGN_ID:-$(security find-identity -v -p codesigning 2>/dev/null \
  | grep 'Developer ID Application' | head -1 | sed -E 's/.*"(.*)".*/\1/' || true)}"
VERSION="$(sed -nE 's/^ *MARKETING_VERSION: *"?([0-9.]+)"?.*/\1/p' project.yml | head -1)"
APP="build/DerivedData/Build/Products/Release/OpenStats.app"
DMG_NAME="OpenStats-${VERSION}.dmg"

if [ -z "$SIGN_ID" ]; then
  echo "error: 钥匙串里没有 Developer ID Application 证书，无法发布。" >&2
  exit 1
fi
TEAM_ID="$(echo "$SIGN_ID" | sed -nE 's/.*\(([A-Z0-9]+)\)$/\1/p')"
echo "版本 ${VERSION} · 签名身份：${SIGN_ID}"

# ---- 构建 --------------------------------------------------------------------

make build CONFIG=Release SIGN_ID="$SIGN_ID"

codesign --verify --deep --strict --verbose=2 "$APP"
for binary in "$APP" "$APP/Contents/MacOS/OpenStatsHelper"; do
  details="$(codesign -dvv "$binary" 2>&1)"
  echo "$details" | grep -q "TeamIdentifier=${TEAM_ID}" \
    || { echo "error: $binary 未使用团队 ${TEAM_ID} 签名" >&2; exit 1; }
  echo "$details" | grep -q "Timestamp=" \
    || { echo "error: $binary 缺少安全时间戳" >&2; exit 1; }
  echo "$details" | grep -Eq "flags=.*runtime" \
    || { echo "error: $binary 未启用 Hardened Runtime" >&2; exit 1; }
done

notarize() {
  echo "提交公证：$(basename "$1")（通常需要几分钟）…"
  xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait
}

# ---- 公证 App ----------------------------------------------------------------

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [ "${SKIP_NOTARIZE:-0}" != "1" ]; then
  # ditto 而不是 zip：保留包内的符号链接与扩展属性
  ditto -c -k --keepParent "$APP" "$WORK/OpenStats.zip"
  notarize "$WORK/OpenStats.zip"
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  # 拒绝发布 Gatekeeper 在用户机器上仍会拒绝的包
  if ! spctl -a -vv "$APP" 2>&1 | grep -q accepted; then
    echo "error: Gatekeeper 仍然拒绝该 App，停止发布。" >&2
    spctl -a -vv "$APP" || true
    exit 1
  fi
fi

# ---- DMG ---------------------------------------------------------------------

rm -rf "$DIST"
mkdir -p "$DIST" "$WORK/dmg"
ditto "$APP" "$WORK/dmg/OpenStats.app"
ln -s /Applications "$WORK/dmg/Applications"
hdiutil create -volname "OpenStats ${VERSION}" -srcfolder "$WORK/dmg" -ov -format UDZO "$DIST/$DMG_NAME" >/dev/null
codesign --force --timestamp --sign "$SIGN_ID" "$DIST/$DMG_NAME"

if [ "${SKIP_NOTARIZE:-0}" != "1" ]; then
  notarize "$DIST/$DMG_NAME"
  xcrun stapler staple "$DIST/$DMG_NAME"
  spctl -a -t open --context context:primary-signature -vv "$DIST/$DMG_NAME"
fi

SHA256="$(shasum -a 256 "$DIST/$DMG_NAME" | cut -d' ' -f1)"

# ---- Homebrew cask ------------------------------------------------------------

cat > "$DIST/openstats.rb" <<CASK
cask "openstats" do
  version "${VERSION}"
  sha256 "${SHA256}"

  url "https://github.com/${REPO}/releases/download/v#{version}/OpenStats-#{version}.dmg"
  name "OpenStats"
  desc "Menu bar system monitor with fan control, keep-awake and cleanup"
  homepage "https://getopenstats.com"

  depends_on macos: ">= :sonoma"

  app "OpenStats.app"

  zap trash: [
    "~/Library/Logs/OpenStats",
    "~/Library/Preferences/com.openstats.app.plist",
  ]
end
CASK

echo
echo "✅ ${DIST}/${DMG_NAME}"
echo "   SHA-256 ${SHA256}"
echo "   Homebrew cask：${DIST}/openstats.rb"
if [ "${SKIP_NOTARIZE:-0}" = "1" ]; then
  echo "⚠️  未公证，仅供本机测试。"
else
  echo "下一步：创建 GitHub Release v${VERSION} 并上传 DMG，再把 cask 提交到 gentpan/homebrew-tap。"
fi
