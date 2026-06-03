#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SENTRY_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NAV_WS_ROOT="${NAV_WS_ROOT:-$HOME/nav_ws}"

ROS_SETUP="${ROS_SETUP:-/opt/ros/foxy/setup.bash}"
NAV_WS_SETUP="${NAV_WS_SETUP:-$NAV_WS_ROOT/install/setup.bash}"
RM_NAVIGATION_WS_SETUP="${RM_NAVIGATION_WS_SETUP:-$SENTRY_ROOT/rm_navigation_ws/install/setup.bash}"
FASTLIO_CONFIG="${FASTLIO_CONFIG:-$NAV_WS_ROOT/src/FAST_LIO/config/mid360.yaml}"
MAP_FILE="${MAP_FILE:-$HOME/work/go2_nav/maps/mid360_fastlio_latest/nav2_map/map.yaml}"
NAV2_PARAMS_FILE="${NAV2_PARAMS_FILE:-$SENTRY_ROOT/config/go2_nav2_params_light.yaml}"
NAV2_BT_XML="${NAV2_BT_XML:-}"
LOG_DIR="${LOG_DIR:-/tmp/mid360_fastlio_nav2}"
RUNTIME_NAV2_PARAMS_FILE="${RUNTIME_NAV2_PARAMS_FILE:-$LOG_DIR/nav2_params_runtime.yaml}"
RMW_IMPLEMENTATION="${GO2_NAV_RMW_IMPLEMENTATION:-rmw_fastrtps_cpp}"

MID360_IFACE="${MID360_IFACE:-eth0}"
MID360_HOST_IP="${MID360_HOST_IP:-192.168.1.2}"
MID360_LIDAR_IP="${MID360_LIDAR_IP:-192.168.1.3}"
LIDAR_CLOUD_TOPIC="${LIDAR_CLOUD_TOPIC:-/livox/lidar}"
LIDAR_IMU_TOPIC="${LIDAR_IMU_TOPIC:-/livox/imu}"

FASTLIO_ODOM_FRAME="${FASTLIO_ODOM_FRAME:-odom}"
FASTLIO_BODY_FRAME="${FASTLIO_BODY_FRAME:-livox_frame}"
FASTLIO_ODOM_TOPIC="${FASTLIO_ODOM_TOPIC:-/Odometry}"
NAV_BASE_FRAME="${NAV_BASE_FRAME:-base_link}"
NAV_ODOM_TOPIC="${NAV_ODOM_TOPIC:-/Odometry}"
LIDAR_TO_BASE_X="${LIDAR_TO_BASE_X:-0.0}"
LIDAR_TO_BASE_Y="${LIDAR_TO_BASE_Y:-0.0}"
LIDAR_TO_BASE_Z="${LIDAR_TO_BASE_Z:-0.0}"
LIDAR_TO_BASE_ROLL="${LIDAR_TO_BASE_ROLL:-0.0}"
LIDAR_TO_BASE_PITCH="${LIDAR_TO_BASE_PITCH:-0.0}"
LIDAR_TO_BASE_YAW="${LIDAR_TO_BASE_YAW:-0.0}"
if [ -n "${LIDAR_TO_BASE_YAW_DEG:-}" ]; then
    LIDAR_TO_BASE_YAW="$(python3 - "$LIDAR_TO_BASE_YAW_DEG" <<'PY'
import math
import sys
print(float(sys.argv[1]) * math.pi / 180.0)
PY
)"
fi
BODY_CLOUD_TOPIC="${BODY_CLOUD_TOPIC:-/cloud_registered_body}"
SCAN_TOPIC="${SCAN_TOPIC:-/scan}"
RESTAMP_BODY_CLOUD="${RESTAMP_BODY_CLOUD:-false}"
RESTAMPED_BODY_CLOUD_TOPIC="${RESTAMPED_BODY_CLOUD_TOPIC:-/mid360/cloud_registered_body_now}"

# Keep the default slice wide for the MID360-on-Go2 setup. Until the lidar-to-base
# roll/pitch/z extrinsic is measured, a narrow z band can filter out the whole scan.
SCAN_MIN_HEIGHT="${SCAN_MIN_HEIGHT:--3.0}"
SCAN_MAX_HEIGHT="${SCAN_MAX_HEIGHT:-3.0}"
SCAN_ANGLE_INCREMENT="${SCAN_ANGLE_INCREMENT:-0.00872665}"
SCAN_TIME="${SCAN_TIME:-0.10}"
SCAN_RANGE_MIN="${SCAN_RANGE_MIN:-0.15}"
SCAN_RANGE_MAX="${SCAN_RANGE_MAX:-12.0}"
SCAN_TRANSFORM_TOLERANCE="${SCAN_TRANSFORM_TOLERANCE:-0.3}"
SCAN_USE_INF="${SCAN_USE_INF:-false}"
SCAN_TARGET_FRAME="${SCAN_TARGET_FRAME:-$NAV_BASE_FRAME}"

USE_SIM_TIME="${USE_SIM_TIME:-false}"
AUTOSTART="${AUTOSTART:-true}"
START_RVIZ="${START_RVIZ:-true}"
START_NAVIGATION="${START_NAVIGATION:-true}"
RVIZ_DISPLAY="${RVIZ_DISPLAY:-:1}"
RVIZ_CONFIG="${RVIZ_CONFIG:-$SENTRY_ROOT/config/go2_nav2_light.rviz}"

PUBLISH_INITIAL_POSE="${PUBLISH_INITIAL_POSE:-true}"
INITIAL_POSE_X="${INITIAL_POSE_X:-0.0}"
INITIAL_POSE_Y="${INITIAL_POSE_Y:-0.0}"
INITIAL_POSE_YAW="${INITIAL_POSE_YAW:-0.0}"
if [ -n "${INITIAL_POSE_YAW_DEG:-}" ]; then
    INITIAL_POSE_YAW="$(python3 - "$INITIAL_POSE_YAW_DEG" <<'PY'
