# syntax=docker/dockerfile:1

FROM ghcr.io/linuxserver/baseimage-selkies:debiantrixie

# set version label
ARG BUILD_DATE
ARG VERSION
ARG CHROME_VERSION
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="thelamer"

# title
ENV TITLE=Chrome \
    PATH="$HOME/.local/bin:$PATH" \
    UV_PYTHON_PREFERENCE=only-managed \
    PYTHONUNBUFFERED=1 \
    PIXELFLUX_WAYLAND=true

RUN \
  echo "**** add icon ****" && \
  curl -o \
    /usr/share/selkies/www/icon.png \
    https://raw.githubusercontent.com/linuxserver/docker-templates/master/linuxserver.io/img/chrome-logo.png && \
  echo "**** setup repo ****" && \
  curl -fsSL \
    https://dl.google.com/linux/linux_signing_key.pub \
    | gpg --dearmor | tee /usr/share/keyrings/google-chrome.gpg >/dev/null && \
  echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main" >> \
    /etc/apt/sources.list.d/google-chrome.list && \
  echo "**** install packages ****" && \
  if [ -z "${CHROME_VERSION+x}" ]; then \
    CHROME_VERSION=$(curl -sX GET http://dl.google.com/linux/chrome/deb/dists/stable/main/binary-amd64/Packages | grep -A 7 -m 1 'Package: google-chrome-stable' | awk -F ': ' '/Version/{print $2;exit}'); \
  fi && \
  apt-get update && \
  apt-get install -y --no-install-recommends wget \
    google-chrome-stable=${CHROME_VERSION} && \
  curl -LsSf https://astral.sh/uv/install.sh | sh && \
  uv python install 3.11 && \
  wget -q https://github.com/fatedier/frp/releases/download/v0.68.0/frp_0.68.0_linux_amd64.tar.gz -O /tmp/frp.tar.gz && \
  tar -xzf /tmp/frp.tar.gz -C /tmp/ \
  mv /tmp/frp_*/frpc /usr/local/bin/frpc && \
  echo "**** cleanup ****" && \
  apt-get autoclean && \
  mkdir -p /app/user_data && \
  rm -rf \
    /config/.cache \
    /var/lib/apt/lists/* \
    /var/tmp/* \
    /tmp/*

# add local files
COPY docker-chrome/root /

# ports and volumes
EXPOSE 3000

VOLUME /config
