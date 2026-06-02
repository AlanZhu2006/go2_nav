#!/usr/bin/env bash

set -euo pipefail

DISPLAY_NUM="${DISPLAY_NUM:-1}"
RUNTIME_BASE="${XDG_RUNTIME_DIR:-/tmp}"
RUN_DIR="$RUNTIME_BASE/rviz-x11vnc"

pkill -f "[x]11vnc .* -display :$DISPLAY_NUM" 2>/dev/null || true

for name in xfce xvfb; do
    pid_file="$RUN_DIR/$name-$DISPLAY_NUM.pid"
    if [ -f "$pid_file" ]; then
        pid="$(cat "$pid_file" 2>/dev/null || true)"
        if [ -n "$pid" ]; then
            kill "$pid" >/dev/null 2>&1 || true
        fi
        rm -f "$pid_file"
    fi
done
