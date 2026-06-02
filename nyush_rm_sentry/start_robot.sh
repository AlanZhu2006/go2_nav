#!/usr/bin/env bash

set -eo pipefail

# --- 脚本功能：一键启动 激光雷达 + FAST-LIO + Nav2 + 当前主线行为树 ---

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ "${GO2_NAV2_ONLY:-0}" = "1" ]; then
    exec "$SCRIPT_DIR/scripts/start_go2_nav2_with_rviz.sh"
fi

SENTRY_ROOT="$SCRIPT_DIR"
NAV_WS_ROOT="${NAV_WS_ROOT:-$HOME/nav_ws}"
RM_VISION_WS_ROOT="${RM_VISION_WS_ROOT:-$SENTRY_ROOT/rm_vision_ws}"
RM_DECISION_WS_ROOT="${RM_DECISION_WS_ROOT:-$SENTRY_ROOT/rm_decision_ws}"
ROS_DISTRO_NAME="${ROS_DISTRO_NAME:-foxy}"
ROS_SETUP="${ROS_SETUP:-/opt/ros/$ROS_DISTRO_NAME/setup.bash}"
BT_STYLE="${BT_STYLE:-center_attack_simple}"
USE_SIM_TIME="${USE_SIM_TIME:-False}"
ENABLE_RVIZ="${ENABLE_RVIZ:-0}"
RVIZ_CONFIG="${RVIZ_CONFIG:-}"
RESET_FASTRTPS_SHM="${RESET_FASTRTPS_SHM:-0}"
START_SERIAL_SENDER="${START_SERIAL_SENDER:-0}"
RADAR_PTY="${RADAR_PTY:-}"
SERIAL_SENDER_TOPIC="${SERIAL_SENDER_TOPIC:-/cmd_vel_chassis_bt}"
SERIAL_SENDER_PORT="${SERIAL_SENDER_PORT:-$RADAR_PTY}"
MAP_FILE="${MAP_FILE:-$SENTRY_ROOT/rm_navigation_ws/src/rm_nav_bringup/map/RMUL2026.yaml}"
NAV2_PARAMS_FILE="${NAV2_PARAMS_FILE:-$SENTRY_ROOT/my_nav2_params.yaml}"
PUBLISH_NAV2_INITIAL_POSE="${PUBLISH_NAV2_INITIAL_POSE:-1}"
NAV2_INITIAL_POSE_X="${NAV2_INITIAL_POSE_X:-0.8}"
NAV2_INITIAL_POSE_Y="${NAV2_INITIAL_POSE_Y:-7.8}"
NAV2_INITIAL_POSE_YAW="${NAV2_INITIAL_POSE_YAW:-0.0}"
LOCALIZATION_MODE="${LOCALIZATION_MODE:-amcl}"
WAIT_MANUAL_INITIAL_POSE="${WAIT_MANUAL_INITIAL_POSE:-0}"
WAIT_MANUAL_INITIAL_POSE_TIMEOUT="${WAIT_MANUAL_INITIAL_POSE_TIMEOUT:-600}"
RVIZ_STARTED="${RVIZ_STARTED:-0}"
NAV_BASE_FRAME="${NAV_BASE_FRAME:-base_link}"
FAKE_VEL_USE_PATH_HEADING_COMPENSATION="${FAKE_VEL_USE_PATH_HEADING_COMPENSATION:-false}"
FAKE_VEL_SWAP_NAV_XY="${FAKE_VEL_SWAP_NAV_XY:-false}"
FAKE_VEL_CHASSIS_X_SIGN="${FAKE_VEL_CHASSIS_X_SIGN:-1.0}"
FAKE_VEL_CHASSIS_Y_SIGN="${FAKE_VEL_CHASSIS_Y_SIGN:-1.0}"
CHASSIS_BACKEND="${CHASSIS_BACKEND:-go2}"  # go2, serial, none
UNITREE_NET_IF="${UNITREE_NET_IF:-eth0}"
UNITREE_SDK2PY_PATH="${UNITREE_SDK2PY_PATH:-/home/unitree/unitree_sdk2_python}"
GO2_CMD_TOPIC="${GO2_CMD_TOPIC:-/cmd_vel_chassis_bt}"
GO2_MAX_VX="${GO2_MAX_VX:-0.35}"
GO2_MAX_VY="${GO2_MAX_VY:-0.25}"
GO2_MAX_WZ="${GO2_MAX_WZ:-0.60}"
GO2_X_SIGN="${GO2_X_SIGN:-1.0}"
GO2_Y_SIGN="${GO2_Y_SIGN:-1.0}"
GO2_WZ_SIGN="${GO2_WZ_SIGN:-1.0}"
GO2_SWAP_XY="${GO2_SWAP_XY:-false}"
MAP_BASENAME="$(basename "${MAP_FILE%.yaml}")"
MAP_DIR="$(dirname "$MAP_FILE")"
MAP_ROOT_DIR="$(dirname "$MAP_DIR")"
ICP_CONFIG_FILE="${ICP_CONFIG_FILE:-$NAV_WS_ROOT/src/pb_rm_simulation/src/rm_nav_bringup/config/reality/icp_registration_real.yaml}"
ICP_PCD_FILE="${ICP_PCD_FILE:-$MAP_ROOT_DIR/PCD/${MAP_BASENAME}.pcd}"
if [ ! -f "$ICP_PCD_FILE" ]; then
    ALT_ICP_PCD_FILE="$NAV_WS_ROOT/src/pb_rm_simulation/src/rm_nav_bringup/PCD/${MAP_BASENAME}.pcd"
    if [ -f "$ALT_ICP_PCD_FILE" ]; then
        ICP_PCD_FILE="$ALT_ICP_PCD_FILE"
    fi
