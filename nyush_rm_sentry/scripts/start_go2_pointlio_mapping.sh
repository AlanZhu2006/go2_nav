#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAV_WS_ROOT="${NAV_WS_ROOT:-$HOME/nav_ws}"
POINTLIO_SRC="${POINTLIO_SRC:-$NAV_WS_ROOT/src/point_lio_ros2}"
GO2_DDS_ENV="${GO2_DDS_ENV:-$SCRIPT_DIR/go2_dds_env.sh}"
POINTLIO_CONFIG="${POINTLIO_CONFIG:-$POINTLIO_SRC/config/go2_builtin_l1.yaml}"
LOG_DIR="${LOG_DIR:-/tmp/go2_pointlio_mapping}"
MAP_DIR="${MAP_DIR:-$HOME/work/go2_nav/maps/go2_pointlio_latest}"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUTPUT="${OUTPUT:-$MAP_DIR/pointlio_map_${STAMP}.pcd}"
LATEST="${LATEST:-$MAP_DIR/pointlio_latest.pcd}"
POINTLIO_INTERNAL_PCD="${POINTLIO_INTERNAL_PCD:-$POINTLIO_SRC/PCD/scans.pcd}"

LIDAR_CLOUD_TOPIC="${LIDAR_CLOUD_TOPIC:-/utlidar/cloud}"
LIDAR_IMU_TOPIC="${LIDAR_IMU_TOPIC:-/utlidar/imu}"
WAIT_TOPIC_TIMEOUT="${WAIT_TOPIC_TIMEOUT:-15}"
POINTLIO_STATIC_INIT_SECONDS="${POINTLIO_STATIC_INIT_SECONDS:-8}"
START_RVIZ="${START_RVIZ:-true}"
RVIZ_DISPLAY="${RVIZ_DISPLAY:-:1}"
RVIZ_CONFIG="${RVIZ_CONFIG:-$POINTLIO_SRC/rviz_cfg/loam_livox.rviz}"
RVIZ_LOG="${RVIZ_LOG:-$LOG_DIR/rviz.log}"
POINTLIO_LOG="${POINTLIO_LOG:-$LOG_DIR/pointlio_mapping.log}"
CONVERT_TO_PGM="${CONVERT_TO_PGM:-false}"
PGM_OUT_DIR="${PGM_OUT_DIR:-$MAP_DIR/nav2_map}"
POINTLIO_PGM_Z_MIN="${POINTLIO_PGM_Z_MIN:--0.5}"
POINTLIO_PGM_Z_MAX="${POINTLIO_PGM_Z_MAX:-1.2}"
POINTLIO_PGM_RADIUS="${POINTLIO_PGM_RADIUS:-0.10}"
POINTLIO_PGM_POINT_COUNT="${POINTLIO_PGM_POINT_COUNT:-2}"
POINTLIO_DET_RANGE="${POINTLIO_DET_RANGE:-100.0}"
POINTLIO_SANITY_CHECK="${POINTLIO_SANITY_CHECK:-true}"
POINTLIO_SANITY_SECONDS="${POINTLIO_SANITY_SECONDS:-6}"
POINTLIO_MAX_STATIC_DRIFT="${POINTLIO_MAX_STATIC_DRIFT:-0.50}"

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
node = Node("go2_pointlio_wait_for_sample")
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

stop_pointlio_and_save() {
    local pid="$1"

    echo
    echo ">>> Stopping Point-LIO and waiting for PCD save"
    if kill -0 "$pid" 2>/dev/null; then
        kill -INT "$pid" 2>/dev/null || true
        local deadline=$((SECONDS + 25))
        while kill -0 "$pid" 2>/dev/null && [ "$SECONDS" -lt "$deadline" ]; do
            sleep 1
        done
        if kill -0 "$pid" 2>/dev/null; then
            echo "Warning: Point-LIO did not exit after SIGINT; sending TERM." >&2
            kill -TERM "$pid" 2>/dev/null || true
            sleep 2
        fi
    fi

    if [ ! -s "$POINTLIO_INTERNAL_PCD" ]; then
        echo "Error: Point-LIO did not create $POINTLIO_INTERNAL_PCD" >&2
        echo "Check log: $POINTLIO_LOG" >&2
        return 1
    fi

    cp "$POINTLIO_INTERNAL_PCD" "$OUTPUT"
    ln -sfn "$OUTPUT" "$LATEST"
    echo "Saved Point-LIO global PCD:"
    ls -lh "$OUTPUT" "$LATEST"

    if [ "$CONVERT_TO_PGM" = "true" ] || [ "$CONVERT_TO_PGM" = "1" ]; then
        echo
        echo ">>> Converting Point-LIO PCD to Nav2 PGM/YAML"
        PCD_INPUT="$OUTPUT" \
        MAP_OUT_DIR="$PGM_OUT_DIR" \
        PCD2PGM_Z_MIN="$POINTLIO_PGM_Z_MIN" \
        PCD2PGM_Z_MAX="$POINTLIO_PGM_Z_MAX" \
        PCD2PGM_RADIUS="$POINTLIO_PGM_RADIUS" \
        PCD2PGM_POINT_COUNT="$POINTLIO_PGM_POINT_COUNT" \
        "$SCRIPT_DIR/pcd2pgm_go2.sh"
    fi
}

