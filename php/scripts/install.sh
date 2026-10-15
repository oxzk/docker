#!/bin/bash
set -euxo pipefail

BUILD_DIR=/tmp/build
CONF_DIR=/tmp/conf
DOCKER_DIR=/tmp/docker
OPENSSL_PREFIX=/usr/local/openssl

APT_PACKAGES=(
    autoconf
    automake
    build-essential
    ca-certificates
    cmake
    curl
    file
    g++
    gcc
    git
    libc-dev
    libcurl4-openssl-dev
    libicu-dev
    libjpeg-dev
    libmagickwand-dev
    libonig-dev
    libpng-dev
    libsodium-dev
    libsqlite3-dev
    libssl-dev
    libtool
    libwebp-dev
    libxml2-dev
    libxslt1-dev
    libzip-dev
    make
    openssl
    perl
    pkg-config
    re2c
    wget
    xz-utils
    zlib1g-dev
)

APT_PURGE_PACKAGES=(
    autoconf
    automake
    build-essential
    cmake
    g++
    gcc
    git
    libc-dev
    libtool
    make
    perl
    pkg-config
    re2c
    wget
)

PHP_CONFIG_OPTIONS=(
    --prefix=/usr/local/php
    --with-config-file-path=/usr/local/php/etc
    --with-config-file-scan-dir=/usr/local/php/conf.d
    --enable-fpm
    --with-fpm-user=www
    --with-fpm-group=www
    --enable-mysqlnd
    --with-mysqli=mysqlnd
    --with-pdo-mysql=mysqlnd
    --with-iconv
    --with-zlib
    --with-libxml
    --enable-xml
    --disable-rpath
    --enable-bcmath
    --enable-shmop
    --enable-sysvsem
    --with-curl
    --enable-mbregex
    --enable-mbstring
    --enable-intl
    --enable-pcntl
    --enable-ftp
    --with-gd
    --with-jpeg
    --with-webp
    --with-openssl="${OPENSSL_PREFIX}"
    --enable-sockets
    --with-xmlrpc
    --with-zip
    --enable-soap
    --with-gettext
    --enable-opcache
    --with-xsl
    --with-pear
    --with-sodium
)

install_runtime_scripts() {
    install -m 0755 "${DOCKER_DIR}/entrypoint.sh" /usr/local/bin/docker-entrypoint.sh
}

install_system_packages() {
    apt-get update
    apt-get install -y --no-install-recommends "${APT_PACKAGES[@]}"
}

create_runtime_user() {
    groupadd -r www
    useradd -r -s /usr/sbin/nologin -g www www
}

prepare_runtime_directories() {
    mkdir -p \
        /data/wwwroot/default \
        /data/wwwlogs \
        /usr/local/php/etc/php-fpm.d \
        /usr/local/php/conf.d
    chown -R www:www /data
}

fetch() {
    local url="$1"
    local output="${2:-}"

    if [[ -n "${output}" ]]; then
        wget -c --no-check-certificate "${url}" -O "${output}"
    else
        wget -c --no-check-certificate "${url}"
    fi
}

download_openssl() {
    local archive="${OPENSSL_VERSION}.tar.gz"

    if fetch "https://github.com/openssl/openssl/releases/download/${OPENSSL_RELEASE_TAG}/${archive}" "${archive}"; then
        return 0
    fi

    rm -f "${archive}"
    fetch "https://github.com/openssl/openssl/archive/refs/tags/${OPENSSL_RELEASE_TAG}.tar.gz" "${archive}"
}