import math
import sys
print(float(sys.argv[1]) * math.pi / 180.0)
PY
)"
fi
INITIAL_POSE_REPEAT="${INITIAL_POSE_REPEAT:-3}"
INITIAL_POSE_INTERVAL="${INITIAL_POSE_INTERVAL:-0.8}"
INITIAL_POSE_STAMP_BACKDATE="${INITIAL_POSE_STAMP_BACKDATE:-1.5}"
INITIAL_POSE_STAMP_MODE="${INITIAL_POSE_STAMP_MODE:-now}"
AMCL_GLOBAL_LOCALIZATION="${AMCL_GLOBAL_LOCALIZATION:-false}"
AMCL_GLOBAL_LOCALIZATION_DELAY="${AMCL_GLOBAL_LOCALIZATION_DELAY:-2}"
MAP_SERVER_SETTLE_SEC="${MAP_SERVER_SETTLE_SEC:-2}"
AMCL_SETTLE_SEC="${AMCL_SETTLE_SEC:-4}"
AMCL_READY_TIMEOUT="${AMCL_READY_TIMEOUT:-35}"
AMCL_OUTPUT_WAIT="${AMCL_OUTPUT_WAIT:-8}"
AMCL_STRICT_STARTUP="${AMCL_STRICT_STARTUP:-true}"
AMCL_REQUIRE_OUTPUT_TOPICS="${AMCL_REQUIRE_OUTPUT_TOPICS:-false}"
ICP_CONFIG_FILE="${ICP_CONFIG_FILE:-$SENTRY_ROOT/rm_navigation_ws/src/rm_nav_bringup/config/reality/icp_registration_real.yaml}"
ICP_PCD_FILE="${ICP_PCD_FILE:-$HOME/work/go2_nav/maps/mid360_fastlio_latest/fastlio_map.pcd}"
ICP_RUNTIME_CONFIG="${ICP_RUNTIME_CONFIG:-$LOG_DIR/icp_registration_runtime.yaml}"
ICP_POINTCLOUD_TOPIC="${ICP_POINTCLOUD_TOPIC:-$BODY_CLOUD_TOPIC}"
ICP_LASER_FRAME_ID="${ICP_LASER_FRAME_ID:-$FASTLIO_BODY_FRAME}"
ICP_RANGE_ODOM_FRAME_ID="${ICP_RANGE_ODOM_FRAME_ID:-$FASTLIO_ODOM_FRAME}"
ICP_ODOM_FRAME_ID="${ICP_ODOM_FRAME_ID:-$FASTLIO_ODOM_FRAME}"
ICP_INITIAL_POSE_X="${ICP_INITIAL_POSE_X:-$INITIAL_POSE_X}"
ICP_INITIAL_POSE_Y="${ICP_INITIAL_POSE_Y:-$INITIAL_POSE_Y}"
ICP_INITIAL_POSE_Z="${ICP_INITIAL_POSE_Z:-0.0}"
ICP_INITIAL_POSE_ROLL="${ICP_INITIAL_POSE_ROLL:-0.0}"
ICP_INITIAL_POSE_PITCH="${ICP_INITIAL_POSE_PITCH:-0.0}"
ICP_INITIAL_POSE_YAW="${ICP_INITIAL_POSE_YAW:-$INITIAL_POSE_YAW}"
ICP_THRESH="${ICP_THRESH:-0.35}"
ICP_XY_OFFSET="${ICP_XY_OFFSET:-0.75}"
ICP_XY_SEARCH_STEPS="${ICP_XY_SEARCH_STEPS:-3}"
ICP_YAW_OFFSET="${ICP_YAW_OFFSET:-180.0}"
ICP_YAW_RESOLUTION="${ICP_YAW_RESOLUTION:-15.0}"
ICP_MAP_OFFSET_X="${ICP_MAP_OFFSET_X:-}"
ICP_MAP_OFFSET_Y="${ICP_MAP_OFFSET_Y:-}"
ICP_MAP_OFFSET_Z="${ICP_MAP_OFFSET_Z:-0.0}"
LOCALIZATION_MODE="${LOCALIZATION_MODE:-}"
if [ -z "$LOCALIZATION_MODE" ]; then
    if [ "$AMCL_GLOBAL_LOCALIZATION" = "true" ] || [ "$AMCL_GLOBAL_LOCALIZATION" = "1" ]; then
        LOCALIZATION_MODE="amcl"
    else
        LOCALIZATION_MODE="static"
    fi
fi
if [ -z "${START_SCAN_AFTER_AMCL+x}" ]; then
    if [ "$LOCALIZATION_MODE" = "amcl" ]; then
        START_SCAN_AFTER_AMCL=true
    else
        START_SCAN_AFTER_AMCL=false
    fi
fi

START_GO2_CMD_BRIDGE="${START_GO2_CMD_BRIDGE:-false}"
UNITREE_NET_IF="${UNITREE_NET_IF:-eth0}"
UNITREE_SDK2PY_PATH="${UNITREE_SDK2PY_PATH:-/home/unitree/unitree_sdk2_python}"
GO2_CYCLONEDDS_HOME="${GO2_CYCLONEDDS_HOME:-$HOME/cyclonedds/install}"
GO2_CMD_TOPIC="${GO2_CMD_TOPIC:-/cmd_vel}"
GO2_MAX_VX="${GO2_MAX_VX:-0.25}"
GO2_MAX_VY="${GO2_MAX_VY:-0.00}"
GO2_MAX_WZ="${GO2_MAX_WZ:-0.45}"
GO2_X_SIGN="${GO2_X_SIGN:-1.0}"
GO2_Y_SIGN="${GO2_Y_SIGN:-1.0}"
GO2_WZ_SIGN="${GO2_WZ_SIGN:-1.0}"
GO2_SWAP_XY="${GO2_SWAP_XY:-false}"
GO2_DEADBAND_V="${GO2_DEADBAND_V:-0.02}"
GO2_DEADBAND_W="${GO2_DEADBAND_W:-0.04}"
GO2_MIN_CMD_V="${GO2_MIN_CMD_V:-0.0}"
GO2_MIN_CMD_W="${GO2_MIN_CMD_W:-0.0}"
GO2_CMD_BRIDGE_ENABLED="${GO2_CMD_BRIDGE_ENABLED:-true}"
GO2_SEND_ZERO_WHEN_IDLE="${GO2_SEND_ZERO_WHEN_IDLE:-false}"
GO2_REMOTE_PRIORITY="${GO2_REMOTE_PRIORITY:-true}"
GO2_REMOTE_TOPIC="${GO2_REMOTE_TOPIC:-rt/lowstate}"
GO2_REMOTE_DEADBAND="${GO2_REMOTE_DEADBAND:-0.12}"
GO2_REMOTE_HOLD_SEC="${GO2_REMOTE_HOLD_SEC:-0.8}"
GO2_LOG_COMMANDS="${GO2_LOG_COMMANDS:-false}"
GO2_LOG_INTERVAL_SEC="${GO2_LOG_INTERVAL_SEC:-0.5}"

mkdir -p "$LOG_DIR"

remove_path_entry() {
    local value="${1:-}"
    local remove="$2"
    local output=""
    local entry
    IFS=':' read -ra entries <<< "$value"
    for entry in "${entries[@]}"; do
        if [ -n "$entry" ] && [ "$entry" != "$remove" ]; then
            if [ -n "$output" ]; then
                output="$output:$entry"
            else
                output="$entry"
            fi
        fi
    done
    printf '%s\n' "$output"
}

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
    echo ">>> Stopping MID360 FAST-LIO Nav2 stack"
    kill $(jobs -p) 2>/dev/null || true
    kill_matching_processes "[/]go2_cmd_bridge.py" TERM
    kill_matching_processes "[/]publish_static_map_to_odom_from_pose.py" TERM
    CYCLONEDDS_HOME="$GO2_CYCLONEDDS_HOME" \
    LD_LIBRARY_PATH="$GO2_CYCLONEDDS_HOME/lib:${LD_LIBRARY_PATH:-}" \
    RMW_IMPLEMENTATION="$RMW_IMPLEMENTATION" \
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

