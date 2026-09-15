FROM h4ckf0r0day/obscura:latest AS official

FROM oxzk/debian

ENV DEBIAN_FRONTEND=noninteractive \
    OBSCURA_HOST=0.0.0.0 \
    OBSCURA_PORT=9222 \
    PATH="/usr/local/bin:${PATH}"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# 安装 Noto CJK 中日韩字体.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        fonts-noto-cjk; \
    find /usr/share/fonts/opentype/noto -type f \( -name '*.ttc' -o -name '*.ttf' -o -name '*.otf' -o -name '*.otc' \) \
        | grep -E 'NotoSansCJK|NotoSerifCJK'; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# 使用官网 latest 二进制, 保持 obscura 与 obscura-worker 同目录.
COPY --from=official /obscura /usr/local/bin/obscura
COPY --from=official /obscura-worker /usr/local/bin/obscura-worker

COPY entrypoint.sh /entrypoint.sh

RUN set -eux; \
    chmod 0755 /usr/local/bin/obscura /usr/local/bin/obscura-worker /entrypoint.sh; \
    obscura --version

EXPOSE 9222

ENTRYPOINT ["/entrypoint.sh"]
CMD ["serve"]
