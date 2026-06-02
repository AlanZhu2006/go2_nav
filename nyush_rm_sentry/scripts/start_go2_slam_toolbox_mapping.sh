#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SENTRY_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NAV_WS_ROOT="${NAV_WS_ROOT:-$HOME/nav_ws}"
GO2_DDS_ENV="${GO2_DDS_ENV:-$SCRIPT_DIR/go2_dds_env.sh}"
SLAM_PARAMS_FILE="${SLAM_PARAMS_FILE:-$SENTRY_ROOT/config/go2_slam_toolbox_params.yaml}"
RVIZ_CONFIG="${RVIZ_CONFIG:-$SENTRY_ROOT/config/go2_slam_toolbox.rviz}"
LOG_DIR="${LOG_DIR:-/tmp/go2_slam_toolbox}"
MAP_ROOT="${MAP_ROOT:-$HOME/work/go2_nav/maps}"
STAMP="$(date +%Y%m%d-%H%M%S)"
MAP_DIR="${MAP_DIR:-$MAP_ROOT/go2_slam_toolbox_$STAMP}"
LATEST_LINK="${LATEST_LINK:-$MAP_ROOT/go2_slam_toolbox_latest}"

LIDAR_CLOUD_TOPIC="${LIDAR_CLOUD_TOPIC:-/utlidar/cloud_base}"
RESTAMPED_CLOUD_TOPIC="${RESTAMPED_CLOUD_TOPIC:-/go2_slam/cloud_base}"
RESTAMP_CLOUD_FRAME="${RESTAMP_CLOUD_FRAME:-base_link}"
ODOM_TOPIC="${ODOM_TOPIC:-/utlidar/robot_odom}"
SCAN_TOPIC="${SCAN_TOPIC:-/scan}"
USE_SIM_TIME="${USE_SIM_TIME:-false}"
GO2_LIDAR_STATIC_TF="${GO2_LIDAR_STATIC_TF:-false}"
GO2_LIDAR_TF_PARENT="${GO2_LIDAR_TF_PARENT:-base_link}"
GO2_LIDAR_TF_CHILD="${GO2_LIDAR_TF_CHILD:-utlidar_lidar}"
GO2_LIDAR_TF_X="${GO2_LIDAR_TF_X:-0.28945}"
GO2_LIDAR_TF_Y="${GO2_LIDAR_TF_Y:-0.0}"
GO2_LIDAR_TF_Z="${GO2_LIDAR_TF_Z:--0.046825}"
GO2_LIDAR_TF_YAW="${GO2_LIDAR_TF_YAW:-0.0}"
GO2_LIDAR_TF_PITCH="${GO2_LIDAR_TF_PITCH:-2.8782}"
GO2_LIDAR_TF_ROLL="${GO2_LIDAR_TF_ROLL:-0.0}"
GO2_SCAN_MIN_HEIGHT="${GO2_SCAN_MIN_HEIGHT:--0.40}"
GO2_SCAN_MAX_HEIGHT="${GO2_SCAN_MAX_HEIGHT:-0.10}"
GO2_SCAN_ANGLE_INCREMENT="${GO2_SCAN_ANGLE_INCREMENT:-0.0174533}"
GO2_SCAN_TIME="${GO2_SCAN_TIME:-0.10}"
GO2_SCAN_RANGE_MIN="${GO2_SCAN_RANGE_MIN:-0.20}"
GO2_SCAN_RANGE_MAX="${GO2_SCAN_RANGE_MAX:-10.0}"
GO2_SCAN_TRANSFORM_TOLERANCE="${GO2_SCAN_TRANSFORM_TOLERANCE:-0.2}"

START_RVIZ="${START_RVIZ:-true}"
RVIZ_DISPLAY="${RVIZ_DISPLAY:-:1}"
START_GO2_CMD_BRIDGE="${START_GO2_CMD_BRIDGE:-false}"
UNITREE_NET_IF="${UNITREE_NET_IF:-eth0}"
UNITREE_SDK2PY_PATH="${UNITREE_SDK2PY_PATH:-/home/unitree/unitree_sdk2_python}"
GO2_CMD_TOPIC="${GO2_CMD_TOPIC:-/cmd_vel}"
GO2_MAX_VX="${GO2_MAX_VX:-0.25}"
GO2_MAX_VY="${GO2_MAX_VY:-0.00}"
GO2_MAX_WZ="${GO2_MAX_WZ:-0.45}"

mkdir -p "$LOG_DIR" "$MAP_DIR"

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

kill_matching_processes() {
    local pattern="$1"
    local signal_name="${2:-TERM}"
    pkill "-$signal_name" -f "$pattern" 2>/dev/null || true
}