wait_for_topic_message() {
    local topic="$1"
    local msg_type="$2"
    local timeout_secs="$3"

    python3 - "$topic" "$msg_type" "$timeout_secs" <<'PY'
import sys

import rclpy
from rclpy.node import Node
from rclpy.qos import HistoryPolicy, QoSProfile, ReliabilityPolicy
from rosidl_runtime_py.utilities import get_message

topic = sys.argv[1]
msg_type = sys.argv[2]
timeout_secs = float(sys.argv[3])

rclpy.init()
node = Node("mid360_fastlio_nav2_wait_for_message")
message_class = get_message(msg_type)
qos = QoSProfile(
    history=HistoryPolicy.KEEP_LAST,
    depth=10,
    reliability=ReliabilityPolicy.BEST_EFFORT,
)
seen = False

def callback(_msg):
    global seen
    seen = True

node.create_subscription(message_class, topic, callback, qos)
deadline = node.get_clock().now().nanoseconds + int(timeout_secs * 1e9)

while rclpy.ok() and node.get_clock().now().nanoseconds < deadline and not seen:
    rclpy.spin_once(node, timeout_sec=0.1)

node.destroy_node()
rclpy.shutdown()
sys.exit(0 if seen else 1)
PY
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
node = Node("mid360_fastlio_nav2_wait_for_tf")
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

lifecycle_set_retry() {
    local node="$1"
    local transition="$2"
    local timeout_secs="$3"
    local deadline

    deadline=$((SECONDS + timeout_secs))
    while [ "$SECONDS" -lt "$deadline" ]; do
        if timeout 4 ros2 lifecycle set "$node" "$transition"; then
            return 0
        fi
        sleep 0.5
    done
    return 1
}

lifecycle_wait_active() {
    local node="$1"
    local timeout_secs="$2"
    local deadline

    deadline=$((SECONDS + timeout_secs))
    while [ "$SECONDS" -lt "$deadline" ]; do
        if ros2 lifecycle get "$node" 2>/dev/null | grep -q '^active '; then
            return 0
        fi
        sleep 0.5
    done
    return 1
}

monitor_process() {
    local pid="$1"
    local label="$2"
    local log_file="$3"

    (
        while kill -0 "$pid" 2>/dev/null; do
            sleep 1
        done
        echo "[$(date '+%F %T')] $label process disappeared (pid=$pid)" >> "$log_file"
    ) &
}

run_logged() {
    local label="$1"
    local log_file="$2"
    shift 2

    (
        set +e
        "$@"
        code=$?
        echo "[$(date '+%F %T')] $label exited with code $code" >> "$LOG_DIR/nav2_localization.log"
        exit "$code"
    ) >> "$log_file" 2>&1 &
}

wait_for_node() {
    local node="$1"
    local timeout_secs="$2"
    local deadline

    deadline=$((SECONDS + timeout_secs))
    while [ "$SECONDS" -lt "$deadline" ]; do
        if ros2 node list 2>/dev/null | grep -qx "$node"; then
            return 0
        fi
        sleep 0.5
    done
    return 1
}

amcl_startup_failure() {
    local message="$1"
    echo "Warning: $message" >&2
    echo "         Check $LOG_DIR/nav2_localization.log" >&2
    tail -120 "$LOG_DIR/nav2_localization.log" >&2 || true
    if [ "$AMCL_STRICT_STARTUP" = "true" ] || [ "$AMCL_STRICT_STARTUP" = "1" ]; then
        exit 1
    fi
}

publish_initial_pose() {
    local attempt

    wait_for_tf "$FASTLIO_ODOM_FRAME" "$NAV_BASE_FRAME" 5 >/dev/null || true
    for ((attempt = 1; attempt <= INITIAL_POSE_REPEAT; attempt++)); do
        python3 - "$INITIAL_POSE_X" "$INITIAL_POSE_Y" "$INITIAL_POSE_YAW" "$INITIAL_POSE_STAMP_BACKDATE" "$INITIAL_POSE_STAMP_MODE" <<'PY' >/dev/null || true
import math
import sys
import time

import rclpy
from geometry_msgs.msg import PoseWithCovarianceStamped
from rclpy.node import Node

x = float(sys.argv[1])
y = float(sys.argv[2])
yaw = float(sys.argv[3])
backdate = float(sys.argv[4])
stamp_mode = sys.argv[5]

rclpy.init()
node = Node("mid360_fastlio_nav2_publish_initial_pose")
pub = node.create_publisher(PoseWithCovarianceStamped, "/initialpose", 10)

deadline = time.time() + 1.0
while pub.get_subscription_count() == 0 and time.time() < deadline:
    rclpy.spin_once(node, timeout_sec=0.05)

msg = PoseWithCovarianceStamped()
msg.header.frame_id = "map"
msg.pose.pose.position.x = x
msg.pose.pose.position.y = y
msg.pose.pose.position.z = 0.0
msg.pose.pose.orientation.z = math.sin(yaw * 0.5)
msg.pose.pose.orientation.w = math.cos(yaw * 0.5)
msg.pose.covariance[0] = 0.25
msg.pose.covariance[7] = 0.25
msg.pose.covariance[35] = 0.06853891945200942

if stamp_mode == "zero":
    msg.header.stamp.sec = 0
    msg.header.stamp.nanosec = 0
else:
    stamp_ns = max(0, node.get_clock().now().nanoseconds - int(backdate * 1e9))
    msg.header.stamp.sec = stamp_ns // 1000000000
    msg.header.stamp.nanosec = stamp_ns % 1000000000
pub.publish(msg)
rclpy.spin_once(node, timeout_sec=0.1)
time.sleep(0.1)

node.destroy_node()
rclpy.shutdown()
PY
        if wait_for_tf map "$NAV_BASE_FRAME" 2 >/dev/null; then
            return 0
        fi
        sleep "$INITIAL_POSE_INTERVAL"
    done
    return 1
}

topic_type() {
    local topic="$1"
    ros2 topic list -t 2>/dev/null | awk -v topic="$topic" '$1 == topic {gsub(/\[|\]/, "", $2); print $2; exit}'
}

prepare_runtime_nav2_params() {
    python3 - "$NAV2_PARAMS_FILE" "$RUNTIME_NAV2_PARAMS_FILE" "$NAV_BASE_FRAME" "$NAV_ODOM_TOPIC" "$NAV2_BT_XML" <<'PY'
import sys
from pathlib import Path

import yaml

src = Path(sys.argv[1]).expanduser()
dst = Path(sys.argv[2]).expanduser()
base_frame = sys.argv[3]
odom_topic = sys.argv[4]
bt_xml = sys.argv[5]

with src.open("r", encoding="utf-8") as f:
    data = yaml.safe_load(f)

def params_for(*path):
    node = data
    for key in path:
        node = node.setdefault(key, {})
    return node.setdefault("ros__parameters", {})

params_for("amcl")["base_frame_id"] = base_frame
params_for("bt_navigator")["robot_base_frame"] = base_frame
params_for("bt_navigator")["odom_topic"] = odom_topic
if bt_xml.strip():
    params_for("bt_navigator")["default_bt_xml_filename"] = bt_xml
params_for("controller_server")["odom_topic"] = odom_topic
params_for("local_costmap", "local_costmap")["robot_base_frame"] = base_frame
params_for("global_costmap", "global_costmap")["robot_base_frame"] = base_frame

dst.parent.mkdir(parents=True, exist_ok=True)
with dst.open("w", encoding="utf-8") as f:
    yaml.safe_dump(data, f, sort_keys=False)
PY
    NAV2_PARAMS_FILE="$RUNTIME_NAV2_PARAMS_FILE"
}

prepare_runtime_icp_params() {
    python3 - "$ICP_CONFIG_FILE" "$ICP_RUNTIME_CONFIG" "$ICP_PCD_FILE" "$ICP_POINTCLOUD_TOPIC" \
        "$ICP_LASER_FRAME_ID" "$ICP_RANGE_ODOM_FRAME_ID" "$ICP_ODOM_FRAME_ID" \
        "$ICP_THRESH" "$ICP_XY_OFFSET" "$ICP_XY_SEARCH_STEPS" "$ICP_YAW_OFFSET" "$ICP_YAW_RESOLUTION" \
        "$ICP_INITIAL_POSE_X" "$ICP_INITIAL_POSE_Y" "$ICP_INITIAL_POSE_Z" \
        "$ICP_INITIAL_POSE_ROLL" "$ICP_INITIAL_POSE_PITCH" "$ICP_INITIAL_POSE_YAW" \
        "$MAP_FILE" "$ICP_MAP_OFFSET_X" "$ICP_MAP_OFFSET_Y" "$ICP_MAP_OFFSET_Z" <<'PY'
import sys
from pathlib import Path

import yaml

(
    config_file,
    output_file,
    pcd_file,
    pointcloud_topic,
    laser_frame_id,
    range_odom_frame_id,
    odom_frame_id,
    thresh,
    xy_offset,
    xy_search_steps,
    yaw_offset,
    yaw_resolution,
    initial_x,
    initial_y,
    initial_z,
    initial_roll,
    initial_pitch,
    initial_yaw,
    map_file,
    map_offset_x,
    map_offset_y,
    map_offset_z,
) = sys.argv[1:]

with open(config_file, "r", encoding="utf-8") as f:
    config = yaml.safe_load(f)

params = config.setdefault("/icp_registration", {}).setdefault("ros__parameters", {})
params["pcd_path"] = str(Path(pcd_file).expanduser())
params["pointcloud_topic"] = pointcloud_topic
params["laser_frame_id"] = laser_frame_id
params["range_odom_frame_id"] = range_odom_frame_id
params["odom_frame_id"] = odom_frame_id
params["thresh"] = float(thresh)
params["xy_offset"] = float(xy_offset)
params["xy_search_steps"] = int(xy_search_steps)
params["yaw_offset"] = float(yaw_offset)
params["yaw_resolution"] = float(yaw_resolution)
params["initial_pose"] = [
    float(initial_x),
    float(initial_y),
    float(initial_z),
    float(initial_roll),
    float(initial_pitch),
    float(initial_yaw),
]

if map_offset_x.strip() and map_offset_y.strip():
    params["map_offset_x"] = float(map_offset_x)
    params["map_offset_y"] = float(map_offset_y)
    params["map_offset_z"] = float(map_offset_z or "0.0")
else:
    # Keep compatibility with the original start_robot.sh runtime config.
    # Newer icp_registration builds ignore these if the parameters are not declared.
    try:
        import numpy as np
        import open3d as o3d

        with open(map_file, "r", encoding="utf-8") as f:
            map_config = yaml.safe_load(f)
        origin = map_config.get("origin", [0.0, 0.0, 0.0])
        pcd = o3d.io.read_point_cloud(str(Path(pcd_file).expanduser()))
        points = np.asarray(pcd.points)
        if points.size:
            min_bound = points.min(axis=0)
            params["map_offset_x"] = float(origin[0]) - float(min_bound[0])
            params["map_offset_y"] = float(origin[1]) - float(min_bound[1])
            params["map_offset_z"] = float(map_offset_z or "0.0")
    except Exception:
        pass

Path(output_file).parent.mkdir(parents=True, exist_ok=True)
with open(output_file, "w", encoding="utf-8") as f:
    yaml.safe_dump(config, f, sort_keys=False)
PY
}

if [ ! -f "$ROS_SETUP" ]; then
    echo "Error: ROS setup not found: $ROS_SETUP" >&2
    exit 1
fi
if [ ! -f "$NAV_WS_SETUP" ]; then
    echo "Error: nav_ws setup not found: $NAV_WS_SETUP" >&2
    exit 1
fi
if [ ! -f "$FASTLIO_CONFIG" ]; then
    echo "Error: FAST-LIO config not found: $FASTLIO_CONFIG" >&2
    exit 1
fi
if [ ! -f "$MAP_FILE" ]; then
    echo "Error: Nav2 map not found: $MAP_FILE" >&2
    echo "Create it first with scripts/save_mid360_fastlio_map.sh and scripts/pcd2pgm_go2.sh" >&2
    exit 1
fi
if [ ! -f "$NAV2_PARAMS_FILE" ]; then
    echo "Error: Nav2 params not found: $NAV2_PARAMS_FILE" >&2
    exit 1
fi
if [ "$LOCALIZATION_MODE" = "icp" ]; then
    if [ ! -f "$ICP_CONFIG_FILE" ]; then
        echo "Error: ICP config not found: $ICP_CONFIG_FILE" >&2
        exit 1
    fi
    if [ ! -f "$ICP_PCD_FILE" ]; then
        echo "Error: ICP PCD not found: $ICP_PCD_FILE" >&2
        exit 1
    fi
fi

echo ">>> [0/11] Loading ROS 2 Foxy + nav_ws"
unset CYCLONEDDS_URI
unset CYCLONEDDS_HOME
export RMW_IMPLEMENTATION
export LD_LIBRARY_PATH="$(remove_path_entry "${LD_LIBRARY_PATH:-}" "$HOME/cyclonedds/install/lib")"
source_relaxed "$ROS_SETUP"
source_relaxed "$NAV_WS_SETUP"
if [ -f "$RM_NAVIGATION_WS_SETUP" ]; then
    source_relaxed "$RM_NAVIGATION_WS_SETUP"
fi
unset CYCLONEDDS_URI
unset CYCLONEDDS_HOME
export RMW_IMPLEMENTATION
export LD_LIBRARY_PATH="$(remove_path_entry "${LD_LIBRARY_PATH:-}" "$HOME/cyclonedds/install/lib")"

export ROS_LOG_DIR="${ROS_LOG_DIR:-$LOG_DIR/ros_logs}"
mkdir -p "$ROS_LOG_DIR"

prepare_runtime_nav2_params
echo "    runtime params: $NAV2_PARAMS_FILE"
echo "    nav base frame: $NAV_BASE_FRAME"
echo "    nav odom topic: $NAV_ODOM_TOPIC"

echo ">>> [1/11] Checking MID360 network"
echo "    iface:    $MID360_IFACE"
echo "    host ip:  $MID360_HOST_IP"
echo "    lidar ip: $MID360_LIDAR_IP"
if ! ip -4 addr show dev "$MID360_IFACE" | grep -q "$MID360_HOST_IP"; then
    echo "Error: $MID360_IFACE does not have $MID360_HOST_IP." >&2
    echo "Expected native eth0 to have both 192.168.123.18/24 and 192.168.1.2/24." >&2
    echo "Try: sudo nmcli con up \"Wired connection 1\"" >&2
    exit 1
fi
ip route get "$MID360_LIDAR_IP" || true

echo ">>> [2/11] Cleaning old navigation processes"
kill_matching_processes "[l]ivox_ros_driver2_node" TERM
kill_matching_processes "[r]os2 launch livox_ros_driver2 msg_MID360_launch.py" TERM
kill_matching_processes "[f]astlio_mapping" TERM
kill_matching_processes "[p]ointcloud_to_laserscan_node" TERM
kill_matching_processes "[p]cd2pgm_node" TERM
kill_matching_processes "[/]go2_cmd_bridge.py" TERM
kill_matching_processes "[r]os2 launch nav2_bringup bringup_launch.py" TERM
kill_matching_processes "[r]os2 launch nav2_bringup navigation_launch.py" TERM
kill_matching_processes "[/]publish_static_map_to_odom_from_pose.py" TERM
kill_matching_processes "[/]controller_server([[:space:]]|$)" TERM
kill_matching_processes "[/]planner_server([[:space:]]|$)" TERM
kill_matching_processes "[/]recoveries_server([[:space:]]|$)" TERM
kill_matching_processes "[/]bt_navigator([[:space:]]|$)" TERM
kill_matching_processes "[/]waypoint_follower([[:space:]]|$)" TERM
kill_matching_processes "[/]amcl([[:space:]]|$)" TERM
kill_matching_processes "[/]map_server([[:space:]]|$)" TERM
kill_matching_processes "[/]lifecycle_manager([[:space:]]|$)" TERM
kill_matching_processes "[/]component_container([[:space:]]|$)" TERM
kill_matching_processes "[r]viz2" TERM
sleep 2
kill_matching_processes "[l]ivox_ros_driver2_node" KILL
kill_matching_processes "[f]astlio_mapping" KILL
kill_matching_processes "[p]ointcloud_to_laserscan_node" KILL
kill_matching_processes "[p]cd2pgm_node" KILL
kill_matching_processes "[r]os2 launch nav2_bringup bringup_launch.py" KILL
kill_matching_processes "[r]os2 launch nav2_bringup navigation_launch.py" KILL
kill_matching_processes "[/]publish_static_map_to_odom_from_pose.py" KILL
kill_matching_processes "[/]controller_server([[:space:]]|$)" KILL
kill_matching_processes "[/]planner_server([[:space:]]|$)" KILL
kill_matching_processes "[/]recoveries_server([[:space:]]|$)" KILL
kill_matching_processes "[/]bt_navigator([[:space:]]|$)" KILL
kill_matching_processes "[/]waypoint_follower([[:space:]]|$)" KILL
kill_matching_processes "[/]amcl([[:space:]]|$)" KILL
kill_matching_processes "[/]map_server([[:space:]]|$)" KILL
kill_matching_processes "[/]lifecycle_manager([[:space:]]|$)" KILL
kill_matching_processes "[/]component_container([[:space:]]|$)" KILL
kill_matching_processes "[r]viz2" KILL
ros2 daemon stop >/dev/null 2>&1 || true
ros2 daemon start >/dev/null 2>&1 || true

echo ">>> [3/11] Starting Livox MID360 driver"
ros2 launch livox_ros_driver2 msg_MID360_launch.py \
    > "$LOG_DIR/livox_driver.log" 2>&1 &

if ! wait_for_topic_publisher "$LIDAR_CLOUD_TOPIC" 25; then
    echo "Error: no publisher for $LIDAR_CLOUD_TOPIC" >&2
    tail -120 "$LOG_DIR/livox_driver.log" >&2 || true
    exit 1
fi
cloud_type="$(topic_type "$LIDAR_CLOUD_TOPIC")"
if [ "$cloud_type" != "livox_ros_driver2/msg/CustomMsg" ]; then
    echo "Error: $LIDAR_CLOUD_TOPIC is '$cloud_type', expected livox_ros_driver2/msg/CustomMsg." >&2
    echo "FAST-LIO needs livox_ros_driver2 xfer_format=1." >&2
    exit 1
fi
if ! wait_for_topic_message "$LIDAR_CLOUD_TOPIC" livox_ros_driver2/msg/CustomMsg 15; then
    echo "Error: $LIDAR_CLOUD_TOPIC has a publisher but no CustomMsg point packets arrived." >&2
    echo "       The MID360 driver may be initialized but point UDP is not flowing." >&2
    echo "       Check MID360 power/link, IP/ports in MID360_config.json, and stop any other Livox driver." >&2
    tail -120 "$LOG_DIR/livox_driver.log" >&2 || true
    exit 1
fi
if ! wait_for_topic_publisher "$LIDAR_IMU_TOPIC" 25; then
    echo "Error: no publisher for $LIDAR_IMU_TOPIC" >&2
    tail -120 "$LOG_DIR/livox_driver.log" >&2 || true
    exit 1
fi
if ! wait_for_topic_message "$LIDAR_IMU_TOPIC" sensor_msgs/msg/Imu 10; then
    echo "Error: $LIDAR_IMU_TOPIC has a publisher but no IMU messages arrived." >&2
    tail -120 "$LOG_DIR/livox_driver.log" >&2 || true
    exit 1
fi

echo ">>> [4/11] Starting FAST-LIO odometry"
ros2 run fast_lio fastlio_mapping --ros-args \
    --params-file "$FASTLIO_CONFIG" \
    -p common.lid_topic:="$LIDAR_CLOUD_TOPIC" \
    -p common.imu_topic:="$LIDAR_IMU_TOPIC" \
    -p preprocess.lidar_type:=1 \
    -p preprocess.timestamp_unit:=3 \
    -p pcd_save.pcd_save_en:=false \
    > "$LOG_DIR/fastlio_mapping.log" 2>&1 &

sleep 4
if ! wait_for_topic_publisher "$BODY_CLOUD_TOPIC" 25; then
    echo "Error: no publisher for $BODY_CLOUD_TOPIC" >&2
    tail -120 "$LOG_DIR/fastlio_mapping.log" >&2 || true
    exit 1
fi
if ! wait_for_topic_message "$BODY_CLOUD_TOPIC" sensor_msgs/msg/PointCloud2 15; then
    echo "Error: $BODY_CLOUD_TOPIC has a publisher but no PointCloud2 messages arrived." >&2
    tail -120 "$LOG_DIR/fastlio_mapping.log" >&2 || true
    exit 1
fi

echo ">>> [5/11] Connecting FAST-LIO body frame to Nav2 base_link"
if [ "$FASTLIO_BODY_FRAME" != "$NAV_BASE_FRAME" ]; then
    # ROS 2 Foxy's static_transform_publisher uses yaw pitch roll order.
    ros2 run tf2_ros static_transform_publisher \
        "$LIDAR_TO_BASE_X" "$LIDAR_TO_BASE_Y" "$LIDAR_TO_BASE_Z" \
        "$LIDAR_TO_BASE_YAW" "$LIDAR_TO_BASE_PITCH" "$LIDAR_TO_BASE_ROLL" \
        "$FASTLIO_BODY_FRAME" "$NAV_BASE_FRAME" \
        > "$LOG_DIR/livox_frame_to_base_link.log" 2>&1 &
fi
if ! wait_for_tf "$FASTLIO_ODOM_FRAME" "$NAV_BASE_FRAME" 25; then
    echo "Error: $FASTLIO_ODOM_FRAME -> $NAV_BASE_FRAME TF did not appear." >&2
    echo "Check $LOG_DIR/fastlio_mapping.log and $LOG_DIR/livox_frame_to_base_link.log" >&2
    exit 1
fi

if [ "$NAV_BASE_FRAME" != "$FASTLIO_BODY_FRAME" ] && [ "$NAV_ODOM_TOPIC" != "$FASTLIO_ODOM_TOPIC" ]; then
    echo ">>> [5.2/11] Republishing FAST-LIO odometry as $NAV_BASE_FRAME odometry"
    python3 "$SCRIPT_DIR/republish_odom_base_link.py" --ros-args \
        -p source_odom_topic:="$FASTLIO_ODOM_TOPIC" \
        -p output_odom_topic:="$NAV_ODOM_TOPIC" \
        -p odom_frame_id:="$FASTLIO_ODOM_FRAME" \
        -p source_base_frame:="$FASTLIO_BODY_FRAME" \
        -p target_base_frame:="$NAV_BASE_FRAME" \
        -p stamp_mode:=source \
        > "$LOG_DIR/odom_base_link.log" 2>&1 &
    if ! wait_for_topic_message "$NAV_ODOM_TOPIC" nav_msgs/msg/Odometry 15; then
        echo "Error: $NAV_ODOM_TOPIC has no Odometry messages." >&2
        tail -80 "$LOG_DIR/odom_base_link.log" >&2 || true
        exit 1
    fi
fi

SCAN_CLOUD_TOPIC="$BODY_CLOUD_TOPIC"
if [ "$RESTAMP_BODY_CLOUD" = "true" ] || [ "$RESTAMP_BODY_CLOUD" = "1" ]; then
    echo ">>> [5.5/11] Restamping body cloud to ROS now"
    RESTAMP_CLOUD_INPUT="$BODY_CLOUD_TOPIC" \
    RESTAMP_CLOUD_OUTPUT="$RESTAMPED_BODY_CLOUD_TOPIC" \
    RESTAMP_CLOUD_FRAME="$NAV_BASE_FRAME" \
    python3 "$SCRIPT_DIR/restamp_pointcloud2.py" \
        > "$LOG_DIR/restamp_body_cloud.log" 2>&1 &
    SCAN_CLOUD_TOPIC="$RESTAMPED_BODY_CLOUD_TOPIC"
    if ! wait_for_topic_message "$SCAN_CLOUD_TOPIC" sensor_msgs/msg/PointCloud2 10; then
        echo "Error: restamped body cloud has no messages: $SCAN_CLOUD_TOPIC" >&2
        tail -80 "$LOG_DIR/restamp_body_cloud.log" >&2 || true
        exit 1
    fi
fi

scan_started=false
start_scan_pipeline() {
    if [ "$scan_started" = "true" ]; then
        return 0
    fi

    echo ">>> [6/11] Starting PointCloud2 -> LaserScan"
    ros2 run pointcloud_to_laserscan pointcloud_to_laserscan_node --ros-args \
        -r cloud_in:="$SCAN_CLOUD_TOPIC" \
        -r scan:="$SCAN_TOPIC" \
        -p target_frame:="$SCAN_TARGET_FRAME" \
        -p transform_tolerance:="$SCAN_TRANSFORM_TOLERANCE" \
        -p min_height:="$SCAN_MIN_HEIGHT" \
        -p max_height:="$SCAN_MAX_HEIGHT" \
        -p angle_min:=-3.14159 \
        -p angle_max:=3.14159 \
        -p angle_increment:="$SCAN_ANGLE_INCREMENT" \
        -p scan_time:="$SCAN_TIME" \
        -p range_min:="$SCAN_RANGE_MIN" \
        -p range_max:="$SCAN_RANGE_MAX" \
        -p use_inf:="$SCAN_USE_INF" \
        > "$LOG_DIR/pointcloud_to_laserscan.log" 2>&1 &

    if ! wait_for_topic_publisher "$SCAN_TOPIC" 25; then
        echo "Error: no publisher for $SCAN_TOPIC" >&2
        tail -120 "$LOG_DIR/pointcloud_to_laserscan.log" >&2 || true
        exit 1
    fi
    if ! wait_for_topic_message "$SCAN_TOPIC" sensor_msgs/msg/LaserScan 25; then
        echo "Error: $SCAN_TOPIC has a publisher but no LaserScan messages arrived." >&2
        tail -120 "$LOG_DIR/pointcloud_to_laserscan.log" >&2 || true
        exit 1
    fi

    scan_started=true
}

if [ "$LOCALIZATION_MODE" = "amcl" ] && { [ "$START_SCAN_AFTER_AMCL" = "true" ] || [ "$START_SCAN_AFTER_AMCL" = "1" ]; }; then
    echo ">>> [6/11] Delaying PointCloud2 -> LaserScan until AMCL is active"
else
    start_scan_pipeline
fi

echo ">>> [7/11] Starting Nav2"
echo "    map:    $MAP_FILE"
echo "    params: $NAV2_PARAMS_FILE"
echo "    localization_mode: $LOCALIZATION_MODE"
INITIAL_POSE_WAS_PUBLISHED=false
if [ "$LOCALIZATION_MODE" = "static" ]; then
    ros2 run nav2_map_server map_server --ros-args \
        -p use_sim_time:="$USE_SIM_TIME" \
        -p yaml_filename:="$MAP_FILE" \
        > "$LOG_DIR/map_server.log" 2>&1 &

    lifecycle_set_retry /map_server configure 15 >> "$LOG_DIR/map_server.log" 2>&1 || true
    lifecycle_set_retry /map_server activate 15 >> "$LOG_DIR/map_server.log" 2>&1 || true

    python3 "$SCRIPT_DIR/publish_static_map_to_odom_from_pose.py" \
        "$INITIAL_POSE_X" "$INITIAL_POSE_Y" "$INITIAL_POSE_YAW" \
        "$FASTLIO_ODOM_FRAME" "$NAV_BASE_FRAME" \
        > "$LOG_DIR/static_map_to_odom.log" 2>&1 &

    if ! wait_for_tf map "$NAV_BASE_FRAME" 10; then
        echo "Error: static map -> $NAV_BASE_FRAME TF did not appear." >&2
        tail -80 "$LOG_DIR/static_map_to_odom.log" >&2 || true
        exit 1
    fi

    if [ "$START_NAVIGATION" = "true" ] || [ "$START_NAVIGATION" = "1" ]; then
        ros2 launch nav2_bringup navigation_launch.py \
            use_sim_time:="$USE_SIM_TIME" \
            params_file:="$NAV2_PARAMS_FILE" \
            autostart:="$AUTOSTART" \
            map_subscribe_transient_local:=true \
            > "$LOG_DIR/nav2_bringup.log" 2>&1 &
    else
        echo "    START_NAVIGATION=false, skipping Nav2 planner/controller/costmaps."
    fi
elif [ "$LOCALIZATION_MODE" = "icp" ]; then
    : > "$LOG_DIR/nav2_localization.log"
    : > "$LOG_DIR/map_server.log"
    : > "$LOG_DIR/icp_registration.log"

    echo ">>> Starting map_server manually" >> "$LOG_DIR/nav2_localization.log"
    run_logged "map_server" "$LOG_DIR/map_server.log" \
        env RCUTILS_LOGGING_BUFFERED_STREAM=0 \
        stdbuf -oL -eL ros2 run nav2_map_server map_server --ros-args \
        -p use_sim_time:="$USE_SIM_TIME" \
        -p yaml_filename:="$MAP_FILE"
    map_server_pid=$!
    monitor_process "$map_server_pid" "map_server" "$LOG_DIR/nav2_localization.log"

    if ! wait_for_node /map_server 15; then
        amcl_startup_failure "/map_server node did not appear."
    fi
    if ! lifecycle_set_retry /map_server configure 20 >> "$LOG_DIR/nav2_localization.log" 2>&1; then
        amcl_startup_failure "/map_server configure failed."
    fi
    if ! lifecycle_set_retry /map_server activate 20 >> "$LOG_DIR/nav2_localization.log" 2>&1; then
        amcl_startup_failure "/map_server activate failed."
    fi
    if ! lifecycle_wait_active /map_server 20; then
        amcl_startup_failure "/map_server did not stay active."
    fi

    prepare_runtime_icp_params
    echo ">>> [7.5/11] Starting ICP localization"
    echo "    pcd:         $ICP_PCD_FILE"
    echo "    cloud:       $ICP_POINTCLOUD_TOPIC"
    echo "    laser frame: $ICP_LASER_FRAME_ID"
    echo "    odom frame:  $ICP_ODOM_FRAME_ID"
    run_logged "icp_registration" "$LOG_DIR/icp_registration.log" \
        env RCUTILS_LOGGING_BUFFERED_STREAM=0 \
        stdbuf -oL -eL ros2 run icp_registration icp_registration_node --ros-args \
        --params-file "$ICP_RUNTIME_CONFIG"
    icp_pid=$!
    monitor_process "$icp_pid" "icp_registration" "$LOG_DIR/nav2_localization.log"

    if ! wait_for_node /icp_registration 15; then
        amcl_startup_failure "/icp_registration node did not appear."
    fi
    if ! wait_for_tf "$ICP_ODOM_FRAME_ID" "$ICP_LASER_FRAME_ID" 20; then
        amcl_startup_failure "$ICP_ODOM_FRAME_ID -> $ICP_LASER_FRAME_ID TF is not available for ICP."
    fi
    if ! wait_for_tf map "$ICP_ODOM_FRAME_ID" 90; then
        echo "Error: ICP did not publish map -> $ICP_ODOM_FRAME_ID within timeout." >&2
        tail -160 "$LOG_DIR/icp_registration.log" >&2 || true
        exit 1
    fi
    if ! wait_for_tf map "$NAV_BASE_FRAME" 20; then
        echo "Error: ICP map -> $NAV_BASE_FRAME TF is not available." >&2
        tail -160 "$LOG_DIR/icp_registration.log" >&2 || true
        exit 1
    fi

    if [ "$START_NAVIGATION" = "true" ] || [ "$START_NAVIGATION" = "1" ]; then
        ros2 launch nav2_bringup navigation_launch.py \
            use_sim_time:="$USE_SIM_TIME" \
            params_file:="$NAV2_PARAMS_FILE" \
            autostart:="$AUTOSTART" \
            map_subscribe_transient_local:=true \
            > "$LOG_DIR/nav2_bringup.log" 2>&1 &
    else
        echo "    START_NAVIGATION=false, skipping Nav2 planner/controller/costmaps."
        echo "    ICP localization-only mode: verify map->$NAV_BASE_FRAME first."
    fi
elif [ "$LOCALIZATION_MODE" = "amcl" ]; then
    : > "$LOG_DIR/nav2_localization.log"
    : > "$LOG_DIR/map_server.log"
    : > "$LOG_DIR/amcl.log"

    echo ">>> Starting map_server manually" >> "$LOG_DIR/nav2_localization.log"
    run_logged "map_server" "$LOG_DIR/map_server.log" \
        env RCUTILS_LOGGING_BUFFERED_STREAM=0 \
        stdbuf -oL -eL ros2 run nav2_map_server map_server --ros-args \
        -p use_sim_time:="$USE_SIM_TIME" \
        -p yaml_filename:="$MAP_FILE"
    map_server_pid=$!
    monitor_process "$map_server_pid" "map_server" "$LOG_DIR/nav2_localization.log"

    if ! wait_for_node /map_server 15; then
        amcl_startup_failure "/map_server node did not appear."
    fi
    if ! lifecycle_set_retry /map_server configure 20 >> "$LOG_DIR/nav2_localization.log" 2>&1; then
        amcl_startup_failure "/map_server configure failed."
    fi
    if ! lifecycle_set_retry /map_server activate 20 >> "$LOG_DIR/nav2_localization.log" 2>&1; then
        amcl_startup_failure "/map_server activate failed."
    fi
    if ! lifecycle_wait_active /map_server 20; then
        amcl_startup_failure "/map_server did not stay active."
    fi
    sleep "$MAP_SERVER_SETTLE_SEC"

    echo ">>> Starting AMCL manually" >> "$LOG_DIR/nav2_localization.log"
    run_logged "amcl" "$LOG_DIR/amcl.log" \
        env RCUTILS_LOGGING_BUFFERED_STREAM=0 \
        stdbuf -oL -eL ros2 run nav2_amcl amcl --ros-args \
        -r __node:=amcl \
        --params-file "$NAV2_PARAMS_FILE" \
        -p set_initial_pose:=true \
        -p always_reset_initial_pose:=true \
        -p initial_pose.x:="$INITIAL_POSE_X" \
        -p initial_pose.y:="$INITIAL_POSE_Y" \
        -p initial_pose.z:=0.0 \
        -p initial_pose.yaw:="$INITIAL_POSE_YAW"
    amcl_pid=$!
    monitor_process "$amcl_pid" "amcl" "$LOG_DIR/nav2_localization.log"

    if ! wait_for_node /amcl 15; then
        amcl_startup_failure "/amcl node did not appear."
    fi
    if ! lifecycle_set_retry /amcl configure 25 >> "$LOG_DIR/nav2_localization.log" 2>&1; then
        amcl_startup_failure "/amcl configure failed."
    fi
    if ! lifecycle_set_retry /amcl activate 25 >> "$LOG_DIR/nav2_localization.log" 2>&1; then
        amcl_startup_failure "/amcl activate failed."
    fi
    if ! lifecycle_wait_active /amcl 25; then
        amcl_startup_failure "/amcl did not stay active."
    fi
    sleep "$AMCL_SETTLE_SEC"

    if ! wait_for_node /amcl 2; then
        amcl_startup_failure "/amcl exited immediately after activation."
    fi
    start_scan_pipeline
    if ! wait_for_topic_message "$SCAN_TOPIC" sensor_msgs/msg/LaserScan "$AMCL_OUTPUT_WAIT"; then
        amcl_startup_failure "$SCAN_TOPIC did not provide a fresh scan before AMCL validation."
    fi

    if [ "$PUBLISH_INITIAL_POSE" = "true" ] || [ "$PUBLISH_INITIAL_POSE" = "1" ]; then
        echo ">>> [7.5/11] Checking AMCL initial pose before navigation"
        if wait_for_tf map "$NAV_BASE_FRAME" 2; then
            INITIAL_POSE_WAS_PUBLISHED=true
            echo "    map -> $NAV_BASE_FRAME TF is already available; skip duplicate /initialpose"
        else
            echo "    publishing initial pose: x=$INITIAL_POSE_X y=$INITIAL_POSE_Y yaw=$INITIAL_POSE_YAW repeat=$INITIAL_POSE_REPEAT"
            if publish_initial_pose; then
                INITIAL_POSE_WAS_PUBLISHED=true
                echo "    map -> $NAV_BASE_FRAME TF is available"
            else
                echo "Warning: map -> $NAV_BASE_FRAME TF did not appear after initial pose." >&2
                echo "         Check $LOG_DIR/nav2_localization.log" >&2
            fi
        fi
    elif [ "$AMCL_GLOBAL_LOCALIZATION" = "true" ] || [ "$AMCL_GLOBAL_LOCALIZATION" = "1" ]; then
        echo ">>> [7.5/11] Requesting AMCL global localization before navigation"
        sleep "$AMCL_GLOBAL_LOCALIZATION_DELAY"
        if ros2 service list | grep -qx "/reinitialize_global_localization"; then
            ros2 service call /reinitialize_global_localization std_srvs/srv/Empty "{}" >/dev/null || true
        else
            echo "Warning: /reinitialize_global_localization service is not available." >&2
        fi
    fi

    if ! wait_for_tf map "$NAV_BASE_FRAME" "$AMCL_READY_TIMEOUT"; then
        amcl_startup_failure "AMCL map -> $NAV_BASE_FRAME TF is not available yet."
    fi

    if ! wait_for_node /amcl 2; then
        amcl_startup_failure "/amcl exited after publishing initial TF."
    fi
    if ! wait_for_topic_message /particle_cloud nav2_msgs/msg/ParticleCloud "$AMCL_OUTPUT_WAIT"; then
        echo "Warning: /particle_cloud did not publish during startup validation." >&2
        echo "         This is not fatal unless AMCL_REQUIRE_OUTPUT_TOPICS=true." >&2
        if [ "$AMCL_REQUIRE_OUTPUT_TOPICS" = "true" ] || [ "$AMCL_REQUIRE_OUTPUT_TOPICS" = "1" ]; then
            amcl_startup_failure "/particle_cloud did not publish."
        fi
    fi
    if ! wait_for_topic_message /amcl_pose geometry_msgs/msg/PoseWithCovarianceStamped "$AMCL_OUTPUT_WAIT"; then
        echo "Warning: /amcl_pose did not publish during startup validation." >&2
        echo "         This is not fatal unless AMCL_REQUIRE_OUTPUT_TOPICS=true." >&2
        if [ "$AMCL_REQUIRE_OUTPUT_TOPICS" = "true" ] || [ "$AMCL_REQUIRE_OUTPUT_TOPICS" = "1" ]; then
            amcl_startup_failure "/amcl_pose did not publish."
        fi
    fi

    if [ "$START_NAVIGATION" = "true" ] || [ "$START_NAVIGATION" = "1" ]; then
        ros2 launch nav2_bringup navigation_launch.py \
            use_sim_time:="$USE_SIM_TIME" \
            params_file:="$NAV2_PARAMS_FILE" \
            autostart:="$AUTOSTART" \
            map_subscribe_transient_local:=true \
            > "$LOG_DIR/nav2_bringup.log" 2>&1 &
    else
        echo "    START_NAVIGATION=false, skipping Nav2 planner/controller/costmaps."
        echo "    Localization-only mode: verify /scan, odom->$NAV_BASE_FRAME, and map->$NAV_BASE_FRAME first."
    fi
else
    echo "Error: unsupported LOCALIZATION_MODE=$LOCALIZATION_MODE (expected static, amcl, or icp)" >&2
    exit 1
fi

if [ "$START_NAVIGATION" = "true" ] || [ "$START_NAVIGATION" = "1" ]; then
    sleep 8
else
    sleep 2
fi

echo ">>> [8/11] Starting RViz in VNC"
if [ "$START_RVIZ" = "true" ] || [ "$START_RVIZ" = "1" ]; then
    if systemctl --user list-unit-files 2>/dev/null | grep -q '^rviz-vnc.service'; then
        systemctl --user start rviz-vnc.service || true
    fi
    if [ ! -S "/tmp/.X11-unix/X${RVIZ_DISPLAY#:}" ]; then
        echo "Warning: display $RVIZ_DISPLAY is not available; RViz not started." >&2
        echo "Try: systemctl --user restart rviz-vnc.service" >&2
    else
        DISPLAY="$RVIZ_DISPLAY" \
        XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}" \
        LIBGL_ALWAYS_SOFTWARE=1 \
        QT_X11_NO_MITSHM=1 \
        setsid nohup ros2 run rviz2 rviz2 -d "$RVIZ_CONFIG" \
        > "$LOG_DIR/rviz.log" 2>&1 < /dev/null &
        sleep 3
        if ! pgrep -af "/opt/ros/foxy/lib/rviz2/rviz2.*$RVIZ_CONFIG" >/dev/null; then
            echo "Warning: RViz process exited shortly after launch. Check $LOG_DIR/rviz.log" >&2
        fi
    fi
