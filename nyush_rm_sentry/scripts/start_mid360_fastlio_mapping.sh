#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAV_WS_ROOT="${NAV_WS_ROOT:-$HOME/nav_ws}"
FASTLIO_CONFIG="${FASTLIO_CONFIG:-$NAV_WS_ROOT/src/FAST_LIO/config/mid360.yaml}"
MAP_OUTPUT_DIR="${MAP_OUTPUT_DIR:-$HOME/work/go2_nav/maps/mid360_fastlio_latest}"
MAP_FILE="${MAP_FILE:-$MAP_OUTPUT_DIR/fastlio_map.pcd}"
LOG_DIR="${LOG_DIR:-/tmp/mid360_fastlio_mapping}"
LIVOX_LOG="${LIVOX_LOG:-$LOG_DIR/livox_driver.log}"
FASTLIO_LOG="${FASTLIO_LOG:-$LOG_DIR/fastlio_mapping.log}"
START_RVIZ="${START_RVIZ:-true}"
RVIZ_DISPLAY="${RVIZ_DISPLAY:-:1}"
RVIZ_CONFIG="${RVIZ_CONFIG:-$HOME/work/go2_nav/mid360_fastlio.rviz}"
RVIZ_LOG="${RVIZ_LOG:-$LOG_DIR/rviz.log}"

MID360_IFACE="${MID360_IFACE:-eth0}"
MID360_HOST_IP="${MID360_HOST_IP:-192.168.1.2}"
MID360_LIDAR_IP="${MID360_LIDAR_IP:-192.168.1.3}"
LIDAR_CLOUD_TOPIC="${LIDAR_CLOUD_TOPIC:-/livox/lidar}"
LIDAR_IMU_TOPIC="${LIDAR_IMU_TOPIC:-/livox/imu}"
WAIT_TOPIC_TIMEOUT="${WAIT_TOPIC_TIMEOUT:-20}"
CHECK_SAMPLE_TIMEOUT="${CHECK_SAMPLE_TIMEOUT:-8}"

mkdir -p "$MAP_OUTPUT_DIR" "$LOG_DIR"

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

