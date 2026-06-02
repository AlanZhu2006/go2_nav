#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${GO2_CMD_BRIDGE_LOG:-/tmp/go2_cmd_bridge_debug.log}"

ROS_SETUP="${ROS_SETUP:-/opt/ros/foxy/setup.bash}"
NAV_WS_SETUP="${NAV_WS_SETUP:-$HOME/nav_ws/install/setup.bash}"
RM_NAVIGATION_WS_SETUP="${RM_NAVIGATION_WS_SETUP:-$HOME/work/nyush_rm_sentry/rm_navigation_ws/install/setup.bash}"
GO2_CYCLONEDDS_HOME="${GO2_CYCLONEDDS_HOME:-$HOME/cyclonedds/install}"
RMW_IMPLEMENTATION="${GO2_NAV_RMW_IMPLEMENTATION:-rmw_fastrtps_cpp}"
UNITREE_NET_IF="${UNITREE_NET_IF:-eth0}"
UNITREE_SDK2PY_PATH="${UNITREE_SDK2PY_PATH:-/home/unitree/unitree_sdk2_python}"
GO2_CMD_TOPIC="${GO2_CMD_TOPIC:-/cmd_vel}"
GO2_MAX_VX="${GO2_MAX_VX:-0.45}"
GO2_MAX_VY="${GO2_MAX_VY:-0.25}"
GO2_MAX_WZ="${GO2_MAX_WZ:-0.80}"
GO2_X_SIGN="${GO2_X_SIGN:-1.0}"
GO2_Y_SIGN="${GO2_Y_SIGN:-1.0}"
GO2_WZ_SIGN="${GO2_WZ_SIGN:-1.0}"
GO2_SWAP_XY="${GO2_SWAP_XY:-false}"
GO2_DEADBAND_V="${GO2_DEADBAND_V:-0.01}"
GO2_DEADBAND_W="${GO2_DEADBAND_W:-0.02}"
GO2_MIN_CMD_V="${GO2_MIN_CMD_V:-0.0}"
GO2_MIN_CMD_W="${GO2_MIN_CMD_W:-0.0}"
GO2_SEND_ZERO_WHEN_IDLE="${GO2_SEND_ZERO_WHEN_IDLE:-false}"
GO2_REMOTE_PRIORITY="${GO2_REMOTE_PRIORITY:-false}"
GO2_LOG_COMMANDS="${GO2_LOG_COMMANDS:-true}"
GO2_LOG_INTERVAL_SEC="${GO2_LOG_INTERVAL_SEC:-0.2}"

echo ">>> Stopping old Go2 cmd bridge"
pkill -TERM -f "[/]go2_cmd_bridge.py" 2>/dev/null || true
sleep 0.5
pkill -KILL -f "[/]go2_cmd_bridge.py" 2>/dev/null || true

echo ">>> Loading ROS environment"
had_nounset=0
case $- in
    *u*) had_nounset=1; set +u ;;
esac
source "$ROS_SETUP"
if [ -f "$NAV_WS_SETUP" ]; then
    source "$NAV_WS_SETUP"
fi
if [ -f "$RM_NAVIGATION_WS_SETUP" ]; then
    source "$RM_NAVIGATION_WS_SETUP"
fi
if [ "$had_nounset" = "1" ]; then
    set -u
fi
unset had_nounset

unset CYCLONEDDS_URI
export CYCLONEDDS_HOME="$GO2_CYCLONEDDS_HOME"
export LD_LIBRARY_PATH="$GO2_CYCLONEDDS_HOME/lib:${LD_LIBRARY_PATH:-}"
export RMW_IMPLEMENTATION

echo ">>> Starting Go2 cmd bridge debug"
echo "    topic:     $GO2_CMD_TOPIC"
echo "    interface: $UNITREE_NET_IF"
echo "    rmw:       $RMW_IMPLEMENTATION"
echo "    limits:    vx=$GO2_MAX_VX vy=$GO2_MAX_VY wz=$GO2_MAX_WZ"
echo "    mapping:   swap_xy=$GO2_SWAP_XY signs=($GO2_X_SIGN,$GO2_Y_SIGN,$GO2_WZ_SIGN)"
echo "    deadband:  v=$GO2_DEADBAND_V w=$GO2_DEADBAND_W"
echo "    floor:     v=$GO2_MIN_CMD_V w=$GO2_MIN_CMD_W"
echo "    log:       $LOG_FILE"

CYCLONEDDS_HOME="$GO2_CYCLONEDDS_HOME" \
LD_LIBRARY_PATH="$GO2_CYCLONEDDS_HOME/lib:${LD_LIBRARY_PATH:-}" \
RMW_IMPLEMENTATION="$RMW_IMPLEMENTATION" \
UNITREE_NET_IF="$UNITREE_NET_IF" UNITREE_SDK2PY_PATH="$UNITREE_SDK2PY_PATH" \
python3 "$SCRIPT_DIR/go2_cmd_bridge.py" --net-if "$UNITREE_NET_IF" --ros-args \
    -p cmd_vel_topic:="$GO2_CMD_TOPIC" \
    -p max_vx:="$GO2_MAX_VX" \
    -p max_vy:="$GO2_MAX_VY" \
    -p max_wz:="$GO2_MAX_WZ" \
    -p x_sign:="$GO2_X_SIGN" \
    -p y_sign:="$GO2_Y_SIGN" \
    -p wz_sign:="$GO2_WZ_SIGN" \
    -p swap_xy:="$GO2_SWAP_XY" \
    -p deadband_v:="$GO2_DEADBAND_V" \
    -p deadband_w:="$GO2_DEADBAND_W" \
    -p min_cmd_v:="$GO2_MIN_CMD_V" \
    -p min_cmd_w:="$GO2_MIN_CMD_W" \
    -p enabled:=true \
    -p send_zero_when_idle:="$GO2_SEND_ZERO_WHEN_IDLE" \
    -p remote_priority:="$GO2_REMOTE_PRIORITY" \
    -p log_commands:="$GO2_LOG_COMMANDS" \
    -p log_interval_sec:="$GO2_LOG_INTERVAL_SEC" \
    > "$LOG_FILE" 2>&1 &

sleep 1

echo ">>> Bridge process"
pgrep -af "[/]go2_cmd_bridge.py" || true

echo
echo "Keyboard test:"
echo "  cd ~/work/nyush_rm_sentry"
echo "  source /opt/ros/foxy/setup.bash"
echo "  source ~/nav_ws/install/setup.bash"
echo "  source ~/work/nyush_rm_sentry/rm_navigation_ws/install/setup.bash"
echo "  export RMW_IMPLEMENTATION=rmw_fastrtps_cpp"
echo "  ./scripts/keyboard_cmd_vel_debug.py --vx 0.30 --vy 0.16 --wz 0.55 --latch"
echo
echo "Watch bridge output:"
echo "  tail -f $LOG_FILE"
