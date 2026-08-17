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

## coding-tools-mcp

基于上游 [coding-tools-mcp](https://github.com/xyTom/coding-tools-mcp) 构建，提供 Python 3.11 MCP 服务与 cloudflared。镜像默认启动 Streamable HTTP，MCP 端点为 `/mcp`，工作区为 `/workspace`。

构建:

```bash
docker build -t oxzk/coding-tools-mcp ./coding-tools-mcp
```

启动 HTTP MCP 与 cloudflared quick tunnel:

```bash
docker run --rm -it \
    -p 8765:8765 \
    -v "$PWD:/workspace" \
    oxzk/coding-tools-mcp
```

HTTP 模式会默认启动 cloudflared；quick tunnel 的 `https://*.trycloudflare.com` 访问地址会从 cloudflared 日志中解析并输出到容器日志。由于 quick tunnel 会公开服务，生产环境建议使用 Cloudflare named tunnel token。

HTTP 模式默认使用 bearer 认证。入口脚本参考上游 CLI 的 `--auth-token` 参数：如果 `CODING_TOOLS_MCP_AUTH_TOKEN` 为空，会在启动时使用 `openssl rand -hex 32` 自动生成 token，通过 `--auth-token` 传给 MCP，并将一次性 token 输出到容器日志；远程 MCP 客户端应访问 cloudflared 输出的 HTTPS `/mcp` 地址，并携带 `Authorization: Bearer <token>`。生产环境建议显式设置并定期轮换 `CODING_TOOLS_MCP_AUTH_TOKEN`。

使用 cloudflared token tunnel:

```bash
docker run --rm -it \
    -p 8765:8765 \
    -v "$PWD:/workspace" \
    -e CLOUDFLARED_TUNNEL_TOKEN='your-cloudflare-tunnel-token' \
    -e CODING_TOOLS_MCP_AUTH_TOKEN='your-mcp-bearer-token' \
    oxzk/coding-tools-mcp
```

`CLOUDFLARED_TUNNEL_TOKEN` 只用于 cloudflared named tunnel 连接认证；`CODING_TOOLS_MCP_AUTH_TOKEN` 用于 MCP HTTP bearer 认证，两者职责不同。入口脚本不会主动输出 cloudflared token。未设置 tunnel token 时，HTTP 模式会自动使用 quick tunnel，并将 `trycloudflare.com` 访问地址输出到容器日志。

环境变量:

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `MCP_MODE` | `http` | `http` 或 `stdio`；stdio 模式不启动 cloudflared |
| `MCP_HOST` | `0.0.0.0` | MCP HTTP 监听地址 |
| `MCP_PORT` | `8765` | MCP HTTP 监听端口 |
| `MCP_WORKSPACE` | `/workspace` | MCP 工作区路径 |
| `CODING_TOOLS_MCP_PERMISSION_MODE` | `trusted` | 上游权限模式；不建议远程使用 `dangerous` |
| `CODING_TOOLS_MCP_AUTH_MODE` | `bearer` | `bearer`、`oauth` 或 `noauth`；`bearer` 模式为空 token 时自动生成 |
| `CODING_TOOLS_MCP_AUTH_TOKEN` | 自动生成 | MCP bearer token；设置后通过上游 `--auth-token` 参数传入 |
| `CLOUDFLARED_TUNNEL_TOKEN` | 空 | Cloudflare named tunnel token；设置后优先使用 token tunnel |
| `CLOUDFLARED_TUNNEL_URL` | `http://127.0.0.1:8765` | quick tunnel 的本地转发地址 |

stdio 模式示例:

```bash
docker run --rm -i \
    -e MCP_MODE=stdio \
    -v "$PWD:/workspace" \
    oxzk/coding-tools-mcp
```
