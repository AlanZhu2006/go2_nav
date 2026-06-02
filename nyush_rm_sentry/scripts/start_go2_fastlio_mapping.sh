#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SENTRY_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NAV_WS_ROOT="${NAV_WS_ROOT:-$HOME/nav_ws}"
GO2_DDS_ENV="${GO2_DDS_ENV:-$SCRIPT_DIR/go2_dds_env.sh}"

FASTLIO_CONFIG="${FASTLIO_CONFIG:-$SENTRY_ROOT/config/fastlio_go2_l2.yaml}"
MAP_OUTPUT_DIR="${MAP_OUTPUT_DIR:-$HOME/maps/fastlio_mapping_latest}"
MAP_FILE="${MAP_FILE:-$MAP_OUTPUT_DIR/fastlio_map.pcd}"
LOG_DIR="${LOG_DIR:-/tmp/go2_fastlio_mapping}"

LIDAR_CLOUD_TOPIC="${LIDAR_CLOUD_TOPIC:-/utlidar/cloud}"
LIDAR_IMU_TOPIC="${LIDAR_IMU_TOPIC:-/utlidar/imu}"
LIDAR_SWITCH_TOPIC="${LIDAR_SWITCH_TOPIC:-/utlidar/switch}"
WAIT_TOPIC_TIMEOUT="${WAIT_TOPIC_TIMEOUT:-15}"
CHECK_SAMPLE_TIMEOUT="${CHECK_SAMPLE_TIMEOUT:-6}"
REQUIRE_LIDAR_SAMPLE="${REQUIRE_LIDAR_SAMPLE:-0}"
START_RVIZ="${START_RVIZ:-0}"
RVIZ_DISPLAY="${RVIZ_DISPLAY:-:1}"
RVIZ_CONFIG="${RVIZ_CONFIG:-$SENTRY_ROOT/rm_navigation_ws/src/rm_nav_bringup/rviz/fastlio.rviz}"
RVIZ_LOG="${RVIZ_LOG:-$LOG_DIR/rviz.log}"
RVIZ_PID_FILE="${RVIZ_PID_FILE:-$LOG_DIR/rviz.pid}"

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

if [ ! -f "$GO2_DDS_ENV" ]; then
    echo "Error: Go2 DDS env script not found: $GO2_DDS_ENV" >&2
    exit 1
fi

if [ ! -f "$FASTLIO_CONFIG" ]; then
    echo "Error: FAST-LIO config not found: $FASTLIO_CONFIG" >&2
    exit 1
fi

source "$GO2_DDS_ENV"

if [ -f "$NAV_WS_ROOT/install/setup.bash" ]; then
    source_relaxed "$NAV_WS_ROOT/install/setup.bash"
else
    echo "Error: nav workspace setup not found: $NAV_WS_ROOT/install/setup.bash" >&2
    exit 1
fi

