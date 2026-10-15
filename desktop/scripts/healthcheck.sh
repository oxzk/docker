#!/usr/bin/env bash
# 检查桌面就绪标记, X 服务和 GNOME Shell.
set -Eeuo pipefail

test -f /run/desktop/ready
timeout 3 xdpyinfo -display "$DISPLAY" >/dev/null
timeout 3 gdbus call --session \
    --dest org.gnome.Shell --object-path /org/gnome/Shell \
    --method org.freedesktop.DBus.Peer.Ping >/dev/null
