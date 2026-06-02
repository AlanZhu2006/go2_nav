#!/usr/bin/env bash

set -euo pipefail

ROOT="${REALSENSE_RSUSB_ROOT:-$HOME/work/realsense_rsusb}"
PREFIX="${REALSENSE_RSUSB_PREFIX:-$ROOT/install}"

export LD_LIBRARY_PATH="$PREFIX/lib:$PREFIX/lib/aarch64-linux-gnu:${LD_LIBRARY_PATH:-}"

if [ -x "$PREFIX/bin/rs-enumerate-devices" ]; then
    "$PREFIX/bin/rs-enumerate-devices"
else
    echo "Error: $PREFIX/bin/rs-enumerate-devices does not exist." >&2
    echo "Build first: ~/work/nyush_rm_sentry/scripts/build_realsense_rsusb.sh" >&2
    exit 1
fi
