#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 SERVER_HOST REMOTE_PANEL_PORT LOCAL_PANEL_PORT PANEL_SCHEME PANEL_BASE_PATH ABSOLUTE_PRIVATE_KEY_PATH OUTPUT.command" >&2
}

if [[ $# -ne 7 ]]; then
  usage
  exit 2
fi

server_host=$1
remote_panel_port=$2
local_panel_port=$3
panel_scheme=$4
panel_path=$5
private_key=$6
output_file=$7

if [[ ! $server_host =~ ^[A-Za-z0-9.-]+$ ]]; then
  echo "Invalid server host: $server_host" >&2
  exit 2
fi

if [[ ! $remote_panel_port =~ ^[0-9]+$ ]] || (( remote_panel_port < 1 || remote_panel_port > 65535 )); then
  echo "Invalid remote panel port: $remote_panel_port" >&2
  exit 2
fi

if [[ ! $local_panel_port =~ ^[0-9]+$ ]] || (( local_panel_port < 1 || local_panel_port > 65535 )); then
  echo "Invalid local panel port: $local_panel_port" >&2
  exit 2
fi

if [[ $panel_scheme != http && $panel_scheme != https ]]; then
  echo "Panel scheme must be http or https." >&2
  exit 2
fi

if [[ $panel_path != /* ]]; then
  panel_path="/$panel_path"
fi
if [[ $panel_path != */ ]]; then
  panel_path="$panel_path/"
fi
if [[ ! $panel_path =~ ^/[A-Za-z0-9/_-]*/$ ]]; then
  echo "Panel path may contain only letters, digits, slash, underscore, and hyphen." >&2
  exit 2
fi

if [[ $private_key != /* ]] || [[ $private_key == *"'"* ]] || [[ $private_key == *$'\n'* ]]; then
  echo "Private key path must be an absolute path without quotes or newlines." >&2
  exit 2
fi

if [[ $output_file == *$'\n'* ]]; then
  echo "Output path may not contain newlines." >&2
  exit 2
fi

cat >"$output_file" <<EOF
#!/bin/zsh

key_path='$private_key'
server='panel-tunnel@$server_host'
panel_url='$panel_scheme://127.0.0.1:$local_panel_port$panel_path'

if [[ ! -f "\$key_path" ]]; then
  echo "找不到 SSH 私钥：\$key_path"
  echo "按回车键关闭窗口。"
  read -r
  exit 1
fi

echo "正在建立 3x-ui 安全隧道……"
/usr/bin/ssh \\
  -i "\$key_path" \\
  -o BatchMode=yes \\
  -o IdentitiesOnly=yes \\
  -o StrictHostKeyChecking=yes \\
  -o ExitOnForwardFailure=yes \\
  -N \\
  -L 127.0.0.1:$local_panel_port:127.0.0.1:$remote_panel_port \\
  "\$server" &
tunnel_pid=\$!

cleanup() {
  /bin/kill "\$tunnel_pid" 2>/dev/null
}
trap cleanup EXIT INT TERM HUP

for attempt in {1..30}; do
  if ! /bin/kill -0 "\$tunnel_pid" 2>/dev/null; then
    wait "\$tunnel_pid"
    status=\$?
    echo "SSH 隧道启动失败（退出码：\$status）。"
    echo "按回车键关闭窗口。"
    read -r
    exit "\$status"
  fi

  if /usr/bin/curl -k -sS --connect-timeout 1 -o /dev/null "\$panel_url" 2>/dev/null; then
    /usr/bin/open "\$panel_url"
    echo "面板已在浏览器中打开。"
    echo "请保持此窗口开启；关闭窗口或按 Control+C 会断开隧道。"
    wait "\$tunnel_pid"
    exit \$?
  fi

  /bin/sleep 0.2
done

echo "隧道已连接，但面板在等待时间内没有响应。"
echo "按回车键关闭窗口。"
read -r
exit 1
EOF

chmod 700 "$output_file"
echo "Created: $output_file"
