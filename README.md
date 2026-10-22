# docker

## coding-tools-mcp

```bash
docker build -t oxzk/coding-tools-mcp ./coding-tools-mcp
```

```bash
# HTTP + quick tunnel（默认 OAuth 认证，授权密码见容器日志）
docker run --rm -it -p 8765:8765 -v "$PWD:/workspace" oxzk/coding-tools-mcp

# HTTP + named tunnel + bearer 认证
docker run --rm -it -p 8765:8765 -v "$PWD:/workspace" \
    -e CLOUDFLARED_TUNNEL_TOKEN='your-cloudflare-tunnel-token' \
    -e CODING_TOOLS_MCP_AUTH_MODE=bearer \
    -e CODING_TOOLS_MCP_AUTH_TOKEN='your-mcp-bearer-token' \
    oxzk/coding-tools-mcp

# stdio
docker run --rm -i -e MCP_MODE=stdio -v "$PWD:/workspace" oxzk/coding-tools-mcp
```

MCP 端点为 HTTPS `/mcp`.

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `MCP_MODE` | `http` | `http` 或 `stdio`；stdio 模式不启动 cloudflared |
| `MCP_HOST` | `0.0.0.0` | MCP HTTP 监听地址 |
| `MCP_PORT` | `8765` | MCP HTTP 监听端口 |
| `MCP_WORKSPACE` | `/workspace` | MCP 工作区路径 |
| `CODING_TOOLS_MCP_PERMISSION_MODE` | `trusted` | 上游权限模式；不建议远程使用 `dangerous` |
| `CODING_TOOLS_MCP_AUTH_MODE` | `oauth` | `bearer`、`oauth` 或 `noauth`；空密码/token 时自动生成并输出到容器日志 |
| `CODING_TOOLS_MCP_OAUTH_PASSWORD` | 自动生成 | OAuth 授权页密码 |
| `CODING_TOOLS_MCP_SERVER_URL` | 空 | 固定公开 origin（不含 `/mcp`），用于固定 OAuth issuer |
| `CODING_TOOLS_MCP_OAUTH_CLIENT_ID` | `oxzk-coding-tools-mcp` | 预注册 OAuth 客户端 ID |
| `CODING_TOOLS_MCP_OAUTH_CLIENT_SECRET` | 内置固定值 | 预注册客户端密钥；生产环境必须覆盖 |
| `CODING_TOOLS_MCP_OAUTH_REDIRECT_URIS` | `http://127.0.0.1/callback,http://localhost/callback` | 回调地址，逗号分隔，需与客户端实际回调一致 |
| `CODING_TOOLS_MCP_OAUTH_TOKEN_SECRET` | 自动生成 | OAuth access token 签名密钥，hex 编码且至少 32 字节；固定后重启不会使 token 失效 |
| `CODING_TOOLS_MCP_OAUTH_TOKEN_TTL` | `86400` | OAuth access token 有效期（秒，60–604800） |
| `CODING_TOOLS_MCP_AUTH_TOKEN` | 自动生成 | bearer token；仅 `bearer` 模式使用 |
| `CLOUDFLARED_TUNNEL_TOKEN` | 空 | named tunnel token；设置后优先于 quick tunnel |
| `CLOUDFLARED_TUNNEL_URL` | `http://127.0.0.1:8765` | quick tunnel 的本地转发地址 |

## webtop

```bash
cd webtop
docker compose up -d --build
docker compose logs -f webtop   # 查看启动状态与 trycloudflare.com 地址
```

访问 `http://127.0.0.1:8444`.

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `CLOUDFLARED_TOKEN` | 空 | named tunnel token；为空时使用 quick tunnel |
| `PASSWORD` | 空 | KasmVNC Web Basic Auth 密码；为空时关闭认证直接进入桌面 |
| `WARPSCOUT_COUNTRY` | `US` | Warpscout SOCKS5 代理国家 |