fi
ICP_INITIAL_POSE_X="${ICP_INITIAL_POSE_X:-$NAV2_INITIAL_POSE_X}"
ICP_INITIAL_POSE_Y="${ICP_INITIAL_POSE_Y:-$NAV2_INITIAL_POSE_Y}"
ICP_INITIAL_POSE_Z="${ICP_INITIAL_POSE_Z:-0.0}"
ICP_INITIAL_POSE_ROLL="${ICP_INITIAL_POSE_ROLL:-0.0}"
ICP_INITIAL_POSE_PITCH="${ICP_INITIAL_POSE_PITCH:-0.0}"
ICP_INITIAL_POSE_YAW="${ICP_INITIAL_POSE_YAW:-$NAV2_INITIAL_POSE_YAW}"
ICP_THRESH="${ICP_THRESH:-0.35}"
ICP_XY_OFFSET="${ICP_XY_OFFSET:-0.75}"
ICP_XY_SEARCH_STEPS="${ICP_XY_SEARCH_STEPS:-3}"
ICP_YAW_OFFSET="${ICP_YAW_OFFSET:-180.0}"
ICP_YAW_RESOLUTION="${ICP_YAW_RESOLUTION:-15.0}"
ICP_POINTCLOUD_TOPIC="${ICP_POINTCLOUD_TOPIC:-/cloud_registered_body}"
ICP_LASER_FRAME_ID="${ICP_LASER_FRAME_ID:-base_link}"
ICP_RANGE_ODOM_FRAME_ID="${ICP_RANGE_ODOM_FRAME_ID:-odom}"
ICP_ODOM_FRAME_ID="${ICP_ODOM_FRAME_ID:-odom}"
ICP_MAP_OFFSET_X="${ICP_MAP_OFFSET_X:-}"
ICP_MAP_OFFSET_Y="${ICP_MAP_OFFSET_Y:-}"
ICP_MAP_OFFSET_Z="${ICP_MAP_OFFSET_Z:-0.0}"