wait_for_topic() {
    local topic="$1"
    local timeout_secs="$2"
    local deadline=$((SECONDS + timeout_secs))

    while [ "$SECONDS" -lt "$deadline" ]; do
        if ros2 topic info "$topic" 2>/dev/null | grep -q "Publisher count: [1-9]"; then
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
node = Node("go2_fastlio_wait_for_sample")
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

echo ">>> [0/5] Go2 DDS environment"
echo "    RMW_IMPLEMENTATION=$RMW_IMPLEMENTATION"
echo "    CYCLONEDDS_URI=$CYCLONEDDS_URI"
echo "    NAV_WS_ROOT=$NAV_WS_ROOT"

echo ">>> [1/5] Clearing old mapping processes"
pkill -x fastlio_mapping 2>/dev/null || true
pkill -f "ros2 service call /map_save" 2>/dev/null || true
sleep 1

echo ">>> [2/5] Enabling / checking Unitree L2 lidar"
timeout 2 ros2 topic pub "$LIDAR_SWITCH_TOPIC" std_msgs/msg/String "{data: 'ON'}" -r 2 >/dev/null 2>&1 || true

if ! wait_for_topic "$LIDAR_CLOUD_TOPIC" "$WAIT_TOPIC_TIMEOUT"; then
    echo "Error: no publisher found for $LIDAR_CLOUD_TOPIC" >&2
    echo "Run: source scripts/go2_dds_env.sh && ros2 topic list -t | grep utlidar" >&2
    exit 1
fi

if ! wait_for_topic "$LIDAR_IMU_TOPIC" "$WAIT_TOPIC_TIMEOUT"; then
    echo "Error: no publisher found for $LIDAR_IMU_TOPIC" >&2
    exit 1
fi

if wait_for_sample "$LIDAR_CLOUD_TOPIC" "$CHECK_SAMPLE_TIMEOUT" "sensor_msgs/msg/PointCloud2"; then
    echo "    Received a sample from $LIDAR_CLOUD_TOPIC"
else
    echo "Warning: publisher exists, but no sample was received from $LIDAR_CLOUD_TOPIC within ${CHECK_SAMPLE_TIMEOUT}s"
    echo "         FAST-LIO will start, but map will not grow until lidar samples arrive."
    if [ "$REQUIRE_LIDAR_SAMPLE" = "1" ]; then
        exit 1
    fi
fi

echo ">>> [3/5] Starting FAST-LIO mapping"
echo "    point cloud: $LIDAR_CLOUD_TOPIC"
echo "    imu:         $LIDAR_IMU_TOPIC"
echo "    map file:    $MAP_FILE"
echo "    log:         $LOG_DIR/fastlio_mapping.log"

setsid nohup ros2 run fast_lio fastlio_mapping --ros-args \
    --params-file "$FASTLIO_CONFIG" \
    -p map_file_path:="$MAP_FILE" \
    -p common.lid_topic:="$LIDAR_CLOUD_TOPIC" \
    -p common.imu_topic:="$LIDAR_IMU_TOPIC" \
    -p preprocess.lidar_type:=2 \
    -p preprocess.timestamp_unit:=0 \
    -p pcd_save.pcd_save_en:=true \
    > "$LOG_DIR/fastlio_mapping.log" 2>&1 < /dev/null &
FASTLIO_PID=$!
echo "$FASTLIO_PID" > "$LOG_DIR/fastlio_mapping.pid"

echo ">>> [4/5] Waiting for FAST-LIO outputs"
sleep 3
if ! kill -0 "$FASTLIO_PID" 2>/dev/null; then
    echo "Error: FAST-LIO exited during startup. Log follows:" >&2
    tail -80 "$LOG_DIR/fastlio_mapping.log" >&2 || true
    exit 1
fi

if ros2 topic info /cloud_registered 2>/dev/null | grep -q "Publisher count: [1-9]"; then
    echo "    /cloud_registered publisher is up"
else
    echo "Warning: /cloud_registered publisher not visible yet. Check $LOG_DIR/fastlio_mapping.log"
fi

if [ "$START_RVIZ" = "1" ]; then
    echo ">>> [5/5] Starting RViz"
    pkill -f "[r]viz2.*$RVIZ_CONFIG" 2>/dev/null || true
    if [ ! -S "/tmp/.X11-unix/X${RVIZ_DISPLAY#:}" ]; then
        echo "Warning: VNC/X display $RVIZ_DISPLAY is not available. RViz was not started." >&2
        echo "         Start it with: systemctl --user restart rviz-vnc.service" >&2
    else
        rviz_args=()
        if [ -f "$RVIZ_CONFIG" ]; then
            rviz_args=(-d "$RVIZ_CONFIG")
            echo "    config:      $RVIZ_CONFIG"
        else
            echo "Warning: RViz config not found: $RVIZ_CONFIG; starting with default layout." >&2
        fi
        echo "    display:     $RVIZ_DISPLAY"
        echo "    log:         $RVIZ_LOG"
        DISPLAY="$RVIZ_DISPLAY" \
        XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}" \
        LIBGL_ALWAYS_SOFTWARE=1 \
        QT_X11_NO_MITSHM=1 \
        setsid nohup ros2 run rviz2 rviz2 "${rviz_args[@]}" \
            > "$RVIZ_LOG" 2>&1 < /dev/null &
        echo "$!" > "$RVIZ_PID_FILE"
    fi
else
    echo ">>> [5/5] Mapping process started"
fi

cat <<EOF

Next checks:
  source $GO2_DDS_ENV
  source $NAV_WS_ROOT/install/setup.bash
  ros2 topic hz /cloud_registered
  tail -f $LOG_DIR/fastlio_mapping.log

Save map when ready:
  MAP_FILE="$MAP_FILE" $SCRIPT_DIR/save_go2_fastlio_map.sh

RViz:
  VNC viewer -> 10.209.69.61:5901
  log        -> $RVIZ_LOG

EOF
