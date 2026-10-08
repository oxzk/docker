#!/usr/bin/env bash
# 管理系统总线, GNOME/KasmVNC 和 Cloudflared 的启动和退出清理.
set -Eeuo pipefail

# 检查数值配置后再写入 YAML 和启动参数.
require_number() {
    local name="$1" maximum="$2" value="${!1}"
    if [[ ! "$value" =~ ^[1-9][0-9]{0,4}$ ]] || (( 10#$value > maximum )); then
        printf 'Invalid %s: expected 1..%s\n' "$name" "$maximum" >&2
        exit 1
    fi
}

: "${PASSWORD:?Set PASSWORD for the desktop login}"
if (( ${#PASSWORD} < 6 )) || [[ "$PASSWORD" == *$'\n'* || "$PASSWORD" == *$'\r'* ]]; then
    printf 'PASSWORD must contain at least 6 characters and no line breaks\n' >&2
    exit 1
fi
require_number KASMVNC_WEBSOCKET_PORT 65535
require_number DESKTOP_WIDTH 8192
require_number DESKTOP_HEIGHT 8192

PIDS=()
# 向每个独立进程组发送信号, 同时结束服务启动的子进程.
cleanup() {
    local status=$?
    trap - EXIT TERM INT
    for pid in "${PIDS[@]}"; do
        kill -TERM -- "-$pid" 2>/dev/null || true
    done
    exit "$status"
}
trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

# 每个服务使用独立进程组, 任一关键进程退出都会结束容器.
start_service() {
    setsid "$@" &
    PIDS+=("$!")
}

# 绑定挂载会覆盖镜像内的主目录权限, 先确保 admin 能创建密码临时文件.
install -d -m 700 -o admin -g admin /home/admin
install -d -m 755 /run/dbus
install -d -m 700 -o admin -g admin "$XDG_RUNTIME_DIR" /home/admin/.vnc
install -d -m 1777 /tmp/.X11-unix
dbus-uuidgen --ensure=/etc/machine-id
ln -sf /etc/machine-id /var/lib/dbus/machine-id
# 重启容器时移除上次异常退出留下的固定显示锁.
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1 /run/dbus/pid
start_service dbus-daemon --system --nofork --nopidfile

cat > /home/admin/.vnc/kasmvnc.yaml <<YAML
desktop:
  resolution:
    width: ${DESKTOP_WIDTH}
    height: ${DESKTOP_HEIGHT}
  allow_resize: true
  pixel_depth: 24
network:
  protocol: http
  interface: 0.0.0.0
  websocket_port: ${KASMVNC_WEBSOCKET_PORT}
  use_ipv4: true
  use_ipv6: false
  udp:
    port: 0
  ssl:
    require_ssl: false
user_session:
  session_type: shared
command_line:
  prompt: false
YAML
install -o admin -g admin -m 755 /opt/desktop/xstartup /home/admin/.vnc/xstartup
touch /home/admin/.vnc/.de-was-selected
chown admin:admin /home/admin/.vnc/kasmvnc.yaml /home/admin/.vnc/.de-was-selected
chmod 600 /home/admin/.vnc/kasmvnc.yaml
if ! printf '%s\n%s\n' "$PASSWORD" "$PASSWORD" \
    | runuser -u admin -- vncpasswd -u admin -ow /home/admin/.kasmpasswd \
    || [[ ! -s /home/admin/.kasmpasswd ]]; then
    printf 'Failed to create KasmVNC password file: /home/admin/.kasmpasswd\n' >&2
    exit 1
fi
chown admin:admin /home/admin/.kasmpasswd
chmod 600 /home/admin/.kasmpasswd
unset PASSWORD
runuser -u admin -- xdg-user-dirs-update
start_service runuser -u admin -- vncserver :1 -fg \
    -geometry "${DESKTOP_WIDTH}x${DESKTOP_HEIGHT}" \
    -websocketPort "$KASMVNC_WEBSOCKET_PORT" -interface 0.0.0.0

printf 'Starting GNOME desktop: http://localhost:%s, username=admin\n' "$KASMVNC_WEBSOCKET_PORT"

# 始终启动 Tunnel, 有令牌时使用受管模式, 否则创建 Quick Tunnel.
if [[ -n "${CLOUDFLARED_TOKEN:-}" ]]; then
    # 使用环境变量传入受管 Tunnel 令牌, 不写入命令行或日志.
    start_service env TUNNEL_TOKEN="$CLOUDFLARED_TOKEN" cloudflared tunnel --no-autoupdate run
else
    start_service cloudflared tunnel --no-autoupdate --url "http://127.0.0.1:${KASMVNC_WEBSOCKET_PORT}"
fi
unset CLOUDFLARED_TOKEN

# 即使关键服务以 0 退出, 容器也应报告异常停止以触发重启策略.
status=0
wait -n "${PIDS[@]}" || status=$?
(( status != 0 )) || status=1
exit "$status"
