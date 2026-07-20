# docker

## nginx

构建:

```bash
docker build -t oxzk/nginx ./nginx
```

默认站点目录为 `/data/wwwroot/default`，日志目录为 `/data/wwwlogs`，PHP FastCGI 通过 Unix socket `/tmp/php-cgi.sock` 转发。

目录结构:

```text
nginx/
  Dockerfile
  docker/
    entrypoint.sh
  conf/
    nginx.conf                 # 全局 nginx/http 配置
    conf.d/default.conf        # 默认站点
    snippets/                  # 可复用 PHP、安全、静态缓存片段
    rewrite/                   # 常见框架 rewrite 规则
    examples/ssl-vhost.conf    # HTTPS 站点示例
```

自定义站点推荐挂载到 `/data/nginx/vhost/*.conf`；镜像内也保留 `/usr/local/nginx/conf/vhost/*.conf` include。旧的 `enable-php.conf`、`enable-php-pathinfo.conf`、`pathinfo.conf` 仍可使用，内部已转发到 `snippets/`。

## php

构建:

```bash
docker build -t oxzk/php:7.4 ./php
```

PHP 版本为 `7.4.33`，FPM 以 `www:www` 运行并监听 `/tmp/php-cgi.sock`，编译安装扩展 `amqp`、`imagick`、`mongodb`、`xdebug`、`xlswriter`、`yar`。PHP 编译阶段固定使用 OpenSSL `1.1.1w`，避免 PHP 7.4 与 OpenSSL 3 头文件不兼容。

目录结构:

```text
php/
  Dockerfile
  docker/
    entrypoint.sh              # 启动前根据内存调整 FPM pool
  scripts/
    install.sh                 # 构建 PHP、扩展并清理镜像
  conf/
    php-fpm.conf               # FPM 全局配置
    php-fpm.d/www.conf         # 默认 pool
    conf.d/*.ini               # PHP 扩展配置片段
```

## code-server

构建:

```bash
docker build -t oxzk/code-server ./code-server
```

本地运行并同时暴露 code-server 与 SSH:

```bash
docker run --rm -it \
    -p 9091:9091 \
    -p 2222:22 \
    -e PASSWORD=code001 \
    oxzk/code-server
```

VS Code Remote-SSH 连接:

```sshconfig
Host local-code-server
    HostName 127.0.0.1
    Port 2222
    User root
```

SSH 密码与 code-server Web 登录密码共用 `PASSWORD`.

## camoufox

构建:

```bash
docker build -t oxzk/camoufox ./camoufox
```

本地运行 noVNC:

```bash
docker run --rm -it \
    -e VNC_PASSWORD='change-me' \
    -p 15902:15902 \
    oxzk/camoufox
```

访问:

```text
http://127.0.0.1:15902/
```

默认端口:

| 端口 | 说明 |
| --- | --- |
| `5900` | 容器内部 VNC 端口 |
| `15902` | noVNC Web 入口 |

cloudflared 默认不启动。使用 quick tunnel 映射 noVNC:

```bash
docker run --rm -it \
    -e VNC_PASSWORD='change-me' \
    -e CLOUDFLARED_TUNNEL_ENABLE=1 \
    -e CLOUDFLARED_TUNNEL_URL='http://127.0.0.1:15902' \
    oxzk/camoufox
```

使用 token tunnel:

```bash
docker run --rm -it \
    -e VNC_PASSWORD='change-me' \
    -e CLOUDFLARED_TUNNEL_ENABLE=1 \
    -e CLOUDFLARED_TUNNEL_TOKEN='token' \
    oxzk/camoufox
```

建议始终设置 `VNC_PASSWORD`。未设置时入口脚本会保留无密码 VNC 以兼容本地开发, 并输出警告。
