#!/usr/bin/env bash

set -euo pipefail

LOG_DIR="${LOG_DIR:-/tmp/realsense_foxy}"
PID_FILE="${PID_FILE:-$LOG_DIR/realsense.pid}"
ENABLE_COLOR="${ENABLE_COLOR:-true}"
ENABLE_DEPTH="${ENABLE_DEPTH:-true}"
ENABLE_IMU="${ENABLE_IMU:-true}"
ALIGN_DEPTH="${ALIGN_DEPTH:-true}"
SERIAL_NO="${SERIAL_NO:-}"
REALSENSE_USB_ID="${REALSENSE_USB_ID:-8086:0b3a}"
INITIAL_RESET="${INITIAL_RESET:-false}"
DEPTH_PROFILE="${DEPTH_PROFILE:-640,480,15}"
COLOR_PROFILE="${COLOR_PROFILE:-640,480,15}"

mkdir -p "$LOG_DIR"

pkill -f '[r]ealsense2_camera_node' 2>/dev/null || true
pkill -f '[r]os2 launch realsense2_camera' 2>/dev/null || true

set +u
source /opt/ros/foxy/setup.bash
if [ -f "$HOME/nav_ws/install/setup.bash" ]; then
    source "$HOME/nav_ws/install/setup.bash"
fi
set -u

if [ -n "${REALSENSE_RSUSB_PREFIX:-}" ]; then
    export LD_LIBRARY_PATH="$REALSENSE_RSUSB_PREFIX/lib:$REALSENSE_RSUSB_PREFIX/lib/aarch64-linux-gnu:${LD_LIBRARY_PATH:-}"
    export CMAKE_PREFIX_PATH="$REALSENSE_RSUSB_PREFIX:${CMAKE_PREFIX_PATH:-}"
fi

if ! ros2 pkg prefix realsense2_camera >/dev/null 2>&1; then
    echo "Error: ROS 2 Foxy package realsense2_camera is not installed." >&2
    echo "Install it first:" >&2
    echo "  ~/work/nyush_rm_sentry/scripts/install_realsense_foxy.sh" >&2
    exit 1
fi

if ! lsusb | grep -Eqi "$REALSENSE_USB_ID|realsense" \
    && ! udevadm info -q property -n /dev/video0 2>/dev/null | grep -Eqi 'RealSense|ID_MODEL_ID=0b3a'; then
    echo "Error: RealSense device is not visible in lsusb." >&2
    echo "Check USB3 cable/power and run: lsusb -t" >&2
    exit 1
fi

echo ">>> Starting RealSense ROS 2 driver"
echo "    log: $LOG_DIR/realsense.log"
echo "    color=$ENABLE_COLOR depth=$ENABLE_DEPTH imu=$ENABLE_IMU align_depth=$ALIGN_DEPTH initial_reset=$INITIAL_RESET"
if [ -n "${REALSENSE_RSUSB_PREFIX:-}" ]; then
    echo "    librealsense=$REALSENSE_RSUSB_PREFIX"
    ldd /opt/ros/foxy/lib/librealsense2_camera.so | grep realsense || true
fi

args=(
    enable_color:="$ENABLE_COLOR"
    enable_depth:="$ENABLE_DEPTH"
    enable_infra1:=false
    enable_infra2:=false
    enable_fisheye1:=false
    enable_fisheye2:=false
    enable_confidence:=false
    enable_pose:=false
    align_depth.enable:="$ALIGN_DEPTH"
    enable_sync:=false
    pointcloud.enable:=false
    colorizer.enable:=false
    enable_gyro:="$ENABLE_IMU"
    enable_accel:="$ENABLE_IMU"
    unite_imu_method:=2
    initial_reset:="$INITIAL_RESET"
    depth_module.profile:="$DEPTH_PROFILE"
    rgb_camera.profile:="$COLOR_PROFILE"
)
if [ -n "$SERIAL_NO" ]; then
    args+=(serial_no:="'$SERIAL_NO'")
fi

nohup ros2 launch realsense2_camera rs_launch.py "${args[@]}" \
    > "$LOG_DIR/realsense.log" 2>&1 &
echo "$!" > "$PID_FILE"

sleep 6

echo ">>> RealSense topics"
ros2 topic list | grep -E '^/camera|^/tf' | sort || true
echo "    pid: $(cat "$PID_FILE")"

echo
echo "Check rates:"
echo "  timeout 5 ros2 topic hz /camera/color/image_raw"
echo "  timeout 5 ros2 topic hz /camera/depth/image_rect_raw"
echo "  timeout 5 ros2 topic hz /camera/imu"
echo
echo "Stop:"
echo "  pkill -f '[r]ealsense2_camera_node'"
echo "  pkill -f '[r]os2 launch realsense2_camera'"