show_status() {
    echo
    echo ">>> Point-LIO status"
    ros2 topic list -t | grep -E "utlidar|cloud_registered|Laser_map|aft_mapped|path|tf" || true
    echo
    timeout 4 ros2 topic hz "$LIDAR_CLOUD_TOPIC" || true
    timeout 4 ros2 topic hz /cloud_registered || true
    timeout 4 ros2 topic hz /aft_mapped_to_init || true
    echo
    tail -30 "$POINTLIO_LOG" || true
}

stop_pointlio_without_save() {
    local pid="$1"

    echo
    echo ">>> Stopping Point-LIO without saving"
    if kill -0 "$pid" 2>/dev/null; then
        kill -INT "$pid" 2>/dev/null || true
        local deadline=$((SECONDS + 10))
        while kill -0 "$pid" 2>/dev/null && [ "$SECONDS" -lt "$deadline" ]; do
            sleep 1
        done
        if kill -0 "$pid" 2>/dev/null; then
            kill -TERM "$pid" 2>/dev/null || true
        fi
    fi
}

kill_matching_processes() {
    local pattern="$1"
    local signal_name="${2:-INT}"

    pkill "-$signal_name" -f "$pattern" 2>/dev/null || true
}

if [ ! -f "$GO2_DDS_ENV" ]; then
    echo "Error: Go2 DDS env script not found: $GO2_DDS_ENV" >&2
    exit 1
fi

if [ ! -f "$POINTLIO_CONFIG" ]; then
    echo "Error: Point-LIO config not found: $POINTLIO_CONFIG" >&2
    exit 1
fi

if [ ! -f "$NAV_WS_ROOT/install/setup.bash" ]; then
    echo "Error: nav workspace setup not found: $NAV_WS_ROOT/install/setup.bash" >&2
    echo "Build first: cd $NAV_WS_ROOT && source /opt/ros/foxy/setup.bash && colcon build --symlink-install --packages-select point_lio" >&2
    exit 1
fi

mkdir -p "$LOG_DIR" "$MAP_DIR" "$POINTLIO_SRC/PCD"

source "$GO2_DDS_ENV"
source_relaxed "$NAV_WS_ROOT/install/setup.bash"

POINTLIO_EXE="${POINTLIO_EXE:-$NAV_WS_ROOT/install/point_lio/lib/point_lio/pointlio_mapping}"
if [ ! -x "$POINTLIO_EXE" ]; then
    echo "Error: Point-LIO executable not found: $POINTLIO_EXE" >&2
    echo "Build first: cd $NAV_WS_ROOT && source /opt/ros/foxy/setup.bash && colcon build --symlink-install --packages-select point_lio" >&2
    exit 1
fi

echo ">>> Clearing old Point-LIO processes"
kill_matching_processes "[/]pointlio_mapping([[:space:]]|$)" INT
kill_matching_processes "[/]fastlio_mapping([[:space:]]|$)" INT
sleep 1
kill_matching_processes "[/]pointlio_mapping([[:space:]]|$)" TERM
kill_matching_processes "[/]fastlio_mapping([[:space:]]|$)" TERM
sleep 1
rm -f "$POINTLIO_INTERNAL_PCD"

echo ">>> Starting Go2 built-in lidar services"
"$SCRIPT_DIR/start_go2_lidar_services.py"

echo ">>> Switching Go2 built-in lidar ON"
"$SCRIPT_DIR/go2_utlidar_switch.py" ON --repeat 5 --interval 0.2

if ! wait_for_topic "$LIDAR_CLOUD_TOPIC" "$WAIT_TOPIC_TIMEOUT"; then
    echo "Error: no publisher found for $LIDAR_CLOUD_TOPIC" >&2
    exit 1
fi

if ! wait_for_topic "$LIDAR_IMU_TOPIC" "$WAIT_TOPIC_TIMEOUT"; then
    echo "Error: no publisher found for $LIDAR_IMU_TOPIC" >&2
    exit 1
fi

if wait_for_sample "$LIDAR_CLOUD_TOPIC" 8 "sensor_msgs/msg/PointCloud2"; then
    echo "    Received lidar samples from $LIDAR_CLOUD_TOPIC"
else
    echo "Warning: publisher exists, but no lidar sample was received yet." >&2
fi

echo ">>> Starting Point-LIO"
echo "    config:  $POINTLIO_CONFIG"
echo "    cloud:   $LIDAR_CLOUD_TOPIC"
echo "    imu:     $LIDAR_IMU_TOPIC"
echo "    range:   $POINTLIO_DET_RANGE"
echo "    log:     $POINTLIO_LOG"
echo "    raw pcd: $POINTLIO_INTERNAL_PCD"

