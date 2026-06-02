#!/usr/bin/env bash

set -euo pipefail

ROOT="${REALSENSE_RSUSB_ROOT:-$HOME/work/realsense_rsusb}"
PREFIX="${REALSENSE_RSUSB_PREFIX:-$ROOT/install}"
SRC="$HOME/work/nyush_rm_sentry/scripts/check_realsense_rsusb_depth_stream.cpp"
BIN="${CHECK_REALSENSE_BIN:-/tmp/check_realsense_rsusb_depth_stream}"

WIDTH="${1:-424}"
HEIGHT="${2:-240}"
FPS="${3:-6}"
FRAMES="${4:-30}"

if [ ! -f "$PREFIX/lib/librealsense2.so" ]; then
    echo "Error: RSUSB librealsense was not found in $PREFIX" >&2
    exit 1
fi

pkill -f '[r]ealsense2_camera_node' 2>/dev/null || true
pkill -f '[r]os2 launch realsense2_camera' 2>/dev/null || true

g++ -std=c++14 -O2 "$SRC" \
    -I"$PREFIX/include" \
    -L"$PREFIX/lib" \
    -Wl,-rpath,"$PREFIX/lib" \
    -lrealsense2 \
    -o "$BIN"

LD_LIBRARY_PATH="$PREFIX/lib:${LD_LIBRARY_PATH:-}" "$BIN" "$WIDTH" "$HEIGHT" "$FPS" "$FRAMES"