cleanup() {
    echo "正在关闭所有节点..."
    kill $(jobs -p) 2>/dev/null || true
    rm -f "${ICP_RUNTIME_CONFIG:-}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

wait_for_tf() {
    local target_frame="$1"
    local source_frame="$2"
    local timeout_secs="$3"

    python3 - "$target_frame" "$source_frame" "$timeout_secs" <<'PYWAITTF'
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
node = Node("start_robot_wait_for_tf")
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
PYWAITTF
}

wait_for_initial_pose() {
    local timeout_secs="$1"

    python3 - "$timeout_secs" <<'PYWAITPOSE'
import sys
import time

import rclpy
from rclpy.node import Node
from geometry_msgs.msg import PoseWithCovarianceStamped

timeout_secs = float(sys.argv[1])

rclpy.init()
node = Node("start_robot_wait_for_initial_pose")
received = False

def on_pose(_msg):
    global received
    received = True

sub = node.create_subscription(PoseWithCovarianceStamped, "/initialpose", on_pose, 10)
deadline = time.time() + timeout_secs

while time.time() < deadline and not received:
    rclpy.spin_once(node, timeout_sec=0.1)

node.destroy_node()
rclpy.shutdown()
sys.exit(0 if received else 1)
PYWAITPOSE
}

launch_rviz_background() {
    if [ "$ENABLE_RVIZ" != "1" ] || [ "$RVIZ_STARTED" = "1" ]; then
        return
    fi

    echo ">>> Launching RViz for manual localization..."
    if [ -n "$RVIZ_CONFIG" ] && [ -f "$RVIZ_CONFIG" ]; then
        ros2 run rviz2 rviz2 -d "$RVIZ_CONFIG" &
    else
        ros2 run rviz2 rviz2 &
    fi
    RVIZ_STARTED=1
    sleep 2
}

if [ ! -f "$ROS_SETUP" ]; then
    echo "Error: ROS setup not found: $ROS_SETUP"
    echo "Set ROS_DISTRO_NAME=foxy or ROS_SETUP=/path/to/setup.bash"
    exit 1
fi
source "$ROS_SETUP"
for setup_file in \
    "$NAV_WS_ROOT/install/setup.bash" \
    "$SENTRY_ROOT/rm_navigation_ws/install/setup.bash" \
    "$RM_VISION_WS_ROOT/install/setup.bash" \
    "$RM_DECISION_WS_ROOT/install/setup.bash"
do
    if [ -f "$setup_file" ]; then
        source "$setup_file"
    fi
done

if [ -z "$RVIZ_CONFIG" ]; then
    RVIZ_CONFIG="$(ros2 pkg prefix nav2_bringup 2>/dev/null || true)/share/nav2_bringup/rviz/nav2_default_view.rviz"
fi

if [ ! -w "$HOME/.ros/log" ] 2>/dev/null; then
    export ROS_LOG_DIR="${ROS_LOG_DIR:-/tmp/ros_logs_start_robot}"
    mkdir -p "$ROS_LOG_DIR"
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "❌ 错误：未找到 python3"
    exit 1
fi

echo ">>> [0/11] 清理环境..."
if [ "$RESET_FASTRTPS_SHM" = "1" ]; then
    echo "    RESET_FASTRTPS_SHM=1, removing /dev/shm/fastrtps_* ..."
    rm -f /dev/shm/fastrtps_* 2>/dev/null || true
fi
ros2 daemon stop || true
ros2 daemon start

echo "   正在停止旧的 ROS2 / 导航 / 行为树残留进程..."
pkill -9 -f fast_lio_mapping 2>/dev/null || true
pkill -9 -f livox_ros_driver2 2>/dev/null || true
pkill -9 -f pointcloud_to_laserscan 2>/dev/null || true
pkill -9 -f nav2 2>/dev/null || true
pkill -9 -f fake_vel_transform 2>/dev/null || true
pkill -9 -f "$SENTRY_ROOT/scripts/go2_cmd_bridge.py" 2>/dev/null || true
pkill -9 -f icp_registration 2>/dev/null || true
pkill -9 -f rm_behavior_tree 2>/dev/null || true
pkill -9 -f "$SENTRY_ROOT/scripts/bt_comm_adapter.py" 2>/dev/null || true
if [ "$START_SERIAL_SENDER" = "1" ] && [ -n "$SERIAL_SENDER_PORT" ]; then
    pkill -9 -f "/home/nyu/Codespace/nyush-rm-vision/serial_sender.py --port $SERIAL_SENDER_PORT" 2>/dev/null || true
fi
sleep 2

echo ">>> [1/11] 初始化环境..."
echo "   ROS_SETUP=$ROS_SETUP"
echo "   BT_STYLE=$BT_STYLE"
echo "   LOCALIZATION_MODE=$LOCALIZATION_MODE"
echo "   CHASSIS_BACKEND=$CHASSIS_BACKEND"
echo "   USE_SIM_TIME=$USE_SIM_TIME"
echo "   ENABLE_RVIZ=$ENABLE_RVIZ"
echo "   MAP_FILE=$MAP_FILE"
echo "   NAV2_PARAMS_FILE=$NAV2_PARAMS_FILE"
echo "   WAIT_MANUAL_INITIAL_POSE=$WAIT_MANUAL_INITIAL_POSE"
if [ "$PUBLISH_NAV2_INITIAL_POSE" = "1" ]; then
    echo "   NAV2_INITIAL_POSE=($NAV2_INITIAL_POSE_X, $NAV2_INITIAL_POSE_Y, yaw=$NAV2_INITIAL_POSE_YAW)"
fi
if [ "$LOCALIZATION_MODE" = "icp" ]; then
    echo "   ICP_PCD_FILE=$ICP_PCD_FILE"
    echo "   ICP_INITIAL_POSE=($ICP_INITIAL_POSE_X, $ICP_INITIAL_POSE_Y, yaw=$ICP_INITIAL_POSE_YAW)"
    echo "   ICP_SEARCH=(xy_offset=$ICP_XY_OFFSET, xy_steps=$ICP_XY_SEARCH_STEPS, yaw_offset=$ICP_YAW_OFFSET, yaw_resolution=$ICP_YAW_RESOLUTION, thresh=$ICP_THRESH)"
    echo "   ICP_INPUT=(topic=$ICP_POINTCLOUD_TOPIC, laser_frame=$ICP_LASER_FRAME_ID, range_odom=$ICP_RANGE_ODOM_FRAME_ID, odom=$ICP_ODOM_FRAME_ID)"
fi
if [ "$START_SERIAL_SENDER" = "1" ] || [ "$CHASSIS_BACKEND" = "serial" ]; then
    echo "   START_SERIAL_SENDER=1 ($SERIAL_SENDER_PORT <- $SERIAL_SENDER_TOPIC)"
fi
if [ "$CHASSIS_BACKEND" = "go2" ]; then
    echo "   GO2=(net_if=$UNITREE_NET_IF, topic=$GO2_CMD_TOPIC, max=[$GO2_MAX_VX,$GO2_MAX_VY,$GO2_MAX_WZ])"
fi

echo ">>> [2/11] 检查底盘输出后端..."
if [ "$CHASSIS_BACKEND" = "serial" ] || [ "$START_SERIAL_SENDER" = "1" ]; then
    if [ -e /dev/ttyACM0 ]; then
        sudo chmod 777 /dev/ttyACM0
    else
        echo "警告: 未检测到 /dev/ttyACM0，跳过权限设置"
    fi
elif [ "$CHASSIS_BACKEND" = "go2" ]; then
    if [ ! -d "$UNITREE_SDK2PY_PATH" ]; then
        echo "Error: UNITREE_SDK2PY_PATH not found: $UNITREE_SDK2PY_PATH"
        exit 1
    fi
fi

echo ">>> [3/11] 启动 MI360 激光雷达驱动..."
ros2 launch livox_ros_driver2 msg_MID360_launch.py &
DRIVER_PID=$!
echo ">>> 等待雷达驱动启动 (5秒)..."
sleep 5

if timeout 2 ros2 topic echo /livox/lidar --once > /dev/null 2>&1; then
    echo "✅ 雷达驱动已启动并发送数据"
else
    echo "❌ 警告：未检测到雷达数据！请检查网线连接或防火墙。"
fi

echo ">>> [4/11] 发布静态 TF 变换..."
ros2 run tf2_ros static_transform_publisher \
    --x 0 --y 0 --z 0 \
    --yaw 0 --pitch 0 --roll 0 \
    --frame-id odom --child-frame-id camera_init &
ros2 run tf2_ros static_transform_publisher \
    --x 0 --y 0 --z 0 \
    --yaw 0 --pitch -0.873 --roll 0 \
    --frame-id body --child-frame-id base_link &

echo ">>> [5/11] 启动 FAST-LIO 里程计..."
export LD_PRELOAD=/lib/x86_64-linux-gnu/libusb-1.0.so.0
ros2 launch fast_lio mapping.launch.py config_file:=mid360.yaml &
sleep 5

echo ">>> [6/11] 启动 Pointcloud 转 LaserScan..."
ros2 run pointcloud_to_laserscan pointcloud_to_laserscan_node --ros-args -p target_frame:=base_link -p transform_tolerance:=0.01 -p min_height:=-0.4 -p max_height:=1.0 -p angle_min:=-3.1415 -p angle_max:=3.1415 -p range_min:=0.1 -p range_max:=20.0 -p use_inf:=true -p qos_overrides./cloud_in.reliability:=best_effort -r cloud_in:=/cloud_registered -r scan:=/scan &

echo ">>> [7/11] 启动定位与地图服务..."
if [ "$LOCALIZATION_MODE" = "icp" ]; then
    if [ ! -f "$ICP_CONFIG_FILE" ]; then
        echo "Error: ICP config not found: $ICP_CONFIG_FILE"
        exit 1
    fi
    if [ ! -f "$ICP_PCD_FILE" ]; then
        echo "Error: ICP PCD not found: $ICP_PCD_FILE"
        exit 1
    fi
    ros2 launch rm_navigation map_server_launch.py use_sim_time:="$USE_SIM_TIME" map:="$MAP_FILE" params_file:="$NAV2_PARAMS_FILE" use_composition:=False &
    sleep 2
elif [ "$LOCALIZATION_MODE" = "amcl" ]; then
    ros2 launch rm_navigation map_server_launch.py \
        use_sim_time:="$USE_SIM_TIME" \
        map:="$MAP_FILE" \
        params_file:="$NAV2_PARAMS_FILE" \
        use_composition:=False &
    sleep 2
    ros2 launch rm_navigation localization_amcl_launch.py \
        use_sim_time:="$USE_SIM_TIME" \
        params_file:="$NAV2_PARAMS_FILE" \
        use_composition:=False &
else
    echo "Error: unsupported LOCALIZATION_MODE=$LOCALIZATION_MODE (expected amcl or icp)"
    exit 1
fi

echo ">>> [8/11] 等待 Nav2 启动 (8秒)..."
sleep 8

if [ "$LOCALIZATION_MODE" = "icp" ]; then
    echo ">>> [8.5/11] Starting ICP localization..."
    export ICP_CONFIG_FILE ICP_PCD_FILE ICP_INITIAL_POSE_X ICP_INITIAL_POSE_Y
    export ICP_INITIAL_POSE_Z ICP_INITIAL_POSE_ROLL ICP_INITIAL_POSE_PITCH
    export ICP_INITIAL_POSE_YAW ICP_THRESH ICP_XY_OFFSET ICP_XY_SEARCH_STEPS
    export ICP_YAW_OFFSET ICP_YAW_RESOLUTION ICP_POINTCLOUD_TOPIC
    export ICP_LASER_FRAME_ID ICP_RANGE_ODOM_FRAME_ID ICP_ODOM_FRAME_ID
    export ICP_MAP_OFFSET_X ICP_MAP_OFFSET_Y ICP_MAP_OFFSET_Z MAP_FILE USE_SIM_TIME
    ICP_RUNTIME_CONFIG="$(mktemp /tmp/icp_registration.XXXXXX.yaml)"
    export ICP_RUNTIME_CONFIG
    python3 - <<'PYICP'
import os
import warnings
import yaml

warnings.filterwarnings("ignore")

config_path = os.environ["ICP_CONFIG_FILE"]
output_path = os.environ["ICP_RUNTIME_CONFIG"]
with open(config_path, "r", encoding="utf-8") as handle:
    config = yaml.safe_load(handle)

params = config.setdefault("/icp_registration", {}).setdefault("ros__parameters", {})
params["use_sim_time"] = os.environ.get("USE_SIM_TIME", "False").lower() == "true"
params["pcd_path"] = os.environ["ICP_PCD_FILE"]
params["pointcloud_topic"] = os.environ["ICP_POINTCLOUD_TOPIC"]
params["laser_frame_id"] = os.environ["ICP_LASER_FRAME_ID"]
params["range_odom_frame_id"] = os.environ["ICP_RANGE_ODOM_FRAME_ID"]
params["odom_frame_id"] = os.environ["ICP_ODOM_FRAME_ID"]
params["thresh"] = float(os.environ["ICP_THRESH"])
params["xy_offset"] = float(os.environ["ICP_XY_OFFSET"])
params["xy_search_steps"] = int(os.environ["ICP_XY_SEARCH_STEPS"])
params["yaw_offset"] = float(os.environ["ICP_YAW_OFFSET"])
params["yaw_resolution"] = float(os.environ["ICP_YAW_RESOLUTION"])

map_offset_x_env = os.environ.get("ICP_MAP_OFFSET_X", "").strip()
map_offset_y_env = os.environ.get("ICP_MAP_OFFSET_Y", "").strip()
map_offset_z_env = os.environ.get("ICP_MAP_OFFSET_Z", "0.0").strip()
if map_offset_x_env and map_offset_y_env:
    map_offset_x = float(map_offset_x_env)
    map_offset_y = float(map_offset_y_env)
else:
    import numpy as np
    import open3d as o3d

    with open(os.environ["MAP_FILE"], "r", encoding="utf-8") as handle:
        map_config = yaml.safe_load(handle)
    map_origin = map_config.get("origin", [0.0, 0.0, 0.0])
    pcd = o3d.io.read_point_cloud(os.environ["ICP_PCD_FILE"])
    points = np.asarray(pcd.points)
    if points.size == 0:
        raise RuntimeError(f"Empty ICP PCD: {os.environ['ICP_PCD_FILE']}")
    min_bound = points.min(axis=0)
    map_offset_x = float(map_origin[0]) - float(min_bound[0])
    map_offset_y = float(map_origin[1]) - float(min_bound[1])
map_offset_z = float(map_offset_z_env or "0.0")
params["map_offset_x"] = map_offset_x
params["map_offset_y"] = map_offset_y
params["map_offset_z"] = map_offset_z
print(
    "ICP_MAP_OFFSET=(%.3f, %.3f, %.3f)" %
    (map_offset_x, map_offset_y, map_offset_z)
)

params["initial_pose"] = [
    float(os.environ["ICP_INITIAL_POSE_X"]),
    float(os.environ["ICP_INITIAL_POSE_Y"]),
    float(os.environ["ICP_INITIAL_POSE_Z"]),
    float(os.environ["ICP_INITIAL_POSE_ROLL"]),
    float(os.environ["ICP_INITIAL_POSE_PITCH"]),
    float(os.environ["ICP_INITIAL_POSE_YAW"]),
]

with open(output_path, "w", encoding="utf-8") as handle:
    yaml.safe_dump(config, handle, sort_keys=False)
PYICP
    ros2 run icp_registration icp_registration_node --ros-args --params-file "$ICP_RUNTIME_CONFIG" &
    echo ">>> [8.6/11] Waiting for odom -> base_link TF..."
    if ! wait_for_tf odom base_link 20; then
        echo "Error: odom -> base_link TF not available. FAST-LIO tree is incomplete."
        exit 1
    fi
    echo ">>> [8.7/11] Waiting for ICP to publish map -> odom..."
    if ! wait_for_tf map odom 90; then
        echo "Error: ICP did not publish map -> odom within timeout."
        exit 1
    fi
    ros2 launch rm_navigation bringup_rm_navigation.py use_sim_time:="$USE_SIM_TIME" map:="$MAP_FILE" params_file:="$NAV2_PARAMS_FILE" nav_rviz:=False &
    sleep 5
elif [ "$PUBLISH_NAV2_INITIAL_POSE" = "1" ]; then
    echo ">>> [8.5/11] 发布 Nav2 初始位姿..."
    export NAV2_INITIAL_POSE_X NAV2_INITIAL_POSE_Y NAV2_INITIAL_POSE_YAW
    INITIAL_POSE_MSG="$(python3 - <<'PYPOSE'
import math
import os

x = float(os.environ.get("NAV2_INITIAL_POSE_X", "0.8"))
y = float(os.environ.get("NAV2_INITIAL_POSE_Y", "7.8"))
yaw = float(os.environ.get("NAV2_INITIAL_POSE_YAW", "0.0"))
qz = math.sin(yaw * 0.5)
qw = math.cos(yaw * 0.5)
cov = [0.0] * 36
cov[0] = 0.25
cov[7] = 0.25
cov[35] = 0.06853891945200942
print(
    "{header: {frame_id: 'map'}, pose: {pose: {position: {x: %.4f, y: %.4f, z: 0.0}, orientation: {x: 0.0, y: 0.0, z: %.8f, w: %.8f}}, covariance: [%s]}}"
    % (x, y, qz, qw, ", ".join(str(v) for v in cov))
)
PYPOSE
)"
    ros2 topic pub -1 /initialpose geometry_msgs/msg/PoseWithCovarianceStamped "$INITIAL_POSE_MSG" > /dev/null
    sleep 1
