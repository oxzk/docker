# GNOME Desktop

使用 Ubuntu 24.04, GNOME X11, KasmVNC 1.5.0 和 Cloudflared. 使用非 root 用户 `admin` 运行桌面, 使用软件渲染. 不安装 SSH Server, 不要求 privileged 或宿主机 systemd.

## 启动

在本目录创建 `.env`, 设置至少 6 个字符的桌面密码:

```dotenv
PASSWORD=replace-with-your-password
```

执行:

```bash
docker compose up -d --build
docker compose logs -f desktop
```

打开 `http://localhost:8444`, 使用用户名 `admin` 和 `.env` 中的密码登录. Cloudflared 始终启动, 未配置令牌时使用 Quick Tunnel, 从容器日志读取 `https://*.trycloudflare.com` 地址后可直接使用浏览器访问.

默认主机名为 `vm`. 系统用户 `admin` 无密码, 可免密执行 `sudo`. KasmVNC 网页登录仍使用 `.env` 中的 `PASSWORD`.

需要固定域名时在 `.env` 中设置 `CLOUDFLARED_TOKEN`, 在 Cloudflare 控制台将该域名的服务配置为 `http://localhost:8444`.

## 单独构建和运行

在仓库根目录执行:

```bash
docker build -t oxzk/desktop:ubuntu24 ./desktop
docker run -d --name desktop --hostname vm --shm-size=2g \
  -p 127.0.0.1:8444:8444 \
  --env-file ./desktop/.env \
  -v desktop-home:/home/admin \
  oxzk/desktop:ubuntu24
```

保留 `/home/admin` 卷以保存桌面文件和应用配置. 使用绑定目录时将目录所有者设置为 UID/GID 1000. 不要在多个容器间共用同一个桌面卷.

## 配置

| 配置 | 默认值 | 约束 |
| --- | --- | --- |
| `PASSWORD` | 必填 | 至少 6 个字符, 不包含换行 |
| `CLOUDFLARED_TOKEN` | 空 | 为空时创建 Quick Tunnel |
| `KASMVNC_WEBSOCKET_PORT` | `8444` | 修改时同时更新端口映射和受管 Tunnel 配置 |
| `DESKTOP_WIDTH` | `1920` | 1..8192 |
| `DESKTOP_HEIGHT` | `1080` | 1..8192 |

使用构建参数 `KASMVNC_VERSION` 和 `CLOUDFLARED_VERSION` 指定组件版本. 支持 `linux/amd64` 和 `linux/arm64` 对应的官方软件包.

关键服务退出时容器返回非零状态, 由重启策略重新启动. 使用 `docker compose down` 停止服务, 保留数据卷.
