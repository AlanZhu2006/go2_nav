#!/usr/bin/env bash

set -euo pipefail

SRC="$HOME/work/nyush_rm_sentry/scripts/check_realsense_v4l2_depth.cpp"
BIN="${CHECK_REALSENSE_V4L2_BIN:-/tmp/check_realsense_v4l2_depth}"

DEVICE="${1:-/dev/video0}"
WIDTH="${2:-640}"
HEIGHT="${3:-480}"
FPS="${4:-15}"
FRAMES="${5:-100}"
FOURCC="${6:-Z16}"

pkill -f '[r]ealsense2_camera_node' 2>/dev/null || true
pkill -f '[r]os2 launch realsense2_camera' 2>/dev/null || true

echo ">>> Building V4L2 direct checker"
g++ -std=c++14 -O2 "$SRC" -o "$BIN"

echo ">>> USB state"
lsusb | grep -Ei '8086|realsense' || true
lsusb -t | sed -n '1,80p'

echo ">>> Device properties"
udevadm info -q property -n "$DEVICE" 2>/dev/null | \
    grep -E 'ID_VENDOR_ID|ID_MODEL_ID|ID_SERIAL_SHORT|ID_PATH|ID_V4L_PRODUCT|ID_V4L_CAPABILITIES' || true

echo ">>> V4L2 direct stream test"
"$BIN" "$DEVICE" "$WIDTH" "$HEIGHT" "$FPS" "$FRAMES" "$FOURCC"
