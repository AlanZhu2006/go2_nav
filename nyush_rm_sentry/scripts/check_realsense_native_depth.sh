#!/usr/bin/env bash

set -euo pipefail

ROOT="${REALSENSE_NATIVE_ROOT:-$HOME/work/realsense_stack_native}"
PREFIX="${REALSENSE_NATIVE_PREFIX:-$ROOT/install}"
SRC="$HOME/work/nyush_rm_sentry/scripts/check_realsense_rsusb_depth_stream.cpp"
BIN="${CHECK_REALSENSE_NATIVE_BIN:-/tmp/check_realsense_native_depth_stream}"

WIDTH="${1:-640}"
HEIGHT="${2:-480}"
FPS="${3:-15}"
FRAMES="${4:-30}"

if [ ! -f "$PREFIX/lib/librealsense2.so" ] && [ ! -f "$PREFIX/lib/aarch64-linux-gnu/librealsense2.so" ]; then
    echo "Error: native librealsense was not found in $PREFIX" >&2
    echo "Build it first: ~/work/nyush_rm_sentry/scripts/build_realsense_native.sh" >&2
    exit 1
fi

pkill -f '[r]ealsense2_camera_node' 2>/dev/null || true
pkill -f '[r]os2 launch realsense2_camera' 2>/dev/null || true

echo ">>> Native RealSense backend"
echo "    prefix: $PREFIX"
echo "    profile: ${WIDTH}x${HEIGHT}@${FPS}"

echo ">>> USB state"
lsusb | grep -Ei '8086|realsense' || true
lsusb -t | sed -n '1,80p'

echo ">>> Native SDK enumerate"
LD_LIBRARY_PATH="$PREFIX/lib:$PREFIX/lib/aarch64-linux-gnu:${LD_LIBRARY_PATH:-}" \
    "$PREFIX/bin/rs-enumerate-devices" -s || true

echo ">>> Building direct depth stream checker"
g++ -std=c++14 -O2 "$SRC" \
    -I"$PREFIX/include" \
    -L"$PREFIX/lib" -L"$PREFIX/lib/aarch64-linux-gnu" \
    -Wl,-rpath,"$PREFIX/lib" \
    -Wl,-rpath,"$PREFIX/lib/aarch64-linux-gnu" \
    -lrealsense2 \
    -o "$BIN"

echo ">>> Direct native depth stream test"
LD_LIBRARY_PATH="$PREFIX/lib:$PREFIX/lib/aarch64-linux-gnu:${LD_LIBRARY_PATH:-}" \
    "$BIN" "$WIDTH" "$HEIGHT" "$FPS" "$FRAMES"
