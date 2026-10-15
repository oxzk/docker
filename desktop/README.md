# GNOME Desktop 配置

## 环境变量

在 `compose.yml` 同目录创建 `.env`:

```dotenv
PASSWORD=replace-with-your-password
CLOUDFLARED_TOKEN=
KASMVNC_WEBSOCKET_PORT=8444
DESKTOP_WIDTH=1920
DESKTOP_HEIGHT=1080
WARPSCOUT_COUNTRY=US
KRYVA_API_KEY=
KRYVA_API_URL=
```

| 配置 | 默认值 | 用途 |
| --- | --- | --- |
| `PASSWORD` | 必填 | 桌面登录密码, 至少 6 个字符 |
| `CLOUDFLARED_TOKEN` | 空 | Cloudflare Tunnel 令牌 |
| `KASMVNC_WEBSOCKET_PORT` | `8444` | KasmVNC WebSocket 端口 |
| `DESKTOP_WIDTH` | `1920` | 桌面宽度 |
| `DESKTOP_HEIGHT` | `1080` | 桌面高度 |
| `WARPSCOUT_COUNTRY` | `US` | Warpscout 端点国家代码 |
| `KRYVA_API_KEY` | 空 | Kryva API Key |
| `KRYVA_API_URL` | `https://kryva.oozuo.com/` | Kryva API 地址 |

应用配置:

```bash
docker compose up -d desktop
```

## 浏览器参数

```bash
python main.py start --url https://muse.ai --profile muse
python main.py start --url https://muse.ai --profile muse --proxy socks5://127.0.0.1:40000
python main.py backup --profile muse
python main.py restore --profile muse
```

| 参数 | 默认值 | 用途 |
| --- | --- | --- |
| `--url` | `https://muse.ai` | 打开的 URL |
| `--profile` | 空 | `data` 目录中的 profile 名称 |
| `--proxy` | 内置 SOCKS5 代理 | 指定 HTTP, HTTPS 或 SOCKS5 代理地址 |

## 代理验证

```bash
curl --proxy socks5h://127.0.0.1:40000 https://api.ip.sb/geoip
```