send_zero_velocity() {
    python3 - "$UNITREE_NET_IF" "$UNITREE_SDK2PY_PATH" <<'PY' || true
import sys
from pathlib import Path

net_if = sys.argv[1]
sdk_path = Path(sys.argv[2]).expanduser()
if sdk_path.exists():
    sys.path.insert(0, str(sdk_path))
try:
    from unitree_sdk2py.core.channel import ChannelFactoryInitialize
    from unitree_sdk2py.go2.sport.sport_client import SportClient
    ChannelFactoryInitialize(0, net_if)
    client = SportClient()
    client.SetTimeout(2.0)
    client.Init()
    client.Move(0.0, 0.0, 0.0)
    client.StopMove()
except Exception:
    pass
PY
}

cleanup() {
    echo
    echo ">>> Stopping Go2 slam_toolbox mapping stack"
    kill $(jobs -p) 2>/dev/null || true
    if [ "$START_GO2_CMD_BRIDGE" = "true" ] || [ "$START_GO2_CMD_BRIDGE" = "1" ]; then
        kill_matching_processes "[/]go2_cmd_bridge.py" TERM
        send_zero_velocity
    fi
}
trap cleanup EXIT INT TERM

wait_for_topic_publisher() {
    local topic="$1"
    local timeout_secs="$2"
    local deadline=$((SECONDS + timeout_secs))
    while [ "$SECONDS" -lt "$deadline" ]; do
        if ros2 topic info "$topic" 2>/dev/null | grep -Eq "Publisher count: [1-9]"; then
            return 0
        fi
        sleep 1
    done
    return 1
}

wait_for_tf() {
    local target_frame="$1"
    local source_frame="$2"
    local timeout_secs="$3"
    python3 - "$target_frame" "$source_frame" "$timeout_secs" <<'PY'
import sys
import time

import rclpy
from rclpy.duration import Duration
from rclpy.node import Node
import tf2_ros

target_frame = sys.argv[1]
source_frame = sys.argv[2]
timeout_secs = float(sys.argv[3])

rclpy.init()
node = Node("go2_slam_wait_for_tf")
buffer = tf2_ros.Buffer()
listener = tf2_ros.TransformListener(buffer, node, spin_thread=False)
deadline = time.time() + timeout_secs
success = False

while time.time() < deadline:
    rclpy.spin_once(node, timeout_sec=0.1)
    try:
        buffer.lookup_transform(target_frame, source_frame, rclpy.time.Time(), timeout=Duration(seconds=0.2))
        success = True
        break
    except Exception:
        time.sleep(0.2)

node.destroy_node()
rclpy.shutdown()
sys.exit(0 if success else 1)
PY
}

save_slam_map() {
    mkdir -p "$MAP_DIR"
    local map_base="$MAP_DIR/map"
    local posegraph_base="$MAP_DIR/posegraph"

    echo
    echo ">>> Saving slam_toolbox map"
    echo "    map:       ${map_base}.{pgm,yaml}"
    echo "    posegraph: ${posegraph_base}.posegraph"

    ros2 run nav2_map_server map_saver_cli \
        -t /map \
        -f "$map_base" \
        --occ 0.65 \
        --free 0.25 \
        --fmt pgm \
        --mode trinary \
        > "$MAP_DIR/map_saver.log" 2>&1 || {
            echo "Error: map_saver_cli failed. Log:" >&2
            cat "$MAP_DIR/map_saver.log" >&2 || true
            return 1
        }

    if ros2 service list | grep -qx "/slam_toolbox/serialize_map"; then
        ros2 service call /slam_toolbox/serialize_map slam_toolbox/srv/SerializePoseGraph \
            "{filename: '$posegraph_base'}" \
            > "$MAP_DIR/serialize_posegraph.log" 2>&1 || true
    fi

    ln -sfn "$MAP_DIR" "$LATEST_LINK"
    echo "Saved map files:"
    ls -lh "$MAP_DIR" || true
    echo
    echo "Latest link:"
    ls -ld "$LATEST_LINK" || true
}

show_status() {
    echo
    echo ">>> Go2 slam_toolbox status"
    ros2 topic list -t | grep -E "^/map|^/scan|^/tf|^/odom|utlidar|slam_toolbox" || true
    echo
    ros2 service list | grep -E "slam_toolbox|map" || true
    echo
    timeout 4 ros2 topic hz "$LIDAR_CLOUD_TOPIC" || true
    timeout 4 ros2 topic hz "$SCAN_TOPIC" || true
    timeout 4 ros2 topic hz /map || true
    echo
    tail -40 "$LOG_DIR/slam_toolbox.log" || true
}

if [ ! -f "$GO2_DDS_ENV" ]; then
    echo "Error: Go2 DDS env script not found: $GO2_DDS_ENV" >&2
    exit 1
fi
if [ ! -f "$SLAM_PARAMS_FILE" ]; then
    echo "Error: slam_toolbox params not found: $SLAM_PARAMS_FILE" >&2
    exit 1
