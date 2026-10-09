#!/usr/bin/env bash
# 验证 Shell 总线接口、显示配置和 HTTP 服务, 不将仅监听端口视为桌面就绪.
set -Eeuo pipefail
pgrep -u admin -x gnome-shell >/dev/null
runuser -u admin -- timeout 3 gdbus call --session \
    --dest org.gnome.Shell --object-path /org/gnome/Shell \
    --method org.freedesktop.DBus.Properties.Get org.gnome.Shell ShellVersion >/dev/null
runuser -u admin -- timeout 3 gdbus call --session \
    --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig \
    --method org.gnome.Mutter.DisplayConfig.GetCurrentState >/dev/null
status="$(curl --silent --noproxy '*' --output /dev/null --write-out '%{http_code}' \
    --connect-timeout 1 --max-time 2 "http://127.0.0.1:${KASMVNC_WEBSOCKET_PORT}/")"
[[ "$status" == 401 ]]
