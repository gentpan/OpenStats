#!/bin/bash
# 本机只保留一个 OpenStats：退出正在运行的旧版 → 删除 /Applications 里的旧版 → 把刚编译的新版移进去 → 启动。
# 用移动而不是复制，编译目录里不留第二份；其他位置被系统登记的同名应用会取消登记并提示。
#
#   Scripts/install_local.sh build/DerivedData/Build/Products/Release/OpenStats.app
set -euo pipefail
cd "$(dirname "$0")/.."

SOURCE="${1:?用法：Scripts/install_local.sh <OpenStats.app>}"
TARGET="/Applications/OpenStats.app"
BUNDLE_ID="com.openstats.app"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

[ -d "$SOURCE" ] || { echo "error: 找不到 $SOURCE" >&2; exit 1; }
codesign --verify --deep --strict "$SOURCE"

# 结束旧版。辅助工具在连接断开时会自动恢复风扇与睡眠设置，所以直接结束是安全的
# （不用 AppleScript 退出，免得弹出“自动化”权限请求）
if pgrep -x OpenStats >/dev/null; then
  pkill -x OpenStats 2>/dev/null || true
  for _ in $(seq 1 25); do pgrep -x OpenStats >/dev/null || break; sleep 0.2; done
fi

if [ -d "$TARGET" ]; then
  "$LSREGISTER" -u "$TARGET" >/dev/null 2>&1 || true
  rm -rf "$TARGET"
fi
mv "$SOURCE" "$TARGET"
"$LSREGISTER" -f "$TARGET"

# 编译目录里残留的旧产物（Debug / Release 另一种配置、发布时另一种芯片的版本）也清掉
for stale in build/DerivedData*/Build/Products/*/OpenStats.app; do
  [ -d "$stale" ] || continue
  "$LSREGISTER" -u "$stale" >/dev/null 2>&1 || true
  rm -rf "$stale"
done

# 其他位置的同名应用只取消登记并提示，不擅自删除
others="$(mdfind "kMDItemCFBundleIdentifier == '$BUNDLE_ID'" 2>/dev/null | grep -vx "$TARGET" | grep -v '^/Volumes/' || true)"
if [ -n "$others" ]; then
  echo "⚠️  其他位置还有 OpenStats（已取消系统登记，如不需要请手动删除）："
  while IFS= read -r path; do
    "$LSREGISTER" -u "$path" >/dev/null 2>&1 || true
    echo "   $path"
  done <<< "$others"
fi

open "$TARGET"
version="$(defaults read "$TARGET/Contents/Info" CFBundleShortVersionString) ($(defaults read "$TARGET/Contents/Info" CFBundleVersion))"
echo "✅ 已安装并启动 OpenStats $version：$TARGET"
