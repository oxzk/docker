# 使用官方 Python Slim 镜像减少体积
FROM python:3.11-slim

# 设置环境变量
ENV TZ=Asia/Shanghai \
    DISPLAY=:99 \
    LANG=zh_CN.UTF-8 \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    DEBIAN_FRONTEND=noninteractive \
    XVFB_WHD=1920x1080x24 \
    VNC_PORT=5900 \
    NOVNC_PORT=31110

# 1. 替换国内源 + 安装核心组件
# xvfb: 虚拟显示器 | fluxbox: 窗口管理 | chromium: 浏览器 | fonts-wqy-microhei: 中文字体
RUN apt-get update && apt-get install -y --no-install-recommends git net-tools procps vim xvfb fluxbox fonts-noto-cjk locales curl x11vnc iproute2 dnsutils dbus wget \
    && sed -i -e 's/# zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen \
    && sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen  \
    && locale-gen zh_CN.UTF-8 \
    && locale-gen en_US.UTF-8 \
    && update-locale LANG=zh_CN.UTF-8 LANGUAGE=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8 \
    && rm -rf /etc/localtime \
    && ln -sf /usr/share/zoneinfo/${TZ} /etc/localtime \
    && pip install --no-cache-dir DrissionPage playwright websockify curl_cffi ddddocr pillow opencv-python-headless \
    && playwright install --with-deps chromium \
    && mkdir -p /opt/noVNC \
    && curl -fsSL https://github.com/novnc/noVNC/archive/refs/tags/v1.4.0.tar.gz | tar -xz --strip-components=1 -C /opt/noVNC \
    && wget -q https://github.com/fatedier/frp/releases/download/v0.68.0/frp_0.68.0_linux_amd64.tar.gz -O /tmp/frp.tar.gz \
    && tar -xzf /tmp/frp.tar.gz -C /tmp/ \
    && mv /tmp/frp_*/frpc /usr/local/bin/frpc \
    && rm -rf /tmp/frp* \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

WORKDIR /app

# 3. 创建持久化用户数据目录 (用于保存 Cookie 和登录状态)
RUN mkdir -p /app/user_data

# 4. 复制启动脚本并授权
COPY chrome/entrypoint.sh /entrypoint.sh
COPY chrome/frpc.toml /etc/frpc.toml
COPY chrome/mihomo /usr/local/bin/mihomo
RUN chmod +x /entrypoint.sh /usr/local/bin/mihomo

# 暴露端口
EXPOSE 9222 5900 16080

ENTRYPOINT ["/entrypoint.sh"]

# CMD ["python"]