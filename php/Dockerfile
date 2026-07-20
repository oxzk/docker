FROM oxzk/debian

ENV PHP_VERSION=php-7.4.33 \
    OPENSSL_VERSION=openssl-1.1.1w \
    OPENSSL_RELEASE_TAG=OpenSSL_1_1_1w \
    AMQP_VERSION=2.1.2 \
    RABBITMQ_C_VERSION=0.13.0 \
    IMAGEMAGICK_VERSION=7.1.1-40 \
    IMAGICK_VERSION=3.7.0 \
    MONGODB_VERSION=mongodb-1.19.4 \
    XDEBUG_VERSION=3.1.6 \
    XLSWRITER_VERSION=1.5.8 \
    YAR_VERSION=2.3.2 \
    PATH="/usr/local/php/bin:/usr/local/php/sbin:${PATH}" \
    DEBIAN_FRONTEND=noninteractive

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

COPY docker /tmp/docker
COPY scripts /tmp/scripts
COPY conf /tmp/conf

RUN chmod +x /tmp/scripts/install.sh /tmp/docker/*.sh && /tmp/scripts/install.sh

WORKDIR /data/wwwroot

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

CMD ["php-fpm", "-F"]
