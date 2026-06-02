#!/usr/bin/env bash

set -euo pipefail

ROOT="${REALSENSE_CLEAN_ROOT:-$HOME/work/realsense_stack_clean}"
LOG_DIR="${LOG_DIR:-/tmp/realsense_clean_rsusb}"
PID_FILE="${PID_FILE:-$LOG_DIR/realsense.pid}"
ENABLE_COLOR="${ENABLE_COLOR:-false}"
ENABLE_DEPTH="${ENABLE_DEPTH:-true}"
ENABLE_IMU="${ENABLE_IMU:-false}"
ALIGN_DEPTH="${ALIGN_DEPTH:-false}"
INITIAL_RESET="${INITIAL_RESET:-false}"
DEPTH_PROFILE="${DEPTH_PROFILE:-640,480,15}"
COLOR_PROFILE="${COLOR_PROFILE:-640,480,15}"
SERIAL_NO="${SERIAL_NO:-}"

if [ ! -f "$ROOT/env.sh" ]; then
    echo "Error: clean RealSense stack is not built." >&2
    echo "Build it first:" >&2
    echo "  ~/work/nyush_rm_sentry/scripts/build_realsense_clean_rsusb_foxy.sh" >&2
    exit 1
fi

mkdir -p "$LOG_DIR"

echo ">>> Stopping old RealSense ROS processes"
pkill -f '[r]ealsense2_camera_node' 2>/dev/null || true
pkill -f '[r]os2 launch realsense2_camera' 2>/dev/null || true
sleep 1

set +u
source "$ROOT/env.sh"
set -u

camera_prefix="$(ros2 pkg prefix realsense2_camera)"
camera_lib="$camera_prefix/lib/librealsense2_camera.so"
camera_launch="$(ros2 pkg prefix realsense2_camera)/share/realsense2_camera/launch/rs_launch.py"

if [ ! -f "$camera_launch" ]; then
    echo "Error: clean realsense2_camera launch file not found: $camera_launch" >&2
    exit 1
fi

echo ">>> Clean RealSense stack"
echo "    root:     $ROOT"
echo "    package:  $camera_prefix"
echo "    log:      $LOG_DIR/realsense.log"
echo "    depth:    $ENABLE_DEPTH $DEPTH_PROFILE"
echo "    color:    $ENABLE_COLOR $COLOR_PROFILE"
echo "    imu:      $ENABLE_IMU"
echo "    align:    $ALIGN_DEPTH"

echo ">>> Runtime librealsense"
if [ -f "$camera_lib" ]; then
    ldd "$camera_lib" | grep realsense || true
else
    echo "Warning: camera library not found at $camera_lib"
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

echo ">>> Launching RealSense ROS wrapper"
nohup ros2 launch realsense2_camera rs_launch.py "${args[@]}" \
    > "$LOG_DIR/realsense.log" 2>&1 &
echo "$!" > "$PID_FILE"

sleep 8

if ! ps -p "$(cat "$PID_FILE")" >/dev/null 2>&1; then
    echo "Error: launch process exited early. Log:" >&2
    tail -120 "$LOG_DIR/realsense.log" >&2 || true
    exit 1
fi

echo ">>> Topics"
ros2 topic list | grep -E '^/camera|^/tf' | sort || true
echo "    pid: $(cat "$PID_FILE")"

echo
echo "Check:"
echo "  source $ROOT/env.sh"
echo "  timeout 10 ros2 topic hz /camera/depth/image_rect_raw"
echo "  timeout 10 ros2 topic hz /camera/color/image_raw"
echo "  tail -f $LOG_DIR/realsense.log"
