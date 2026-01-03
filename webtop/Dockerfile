FROM ghcr.io/linuxserver/baseimage-kasmvnc:ubuntunoble

# set labels
ARG IMAGE_BUILD_DATE
LABEL maintainer="oxzk"

# branding
ENV LSIO_FIRST_PARTY=false

# title
ENV TITLE="Ubuntu"

# environment settings
ARG DEBIAN_FRONTEND="noninteractive"

# prevent Ubuntu's firefox stub from being installed
COPY /root/etc/apt/preferences.d/mozilla /etc/apt/preferences.d/mozilla

RUN \
  echo "**** add package sources ****" && \
  curl -vSLo \
    /etc/apt/keyrings/packages.mozilla.org.asc \
    https://packages.mozilla.org/apt/repo-signing-key.gpg && \
  echo \
    "deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main" \
    > /etc/apt/sources.list.d/mozilla.list && \
  echo "**** add Google Chrome repository ****" && \
  curl -fsSL https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /etc/apt/keyrings/google-chrome.gpg && \
  echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main" \
    > /etc/apt/sources.list.d/google-chrome.list && \
  echo "**** install packages ****" && \
  apt-get update && \
  apt-get install --no-install-recommends -y \
    dbus-x11 \
    vim \
    wget \
    curl \
    fonts-ubuntu \
    language-pack-en-base \
    language-pack-gnome-en \
    mesa-utils \
    xdg-desktop-portal \
    ubuntu-desktop \
    ubuntu-settings \
    ubuntu-keyring \
    ubuntu-wallpapers \
    yaru-theme-gtk \
    yaru-theme-icon \
    yaru-theme-sound \
    yaru-theme-gnome-shell \
    adwaita-icon-theme \
    gnome-shell \
    gnome-control-center \
    gnome-online-accounts \
    gnome-system-monitor \
    gnome-terminal \
    nautilus \
    nautilus-extension-gnome-terminal \
    firefox \
    google-chrome-stable \
    fonts-noto-cjk \
    fonts-noto-cjk-extra \
    fonts-wqy-zenhei \
    fonts-wqy-microhei \
    language-pack-zh-hans \
    language-pack-gnome-zh-hans && \
  echo "**** remove un-needed packages ****" && \
  apt-get remove -y \
    gnome-power-manager \
    gnome-bluetooth \
    yelp \
    snapd && \
  echo "**** cleanup ****" && \
  apt-get autoclean && \
  rm -rf \
    /config/.cache \
    /config/.launchpadlib \
    /var/lib/apt/lists/* \
    /var/tmp/* \
    /tmp/*

# add local files
COPY /root /

# ports and volumes
EXPOSE 3000
VOLUME /config
