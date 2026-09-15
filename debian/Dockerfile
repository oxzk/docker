FROM debian:bookworm-slim

ENV TZ=Asia/Shanghai \
    LANG=C.UTF-8 \
    LANGUAGE=C.UTF-8 \
    DEBIAN_FRONTEND=noninteractive

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# 构建基础运行环境：证书、网络工具、归档工具、时区与中文 locale。
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        git \
        gzip \
        locales \
        openssl \
        tar \
        tzdata \
        unzip \
        wget \
        xz-utils; \
    printf '%s\n' 'zh_CN.UTF-8 UTF-8' 'en_US.UTF-8 UTF-8' > /etc/locale.gen; \
    locale-gen zh_CN.UTF-8 en_US.UTF-8; \
    update-locale LANG=zh_CN.UTF-8 LANGUAGE=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8; \
    ln -snf "/usr/share/zoneinfo/${TZ}" /etc/localtime; \
    echo "${TZ}" > /etc/timezone; \
    { \
        echo '* soft nproc 65535'; \
        echo '* hard nproc 65535'; \
        echo '* soft nofile 65535'; \
        echo '* hard nofile 65535'; \
    } >> /etc/security/limits.conf; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# locale 生成完成后再切换，避免构建阶段出现 locale 不存在的警告。
ENV LANG=zh_CN.UTF-8 \
    LANGUAGE=zh_CN.UTF-8 \
    LC_ALL=zh_CN.UTF-8

CMD ["bash"]