wait_for_topic() {
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

wait_for_sample() {
    local topic="$1"
    local timeout_secs="$2"
    local msg_type="$3"

    python3 - "$topic" "$timeout_secs" "$msg_type" <<'PY'
import importlib
import sys
import time

import rclpy
from rclpy.node import Node
from rclpy.qos import DurabilityPolicy, HistoryPolicy, QoSProfile, ReliabilityPolicy

topic = sys.argv[1]
timeout = float(sys.argv[2])
msg_type_name = sys.argv[3]

package, _, name = msg_type_name.partition("/msg/")
module = importlib.import_module(f"{package}.msg")
msg_cls = getattr(module, name)

rclpy.init()
node = Node("mid360_fastlio_wait_for_sample")
qos = QoSProfile(
    history=HistoryPolicy.KEEP_LAST,
    depth=5,
    reliability=ReliabilityPolicy.RELIABLE,
    durability=DurabilityPolicy.VOLATILE,
)
received = False

def cb(_msg):
    global received
    received = True

node.create_subscription(msg_cls, topic, cb, qos)
deadline = time.time() + timeout
while time.time() < deadline and not received:
    rclpy.spin_once(node, timeout_sec=0.1)

node.destroy_node()
rclpy.shutdown()
sys.exit(0 if received else 1)
PY
}

topic_type() {
    local topic="$1"
    ros2 topic list -t 2>/dev/null | awk -v topic="$topic" '$1 == topic {gsub(/\[|\]/, "", $2); print $2; exit}'
}

echo ">>> [0/7] Loading ROS 2 Foxy + nav_ws"
source_relaxed /opt/ros/foxy/setup.bash
source_relaxed "$NAV_WS_ROOT/install/setup.bash"

if [ ! -f "$FASTLIO_CONFIG" ]; then
    echo "Error: FAST-LIO config not found: $FASTLIO_CONFIG" >&2
    exit 1
fi

echo ">>> [1/7] Checking MID360 network"
echo "    iface:    $MID360_IFACE"
echo "    host ip:  $MID360_HOST_IP"
echo "    lidar ip: $MID360_LIDAR_IP"
if ! ip -4 addr show dev "$MID360_IFACE" | grep -q "$MID360_HOST_IP"; then
    echo "Error: $MID360_IFACE does not have $MID360_HOST_IP." >&2
    echo "Expected eth0 to have both 192.168.123.18/24 and 192.168.1.2/24." >&2
    echo "Run:" >&2
    echo "  sudo nmcli con up \"Wired connection 1\"" >&2
    exit 1
fi
ip route get "$MID360_LIDAR_IP" || true

echo ">>> [2/7] Clearing old Livox / FAST-LIO processes"
pkill -f "[l]ivox_ros_driver2_node" 2>/dev/null || true
pkill -f "[r]os2 launch livox_ros_driver2 msg_MID360_launch.py" 2>/dev/null || true
pkill -x fastlio_mapping 2>/dev/null || true
pkill -f "[r]os2 service call /map_save" 2>/dev/null || true
sleep 1

echo ">>> [3/7] Starting Livox MID360 driver"
echo "    log: $LIVOX_LOG"
setsid nohup ros2 launch livox_ros_driver2 msg_MID360_launch.py \
    > "$LIVOX_LOG" 2>&1 < /dev/null &
LIVOX_PID=$!
echo "$LIVOX_PID" > "$LOG_DIR/livox_driver.pid"

if ! wait_for_topic "$LIDAR_CLOUD_TOPIC" "$WAIT_TOPIC_TIMEOUT"; then
    echo "Error: no publisher found for $LIDAR_CLOUD_TOPIC" >&2
    tail -100 "$LIVOX_LOG" >&2 || true
    exit 1
fi
cloud_type="$(topic_type "$LIDAR_CLOUD_TOPIC")"
if [ "$cloud_type" != "livox_ros_driver2/msg/CustomMsg" ]; then
    echo "Error: $LIDAR_CLOUD_TOPIC has type '$cloud_type', but FAST-LIO Livox mode requires livox_ros_driver2/msg/CustomMsg." >&2
    echo "Use livox_ros_driver2 msg_MID360_launch.py with xfer_format=1, not PointCloud2 xfer_format=0." >&2
    tail -100 "$LIVOX_LOG" >&2 || true
    exit 1
fi
if ! wait_for_topic "$LIDAR_IMU_TOPIC" "$WAIT_TOPIC_TIMEOUT"; then
    echo "Error: no publisher found for $LIDAR_IMU_TOPIC" >&2
    tail -100 "$LIVOX_LOG" >&2 || true
    exit 1
fi
imu_type="$(topic_type "$LIDAR_IMU_TOPIC")"
if [ "$imu_type" != "sensor_msgs/msg/Imu" ]; then
    echo "Error: $LIDAR_IMU_TOPIC has type '$imu_type', expected sensor_msgs/msg/Imu." >&2
    tail -100 "$LIVOX_LOG" >&2 || true
    exit 1
fi

wait_for_sample "$LIDAR_CLOUD_TOPIC" "$CHECK_SAMPLE_TIMEOUT" "livox_ros_driver2/msg/CustomMsg" \
    || echo "Warning: publisher exists, but no CustomMsg sample arrived within ${CHECK_SAMPLE_TIMEOUT}s"
wait_for_sample "$LIDAR_IMU_TOPIC" "$CHECK_SAMPLE_TIMEOUT" "sensor_msgs/msg/Imu" \
    || echo "Warning: publisher exists, but no IMU sample arrived within ${CHECK_SAMPLE_TIMEOUT}s"

echo ">>> [4/7] Starting FAST-LIO2 mapping"
echo "    config: $FASTLIO_CONFIG"
echo "    map:    $MAP_FILE"
echo "    log:    $FASTLIO_LOG"
setsid nohup ros2 run fast_lio fastlio_mapping --ros-args \
    --params-file "$FASTLIO_CONFIG" \
    -p map_file_path:="$MAP_FILE" \
    -p common.lid_topic:="$LIDAR_CLOUD_TOPIC" \
    -p common.imu_topic:="$LIDAR_IMU_TOPIC" \
    -p preprocess.lidar_type:=1 \
    -p preprocess.timestamp_unit:=3 \
    -p pcd_save.pcd_save_en:=true \
    > "$FASTLIO_LOG" 2>&1 < /dev/null &
FASTLIO_PID=$!
echo "$FASTLIO_PID" > "$LOG_DIR/fastlio_mapping.pid"

echo ">>> [5/7] Waiting for FAST-LIO outputs"
sleep 4
if ! kill -0 "$FASTLIO_PID" 2>/dev/null; then
    echo "Error: FAST-LIO exited during startup. Log follows:" >&2
    tail -100 "$FASTLIO_LOG" >&2 || true
    exit 1
fi
if ros2 topic info /cloud_registered 2>/dev/null | grep -Eq "Publisher count: [1-9]"; then
    echo "    /cloud_registered publisher is up"
else
    echo "Warning: /cloud_registered is not visible yet. Check $FASTLIO_LOG"
fi

if [ "$START_RVIZ" = "true" ] || [ "$START_RVIZ" = "1" ]; then
    echo ">>> [6/7] Starting RViz in VNC"
    if [ ! -S "/tmp/.X11-unix/X${RVIZ_DISPLAY#:}" ]; then
        echo "Warning: display $RVIZ_DISPLAY is not available; RViz not started." >&2
        echo "Start VNC first if needed: ~/work/nyush_rm_sentry/scripts/start_x11vnc_rviz.sh" >&2
    else
        rviz_args=()
        [ -f "$RVIZ_CONFIG" ] && rviz_args=(-d "$RVIZ_CONFIG")
        DISPLAY="$RVIZ_DISPLAY" \
        XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}" \
        LIBGL_ALWAYS_SOFTWARE=1 \
        QT_X11_NO_MITSHM=1 \
        setsid nohup ros2 run rviz2 rviz2 "${rviz_args[@]}" \
            > "$RVIZ_LOG" 2>&1 < /dev/null &
        echo "$!" > "$LOG_DIR/rviz.pid"
    fi
else
    echo ">>> [6/7] RViz disabled"
fi

echo ">>> [7/7] MID360 FAST-LIO2 mapping is running"
cat <<EOF

Watch:
  source /opt/ros/foxy/setup.bash
  source $NAV_WS_ROOT/install/setup.bash
  ros2 topic hz /livox/lidar
  ros2 topic hz /livox/imu
  ros2 topic hz /cloud_registered
  tail -f $FASTLIO_LOG

Save map when ready:
  MAP_FILE="$MAP_FILE" LOG_DIR="$LOG_DIR" $SCRIPT_DIR/save_mid360_fastlio_map.sh

Output:
  $MAP_FILE

EOF