fi

echo ">>> [9/11] Initial pose"
if [ "$LOCALIZATION_MODE" = "static" ]; then
    echo "    LOCALIZATION_MODE=static: using fixed map -> odom from initial pose"
    echo "    AMCL is not started, so scan follows FAST-LIO odom without AMCL correction."
elif [ "$AMCL_GLOBAL_LOCALIZATION" = "true" ] || [ "$AMCL_GLOBAL_LOCALIZATION" = "1" ]; then
    echo "    requesting AMCL global localization"
    if ! wait_for_topic_message "$SCAN_TOPIC" sensor_msgs/msg/LaserScan 10; then
        echo "Warning: $SCAN_TOPIC is not receiving fresh messages; skip AMCL global localization." >&2
    elif ! wait_for_topic_message /tf tf2_msgs/msg/TFMessage 10; then
        echo "Warning: /tf is not receiving fresh FAST-LIO transforms; skip AMCL global localization." >&2
    else
    sleep "$AMCL_GLOBAL_LOCALIZATION_DELAY"
    if ros2 service list | grep -qx "/reinitialize_global_localization"; then
        ros2 service call /reinitialize_global_localization std_srvs/srv/Empty "{}" >/dev/null || true
        echo "    AMCL particles reset globally. Move/rotate the robot slowly until scan matches the map."
    else
        echo "Warning: /reinitialize_global_localization service is not available." >&2
    fi
    fi
