#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SENTRY_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RVIZ_DISPLAY="${RVIZ_DISPLAY:-:1}"
RVIZ_CONFIG="${RVIZ_CONFIG:-$SENTRY_ROOT/config/go2_ros2_sdk_mapping.rviz}"
LOG_DIR="${LOG_DIR:-/tmp/go2_ros2_sdk_host_rviz}"
RVIZ_LOG="$LOG_DIR/rviz.log"

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

if [ ! -S "/tmp/.X11-unix/X${RVIZ_DISPLAY#:}" ]; then
    echo "Error: X display $RVIZ_DISPLAY is not available." >&2
    echo "Run: systemctl --user restart rviz-vnc.service" >&2
    exit 1
fi

source_relaxed /opt/ros/foxy/setup.bash
export RMW_IMPLEMENTATION="${RMW_IMPLEMENTATION:-rmw_fastrtps_cpp}"

pkill -f "[r]viz2.*go2_ros2_sdk_mapping.rviz" 2>/dev/null || true

echo ">>> Starting host Foxy RViz for go2_ros2_sdk mapping"
echo "    config:  $RVIZ_CONFIG"
echo "    display: $RVIZ_DISPLAY"
echo "    log:     $RVIZ_LOG"

DISPLAY="$RVIZ_DISPLAY" \
XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}" \
QT_X11_NO_MITSHM=1 \
setsid nohup ros2 run rviz2 rviz2 -d "$RVIZ_CONFIG" \
    > "$RVIZ_LOG" 2>&1 < /dev/null &

echo
echo "RViz is opening in VNC."
echo "Log: $RVIZ_LOG"
