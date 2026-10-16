# syntax=docker/dockerfile:1
FROM ubuntu:24.04

ARG TARGETARCH
ARG KASMVNC_VERSION=1.5.0
ARG CLOUDFLARED_VERSION=2026.10.0
ARG WARPSCOUT_VERSION=v0.16.0
ARG PYTHON_VERSION=3.12.13
ARG USER=admin
ARG WORKDIR=/workspace

ENV DEBIAN_FRONTEND=noninteractive \
    USER=${USER} \
    HOME=/home/${USER} \
    WORKDIR=${WORKDIR} \
    DISPLAY=:1 \
    KASMVNC_WEBSOCKET_PORT=8444 \
    PATH=/home/${USER}/.local/bin:${WORKDIR}/.venv/bin:$PATH

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

COPY install.sh /tmp/webtop-install.sh
COPY main.py /tmp/main.py
RUN chmod +x /tmp/webtop-install.sh && /tmp/webtop-install.sh

# locale 生成完成后再设置默认值, 避免构建阶段出现 locale 缺失警告.
ENV LANG=zh_CN.UTF-8 \
    LANGUAGE=zh_CN.UTF-8 \
    LC_ALL=zh_CN.UTF-8

COPY entrypoint.sh /usr/local/bin/webtop-entrypoint
COPY warpscout-proxy /usr/local/bin/warpscout-proxy
RUN chmod 0755 /usr/local/bin/webtop-entrypoint /usr/local/bin/warpscout-proxy

WORKDIR ${WORKDIR}
USER ${USER}
EXPOSE 8444
ENTRYPOINT ["/usr/local/bin/webtop-entrypoint"]
