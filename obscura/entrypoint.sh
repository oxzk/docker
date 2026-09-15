#!/usr/bin/env bash
set -Eeuo pipefail

HOST="${OBSCURA_HOST:-0.0.0.0}"
PORT="${OBSCURA_PORT:-9222}"

# 判断参数列表中是否已经包含指定长选项, 兼容 `--flag value` 与 `--flag=value`.
has_long_opt() {
    local needle="$1"
    shift
    local arg
    for arg in "$@"; do
        if [[ "${arg}" == "${needle}" || "${arg}" == "${needle}="* ]]; then
            return 0
        fi
    done
    return 1
}

# 默认 serve: 绑定 0.0.0.0, 开启 stealth.
if [[ $# -eq 0 ]]; then
    set -- serve --host "${HOST}" --port "${PORT}" --stealth
elif [[ "$1" == "serve" ]]; then
    extra=()
    if ! has_long_opt --host "$@"; then
        extra+=(--host "${HOST}")
    fi
    if ! has_long_opt --stealth "$@"; then
        extra+=(--stealth)
    fi
    if [[ "${#extra[@]}" -gt 0 ]]; then
        set -- "$@" "${extra[@]}"
    fi
fi

echo "$@"
exec obscura "$@"
