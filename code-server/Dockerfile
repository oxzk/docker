FROM henry0731/debian

# COPY code-server/docker-entrypoint.sh entrypoint.sh
COPY code-server/install.sh /tmp/install.sh
COPY code-server/market.json /tmp/market.json

RUN apt-get update && apt-get install --no-install-recommends ca-certificates openssh-client procps jq zsh git unzip vim wget curl net-tools iputils-ping neofetch python3 python3.11-venv -y

RUN curl -fsSL https://code-server.dev/install.sh | sh \
    && jq -s '.[0] * .[1]' /tmp/market.json /usr/lib/code-server/lib/vscode/product.json >/tmp/temp.json \
    && cat /tmp/temp.json>/usr/lib/code-server/lib/vscode/product.json \
    && code-server --install-extension ms-python.black-formatter \
    # && code-server --install-extension dbaeumer.vscode-eslint \
    && code-server --install-extension esbenp.prettier-vscode \
    && code-server --install-extension tencent-cloud.coding-copilot \
    && code-server --install-extension dracula-theme.theme-dracula \
    && code-server --install-extension ms-python.python \
    && code-server --install-extension vue.volar \
    code-server --install-extension foxundermoon.shell-format \
    && code-server --install-extension pkief.material-icon-theme \
    && code-server --install-extension k--kato.intellij-idea-keybindings \
    && code-server --install-extension ms-ceintl.vscode-language-pack-zh-hans \
    && echo done

RUN chmod +x /tmp/install.sh && /bin/bash -c '/tmp/install.sh'

ENV PORT=9091
ENV PASSWORD=code001

# ENTRYPOINT ["entrypoint.sh"]

CMD code-server --bind-addr 0.0.0.0:"${PORT}" --app-name code-server --disable-telemetry --auth password /workspace