download_sources() {
    mkdir -p "${BUILD_DIR}"
    cd "${BUILD_DIR}"

    fetch "https://www.php.net/distributions/${PHP_VERSION}.tar.gz"
    download_openssl
    fetch "https://github.com/alanxz/rabbitmq-c/archive/refs/tags/v${RABBITMQ_C_VERSION}.tar.gz" "rabbitmq-c-${RABBITMQ_C_VERSION}.tar.gz"
    fetch "https://pecl.php.net/get/amqp-${AMQP_VERSION}.tgz"
    fetch "https://pecl.php.net/get/${MONGODB_VERSION}.tgz"
    fetch "https://pecl.php.net/get/imagick-${IMAGICK_VERSION}.tgz"
    fetch "https://pecl.php.net/get/xdebug-${XDEBUG_VERSION}.tgz"
    fetch "https://pecl.php.net/get/xlswriter-${XLSWRITER_VERSION}.tgz"
    fetch "https://pecl.php.net/get/yar-${YAR_VERSION}.tgz"
}

build_openssl() {
    local source_dir

    cd "${BUILD_DIR}"
    tar zxf "${OPENSSL_VERSION}.tar.gz"

    if [[ -d "${BUILD_DIR}/${OPENSSL_VERSION}" ]]; then
        source_dir="${BUILD_DIR}/${OPENSSL_VERSION}"
    elif [[ -d "${BUILD_DIR}/openssl-${OPENSSL_RELEASE_TAG}" ]]; then
        source_dir="${BUILD_DIR}/openssl-${OPENSSL_RELEASE_TAG}"
    else
        printf 'Unable to locate extracted OpenSSL source directory\n' >&2
        return 1
    fi

    cd "${source_dir}"

    ./config \
        --prefix="${OPENSSL_PREFIX}" \
        --openssldir="${OPENSSL_PREFIX}/ssl" \
        --libdir=lib \
        shared \
        zlib
    make -j "$(nproc)"
    make install_sw

    mkdir -p "${OPENSSL_PREFIX}/ssl"
    ln -sf /etc/ssl/certs/ca-certificates.crt "${OPENSSL_PREFIX}/ssl/cert.pem"

    echo "${OPENSSL_PREFIX}/lib" > /etc/ld.so.conf.d/openssl-1.1.conf
    ldconfig

    export PKG_CONFIG_PATH="${OPENSSL_PREFIX}/lib/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}"
    export OPENSSL_CFLAGS="-I${OPENSSL_PREFIX}/include"
    export OPENSSL_LIBS="-L${OPENSSL_PREFIX}/lib -lssl -lcrypto"
    export CPPFLAGS="${CPPFLAGS:+${CPPFLAGS} }-I${OPENSSL_PREFIX}/include"
    export LDFLAGS="${LDFLAGS:+${LDFLAGS} }-L${OPENSSL_PREFIX}/lib"
}

build_php() {
    cd "${BUILD_DIR}"
    tar zxf "${PHP_VERSION}.tar.gz"
    cd "${BUILD_DIR}/${PHP_VERSION}"

    ./configure "${PHP_CONFIG_OPTIONS[@]}"
    make -j "$(nproc)"
    make install
    find /usr/local/php/bin /usr/local/php/sbin -type f -executable -exec strip --strip-all '{}' + || true

    ln -sf /usr/local/php/bin/php /usr/bin/php
    ln -sf /usr/local/php/bin/phpize /usr/bin/phpize
    ln -sf /usr/local/php/bin/pear /usr/bin/pear
    ln -sf /usr/local/php/bin/pecl /usr/bin/pecl
    ln -sf /usr/local/php/sbin/php-fpm /usr/bin/php-fpm

    cp php.ini-production /usr/local/php/etc/php.ini
    install -m 0755 sapi/fpm/init.d.php-fpm /etc/init.d/php-fpm
}

