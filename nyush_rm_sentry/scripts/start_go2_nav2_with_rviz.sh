#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SENTRY_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NAV_WS_ROOT="${NAV_WS_ROOT:-$HOME/nav_ws}"
GO2_DDS_ENV="${GO2_DDS_ENV:-$SCRIPT_DIR/go2_dds_env.sh}"
if [ -z "${MAP_FILE:-}" ]; then
    if [ -f "$HOME/work/go2_nav/maps/go2_slam_toolbox_latest/map.yaml" ]; then
        MAP_FILE="$HOME/work/go2_nav/maps/go2_slam_toolbox_latest/map.yaml"
    else
        MAP_FILE="$HOME/work/go2_nav/maps/go2_pointlio_latest/nav2_map/map.yaml"
    fi
fi
NAV2_PARAMS_FILE="${NAV2_PARAMS_FILE:-$SENTRY_ROOT/config/go2_nav2_params.yaml}"
LOG_DIR="${LOG_DIR:-/tmp/go2_nav2}"
USE_SIM_TIME="${USE_SIM_TIME:-false}"
AUTOSTART="${AUTOSTART:-true}"

START_RVIZ="${START_RVIZ:-true}"
RVIZ_DISPLAY="${RVIZ_DISPLAY:-:1}"
RVIZ_CONFIG="${RVIZ_CONFIG:-/opt/ros/foxy/share/nav2_bringup/rviz/nav2_default_view.rviz}"

START_GO2_CMD_BRIDGE="${START_GO2_CMD_BRIDGE:-false}"
UNITREE_NET_IF="${UNITREE_NET_IF:-eth0}"
UNITREE_SDK2PY_PATH="${UNITREE_SDK2PY_PATH:-/home/unitree/unitree_sdk2_python}"
GO2_CMD_TOPIC="${GO2_CMD_TOPIC:-/cmd_vel}"
GO2_MAX_VX="${GO2_MAX_VX:-0.30}"
GO2_MAX_VY="${GO2_MAX_VY:-0.00}"
GO2_MAX_WZ="${GO2_MAX_WZ:-0.55}"

LIDAR_CLOUD_TOPIC="${LIDAR_CLOUD_TOPIC:-/utlidar/cloud_base}"
RESTAMPED_CLOUD_TOPIC="${RESTAMPED_CLOUD_TOPIC:-/go2_nav/cloud_base}"
RESTAMP_CLOUD_FRAME="${RESTAMP_CLOUD_FRAME:-base_link}"
ODOM_TOPIC="${ODOM_TOPIC:-/utlidar/robot_odom}"
SCAN_TOPIC="${SCAN_TOPIC:-/scan}"
GO2_LIDAR_STATIC_TF="${GO2_LIDAR_STATIC_TF:-false}"
GO2_LIDAR_TF_PARENT="${GO2_LIDAR_TF_PARENT:-base_link}"
GO2_LIDAR_TF_CHILD="${GO2_LIDAR_TF_CHILD:-utlidar_lidar}"
GO2_LIDAR_TF_X="${GO2_LIDAR_TF_X:-0.28945}"
GO2_LIDAR_TF_Y="${GO2_LIDAR_TF_Y:-0.0}"
GO2_LIDAR_TF_Z="${GO2_LIDAR_TF_Z:--0.046825}"
GO2_LIDAR_TF_YAW="${GO2_LIDAR_TF_YAW:-0.0}"
GO2_LIDAR_TF_PITCH="${GO2_LIDAR_TF_PITCH:-2.8782}"
GO2_LIDAR_TF_ROLL="${GO2_LIDAR_TF_ROLL:-0.0}"
SCAN_MIN_HEIGHT="${SCAN_MIN_HEIGHT:-${GO2_SCAN_MIN_HEIGHT:--0.40}}"
SCAN_MAX_HEIGHT="${SCAN_MAX_HEIGHT:-${GO2_SCAN_MAX_HEIGHT:-0.10}}"
SCAN_ANGLE_INCREMENT="${SCAN_ANGLE_INCREMENT:-${GO2_SCAN_ANGLE_INCREMENT:-0.0174533}}"
SCAN_TIME="${SCAN_TIME:-${GO2_SCAN_TIME:-0.10}}"
SCAN_RANGE_MIN="${SCAN_RANGE_MIN:-${GO2_SCAN_RANGE_MIN:-0.20}}"
SCAN_RANGE_MAX="${SCAN_RANGE_MAX:-${GO2_SCAN_RANGE_MAX:-10.0}}"
SCAN_TRANSFORM_TOLERANCE="${SCAN_TRANSFORM_TOLERANCE:-${GO2_SCAN_TRANSFORM_TOLERANCE:-0.2}}"
INITIAL_POSE_X="${INITIAL_POSE_X:-0.0}"
INITIAL_POSE_Y="${INITIAL_POSE_Y:-0.0}"
INITIAL_POSE_YAW="${INITIAL_POSE_YAW:-0.0}"
PUBLISH_INITIAL_POSE="${PUBLISH_INITIAL_POSE:-true}"

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

