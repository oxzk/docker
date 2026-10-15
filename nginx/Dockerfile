FROM oxzk/debian

ENV NGINX_VERSION=nginx-1.20.1 \
    OPENSSL_VERSION=openssl-1.1.1k \
    OPENSSL_RELEASE_TAG=OpenSSL_1_1_1k \
    WWW_ROOT=/data/wwwroot/default \
    PATH="/usr/local/nginx/sbin:${PATH}" \
    DEBIAN_FRONTEND=noninteractive

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

COPY conf /tmp/nginx-conf
COPY docker/entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        gcc \
        g++ \
        libpcre3 \
        libpcre3-dev \
        libssl-dev \
        make \
        openssl \
        wget \
        zlib1g \
        zlib1g-dev; \
    groupadd -r www; \
    useradd -r -s /usr/sbin/nologin -g www www; \
    cd /tmp; \
    wget -c --progress=bar:force --prefer-family=IPv4 --no-check-certificate "https://github.com/openssl/openssl/releases/download/${OPENSSL_RELEASE_TAG}/${OPENSSL_VERSION}.tar.gz"; \
    tar zxf "${OPENSSL_VERSION}.tar.gz"; \
    wget -c --progress=bar:force --prefer-family=IPv4 --no-check-certificate "https://nginx.org/download/${NGINX_VERSION}.tar.gz"; \
    tar zxf "${NGINX_VERSION}.tar.gz"; \
    cd "/tmp/${NGINX_VERSION}"; \
    ./configure \
        --prefix=/usr/local/nginx \
        --user=www \
        --group=www \
        --with-http_ssl_module \
        --with-http_sub_module \
        --with-http_gzip_static_module \
        --with-stream \
        --with-stream_ssl_module \
        --with-http_v2_module \
        --with-http_stub_status_module \
        --with-openssl="/tmp/${OPENSSL_VERSION}" \
        --with-openssl-opt='enable-weak-ssl-ciphers'; \
    make -j "$(nproc)"; \
    make install; \
    strip /usr/local/nginx/sbin/nginx* || true; \
    ln -sf /usr/local/nginx/sbin/nginx /usr/bin/nginx; \
    mkdir -p /data/nginx/vhost "${WWW_ROOT}" /data/wwwlogs /usr/local/nginx/conf/vhost; \
    chown -R www:www /data; \
    chmod 0777 /data/wwwlogs; \
    printf 'nginx version %s\n' "${NGINX_VERSION}" > "${WWW_ROOT}/index.html"; \
    printf '%s\n' '<?php phpinfo();' > "${WWW_ROOT}/index.php"; \
    rm -f /usr/local/nginx/conf/nginx.conf; \
    cp -a /tmp/nginx-conf/. /usr/local/nginx/conf/; \
    chmod +x /usr/local/bin/docker-entrypoint.sh; \
    apt-get purge -y --auto-remove build-essential gcc g++ make wget; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

WORKDIR /data/wwwroot

EXPOSE 80 443

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

STOPSIGNAL SIGTERM

CMD ["nginx", "-g", "daemon off;"]