elif [ "$LOCALIZATION_MODE" != "static" ]; then
    echo "    AMCL initial pose was handled before navigation startup; skip duplicate /initialpose"
    if wait_for_tf map "$NAV_BASE_FRAME" 2; then
        echo "    map -> $NAV_BASE_FRAME TF is available"
    else
        echo "Warning: map -> $NAV_BASE_FRAME TF is not available." >&2
        echo "         Do not repeatedly publish /initialpose on Foxy; check $LOG_DIR/nav2_localization.log" >&2
    fi
elif [ "$PUBLISH_INITIAL_POSE" = "true" ] || [ "$PUBLISH_INITIAL_POSE" = "1" ]; then
    if [ "$INITIAL_POSE_WAS_PUBLISHED" = "true" ]; then
        echo "    initial pose was already published before navigation startup"
    else
    echo "    publishing initial pose: x=$INITIAL_POSE_X y=$INITIAL_POSE_Y yaw=$INITIAL_POSE_YAW repeat=$INITIAL_POSE_REPEAT"
    if publish_initial_pose || wait_for_tf map "$NAV_BASE_FRAME" 20; then
        echo "    map -> $NAV_BASE_FRAME TF is available"
    else
        echo "Warning: map -> $NAV_BASE_FRAME TF did not appear." >&2
        echo "         Use RViz '2D Pose Estimate' and check $LOG_DIR/nav2_bringup.log" >&2
    fi
    fi