configure_php_ini() {
    sed -i 's/post_max_size =.*/post_max_size = 50M/g' /usr/local/php/etc/php.ini
    sed -i 's/upload_max_filesize =.*/upload_max_filesize = 50M/g' /usr/local/php/etc/php.ini
    sed -i 's/;date.timezone =.*/date.timezone = PRC/g' /usr/local/php/etc/php.ini
    sed -i 's#;error_log = php_errors.log#error_log = /data/wwwlogs/php_errors.log#g' /usr/local/php/etc/php.ini
    sed -i 's/short_open_tag =.*/short_open_tag = On/g' /usr/local/php/etc/php.ini
    sed -i 's/;cgi.fix_pathinfo=.*/cgi.fix_pathinfo=0/g' /usr/local/php/etc/php.ini
    sed -i 's/max_execution_time =.*/max_execution_time = 300/g' /usr/local/php/etc/php.ini
    sed -i 's/disable_functions =.*/disable_functions = passthru,system,chroot,chgrp,chown,shell_exec,ini_alter,ini_restore,dl,openlog,syslog,readlink,popepassthru,stream_socket_server/g' /usr/local/php/etc/php.ini

    pear config-set php_ini /usr/local/php/etc/php.ini
    pecl update-channels
    rm -f /root/.pearrc
}

install_fpm_config() {
    install -m 0644 "${CONF_DIR}/php-fpm.conf" /usr/local/php/etc/php-fpm.conf
    install -m 0644 "${CONF_DIR}/php-fpm.d/"*.conf /usr/local/php/etc/php-fpm.d/
}

build_rabbitmq_c() {
    cd "${BUILD_DIR}"
    tar zxf "rabbitmq-c-${RABBITMQ_C_VERSION}.tar.gz"
    cd "${BUILD_DIR}/rabbitmq-c-${RABBITMQ_C_VERSION}"

    cmake -DCMAKE_INSTALL_PREFIX=/usr/local/rabbitmq-c .
    cmake --build . --target install -- -j "$(nproc)"
    echo '/usr/local/rabbitmq-c/lib' > /etc/ld.so.conf.d/rabbitmq-c.conf
    ldconfig
}

build_php_extension() {
    local archive="$1"
    local source_dir="$2"
    shift 2

    cd "${BUILD_DIR}"
    tar zxf "${archive}"
    cd "${BUILD_DIR}/${source_dir}"

    phpize
    ./configure --with-php-config=/usr/local/php/bin/php-config "$@"
    make -j "$(nproc)"
    make install
}

build_extensions() {
    build_rabbitmq_c
    build_php_extension "amqp-${AMQP_VERSION}.tgz" "amqp-${AMQP_VERSION}" --with-librabbitmq-dir=/usr/local/rabbitmq-c
    build_php_extension "${MONGODB_VERSION}.tgz" "${MONGODB_VERSION}"
    build_php_extension "imagick-${IMAGICK_VERSION}.tgz" "imagick-${IMAGICK_VERSION}"
    build_php_extension "xdebug-${XDEBUG_VERSION}.tgz" "xdebug-${XDEBUG_VERSION}"
    build_php_extension "xlswriter-${XLSWRITER_VERSION}.tgz" "xlswriter-${XLSWRITER_VERSION}" --enable-reader
    build_php_extension "yar-${YAR_VERSION}.tgz" "yar-${YAR_VERSION}" --enable-yar --enable-msgpack=no
}

install_extension_config() {
    install -m 0644 "${CONF_DIR}/conf.d/"*.ini /usr/local/php/conf.d/
}

create_default_site() {
    printf '%s\n' '<?php phpinfo();' > /data/wwwroot/default/index.php
    chown -R www:www /data
}

cleanup_image() {
    cd /
    apt-get purge -y --auto-remove "${APT_PURGE_PACKAGES[@]}"
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false
    apt-get clean
    find /usr/local/php -type f -name '*.a' -delete
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
}

main() {
    install_runtime_scripts
    install_system_packages
    create_runtime_user
    prepare_runtime_directories
    download_sources
    build_openssl
    build_php
    configure_php_ini
    install_fpm_config
    build_extensions
    install_extension_config
    create_default_site
    cleanup_image

    php --version
    php -m
}

main "$@"
