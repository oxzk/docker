# HF

- 构建镜像: `docker build -t oxzk/hf ./hf`.
- 使用 `PASSWORD` 设置 root SSH 密码, 默认值为 `admin`.
- 在 `FRPC_CONFIG` 和 `FRPC_CONFIG_BASE64` 中必须且只能设置一个.
- 将 `FRPC_CONFIG` 设置为容器内配置文件路径或 HTTP(S) 配置文件地址.
- 将 `FRPC_CONFIG_BASE64` 设置为完整 TOML 配置的标准 Base64 字符串.
- 对 HTTP(S) 地址使用 TOML 配置. 配置下载失败, 解码失败或校验失败时停止启动.
- 通过 `docker logs` 查看 frpc 日志. 任一受监管进程退出时停止容器.

将以下配置保存为 `frpc.toml`, 并替换服务端地址, 端口及认证 token. 在 frps 端允许远程端口 `6000`.

```toml
serverAddr = "frps.example.com"
serverPort = 7000
auth.method = "token"
auth.token = "replace-with-your-token"

[[proxies]]
name = "hf-ssh"
type = "tcp"
localIP = "127.0.0.1"
localPort = 22
remotePort = 6000
```

使用本地文件启动:

```bash
docker run --rm -p 7860:7860 \
    -e PASSWORD='replace-with-your-password' \
    -v "$PWD/frpc.toml:/etc/frp/frpc.toml:ro" \
    -e FRPC_CONFIG=/etc/frp/frpc.toml \
    oxzk/hf
```

使用配置文件地址启动:

```bash
docker run --rm -p 7860:7860 \
    -e PASSWORD='replace-with-your-password' \
    -e FRPC_CONFIG='https://example.com/frpc.toml' \
    oxzk/hf
```

使用 Base64 字符串启动:

```bash
docker run --rm -p 7860:7860 \
    -e PASSWORD='replace-with-your-password' \
    -e FRPC_CONFIG_BASE64="$(base64 < frpc.toml | tr -d '\r\n')" \
    oxzk/hf
```

在 Hugging Face Space 的 Secrets 中设置 `PASSWORD` 和选定的配置变量, 使用 Base64 时粘贴编码结果.

通过 `ssh -p 6000 root@frps.example.com` 连接 SSH. 通过容器端口 `7860` 访问 FastAPI.
