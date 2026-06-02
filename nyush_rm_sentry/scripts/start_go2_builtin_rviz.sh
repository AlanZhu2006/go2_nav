#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SENTRY_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GO2_DDS_ENV="${GO2_DDS_ENV:-$SCRIPT_DIR/go2_dds_env.sh}"
RVIZ_DISPLAY="${RVIZ_DISPLAY:-:1}"
RVIZ_CONFIG="${RVIZ_CONFIG:-$SENTRY_ROOT/config/go2_builtin_lidar.rviz}"
LOG_DIR="${LOG_DIR:-/tmp/go2_builtin_rviz}"
RVIZ_LOG="$LOG_DIR/rviz.log"
RVIZ_PID_FILE="$LOG_DIR/rviz.pid"
ODOM_TF_LOG="$LOG_DIR/odom_to_tf.log"
ODOM_TF_PID_FILE="$LOG_DIR/odom_to_tf.pid"

mkdir -p "$LOG_DIR"

source_relaxed() {
    local setup_file="$1"
    local had_nounset=0
    case $- in
        *u*) had_nounset=1; set +u ;;
    esac
    source "$setup_file"
    if [ "$had_nounset" = "1" ]; then
        set -u
    fi
}

if ! systemctl --user --quiet is-active rviz-vnc.service; then
    echo ">>> Starting RViz VNC service"
    systemctl --user start rviz-vnc.service
fi

if [ ! -S "/tmp/.X11-unix/X${RVIZ_DISPLAY#:}" ]; then
    echo "Error: X display $RVIZ_DISPLAY is not available." >&2
    echo "Run: systemctl --user restart rviz-vnc.service" >&2
    exit 1
fi

if [ ! -f "$GO2_DDS_ENV" ]; then
    echo "Error: Go2 DDS env script not found: $GO2_DDS_ENV" >&2
    exit 1
fi

source "$GO2_DDS_ENV"
source_relaxed /opt/ros/foxy/setup.bash

pkill -f "[r]viz2.*go2_builtin_lidar.rviz" 2>/dev/null || true
pkill -f "[g]o2_odom_to_tf.py" 2>/dev/null || true

echo ">>> Starting odom->TF bridge"
echo "    odom:    ${GO2_ODOM_TOPIC:-/utlidar/robot_odom}"
echo "    tf:      ${GO2_TF_PARENT:-odom} -> ${GO2_TF_CHILD:-base_link}"
echo "    log:     $ODOM_TF_LOG"

setsid nohup python3 "$SCRIPT_DIR/go2_odom_to_tf.py" \
    > "$ODOM_TF_LOG" 2>&1 < /dev/null &

echo "$!" > "$ODOM_TF_PID_FILE"

echo ">>> Starting RViz for Go2 built-in lidar"
echo "    config:  $RVIZ_CONFIG"
echo "    display: $RVIZ_DISPLAY"
echo "    log:     $RVIZ_LOG"

DISPLAY="$RVIZ_DISPLAY" \
XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}" \
LIBGL_ALWAYS_SOFTWARE=1 \
QT_X11_NO_MITSHM=1 \
setsid nohup ros2 run rviz2 rviz2 -d "$RVIZ_CONFIG" \
    > "$RVIZ_LOG" 2>&1 < /dev/null &

echo "$!" > "$RVIZ_PID_FILE"

cat <<EOF

RViz is opening in VNC.

Connect:
  10.209.69.61:5901

Watching official Go2 topics:
  /utlidar/cloud_base
  /utlidar/cloud_deskewed
  /utlidar/robot_odom
  /uslam/cloud_map

TF bridge:
  /utlidar/robot_odom -> /tf
  log: $ODOM_TF_LOG

EOF
