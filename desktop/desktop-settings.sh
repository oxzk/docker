#!/usr/bin/env bash
# 只初始化标准用户目录, 界面默认值由 schema 提供, 保留用户持久化设置.
set -Eeuo pipefail
xdg-user-dirs-update