fi

if [ "$LOCALIZATION_MODE" = "amcl" ] && [ "$WAIT_MANUAL_INITIAL_POSE" = "1" ]; then
    launch_rviz_background
    echo ">>> [8.6/11] Waiting for manual /initialpose..."
    echo "    Use RViz '2D Pose Estimate' or publish /initialpose, then startup will continue."
    if ! wait_for_initial_pose "$WAIT_MANUAL_INITIAL_POSE_TIMEOUT"; then
        echo "Error: Timed out waiting for manual /initialpose."
        exit 1
    fi
    echo ">>> [8.7/11] Waiting for map -> base_link TF after manual initial pose..."
    if ! wait_for_tf map base_link 60; then
        echo "Error: map -> base_link TF did not appear after manual initial pose."
        exit 1
    fi
fi

if [ "$LOCALIZATION_MODE" = "amcl" ]; then
    echo ">>> [8.8/11] Waiting for AMCL map -> $NAV_BASE_FRAME TF..."
    if ! wait_for_tf map "$NAV_BASE_FRAME" 60; then
        echo "Error: map -> $NAV_BASE_FRAME TF did not appear. Check /initialpose, /scan, and odom->$NAV_BASE_FRAME."
        exit 1
    fi
    echo ">>> [8.9/11] Starting Nav2 navigation nodes..."
    ros2 launch rm_navigation bringup_rm_navigation.py \
        use_sim_time:="$USE_SIM_TIME" \
        map:="$MAP_FILE" \
        params_file:="$NAV2_PARAMS_FILE" \
        nav_rviz:=False \
        use_composition:=False &
    sleep 5
