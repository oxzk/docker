#!/bin/bash
set -e

# 清理 Xvfb 可能残留的锁文件
rm -f /tmp/.X99-lock

export DISPLAY="${DISPLAY:-:99}"
export XVFB_WHD="${XVFB_WHD:-1920x1080x24}"

# 解析 Xvfb 分辨率用于浏览器窗口自适应
XVFB_WIDTH=$(echo "${XVFB_WHD}" | cut -dx -f1)
XVFB_HEIGHT=$(echo "${XVFB_WHD}" | cut -dx -f2)

# 0. 配置 DNS (防止容器运行时 DNS 被覆盖)
echo "[entrypoint] configuring DNS"
echo "nameserver 1.1.1.1" > /etc/resolv.conf
echo "nameserver 114.114.114.114" >> /etc/resolv.conf

# 启动 D-Bus (Chromium 依赖)
mkdir -p /run/dbus /var/run/dbus
rm -f /run/dbus/pid /var/run/dbus/pid
dbus-uuidgen --ensure 2>/dev/null || true
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/dbus/session_bus_socket"
dbus-daemon --session --fork --address="${DBUS_SESSION_BUS_ADDRESS}" --print-address 2>/dev/null || true

# 1. 启动 Xvfb (虚拟屏幕)
echo "[entrypoint] starting Xvfb on ${DISPLAY} (${XVFB_WHD})"
Xvfb "${DISPLAY}" -screen 0 "${XVFB_WHD}" -ac -nolisten tcp +extension GLX +extension RANDR +render -noreset >/tmp/xvfb.log 2>&1 &

sleep 2

# 2. 启动 Fluxbox (管理浏览器窗口，防止点击偏移)
echo "[entrypoint] starting Fluxbox"
fluxbox >/tmp/fluxbox.log 2>&1 &
sleep 1

# 3. 启动 x11vnc (VNC 服务器，远程查看虚拟屏幕)
VNC_PORT="${VNC_PORT:-5900}"
echo "[entrypoint] starting x11vnc on port ${VNC_PORT}"
x11vnc -display "${DISPLAY}" -forever -nopw -rfbport "${VNC_PORT}" -shared >/tmp/x11vnc.log 2>&1 &
sleep 2

# 等待 x11vnc 端口就绪
for i in $(seq 1 30); do
    if ss -tln | grep -q ":${VNC_PORT} "; then
        echo "[entrypoint] x11vnc is ready on port ${VNC_PORT}"
        break
    fi
    echo "[entrypoint] waiting for x11vnc... ($i/30)"
    sleep 1
done

# 4. 启动 noVNC (Web VNC 客户端，支持浏览器访问)
NOVNC_PORT="${NOVNC_PORT:-16080}"
echo "[entrypoint] starting noVNC on port ${NOVNC_PORT}"
websockify --web /opt/noVNC "${NOVNC_PORT}" localhost:"${VNC_PORT}" >/tmp/novnc.log 2>&1 &
sleep 2

# 创建自适应入口页 (自动连接 + 缩放适配窗口)
cat > /opt/noVNC/index.html <<'NOVNCHTML'
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>noVNC</title>
  <style>
    body { margin:0; padding:0; overflow:hidden; background:#000; width:100vw; height:100vh; }
    #screen { width:100%; height:100%; display:flex; align-items:center; justify-content:center; }
    #vnc { border:0; }
  </style>
</head>
<body>
  <div id="screen"><iframe id="vnc" src="vnc.html?autoconnect=true&resize=scale&quality=6"></iframe></div>
  <script>
    function resize() {
      var f = document.getElementById('vnc');
      f.style.width = window.innerWidth + 'px';
      f.style.height = window.innerHeight + 'px';
    }
    window.addEventListener('resize', resize);
    resize();
  </script>
</body>
</html>
NOVNCHTML
echo "[entrypoint] noVNC auto-scale index created"

# 验证 websockify 启动成功
if ! ss -tln | grep -q ":${NOVNC_PORT} "; then
    echo "[WARNING] noVNC websockify may not have started correctly, check /tmp/novnc.log"
else
    echo "[entrypoint] noVNC is ready on port ${NOVNC_PORT}"
fi

# 5. 启动 frpc 内网穿透
if [ -f /usr/local/bin/frpc ] && [ -f /etc/frpc.toml ]; then
    # export FRPC_AUTH_TOKEN="${FRPC_AUTH_TOKEN:-01KE4HVB1ZB41DJV6DA0TWEATX}"
    echo "[frpc] Starting frpc for noVNC (port 6080)..."
    /usr/local/bin/frpc -c /etc/frpc.toml &
    sleep 1
    if pgrep -x frpc > /dev/null; then
        echo "[frpc] frpc is running"
    else
        echo "[frpc] WARNING: frpc may not have started correctly"
    fi
fi

if [ -d /app/clash ] && [ -f /app/clash/config.yml ]; then
    echo "[Clash] Starting..."
    /usr/local/bin/mihomo -f /app/clash/config.yml -d /app/clash > /tmp/clash.log 2>&1 &
    sleep 1
    if pgrep -x mihomo > /dev/null; then
        echo "[Clash] Running"
    else
        echo "[Clash] WARNING: Failed to start"
    fi
fi

BROWSER_EXECUTABLE_PATH=$(python3 - <<'PY'
from playwright.sync_api import sync_playwright
try:
    with sync_playwright() as p:
        print(p.chromium.executable_path)
except Exception:
    print("")
PY
)

if [ -z "$BROWSER_EXECUTABLE_PATH" ]; then
    echo "[ERROR] Chromium not found. Did you run 'playwright install chromium'?"
    exit 1
fi

export BROWSER_EXECUTABLE_PATH

# 3. 启动 Chromium 并开启远程调试端口 (CDP)
# --remote-debugging-address=0.0.0.0 允许容器外连接
# --user-data-dir 实现用户信息持久化
# 清理 Chromium 残留锁文件 (防止容器重启后出现 "个人资料已被锁定" 错误)
# rm -f /app/user_data/SingletonLock /app/user_data/SingletonCookie /app/user_data/SingletonSocket

# echo "[CDP] Starting Chromium on port 9222..."
# $BROWSER_EXECUTABLE_PATH \
#     --remote-debugging-port=9222 \
#     --remote-debugging-address=0.0.0.0 \
#     --remote-allow-origins='*' \
#     --user-data-dir=/app/user_data \
#     --no-sandbox \
#     --disable-dev-shm-usage \
#     --disable-blink-features=AutomationControlled \
#     --disable-infobars \
#     --hide-crash-restore-bubble \
#     --use-gl=angle \
#     --disable-smooth-scrolling \
#     --no-first-run \
#     --window-size=${XVFB_WIDTH},${XVFB_HEIGHT} >/tmp/chromium.log 2>&1 & 

# 保持容器运行
if [ $# -eq 0 ]; then
    echo "[Entrypoint] Browser is ready. Listening on 0.0.0.0:9222"
    tail -f /dev/null
else
    echo "[Entrypoint] Running command: $@"
    exec "$@"
fi

# exec "$@"