setsid "$POINTLIO_EXE" --ros-args \
    --params-file "$POINTLIO_CONFIG" \
    -p use_imu_as_input:=false \
    -p prop_at_freq_of_imu:=true \
    -p check_satu:=true \
    -p init_map_size:=10 \
    -p point_filter_num:=1 \
    -p space_down_sample:=true \
    -p filter_size_surf:=0.1 \
    -p filter_size_map:=0.1 \
    -p cube_side_length:=1000.0 \
    -p mapping.det_range:="$POINTLIO_DET_RANGE" \
    -p common.lid_topic:="$LIDAR_CLOUD_TOPIC" \
    -p common.imu_topic:="$LIDAR_IMU_TOPIC" \
    -p pcd_save.pcd_save_en:=true \
    -p pcd_save.interval:=-1 \
    > "$POINTLIO_LOG" 2>&1 < /dev/null &
POINTLIO_PID=$!
echo "$POINTLIO_PID" > "$LOG_DIR/pointlio_mapping.pid"

sleep 3
if ! kill -0 "$POINTLIO_PID" 2>/dev/null; then
    echo "Error: Point-LIO exited during startup. Log follows:" >&2
    tail -100 "$POINTLIO_LOG" >&2 || true
    exit 1
fi

if [ "$POINTLIO_STATIC_INIT_SECONDS" != "0" ]; then
    echo ">>> Keep the robot still for Point-LIO IMU initialization (${POINTLIO_STATIC_INIT_SECONDS}s)"
    sleep "$POINTLIO_STATIC_INIT_SECONDS"
fi

if [ "$POINTLIO_SANITY_CHECK" = "true" ] || [ "$POINTLIO_SANITY_CHECK" = "1" ]; then
    echo ">>> Checking Point-LIO static drift (${POINTLIO_SANITY_SECONDS}s)"
    echo "    Keep the robot still. If this fails, do not use the generated map."
    if ! python3 "$SCRIPT_DIR/diagnose_go2_pointlio_inputs.py" \
        --duration "$POINTLIO_SANITY_SECONDS" \
        --max-static-drift "$POINTLIO_MAX_STATIC_DRIFT" \
        --require-pointlio \
        > "$LOG_DIR/pointlio_input_diagnosis.log" 2>&1; then
        echo "Error: Point-LIO failed the static sanity check." >&2
        echo "       This usually means the raw /utlidar/cloud + /utlidar/imu model is not aligned for this Go2." >&2
        echo "       Diagnosis log:" >&2
        sed -n '1,220p' "$LOG_DIR/pointlio_input_diagnosis.log" >&2 || true
        stop_pointlio_without_save "$POINTLIO_PID"
        exit 1
    fi
    sed -n '1,220p' "$LOG_DIR/pointlio_input_diagnosis.log" || true
fi

if [ "$START_RVIZ" = "true" ] || [ "$START_RVIZ" = "1" ]; then
    echo ">>> Starting RViz in VNC"
    if [ ! -S "/tmp/.X11-unix/X${RVIZ_DISPLAY#:}" ]; then
        echo "Warning: VNC/X display $RVIZ_DISPLAY is not available. RViz was not started." >&2
        echo "         Start it with: systemctl --user restart rviz-vnc.service" >&2
    else
        pkill -f "[r]viz2.*loam_livox.rviz" 2>/dev/null || true
        DISPLAY="$RVIZ_DISPLAY" \
        XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}" \
        LIBGL_ALWAYS_SOFTWARE=1 \
        QT_X11_NO_MITSHM=1 \
        setsid ros2 run rviz2 rviz2 -d "$RVIZ_CONFIG" \
            > "$RVIZ_LOG" 2>&1 < /dev/null &
        echo "$!" > "$LOG_DIR/rviz.pid"
        echo "    VNC: 10.209.69.61:5901"
        echo "    log: $RVIZ_LOG"
    fi
fi

cat <<EOF

>>> Point-LIO mapping is running
    output: $OUTPUT
    nav2 map: $PGM_OUT_DIR  (when CONVERT_TO_PGM=true)
    pcd2pgm z: $POINTLIO_PGM_Z_MIN .. $POINTLIO_PGM_Z_MAX

You can now walk the robot through the area.

Controls:
  1 + Enter  stop Point-LIO, save accumulated PCD, and exit
  s + Enter  show topic/log status
  q + Enter  quit without saving

EOF

while true; do
    read -r -p "pointlio-map> " cmd
    case "$cmd" in
        1)
            stop_pointlio_and_save "$POINTLIO_PID"
            exit $?
            ;;
        s|status)
            show_status
            ;;
        q|quit)
            stop_pointlio_without_save "$POINTLIO_PID"
            exit 0
            ;;
        *)
            echo "Commands: 1 = save and exit, s = status, q = quit without saving"
            ;;
    esac
done