fi

echo ">>> [9/11] 启动行为树通讯适配层..."
echo ">>> [9/11] Starting fake_vel_transform..."
ros2 run fake_vel_transform fake_vel_transform_node --ros-args \
    -p use_sim_time:="$USE_SIM_TIME" \
    -p nav_base_frame:="$NAV_BASE_FRAME" \
    -p use_path_heading_compensation:="$FAKE_VEL_USE_PATH_HEADING_COMPENSATION" \
    -p use_nav_wz:=false \
    -p swap_nav_xy:="$FAKE_VEL_SWAP_NAV_XY" \
    -p chassis_x_sign:="$FAKE_VEL_CHASSIS_X_SIGN" \
    -p chassis_y_sign:="$FAKE_VEL_CHASSIS_Y_SIGN" &
sleep 2
python3 "$SENTRY_ROOT/scripts/bt_comm_adapter.py" &
sleep 2

echo ">>> [10/11] 启动决策行为树 ($BT_STYLE)..."
ros2 launch rm_behavior_tree rm_behavior_tree.launch.py     style:="$BT_STYLE"     use_sim_time:="$USE_SIM_TIME" &
sleep 2

if [ "$CHASSIS_BACKEND" = "go2" ]; then
    echo ">>> [11/11] 启动 Go2 cmd bridge ($GO2_CMD_TOPIC -> SportClient.Move)..."
    UNITREE_NET_IF="$UNITREE_NET_IF" UNITREE_SDK2PY_PATH="$UNITREE_SDK2PY_PATH" \
    python3 "$SENTRY_ROOT/scripts/go2_cmd_bridge.py" --net-if "$UNITREE_NET_IF" --ros-args \
        -p cmd_vel_topic:="$GO2_CMD_TOPIC" \
        -p max_vx:="$GO2_MAX_VX" \
        -p max_vy:="$GO2_MAX_VY" \
        -p max_wz:="$GO2_MAX_WZ" \
        -p x_sign:="$GO2_X_SIGN" \
        -p y_sign:="$GO2_Y_SIGN" \
        -p wz_sign:="$GO2_WZ_SIGN" \
        -p swap_xy:="$GO2_SWAP_XY" &
