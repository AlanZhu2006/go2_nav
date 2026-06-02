#!/usr/bin/env bash

set -euo pipefail

echo ">>> Installing TigerVNC + lightweight desktop for RViz"
sudo apt update
sudo apt install -y \
    tigervnc-standalone-server \
    tigervnc-common \
    xfce4 \
    xfce4-terminal \
    dbus-x11 \
    x11-xserver-utils \
    mesa-utils

mkdir -p "$HOME/.vnc"

if [ ! -f "$HOME/.vnc/passwd" ]; then
    echo ">>> Creating VNC password"
    vncpasswd
fi

cat > "$HOME/.vnc/xstartup" <<'EOF'
#!/usr/bin/env bash
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS

export XDG_SESSION_TYPE=x11
export LIBGL_ALWAYS_SOFTWARE=1
export QT_X11_NO_MITSHM=1

[ -r "$HOME/.Xresources" ] && xrdb "$HOME/.Xresources"

if command -v startxfce4 >/dev/null 2>&1; then
    exec startxfce4
fi

exec xterm
EOF

chmod +x "$HOME/.vnc/xstartup"

cat <<EOF

TigerVNC is installed.

Start VNC:
  ~/work/nyush_rm_sentry/scripts/start_rviz_vnc.sh

Default display:
  :1

SSH tunnel from your laptop:
  ssh -L 5901:localhost:5901 unitree@<go2-ip>

Then connect your VNC viewer to:
  localhost:5901

EOF
