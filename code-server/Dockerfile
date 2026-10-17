# syntax=docker/dockerfile:1
FROM oxzk/debian

ENV SERVER_PORT=9091 \
    SHUTDOWN_TIMEOUT=15 \
    DEBIAN_FRONTEND=noninteractive

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# 软件索引和下载包保留在 BuildKit 缓存挂载中, 不写入最终镜像.
# oxzk/debian 已提供证书, curl, git, tar 和 unzip.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    set -eux; \
    rm -f /etc/apt/apt.conf.d/docker-clean; \
    printf 'Binary::apt::APT::Keep-Downloaded-Packages "true";\n' > /etc/apt/apt.conf.d/keep-cache; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        tini libatomic1 neofetch iproute2 openssh-client procps vim zsh

# 版本参数在同一次安装中传入.
ARG TARGETARCH
ARG GO_VERSION=1.24.3
ARG PYTHON_VERSION=3.12
ARG NVM_VERSION=v0.40.3
ARG NODE_VERSION=22
ENV GOPATH=/root/.local/share/go \
    NVM_DIR=/root/.nvm \
    PATH="/root/.local/bin:/usr/local/go/bin:/root/.local/share/go/bin:${PATH}"

# 一次执行安装脚本, 安装全部工具链.
RUN --mount=type=bind,source=install.sh,target=/build/install.sh \
    --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    bash /build/install.sh

COPY entrypoint.sh /entrypoint.sh
# 登录 shell 读取此文件, 保持其工具路径与容器进程一致.
RUN set -eu; \
    chmod 755 /entrypoint.sh; \
    mkdir -p /workspace; \
    for name in PATH GOPATH NVM_DIR; do \
        printf '%s="%s"\n' "$name" "${!name}"; \
    done >> /etc/environment

WORKDIR /workspace
EXPOSE 9091
ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