elif [ "$START_SERIAL_SENDER" = "1" ] || [ "$CHASSIS_BACKEND" = "serial" ]; then
    if [ -z "$SERIAL_SENDER_PORT" ]; then
        echo "❌ 错误：串口后端需要提供 RADAR_PTY / SERIAL_SENDER_PORT"
        exit 1
    fi
    echo ">>> [11/11] 启动 serial_sender ($SERIAL_SENDER_PORT <- $SERIAL_SENDER_TOPIC)..."
    python3 "${SERIAL_SENDER_SCRIPT:-/home/nyu/Codespace/nyush-rm-vision/serial_sender.py}" \
        --port "$SERIAL_SENDER_PORT" \
        --ros2 \
        --topic "$SERIAL_SENDER_TOPIC" &
else
    echo ">>> [11/11] 启动完成！"
fi

echo "-----------------------------------------------------"
echo ">>> 当前主线节点已启动（Nav2 + bt_comm_adapter + rm_behavior_tree）"
echo ">>> 默认行为树：$BT_STYLE"
echo ">>> 底盘后端：$CHASSIS_BACKEND"
if [ "$CHASSIS_BACKEND" = "go2" ]; then
    echo ">>> Go2 当前使用 Unitree SportClient.Move，高层运动服务需要可用。"
