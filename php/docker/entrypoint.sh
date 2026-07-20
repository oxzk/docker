#!/bin/bash
set -e

PHP_FPM_CONF="${PHP_FPM_CONF:-/usr/local/php/etc/php-fpm.conf}"
PHP_FPM_POOL_CONF="${PHP_FPM_POOL_CONF:-/usr/local/php/etc/php-fpm.d/www.conf}"

if [[ "$#" -eq 0 ]]; then
    set -- php-fpm -F
elif [[ "$1" == -* ]]; then
    set -- php-fpm "$@"
fi

is_php_fpm_command() {
    case "$1" in
        php-fpm | /usr/bin/php-fpm | /usr/local/php/sbin/php-fpm)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

has_fpm_config_arg() {
    local arg

    for arg in "$@"; do
        case "${arg}" in
            -y | --fpm-config | --fpm-config=*)
                return 0
                ;;
        esac
    done

    return 1
}

set_pool_limits() {
    sed -i "s#pm.max_children = .*#pm.max_children = $1#" "${PHP_FPM_POOL_CONF}"
    sed -i "s#pm.start_servers = .*#pm.start_servers = $2#" "${PHP_FPM_POOL_CONF}"
    sed -i "s#pm.min_spare_servers = .*#pm.min_spare_servers = $3#" "${PHP_FPM_POOL_CONF}"
    sed -i "s#pm.max_spare_servers = .*#pm.max_spare_servers = $4#" "${PHP_FPM_POOL_CONF}"
}

configure_pool_for_memory() {
    local mem_total

    mem_total="$(awk '/MemTotal/ { printf "%d", $2 / 1024 }' /proc/meminfo)"

    if [[ "${mem_total}" -gt 1024 && "${mem_total}" -le 2048 ]]; then
        set_pool_limits 20 10 10 20
    elif [[ "${mem_total}" -gt 2048 && "${mem_total}" -le 4096 ]]; then
        set_pool_limits 40 20 20 40
    elif [[ "${mem_total}" -gt 4096 && "${mem_total}" -le 8192 ]]; then
        set_pool_limits 60 30 30 60
    elif [[ "${mem_total}" -gt 8192 ]]; then
        set_pool_limits 80 40 40 80
    fi
}

if is_php_fpm_command "$1"; then
    configure_pool_for_memory

    if ! has_fpm_config_arg "$@"; then
        set -- "$@" --fpm-config "${PHP_FPM_CONF}"
    fi
fi

exec "$@"
