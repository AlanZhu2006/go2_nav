#!/usr/bin/env bash

set -euo pipefail

ROOT="${REALSENSE_RSUSB_ROOT:-$HOME/work/realsense_rsusb}"
PREFIX="${REALSENSE_RSUSB_PREFIX:-$ROOT/install}"

if [ ! -f "$PREFIX/lib/librealsense2.so" ] && [ ! -f "$PREFIX/lib/aarch64-linux-gnu/librealsense2.so" ]; then
    echo "Error: RSUSB librealsense was not found in $PREFIX." >&2
    echo "Build it first:" >&2
    echo "  ~/work/nyush_rm_sentry/scripts/build_realsense_rsusb.sh" >&2
    exit 1
fi

export LD_LIBRARY_PATH="$PREFIX/lib:$PREFIX/lib/aarch64-linux-gnu:${LD_LIBRARY_PATH:-}"
export CMAKE_PREFIX_PATH="$PREFIX:${CMAKE_PREFIX_PATH:-}"
export REALSENSE_RSUSB_PREFIX="$PREFIX"

echo ">>> Using RSUSB librealsense:"
ldd /opt/ros/foxy/lib/realsense2_camera/realsense2_camera_node | grep realsense || true

exec "$HOME/work/nyush_rm_sentry/scripts/start_realsense_foxy.sh" "$@"
