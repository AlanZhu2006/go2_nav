#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SENTRY_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SERVICE_SRC="$SENTRY_ROOT/systemd/user/rviz-vnc.service"
SERVICE_DST="$HOME/.config/systemd/user/rviz-vnc.service"

if [ ! -f "$SERVICE_SRC" ]; then
    echo "Error: service template not found: $SERVICE_SRC" >&2
    exit 1
fi

if ! command -v x11vnc >/dev/null 2>&1 || ! command -v Xvfb >/dev/null 2>&1; then
    echo "Error: x11vnc or Xvfb is not installed." >&2
    echo "Run first:" >&2
    echo "  $SENTRY_ROOT/scripts/install_x11vnc_rviz.sh" >&2
    exit 1
fi

if [ ! -f "$HOME/.vnc/passwd" ]; then
    echo "Error: VNC password is not configured." >&2
    echo "Run first:" >&2
    echo "  x11vnc -storepasswd $HOME/.vnc/passwd" >&2
    exit 1
fi

mkdir -p "$HOME/.config/systemd/user"
cp "$SERVICE_SRC" "$SERVICE_DST"

systemctl --user daemon-reload
systemctl --user enable rviz-vnc.service
systemctl --user restart rviz-vnc.service

cat <<EOF

rviz-vnc.service is enabled and started for this user using x11vnc.

Check status:
  systemctl --user status rviz-vnc.service

Connect from your laptop:
  VNC viewer -> $(hostname -I | awk '{print $1}'):5901

If you specifically want wlan0:
  ip -4 addr show wlan0
  VNC viewer -> <wlan0-ip>:5901

Important: user services only start at boot before login if linger is enabled.
Run once with sudo password:
  sudo loginctl enable-linger "$USER"

EOF