else
    echo "    Use RViz '2D Pose Estimate' before sending Nav2 Goal."
fi

echo ">>> [10/11] Starting Go2 cmd_vel bridge"
if [ "$START_GO2_CMD_BRIDGE" = "true" ] || [ "$START_GO2_CMD_BRIDGE" = "1" ]; then
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
        -p enabled:="$GO2_CMD_BRIDGE_ENABLED" \
        -p send_zero_when_idle:="$GO2_SEND_ZERO_WHEN_IDLE" \
        -p remote_priority:="$GO2_REMOTE_PRIORITY" \
        -p remote_topic:="$GO2_REMOTE_TOPIC" \
        -p remote_deadband:="$GO2_REMOTE_DEADBAND" \
        -p remote_hold_sec:="$GO2_REMOTE_HOLD_SEC" \
        -p log_commands:="$GO2_LOG_COMMANDS" \
        -p log_interval_sec:="$GO2_LOG_INTERVAL_SEC" \
        > "$LOG_DIR/go2_cmd_bridge.log" 2>&1 &
else
    echo "    START_GO2_CMD_BRIDGE=false, Nav2 will plan but not move the robot."
fi

GO2_IP="$(ip -4 addr show wlan0 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -1)"
if [ -z "$GO2_IP" ]; then
    GO2_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