fi
if [ ! -f "$RVIZ_CONFIG" ]; then
    echo "Error: RViz config not found: $RVIZ_CONFIG" >&2
    exit 1
fi

source "$GO2_DDS_ENV"
source_relaxed /opt/ros/foxy/setup.bash
if [ -f "$NAV_WS_ROOT/install/setup.bash" ]; then
    source_relaxed "$NAV_WS_ROOT/install/setup.bash"
fi

export ROS_LOG_DIR="${ROS_LOG_DIR:-$LOG_DIR/ros_logs}"
mkdir -p "$ROS_LOG_DIR"

echo ">>> [0/8] Cleaning old Go2 SLAM processes"
kill_matching_processes "[/]go2_odom_to_tf.py" TERM
kill_matching_processes "[/]restamp_pointcloud2.py" TERM
kill_matching_processes "[p]ointcloud_to_laserscan_node" TERM
kill_matching_processes "[/]async_slam_toolbox_node([[:space:]]|$)" TERM
kill_matching_processes "[/]sync_slam_toolbox_node([[:space:]]|$)" TERM
kill_matching_processes "[/]go2_cmd_bridge.py" TERM
kill_matching_processes "[r]viz2.*go2_slam_toolbox.rviz" TERM
sleep 2

ros2 daemon stop >/dev/null 2>&1 || true
ros2 daemon start >/dev/null 2>&1 || true

echo ">>> [1/8] Starting Go2 built-in lidar services"
"$SCRIPT_DIR/start_go2_lidar_services.py"
"$SCRIPT_DIR/go2_utlidar_switch.py" ON --repeat 5 --interval 0.2

echo ">>> [2/8] Waiting for Go2 odom/cloud topics"
wait_for_topic_publisher "$ODOM_TOPIC" 20 || {
    echo "Error: no publisher for $ODOM_TOPIC" >&2
    exit 1
}
wait_for_topic_publisher "$LIDAR_CLOUD_TOPIC" 20 || {
    echo "Error: no publisher for $LIDAR_CLOUD_TOPIC" >&2
    exit 1
}

echo ">>> [3/8] Starting official odom -> TF bridge"
GO2_ODOM_TOPIC="$ODOM_TOPIC" GO2_TF_PARENT=odom GO2_TF_CHILD=base_link GO2_TF_STAMP_MODE=now GO2_RESTAMPED_ODOM_TOPIC=/odom \
    python3 "$SCRIPT_DIR/go2_odom_to_tf.py" \
    > "$LOG_DIR/go2_odom_to_tf.log" 2>&1 &

wait_for_tf odom base_link 20 || {
    echo "Error: odom -> base_link TF did not appear" >&2
    echo "Check log: $LOG_DIR/go2_odom_to_tf.log" >&2
    exit 1
}

echo ">>> [4/8] Restamping cloud and creating /scan"
if [ "$GO2_LIDAR_STATIC_TF" = "true" ] || [ "$GO2_LIDAR_STATIC_TF" = "1" ]; then
    ros2 run tf2_ros static_transform_publisher \
        "$GO2_LIDAR_TF_X" "$GO2_LIDAR_TF_Y" "$GO2_LIDAR_TF_Z" \
        "$GO2_LIDAR_TF_YAW" "$GO2_LIDAR_TF_PITCH" "$GO2_LIDAR_TF_ROLL" \
        "$GO2_LIDAR_TF_PARENT" "$GO2_LIDAR_TF_CHILD" \
        > "$LOG_DIR/go2_lidar_static_tf.log" 2>&1 &
fi

RESTAMP_CLOUD_INPUT="$LIDAR_CLOUD_TOPIC" RESTAMP_CLOUD_OUTPUT="$RESTAMPED_CLOUD_TOPIC" RESTAMP_CLOUD_FRAME="$RESTAMP_CLOUD_FRAME" \
    python3 "$SCRIPT_DIR/restamp_pointcloud2.py" \
    > "$LOG_DIR/restamp_pointcloud2.log" 2>&1 &

wait_for_topic_publisher "$RESTAMPED_CLOUD_TOPIC" 20 || {
    echo "Error: no publisher for $RESTAMPED_CLOUD_TOPIC" >&2
    echo "Check log: $LOG_DIR/restamp_pointcloud2.log" >&2
    exit 1
}