kill_matching_processes() {
    local pattern="$1"
    local signal_name="${2:-TERM}"
    pkill "-$signal_name" -f "$pattern" 2>/dev/null || true
}

cleanup() {
    echo
    echo ">>> Stopping Go2 Nav2 stack"
    kill $(jobs -p) 2>/dev/null || true
    kill_matching_processes "[/]go2_cmd_bridge.py" TERM
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
node = Node("go2_nav2_wait_for_tf")
buffer = tf2_ros.Buffer()
listener = tf2_ros.TransformListener(buffer, node, spin_thread=False)
deadline = time.time() + timeout_secs
success = False

while time.time() < deadline:
    rclpy.spin_once(node, timeout_sec=0.1)
    try:
        buffer.lookup_transform(
            target_frame,
            source_frame,
            rclpy.time.Time(),
            timeout=Duration(seconds=0.2),
        )
        success = True
        break
    except Exception:
        time.sleep(0.2)

node.destroy_node()
rclpy.shutdown()
sys.exit(0 if success else 1)
PY
}

publish_initial_pose() {
    local initial_pose_msg
    initial_pose_msg="$(python3 - "$INITIAL_POSE_X" "$INITIAL_POSE_Y" "$INITIAL_POSE_YAW" <<'PY'
import math
import sys

x = float(sys.argv[1])
y = float(sys.argv[2])
yaw = float(sys.argv[3])
qz = math.sin(yaw * 0.5)
qw = math.cos(yaw * 0.5)
cov = [0.0] * 36
cov[0] = 0.25
cov[7] = 0.25
cov[35] = 0.06853891945200942
print(
    "{header: {stamp: {sec: 0, nanosec: 0}, frame_id: 'map'}, pose: {pose: {position: {x: %.4f, y: %.4f, z: 0.0}, orientation: {x: 0.0, y: 0.0, z: %.8f, w: %.8f}}, covariance: [%s]}}"
    % (x, y, qz, qw, ", ".join(str(value) for value in cov))
)
PY
)"
    ros2 topic pub -1 /initialpose geometry_msgs/msg/PoseWithCovarianceStamped "$initial_pose_msg"
}

if [ ! -f "$GO2_DDS_ENV" ]; then
    echo "Error: Go2 DDS env script not found: $GO2_DDS_ENV" >&2
    exit 1
fi
if [ ! -f "$MAP_FILE" ]; then
    echo "Error: Nav2 map not found: $MAP_FILE" >&2
    echo "Build a map first: ./scripts/start_go2_slam_toolbox_mapping.sh" >&2
    exit 1
fi
if [ ! -f "$NAV2_PARAMS_FILE" ]; then
    echo "Error: Nav2 params not found: $NAV2_PARAMS_FILE" >&2
    exit 1
fi

