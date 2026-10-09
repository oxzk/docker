#!/usr/bin/env bash
# 在持久化用户总线上配置 Ubuntu GNOME 的远程桌面界面.
set -Eeuo pipefail

gsettings set org.gnome.desktop.interface font-name 'Noto Sans CJK SC 11'
gsettings set org.gnome.desktop.interface document-font-name 'Noto Sans CJK SC 11'
gsettings set org.gnome.desktop.interface monospace-font-name 'Noto Sans Mono CJK SC 12'
gsettings set org.gnome.desktop.interface gtk-theme 'Yaru'
gsettings set org.gnome.desktop.interface icon-theme 'Yaru'
gsettings set org.gnome.desktop.interface enable-animations false
gsettings set org.gnome.desktop.background picture-uri 'file:///usr/share/backgrounds/warty-final-ubuntu.png'
gsettings set org.gnome.desktop.background picture-uri-dark 'file:///usr/share/backgrounds/ubuntu-wallpaper-d.png'
gsettings set org.gnome.desktop.session idle-delay 0
gsettings set org.gnome.desktop.screensaver lock-enabled false
gsettings set org.gnome.desktop.lockdown disable-lock-screen true
gsettings set org.gnome.desktop.lockdown disable-log-out true
gsettings set org.gnome.shell favorite-apps "['org.gnome.Nautilus.desktop', 'org.gnome.Terminal.desktop', 'org.gnome.TextEditor.desktop', 'org.gnome.Settings.desktop']"
xdg-user-dirs-update
