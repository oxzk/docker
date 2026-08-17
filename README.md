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

HTTP 模式默认使用 OAuth 认证（OAuth 2.1 Authorization Code + PKCE，含 RFC 7591 动态客户端注册）。入口脚本在 `CODING_TOOLS_MCP_OAUTH_PASSWORD` 为空时自动生成授权页密码，MCP 服务日志实时输出到容器日志（`docker logs -f` 可一直查看），授权时输入日志中的密码即可；支持 OAuth 发现的 MCP 客户端访问 HTTPS `/mcp` 地址后会自动完成注册与授权。镜像内置预注册客户端（`CODING_TOOLS_MCP_OAUTH_CLIENT_ID=oxzk-coding-tools-mcp`，`CODING_TOOLS_MCP_OAUTH_CLIENT_SECRET` 为固定默认值，回调默认 `http://127.0.0.1/callback,http://localhost/callback`），client_id 跨容器重启保持稳定，避免动态注册随进程重启失效导致的 `Unknown client_id`。内置 secret 为公开默认值，生产环境务必用 `-e` 覆盖；回调地址需与 MCP 客户端的实际回调完全一致（本地桌面客户端一般用回环地址，云端连接器按其要求填写），不匹配时按客户端实际值覆盖 `CODING_TOOLS_MCP_OAUTH_REDIRECT_URIS`。固定域名时还可设置 `CODING_TOOLS_MCP_SERVER_URL` 固定 OAuth issuer。

如需改用静态 bearer 认证，设置 `CODING_TOOLS_MCP_AUTH_MODE=bearer`：此时若 `CODING_TOOLS_MCP_AUTH_TOKEN` 为空会在启动时自动生成并输出到容器日志，远程 MCP 客户端携带 `Authorization: Bearer <token>` 访问 HTTPS `/mcp` 地址。生产环境建议显式设置并定期轮换 `CODING_TOOLS_MCP_AUTH_TOKEN`。

使用 cloudflared token tunnel（默认仍为 OAuth 认证）:

```bash
docker run --rm -it \
    -p 8765:8765 \
    -v "$PWD:/workspace" \
    -e CLOUDFLARED_TUNNEL_TOKEN='your-cloudflare-tunnel-token' \
    oxzk/coding-tools-mcp
```

如需改用静态 bearer 认证：

```bash
docker run --rm -it \
    -p 8765:8765 \
    -v "$PWD:/workspace" \
    -e CLOUDFLARED_TUNNEL_TOKEN='your-cloudflare-tunnel-token' \
    -e CODING_TOOLS_MCP_AUTH_MODE=bearer \
    -e CODING_TOOLS_MCP_AUTH_TOKEN='your-mcp-bearer-token' \
    oxzk/coding-tools-mcp
```

`CLOUDFLARED_TUNNEL_TOKEN` 只用于 cloudflared named tunnel 连接认证；MCP 侧的认证由 `CODING_TOOLS_MCP_AUTH_MODE` 决定（默认 `oauth`，bearer 模式使用 `CODING_TOOLS_MCP_AUTH_TOKEN`），两者职责不同。入口脚本不会主动输出 cloudflared token。未设置 tunnel token 时，HTTP 模式会自动使用 quick tunnel，并将 `trycloudflare.com` 访问地址输出到容器日志。

环境变量:

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `MCP_MODE` | `http` | `http` 或 `stdio`；stdio 模式不启动 cloudflared |
| `MCP_HOST` | `0.0.0.0` | MCP HTTP 监听地址 |
| `MCP_PORT` | `8765` | MCP HTTP 监听端口 |
| `MCP_WORKSPACE` | `/workspace` | MCP 工作区路径 |
| `CODING_TOOLS_MCP_PERMISSION_MODE` | `trusted` | 上游权限模式；不建议远程使用 `dangerous` |
| `CODING_TOOLS_MCP_AUTH_MODE` | `oauth` | `bearer`、`oauth` 或 `noauth`；`oauth` 模式为空密码时自动生成授权页密码，`bearer` 模式为空 token 时自动生成 |
| `CODING_TOOLS_MCP_OAUTH_PASSWORD` | 自动生成 | OAuth 授权页密码；仅 `oauth` 模式使用，设置后不自动生成 |
| `CODING_TOOLS_MCP_SERVER_URL` | 空 | 固定的公开 origin（不含 `/mcp`），用于固定 OAuth issuer；quick tunnel 时留空由服务端从请求推断 |
| `CODING_TOOLS_MCP_OAUTH_CLIENT_ID` | `oxzk-coding-tools-mcp` | 预注册 OAuth 客户端 ID；固定值跨重启有效，可用 `-e` 覆盖 |
| `CODING_TOOLS_MCP_OAUTH_CLIENT_SECRET` | 内置固定值 | 预注册客户端密钥；为公开默认值，生产环境必须用 `-e` 覆盖 |
| `CODING_TOOLS_MCP_OAUTH_REDIRECT_URIS` | `http://127.0.0.1/callback,http://localhost/callback` | 预注册客户端的回调地址（逗号分隔，需与客户端实际回调完全一致）；本地桌面客户端一般用回环地址，云端连接器按其要求覆盖 |
| `CODING_TOOLS_MCP_AUTH_TOKEN` | 自动生成 | MCP bearer token；仅在 `bearer` 模式使用，设置后通过上游 `--auth-token` 参数传入 |
| `CLOUDFLARED_TUNNEL_TOKEN` | 空 | Cloudflare named tunnel token；设置后优先使用 token tunnel |
| `CLOUDFLARED_TUNNEL_URL` | `http://127.0.0.1:8765` | quick tunnel 的本地转发地址 |

stdio 模式示例:

```bash
docker run --rm -i \
    -e MCP_MODE=stdio \
    -v "$PWD:/workspace" \
    oxzk/coding-tools-mcp
```
