#!/usr/bin/env bash

set -euo pipefail

DISPLAY_NUM="${DISPLAY_NUM:-1}"
GEOMETRY="${GEOMETRY:-1920x1080}"
DEPTH="${DEPTH:-24}"
LOCALHOST_ONLY="${LOCALHOST_ONLY:-1}"
FOREGROUND="${FOREGROUND:-0}"
SECURITY_TYPES="${SECURITY_TYPES:-VncAuth}"

if ! command -v vncserver >/dev/null 2>&1; then
    echo "Error: vncserver not found. Run scripts/install_tigervnc_rviz.sh first." >&2
    exit 1
fi

mkdir -p "$HOME/.vnc"

if [ ! -f "$HOME/.vnc/passwd" ]; then
    echo "VNC password is not configured. Run:"
    echo "  vncpasswd"
    exit 1
fi

localhost_arg="-localhost yes"
if [ "$LOCALHOST_ONLY" = "0" ]; then
    localhost_arg="-localhost no"
fi

echo ">>> Stopping stale VNC display :$DISPLAY_NUM if present"
vncserver -kill ":$DISPLAY_NUM" >/dev/null 2>&1 || true

echo ">>> Starting TigerVNC :$DISPLAY_NUM ($GEOMETRY, depth $DEPTH)"
vnc_args=(
    ":$DISPLAY_NUM"
    -geometry "$GEOMETRY"
    -depth "$DEPTH"
    -SecurityTypes "$SECURITY_TYPES"
    $localhost_arg
)

if [ "$SECURITY_TYPES" = "None" ]; then
    vnc_args+=(--I-KNOW-THIS-IS-INSECURE)
fi

if [ "$FOREGROUND" = "1" ]; then
    exec vncserver "${vnc_args[@]}" -fg
fi

vncserver "${vnc_args[@]}"

cat <<EOF

VNC is running on display :$DISPLAY_NUM.

Recommended secure connection from your laptop:
  ssh -L 590$DISPLAY_NUM:localhost:590$DISPLAY_NUM unitree@<go2-ip>

Then open a VNC viewer at:
  localhost:590$DISPLAY_NUM

Inside the VNC desktop, open a terminal and run:
  cd ~/work/nyush_rm_sentry
  source scripts/go2_dds_env.sh
  source ~/nav_ws/install/setup.bash
  export LIBGL_ALWAYS_SOFTWARE=1
  rviz2

EOF
