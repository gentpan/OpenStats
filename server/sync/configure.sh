#!/bin/bash
# 把各登录方式的 Client ID / Secret 写到服务器的 /etc/openstats/sync.env 并重启同步服务。
# 值在本机终端里输入（Secret 不回显），只经 ssh 传到服务器，不进仓库、不进日志。
# 留空表示保持服务器上现有的值不变。
#
#   ./server/sync/configure.sh
set -euo pipefail
HOST="${SITE_HOST:-debian@51.38.126.148}"
KEY="${SITE_KEY:-$HOME/.ssh/gentpan.pem}"
SSH=(ssh -i "$KEY" -o BatchMode=yes "$HOST")

ask() {         # ask 变量名 提示
  local value; read -r -p "$2（留空跳过）: " value; printf -v "$1" '%s' "$value"
}
ask_secret() {  # 不回显
  local value; read -r -s -p "$2（留空跳过）: " value; echo; printf -v "$1" '%s' "$value"
}

echo "写入 $HOST:/etc/openstats/sync.env"
ask GITHUB_CLIENT_ID "GitHub Client ID"
ask_secret GITHUB_CLIENT_SECRET "GitHub Client Secret"
ask GOOGLE_CLIENT_ID "Google Client ID"
ask_secret GOOGLE_CLIENT_SECRET "Google Client Secret"
ask APPLE_CLIENT_ID "Apple Services ID（例如 com.openstats.web）"
ask APPLE_TEAM_ID "Apple Team ID"
ask APPLE_KEY_ID "Apple Key ID"
ask APPLE_P8 "Apple .p8 文件的本机路径"

APPLE_PRIVATE_KEY_FILE=""
if [ -n "$APPLE_P8" ]; then
  [ -r "$APPLE_P8" ] || { echo "读不到 $APPLE_P8" >&2; exit 1; }
  scp -i "$KEY" -o BatchMode=yes "$APPLE_P8" "$HOST:/tmp/apple-signin.p8"
  "${SSH[@]}" 'sudo install -m 640 -o root -g openstats-sync /tmp/apple-signin.p8 /etc/openstats/apple-signin.p8 && rm -f /tmp/apple-signin.p8'
  APPLE_PRIVATE_KEY_FILE=/etc/openstats/apple-signin.p8
fi
export GITHUB_CLIENT_ID GITHUB_CLIENT_SECRET GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET \
       APPLE_CLIENT_ID APPLE_TEAM_ID APPLE_KEY_ID APPLE_PRIVATE_KEY_FILE

# 本机 python 把要改的键值编成一段远端 python（repr 保证转义），经标准输入交给服务器执行；
# 有值的键覆盖，没值的保留，不出现在任何命令行参数里
python3 - <<'PYEOF' | "${SSH[@]}" 'sudo python3 -'
import os
keys = ["GITHUB_CLIENT_ID", "GITHUB_CLIENT_SECRET", "GOOGLE_CLIENT_ID", "GOOGLE_CLIENT_SECRET",
        "APPLE_CLIENT_ID", "APPLE_TEAM_ID", "APPLE_KEY_ID", "APPLE_PRIVATE_KEY_FILE"]
updates = {k: os.environ[k] for k in keys if os.environ.get(k)}
print("""import os, re
path = "/etc/openstats/sync.env"
updates = %r
text = open(path).read() if os.path.exists(path) else ""
lines = text.split("\\n")
seen = set()
for i, line in enumerate(lines):
    m = re.match(r"^([A-Z_]+)=", line)
    if m and m.group(1) in updates:
        lines[i] = m.group(1) + "=" + updates[m.group(1)]
        seen.add(m.group(1))
for k, v in updates.items():
    if k not in seen:
        lines.append(k + "=" + v)
tmp = path + ".new"
with open(tmp, "w") as f:
    f.write("\\n".join(lines).rstrip("\\n") + "\\n")
os.chmod(tmp, 0o640)
os.replace(tmp, path)
print("已更新", ", ".join(sorted(updates)) if updates else "（没有改动）")
""" % (updates,))
PYEOF
"${SSH[@]}" 'sudo chgrp openstats-sync /etc/openstats/sync.env && sudo chmod 640 /etc/openstats/sync.env && sudo systemctl restart openstats-sync && sleep 1 && curl -s http://127.0.0.1:8787/api/v1/auth/providers && echo'