fi

cat <<EOF

>>> [11/11] MID360 FAST-LIO Nav2 stack is running

VNC:
  ${GO2_IP:-<go2-wlan0-ip>}:5901

RViz workflow:
  1. Fixed Frame = map
  2. If the robot is not aligned, prefer AMCL_GLOBAL_LOCALIZATION=true instead of RViz 2D Pose Estimate
  3. Use "Nav2 Goal" to test planning
  4. Enable real motion only after RViz looks sane:
     START_GO2_CMD_BRIDGE=true $0

TF:
  map -> odom              $LOCALIZATION_MODE
  odom -> $FASTLIO_BODY_FRAME      FAST-LIO
EOF

if [ "$FASTLIO_BODY_FRAME" != "$NAV_BASE_FRAME" ]; then
    cat <<EOF
  $FASTLIO_BODY_FRAME -> $NAV_BASE_FRAME  static:
      xyz=($LIDAR_TO_BASE_X, $LIDAR_TO_BASE_Y, $LIDAR_TO_BASE_Z)
      rpy=($LIDAR_TO_BASE_ROLL, $LIDAR_TO_BASE_PITCH, $LIDAR_TO_BASE_YAW)
      foxy_args=yaw,pitch,roll
EOF
else
    cat <<EOF
  base frame is $NAV_BASE_FRAME; no extra lidar->base static TF is published