ros2 run pointcloud_to_laserscan pointcloud_to_laserscan_node --ros-args \
    -r cloud_in:="$RESTAMPED_CLOUD_TOPIC" \
    -r scan:="$SCAN_TOPIC" \
    -p target_frame:=base_link \
    -p transform_tolerance:="$GO2_SCAN_TRANSFORM_TOLERANCE" \
    -p min_height:="$GO2_SCAN_MIN_HEIGHT" \
    -p max_height:="$GO2_SCAN_MAX_HEIGHT" \
    -p angle_min:=-3.14159 \
    -p angle_max:=3.14159 \
    -p angle_increment:="$GO2_SCAN_ANGLE_INCREMENT" \
    -p scan_time:="$GO2_SCAN_TIME" \
    -p range_min:="$GO2_SCAN_RANGE_MIN" \
    -p range_max:="$GO2_SCAN_RANGE_MAX" \
    -p use_inf:=true \
    > "$LOG_DIR/pointcloud_to_laserscan.log" 2>&1 &

wait_for_topic_publisher "$SCAN_TOPIC" 20 || {
    echo "Error: no publisher for $SCAN_TOPIC" >&2
    echo "Check log: $LOG_DIR/pointcloud_to_laserscan.log" >&2
    exit 1
}

echo ">>> [5/8] Starting slam_toolbox online async mapping"
ros2 launch slam_toolbox online_async_launch.py \
    use_sim_time:="$USE_SIM_TIME" \
    params_file:="$SLAM_PARAMS_FILE" \
    > "$LOG_DIR/slam_toolbox.log" 2>&1 &

sleep 5

echo ">>> [6/8] Starting RViz in VNC"
if [ "$START_RVIZ" = "true" ] || [ "$START_RVIZ" = "1" ]; then
    if systemctl --user list-unit-files 2>/dev/null | grep -q '^rviz-vnc.service'; then
        systemctl --user start rviz-vnc.service || true
    fi
    if [ ! -S "/tmp/.X11-unix/X${RVIZ_DISPLAY#:}" ]; then
        echo "Warning: display $RVIZ_DISPLAY is not available; RViz not started." >&2
        echo "         Try: systemctl --user restart rviz-vnc.service" >&2
    else
        DISPLAY="$RVIZ_DISPLAY" \
        XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}" \
        LIBGL_ALWAYS_SOFTWARE=1 \
        QT_X11_NO_MITSHM=1 \
        ros2 run rviz2 rviz2 -d "$RVIZ_CONFIG" \
        > "$LOG_DIR/rviz.log" 2>&1 &
    fi
fi

echo ">>> [7/8] Optional Go2 cmd_vel bridge"
if [ "$START_GO2_CMD_BRIDGE" = "true" ] || [ "$START_GO2_CMD_BRIDGE" = "1" ]; then
    UNITREE_NET_IF="$UNITREE_NET_IF" UNITREE_SDK2PY_PATH="$UNITREE_SDK2PY_PATH" \
    python3 "$SCRIPT_DIR/go2_cmd_bridge.py" --net-if "$UNITREE_NET_IF" --ros-args \
        -p cmd_vel_topic:="$GO2_CMD_TOPIC" \
        -p max_vx:="$GO2_MAX_VX" \
        -p max_vy:="$GO2_MAX_VY" \
        -p max_wz:="$GO2_MAX_WZ" \
        > "$LOG_DIR/go2_cmd_bridge.log" 2>&1 &
else
    echo "    START_GO2_CMD_BRIDGE=false, move the robot manually while mapping."
fi

GO2_IP="$(ip -4 addr show wlan0 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -1)"
if [ -z "$GO2_IP" ]; then
    GO2_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
fi

cat <<EOF

>>> [8/8] Go2 slam_toolbox mapping is running

VNC:
  ${GO2_IP:-<go2-ip>}:5901

Data path:
  $ODOM_TOPIC -> /odom + odom -> base_link
  $LIDAR_CLOUD_TOPIC -> $RESTAMPED_CLOUD_TOPIC -> $SCAN_TOPIC
  slam_toolbox -> /map + map -> odom

Cloud frame:
  restamp frame: $RESTAMP_CLOUD_FRAME
  static TF:     $GO2_LIDAR_STATIC_TF ($GO2_LIDAR_TF_PARENT -> $GO2_LIDAR_TF_CHILD)

Scan slice:
  z:            [$GO2_SCAN_MIN_HEIGHT, $GO2_SCAN_MAX_HEIGHT] in base_link
  angle step:   $GO2_SCAN_ANGLE_INCREMENT rad
  range:        [$GO2_SCAN_RANGE_MIN, $GO2_SCAN_RANGE_MAX] m

Walk the robot slowly through the area.

Controls:
  1 + Enter  save /map to map.pgm/map.yaml and serialize posegraph
  s + Enter  show topic/service/log status
  q + Enter  quit

Output:
  $MAP_DIR

Logs:
  $LOG_DIR

EOF

while true; do
    read -r -p "go2-slam> " cmd
    case "$cmd" in
        1)
            save_slam_map
            ;;
        s|status)
            show_status
            ;;
        q|quit)
            exit 0
            ;;
        *)
            echo "Commands: 1 = save map, s = status, q = quit"
            ;;
    esac
done
