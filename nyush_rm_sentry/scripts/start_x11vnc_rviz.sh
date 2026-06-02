#!/usr/bin/env bash

set -euo pipefail

DISPLAY_NUM="${DISPLAY_NUM:-1}"
VNC_PORT="${VNC_PORT:-5901}"
GEOMETRY="${GEOMETRY:-1920x1080}"
DEPTH="${DEPTH:-24}"
LOCALHOST_ONLY="${LOCALHOST_ONLY:-0}"
PASSWORD_FILE="${PASSWORD_FILE:-$HOME/.vnc/passwd}"

RUNTIME_BASE="${XDG_RUNTIME_DIR:-/tmp}"
RUN_DIR="$RUNTIME_BASE/rviz-x11vnc"
LOG_DIR="$HOME/.vnc"
DISPLAY_NAME=":$DISPLAY_NUM"
XVFB_PID_FILE="$RUN_DIR/xvfb-$DISPLAY_NUM.pid"
XFCE_PID_FILE="$RUN_DIR/xfce-$DISPLAY_NUM.pid"

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Error: $1 is not installed. Run scripts/install_x11vnc_rviz.sh first." >&2
        exit 1
    fi
}

cleanup() {
    local pid
    for pid_file in "$XFCE_PID_FILE" "$XVFB_PID_FILE"; do
        if [ -f "$pid_file" ]; then
            pid="$(cat "$pid_file" 2>/dev/null || true)"
            if [ -n "$pid" ]; then
                kill "$pid" >/dev/null 2>&1 || true
            fi
            rm -f "$pid_file"
        fi
    done
}

require_command Xvfb
require_command x11vnc
require_command startxfce4

if [ ! -f "$PASSWORD_FILE" ]; then
    echo "Error: VNC password file not found: $PASSWORD_FILE" >&2
    echo "Run: x11vnc -storepasswd $PASSWORD_FILE" >&2
    exit 1
fi

mkdir -p "$RUN_DIR" "$LOG_DIR"

trap cleanup EXIT INT TERM

echo ">>> Cleaning stale display $DISPLAY_NAME"
if [ -f "$XVFB_PID_FILE" ]; then
    old_pid="$(cat "$XVFB_PID_FILE" 2>/dev/null || true)"
    [ -z "$old_pid" ] || kill "$old_pid" >/dev/null 2>&1 || true
    rm -f "$XVFB_PID_FILE"
fi

if [ -S "/tmp/.X11-unix/X$DISPLAY_NUM" ]; then
    echo "Error: display $DISPLAY_NAME is already in use." >&2
    echo "Stop the old VNC service or change DISPLAY_NUM." >&2
    exit 1
fi

echo ">>> Starting Xvfb $DISPLAY_NAME ($GEOMETRY, depth $DEPTH)"
Xvfb "$DISPLAY_NAME" \
    -screen 0 "${GEOMETRY}x${DEPTH}" \
    -nolisten tcp \
    >"$LOG_DIR/xvfb-$DISPLAY_NUM.log" 2>&1 &
echo "$!" >"$XVFB_PID_FILE"

for _ in $(seq 1 50); do
    [ -S "/tmp/.X11-unix/X$DISPLAY_NUM" ] && break
    sleep 0.1
done

if [ ! -S "/tmp/.X11-unix/X$DISPLAY_NUM" ]; then
    echo "Error: Xvfb did not create display socket /tmp/.X11-unix/X$DISPLAY_NUM" >&2
    exit 1
fi

export DISPLAY="$DISPLAY_NAME"
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export XDG_SESSION_TYPE=x11
export LIBGL_ALWAYS_SOFTWARE=1
export QT_X11_NO_MITSHM=1

echo ">>> Starting XFCE on $DISPLAY_NAME"
startxfce4 >"$LOG_DIR/xfce-$DISPLAY_NUM.log" 2>&1 &
echo "$!" >"$XFCE_PID_FILE"

listen_args=()
if [ "$LOCALHOST_ONLY" = "1" ]; then
    listen_args=(-localhost)
fi

echo ">>> Starting x11vnc on port $VNC_PORT"
x11vnc \
    -display "$DISPLAY_NAME" \
    -rfbport "$VNC_PORT" \
    -rfbportv6 "$VNC_PORT" \
    -rfbauth "$PASSWORD_FILE" \
    -forever \
    -shared \
    -repeat \
    -xkb \
    -noxdamage \
    -nowf \
    -noscr \
    -no6 \
    -noipv6 \
    "${listen_args[@]}" \
    -o "$LOG_DIR/x11vnc-$DISPLAY_NUM.log"
