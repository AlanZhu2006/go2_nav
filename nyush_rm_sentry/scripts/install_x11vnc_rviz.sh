#!/usr/bin/env bash

set -euo pipefail

echo ">>> Installing x11vnc + Xvfb + lightweight desktop for RViz"
sudo apt update
sudo apt install -y \
    x11vnc \
    xvfb \
    xfce4 \
    xfce4-terminal \
    dbus-x11 \
    x11-xserver-utils \
    mesa-utils

mkdir -p "$HOME/.vnc"

if [ ! -f "$HOME/.vnc/passwd" ]; then
    echo ">>> Creating VNC password for x11vnc"
    x11vnc -storepasswd "$HOME/.vnc/passwd"
fi

chmod 600 "$HOME/.vnc/passwd"

cat <<EOF

x11vnc RViz desktop dependencies are installed.

Enable/start the systemd user service:
  ~/work/nyush_rm_sentry/scripts/install_rviz_vnc_autostart.sh

Connect from your laptop:
  VNC viewer -> <go2-wlan0-ip>:5901

EOF