EOF
fi

cat <<EOF
Topics:
  lidar:        $LIDAR_CLOUD_TOPIC
  imu:          $LIDAR_IMU_TOPIC
  body cloud:   $BODY_CLOUD_TOPIC
  scan:         $SCAN_TOPIC
  map:          /map
  cmd_vel:      $GO2_CMD_TOPIC
  Go2 bridge:   max=($GO2_MAX_VX, $GO2_MAX_VY, $GO2_MAX_WZ)
                mapping swap_xy=$GO2_SWAP_XY signs=($GO2_X_SIGN, $GO2_Y_SIGN, $GO2_WZ_SIGN)
                deadband=($GO2_DEADBAND_V, $GO2_DEADBAND_W) floor=($GO2_MIN_CMD_V, $GO2_MIN_CMD_W)

Localization:
  initial_pose:             $PUBLISH_INITIAL_POSE ($INITIAL_POSE_X, $INITIAL_POSE_Y, $INITIAL_POSE_YAW)
  amcl_global_localization: $AMCL_GLOBAL_LOCALIZATION
  localization_mode:        $LOCALIZATION_MODE

Logs:
  $LOG_DIR

ROS middleware:
  RMW_IMPLEMENTATION=$RMW_IMPLEMENTATION
  CYCLONEDDS_HOME/CYCLONEDDS_URI are unset for this stack

Press Ctrl-C in this terminal to stop the stack and send zero velocity.

EOF

wait
