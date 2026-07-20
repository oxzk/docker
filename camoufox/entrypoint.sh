#!/usr/bin/env bash
set -Eeuo pipefail

BACKGROUND_PIDS=()
MAIN_PID=""

# 统一日志输出，便于在容器日志中快速定位启动阶段。
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# 清理后台进程，避免容器退出后残留子进程。
cleanup() {
    local exit_code=$?

    if [[ -n "${MAIN_PID}" ]]; then
        kill "${MAIN_PID}" >/dev/null 2>&1 || true
    fi

    if [[ "${#BACKGROUND_PIDS[@]}" -gt 0 ]]; then
        log "清理后台进程"
        kill "${BACKGROUND_PIDS[@]}" >/dev/null 2>&1 || true
        wait "${BACKGROUND_PIDS[@]}" >/dev/null 2>&1 || true
    fi

    exit "${exit_code}"
}

# 转发终止信号给主进程，再交给 cleanup 统一清理。
terminate() {
    if [[ -n "${MAIN_PID}" ]]; then
        kill -TERM "${MAIN_PID}" >/dev/null 2>&1 || true
    fi
    exit 143
}

trap cleanup EXIT
trap terminate TERM INT

# 启动后台进程并记录 PID。
start_background() {
    local name="$1"
    local log_file="$2"
    shift 2

    log "启动 ${name}"
    "$@" >"${log_file}" 2>&1 &
    BACKGROUND_PIDS+=("$!")
}

# 等待端口监听，避免固定 sleep 在慢机器上误判服务状态。
wait_for_port() {
    local name="$1"
    local port="$2"
    local timeout="${3:-30}"

    for i in $(seq 1 "${timeout}"); do
        if (echo >"/dev/tcp/127.0.0.1/${port}") >/dev/null 2>&1; then
            log "${name} 已监听端口 ${port}"
            return 0
        fi

        log "等待 ${name} 启动中... (${i}/${timeout})"
        sleep 1
    done

    log "警告：${name} 未在 ${timeout} 秒内监听端口 ${port}"
    return 1
}

# 从 cloudflared 日志解析 quick tunnel 访问地址，最多等待指定秒数。
wait_for_cloudflared_url() {
    local log_file="$1"
    local timeout="${2:-60}"
    local tunnel_url=""

    for i in $(seq 1 "${timeout}"); do
        tunnel_url="$(grep -Eo 'https://[a-zA-Z0-9.-]+\.trycloudflare\.com' "${log_file}" 2>/dev/null | tail -n 1 || true)"
        if [[ -n "${tunnel_url}" ]]; then
            log "cloudflared 访问地址：${tunnel_url}"
            return 0
        fi

        if ! pgrep -x cloudflared >/dev/null; then
            log "警告：cloudflared 已退出，未解析到访问地址"
            return 1
        fi

        log "等待 cloudflared 访问地址... (${i}/${timeout})"
        sleep 1
    done

    log "警告：${timeout} 秒内未解析到 cloudflared 访问地址，请查看 ${log_file}"
    return 1
}

# 配置基础环境。
export DISPLAY="${DISPLAY:-:99}"
export XVFB_WHD="${XVFB_WHD:-1920x1080x24}"
export VNC_PORT="${VNC_PORT:-5900}"
export NOVNC_PORT="${NOVNC_PORT:-15902}"
export CLOUDFLARED_TUNNEL_ENABLE="${CLOUDFLARED_TUNNEL_ENABLE:-0}"
export CLOUDFLARED_TUNNEL_URL="${CLOUDFLARED_TUNNEL_URL:-http://127.0.0.1:${NOVNC_PORT}}"

rm -f "/tmp/.X${DISPLAY#:}-lock"

if [[ "${CONFIGURE_DNS:-0}" == "1" ]]; then
    log "写入容器 DNS 配置"
    {
        echo "nameserver 1.1.1.1"
        echo "nameserver 114.114.114.114"
    } > /etc/resolv.conf
fi