source "$GO2_DDS_ENV"
if [ -f "$NAV_WS_ROOT/install/setup.bash" ]; then
    source_relaxed "$NAV_WS_ROOT/install/setup.bash"
fi
if [ -f "$SENTRY_ROOT/rm_navigation_ws/install/setup.bash" ]; then
    source_relaxed "$SENTRY_ROOT/rm_navigation_ws/install/setup.bash"
fi

export ROS_LOG_DIR="${ROS_LOG_DIR:-$LOG_DIR/ros_logs}"
mkdir -p "$ROS_LOG_DIR"

echo ">>> [0/9] Cleaning old Go2 navigation processes"
kill_matching_processes "[/]pointlio_mapping([[:space:]]|$)" INT
kill_matching_processes "[p]ointcloud_to_laserscan_node" TERM
kill_matching_processes "[/]go2_odom_to_tf.py" TERM
kill_matching_processes "[/]restamp_pointcloud2.py" TERM
kill_matching_processes "[/]go2_cmd_bridge.py" TERM
kill_matching_processes "[/]controller_server([[:space:]]|$)" TERM
kill_matching_processes "[/]planner_server([[:space:]]|$)" TERM
kill_matching_processes "[/]recoveries_server([[:space:]]|$)" TERM
kill_matching_processes "[/]bt_navigator([[:space:]]|$)" TERM
kill_matching_processes "[/]waypoint_follower([[:space:]]|$)" TERM
kill_matching_processes "[/]amcl([[:space:]]|$)" TERM
kill_matching_processes "[/]map_server([[:space:]]|$)" TERM
kill_matching_processes "[/]lifecycle_manager([[:space:]]|$)" TERM
kill_matching_processes "[r]viz2.*nav2_default_view.rviz" TERM
sleep 2

ros2 daemon stop >/dev/null 2>&1 || true
ros2 daemon start >/dev/null 2>&1 || true

echo ">>> [1/9] Starting Go2 built-in lidar services"
"$SCRIPT_DIR/start_go2_lidar_services.py"
"$SCRIPT_DIR/go2_utlidar_switch.py" ON --repeat 5 --interval 0.2

echo ">>> [2/9] Waiting for Go2 topics"
wait_for_topic_publisher "$LIDAR_CLOUD_TOPIC" 20 || {
    echo "Error: no publisher for $LIDAR_CLOUD_TOPIC" >&2
    exit 1
}
wait_for_topic_publisher "$ODOM_TOPIC" 20 || {
    echo "Error: no publisher for $ODOM_TOPIC" >&2
    exit 1
}

echo ">>> [3/9] Starting odom -> TF bridge"
GO2_ODOM_TOPIC="$ODOM_TOPIC" GO2_TF_PARENT=odom GO2_TF_CHILD=base_link GO2_TF_STAMP_MODE=now GO2_RESTAMPED_ODOM_TOPIC=/odom \
    python3 "$SCRIPT_DIR/go2_odom_to_tf.py" \
    > "$LOG_DIR/go2_odom_to_tf.log" 2>&1 &

if ! wait_for_tf odom base_link 20; then
    echo "Error: odom -> base_link TF did not appear" >&2
    echo "Check log: $LOG_DIR/go2_odom_to_tf.log" >&2
    exit 1
fi

echo ">>> [4/9] Restamping cloud and starting PointCloud2 -> LaserScan"
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
    -p transform_tolerance:="$SCAN_TRANSFORM_TOLERANCE" \
    -p min_height:="$SCAN_MIN_HEIGHT" \
    -p max_height:="$SCAN_MAX_HEIGHT" \
    -p angle_min:=-3.14159 \
    -p angle_max:=3.14159 \
    -p angle_increment:="$SCAN_ANGLE_INCREMENT" \
    -p scan_time:="$SCAN_TIME" \
    -p range_min:="$SCAN_RANGE_MIN" \
    -p range_max:="$SCAN_RANGE_MAX" \
    -p use_inf:=true \
    > "$LOG_DIR/pointcloud_to_laserscan.log" 2>&1 &

