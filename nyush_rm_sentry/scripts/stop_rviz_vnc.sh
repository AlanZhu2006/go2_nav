#!/usr/bin/env bash

set -euo pipefail

DISPLAY_NUM="${DISPLAY_NUM:-1}"

if ! command -v vncserver >/dev/null 2>&1; then
    echo "vncserver not found; nothing to stop."
    exit 0
fi

vncserver -kill ":$DISPLAY_NUM" || true