else
    echo ">>> bridge 仍需单独在 nyush-rm-control 终端启动"
    echo ">>> 视觉程序仍需单独连 Vision PTY 启动"
    echo ">>> 如需自动写 Radar PTY，可这样运行："
    echo "    CHASSIS_BACKEND=serial RADAR_PTY=/tmp/nyush-rm-sentry-radar ./start_robot.sh"
fi
echo ""
echo ">>> 常用实机配套终端："
echo "    Go2: UNITREE_NET_IF=eth0 ./start_robot.sh"
echo "    串口哨兵: CHASSIS_BACKEND=serial RADAR_PTY=/tmp/nyush-rm-sentry-radar ./start_robot.sh"
echo ""
echo ">>> 关键话题检查："
echo "    ros2 topic echo /robot_control --once"
echo "    ros2 topic echo /cmd_vel_chassis_bt --once"
echo "-----------------------------------------------------"

if [ "$ENABLE_RVIZ" = "1" ]; then
    if [ "$RVIZ_STARTED" = "1" ]; then
        wait
    elif [ -n "$RVIZ_CONFIG" ] && [ -f "$RVIZ_CONFIG" ]; then
        ros2 run rviz2 rviz2 -d "$RVIZ_CONFIG"
    else
        ros2 run rviz2 rviz2
    fi
else
    wait
fi