wait_for_topic_publisher "$SCAN_TOPIC" 20 || {
    echo "Error: no publisher for $SCAN_TOPIC" >&2
    echo "Check log: $LOG_DIR/pointcloud_to_laserscan.log" >&2
    exit 1
}

echo ">>> [5/9] Starting Nav2 bringup"
echo "    map:    $MAP_FILE"
echo "    params: $NAV2_PARAMS_FILE"
ros2 launch nav2_bringup bringup_launch.py \
    slam:=False \
    map:="$MAP_FILE" \
    use_sim_time:="$USE_SIM_TIME" \
    params_file:="$NAV2_PARAMS_FILE" \
    autostart:="$AUTOSTART" \
    > "$LOG_DIR/nav2_bringup.log" 2>&1 &

sleep 8

echo ">>> [6/9] Starting RViz in VNC"
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

echo ">>> [7/9] Initial pose"
if [ "$PUBLISH_INITIAL_POSE" = "true" ] || [ "$PUBLISH_INITIAL_POSE" = "1" ]; then
    echo "    publishing initial pose: x=$INITIAL_POSE_X y=$INITIAL_POSE_Y yaw=$INITIAL_POSE_YAW"
    publish_initial_pose >/dev/null || true
    if wait_for_tf map odom 15; then
        echo "    map -> odom TF is available"
    else
        echo "Warning: map -> odom TF did not appear after publishing initial pose." >&2
        echo "         Set the pose in RViz with '2D Pose Estimate' and check $LOG_DIR/nav2_bringup.log" >&2
    fi
else
    echo "    Set it in RViz with '2D Pose Estimate' before sending a Nav2 goal."
    echo "    Or restart with: PUBLISH_INITIAL_POSE=true INITIAL_POSE_X=... INITIAL_POSE_Y=... INITIAL_POSE_YAW=..."
fi

echo ">>> [8/9] Starting Go2 cmd_vel bridge"
if [ "$START_GO2_CMD_BRIDGE" = "true" ] || [ "$START_GO2_CMD_BRIDGE" = "1" ]; then
    UNITREE_NET_IF="$UNITREE_NET_IF" UNITREE_SDK2PY_PATH="$UNITREE_SDK2PY_PATH" \
    python3 "$SCRIPT_DIR/go2_cmd_bridge.py" --net-if "$UNITREE_NET_IF" --ros-args \
        -p cmd_vel_topic:="$GO2_CMD_TOPIC" \
        -p max_vx:="$GO2_MAX_VX" \
        -p max_vy:="$GO2_MAX_VY" \
        -p max_wz:="$GO2_MAX_WZ" \
        > "$LOG_DIR/go2_cmd_bridge.log" 2>&1 &
else
    echo "    START_GO2_CMD_BRIDGE=false, Nav2 will plan but not move the robot."
fi

GO2_IP="$(ip -4 addr show wlan0 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -1)"
if [ -z "$GO2_IP" ]; then
    GO2_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
fi

cat <<EOF

>>> [9/9] Go2 Nav2 stack is running

VNC:
  ${GO2_IP:-<go2-ip>}:5901

RViz workflow:
  1. Fixed Frame = map
  2. Use "2D Pose Estimate" to set the robot pose on the loaded map
  3. Use "Nav2 Goal" to send a navigation goal

Main topics:
  map:          /map
  scan:         $SCAN_TOPIC  ($LIDAR_CLOUD_TOPIC -> $RESTAMPED_CLOUD_TOPIC -> LaserScan)
  odom tf:      odom -> base_link  ($ODOM_TOPIC)
  localization: map -> odom  (AMCL)
  command:      $GO2_CMD_TOPIC -> Go2 SportClient.Move

Logs:
  $LOG_DIR

Press Ctrl-C in this terminal to stop Nav2 and send a zero velocity command.

EOF

wait