# Chromium/Firefox 相关库会尝试访问 D-Bus，启动失败不影响主流程。
mkdir -p /run/dbus /var/run/dbus
rm -f /run/dbus/pid /var/run/dbus/pid
dbus-uuidgen --ensure 2>/dev/null || true
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/dbus/session_bus_socket"
dbus-daemon --session --fork --address="${DBUS_SESSION_BUS_ADDRESS}" --print-address >/tmp/dbus.log 2>&1 || true

start_background "Xvfb：${DISPLAY} (${XVFB_WHD})" /tmp/xvfb.log \
    Xvfb "${DISPLAY}" -screen 0 "${XVFB_WHD}" -ac -nolisten tcp +extension GLX +extension RANDR +render -noreset
sleep 1

start_background "Fluxbox" /tmp/fluxbox.log fluxbox
sleep 1

VNC_AUTH_ARGS=("-nopw")
if [[ -n "${VNC_PASSWORD:-}" ]]; then
    VNC_PASSWORD_FILE="/tmp/x11vnc.pass"
    x11vnc -storepasswd "${VNC_PASSWORD}" "${VNC_PASSWORD_FILE}" >/tmp/x11vnc-pass.log 2>&1
    VNC_AUTH_ARGS=("-rfbauth" "${VNC_PASSWORD_FILE}")
    log "已启用 VNC 密码认证"
else
    log "警告：未设置 VNC_PASSWORD，VNC 将使用无密码认证"
fi

start_background "x11vnc：${VNC_PORT}" /tmp/x11vnc.log \
    x11vnc -display "${DISPLAY}" -forever "${VNC_AUTH_ARGS[@]}" -rfbport "${VNC_PORT}" -shared
wait_for_port "x11vnc" "${VNC_PORT}" 30 || true

log "创建 noVNC 自适应入口页"
cat > /opt/noVNC/index.html <<'NOVNCHTML'
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>noVNC</title>
  <style>
    html, body, #screen { width: 100%; height: 100%; }
    body { margin: 0; overflow: hidden; background: #000; }
    #screen { display: flex; align-items: center; justify-content: center; }
    #vnc { width: 100vw; height: 100vh; border: 0; }
  </style>
</head>
<body>
  <div id="screen">
    <iframe id="vnc" src="vnc.html?autoconnect=true&resize=scale&quality=6"></iframe>
  </div>
</body>
</html>
NOVNCHTML

start_background "noVNC：${NOVNC_PORT}" /tmp/novnc.log \
    websockify --web /opt/noVNC "${NOVNC_PORT}" "localhost:${VNC_PORT}"
wait_for_port "noVNC" "${NOVNC_PORT}" 30 || true

if [[ "${CLOUDFLARED_TUNNEL_ENABLE}" == "1" ]]; then
    if [[ -n "${CLOUDFLARED_TUNNEL_TOKEN:-}" ]]; then
        start_background "cloudflared token tunnel" /tmp/cloudflared.log \
            cloudflared tunnel --no-autoupdate run --token "${CLOUDFLARED_TUNNEL_TOKEN}"
    else
        start_background "cloudflared quick tunnel：${CLOUDFLARED_TUNNEL_URL}" /tmp/cloudflared.log \
            cloudflared tunnel --no-autoupdate --url "${CLOUDFLARED_TUNNEL_URL}"
        wait_for_cloudflared_url /tmp/cloudflared.log 60 || true
    fi
fi

if [[ $# -eq 0 ]]; then
    log "未提供自定义命令，容器将保持运行"
    touch /tmp/xvfb.log /tmp/fluxbox.log /tmp/x11vnc.log /tmp/novnc.log /tmp/cloudflared.log
    tail -f /tmp/xvfb.log /tmp/fluxbox.log /tmp/x11vnc.log /tmp/novnc.log /tmp/cloudflared.log &
    MAIN_PID="$!"
    wait "${MAIN_PID}"
    exit 0
fi

log "noVNC 已就绪：http://127.0.0.1:${NOVNC_PORT}/"
log "执行自定义命令：$*"
"$@" &
MAIN_PID="$!"
wait "${MAIN_PID}"
