#!/usr/bin/env bash

set -euo pipefail

ROOT="${REALSENSE_CLEAN_ROOT:-$HOME/work/realsense_stack_clean}"

if [ ! -f "$ROOT/env.sh" ]; then
    echo "Error: clean RealSense stack is not built." >&2
    exit 1
fi

set +u
source "$ROOT/env.sh"
set -u

echo "ROS package:"
ros2 pkg prefix realsense2_camera

echo
echo "librealsense linked by clean wrapper:"
ldd "$(ros2 pkg prefix realsense2_camera)/lib/librealsense2_camera.so" | grep realsense || true

echo
echo "SDK enumeration:"
"$REALSENSE_RSUSB_PREFIX/bin/rs-enumerate-devices" -s
