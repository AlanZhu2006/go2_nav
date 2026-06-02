#!/usr/bin/env bash

set -euo pipefail

SRC="$HOME/work/nyush_rm_sentry/scripts/check_realsense_v4l2_depth.cpp"
BIN="${CHECK_REALSENSE_V4L2_BIN:-/tmp/check_realsense_v4l2_depth}"

echo ">>> Building V4L2 direct checker"
g++ -std=c++14 -O2 "$SRC" -o "$BIN"

echo ">>> USB state"
lsusb | grep -Ei '8086|realsense' || true
lsusb -t | sed -n '1,80p'

for dev in /dev/video*; do
    [ -e "$dev" ] || continue
    echo
    echo "===== $dev ====="
    udevadm info -q property -n "$dev" 2>/dev/null | \
        grep -E 'ID_VENDOR_ID|ID_MODEL_ID|ID_SERIAL_SHORT|ID_PATH|ID_V4L_PRODUCT|ID_V4L_CAPABILITIES' || true
    "$BIN" --list "$dev" || true
done
