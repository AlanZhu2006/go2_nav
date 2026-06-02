#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAV_WS="${NAV_WS:-$HOME/nav_ws}"
ROS_SETUP="${ROS_SETUP:-/opt/ros/foxy/setup.bash}"
NAV_WS_SETUP="${NAV_WS_SETUP:-$NAV_WS/install/setup.bash}"

PCD_INPUT="${PCD_INPUT:-${1:-$HOME/work/go2_nav/maps/go2_builtin_latest/cloud_deskewed_latest.pcd}}"
MAP_OUT_DIR="${MAP_OUT_DIR:-${2:-$HOME/work/go2_nav/maps/go2_builtin_latest/nav2_map}}"
MAP_NAME="${MAP_NAME:-${3:-map}}"
MAP_TOPIC="${MAP_TOPIC:-/pcd2pgm_map_$$}"

MAP_RESOLUTION="${MAP_RESOLUTION:-0.05}"
PCD2PGM_FLAG_PASS_THROUGH="${PCD2PGM_FLAG_PASS_THROUGH:-false}"
PCD2PGM_Z_MIN="${PCD2PGM_Z_MIN:-0.60}"
PCD2PGM_Z_MAX="${PCD2PGM_Z_MAX:-1.80}"
PCD2PGM_RADIUS="${PCD2PGM_RADIUS:-0.15}"
PCD2PGM_POINT_COUNT="${PCD2PGM_POINT_COUNT:-5}"
PCD2PGM_WAIT_SECONDS="${PCD2PGM_WAIT_SECONDS:-4}"
MAP_SAVE_TIMEOUT="${MAP_SAVE_TIMEOUT:-20}"
PCD2PGM_KILL_OLD="${PCD2PGM_KILL_OLD:-true}"
RMW_IMPLEMENTATION="${PCD2PGM_RMW_IMPLEMENTATION:-rmw_fastrtps_cpp}"
ROS_LOCALHOST_ONLY="${PCD2PGM_ROS_LOCALHOST_ONLY:-1}"
ROS_DOMAIN_ID="${PCD2PGM_ROS_DOMAIN_ID:-88}"

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

expand_path() {
    local input="$1"
    case "$input" in
        "~")
            printf '%s\n' "$HOME"
            ;;
        "~/"*)
            printf '%s\n' "$HOME/${input#~/}"
            ;;
        /*)
            printf '%s\n' "$input"
            ;;
        *)
            realpath -m "$input"
            ;;
    esac
}

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

if [ ! -f "$ROS_SETUP" ]; then
    echo "Error: ROS setup not found: $ROS_SETUP" >&2
    exit 1
fi

if [ ! -f "$NAV_WS_SETUP" ]; then
    echo "Error: nav workspace setup not found: $NAV_WS_SETUP" >&2
    echo "Build pcd2pgm first: cd $NAV_WS && colcon build --symlink-install --packages-select pcd2pgm" >&2
    exit 1
fi

PCD_INPUT="$(expand_path "$PCD_INPUT")"
MAP_OUT_DIR="$(expand_path "$MAP_OUT_DIR")"
MAP_PREFIX="$MAP_OUT_DIR/$MAP_NAME"
PARAMS_FILE="$MAP_OUT_DIR/pcd2pgm_go2.yaml"
PCD2PGM_LOG="$MAP_OUT_DIR/pcd2pgm.log"
MAP_SAVER_LOG="$MAP_OUT_DIR/map_saver.log"

if [ ! -f "$PCD_INPUT" ]; then
    echo "Error: PCD input not found: $PCD_INPUT" >&2
    exit 1
fi

mkdir -p "$MAP_OUT_DIR"

cat > "$PARAMS_FILE" <<EOF
pcd2pgm:
  ros__parameters:
    pcd_file: "$PCD_INPUT"
    odom_to_lidar_odom: [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
    flag_pass_through: $PCD2PGM_FLAG_PASS_THROUGH
    map_resolution: $MAP_RESOLUTION
    map_topic_name: "${MAP_TOPIC#/}"
    thre_radius: $PCD2PGM_RADIUS
    thre_z_max: $PCD2PGM_Z_MAX
    thre_z_min: $PCD2PGM_Z_MIN
    thres_point_count: $PCD2PGM_POINT_COUNT
EOF

# This is an offline conversion. Keep it away from Unitree's custom CycloneDDS
# libraries, otherwise local ROS tools can fail with std::bad_alloc.
unset CYCLONEDDS_URI
unset CYCLONEDDS_HOME
export RMW_IMPLEMENTATION
export ROS_LOCALHOST_ONLY
export ROS_DOMAIN_ID
export LD_LIBRARY_PATH="$(remove_path_entry "${LD_LIBRARY_PATH:-}" "$HOME/cyclonedds/install/lib")"

source_relaxed "$ROS_SETUP"
source_relaxed "$NAV_WS_SETUP"

unset CYCLONEDDS_URI
unset CYCLONEDDS_HOME
export RMW_IMPLEMENTATION
export ROS_LOCALHOST_ONLY
export ROS_DOMAIN_ID
export LD_LIBRARY_PATH="$(remove_path_entry "${LD_LIBRARY_PATH:-}" "$HOME/cyclonedds/install/lib")"

if ! ros2 pkg prefix pcd2pgm >/dev/null 2>&1; then
    echo "Error: ROS package pcd2pgm is not visible after sourcing $NAV_WS_SETUP" >&2
    exit 1
fi

if ! ros2 pkg prefix nav2_map_server >/dev/null 2>&1; then
    echo "Error: ROS package nav2_map_server is not installed" >&2
    exit 1
fi

if [ "$PCD2PGM_KILL_OLD" = "true" ] || [ "$PCD2PGM_KILL_OLD" = "1" ]; then
    pkill -f "[p]cd2pgm_node" 2>/dev/null || true
    sleep 1
fi

PIDS=()
cleanup() {
    for pid in "${PIDS[@]:-}"; do
        kill "$pid" >/dev/null 2>&1 || true
    done
    for pid in "${PIDS[@]:-}"; do
        wait "$pid" >/dev/null 2>&1 || true
    done
}
trap cleanup EXIT

echo ">>> Converting PCD to Nav2 map"
echo "    input:      $PCD_INPUT"
echo "    output:     $MAP_PREFIX.{pgm,yaml}"
echo "    params:     $PARAMS_FILE"
echo "    map topic:  $MAP_TOPIC"

ros2 run pcd2pgm pcd2pgm_node --ros-args --params-file "$PARAMS_FILE" \
    > "$PCD2PGM_LOG" 2>&1 &
PIDS+=("$!")

sleep 2
if ! kill -0 "${PIDS[0]}" >/dev/null 2>&1; then
    echo "Error: pcd2pgm_node exited early. Log:" >&2
    tail -80 "$PCD2PGM_LOG" >&2 || true
    exit 1
fi

echo ">>> Waiting ${PCD2PGM_WAIT_SECONDS}s for pcd2pgm to publish $MAP_TOPIC ..."
sleep "$PCD2PGM_WAIT_SECONDS"

echo ">>> Saving $MAP_TOPIC with nav2_map_server/map_saver_cli ..."
if ! timeout "$MAP_SAVE_TIMEOUT" ros2 run nav2_map_server map_saver_cli \
    -t "$MAP_TOPIC" \
    -f "$MAP_PREFIX" \
    --fmt pgm \
    --mode trinary \
    > "$MAP_SAVER_LOG" 2>&1; then
    echo "Error: map_saver_cli failed. pcd2pgm log:" >&2
    tail -80 "$PCD2PGM_LOG" >&2 || true
    echo "map_saver log:" >&2
    tail -80 "$MAP_SAVER_LOG" >&2 || true
    exit 1
fi

if [ ! -f "$MAP_PREFIX.pgm" ] || [ ! -f "$MAP_PREFIX.yaml" ]; then
    echo "Error: map_saver_cli finished but map files were not created." >&2
    tail -80 "$MAP_SAVER_LOG" >&2 || true
    exit 1
fi

ln -sfn "$MAP_PREFIX.pgm" "$MAP_OUT_DIR/latest.pgm"
ln -sfn "$MAP_PREFIX.yaml" "$MAP_OUT_DIR/latest.yaml"

echo
echo "Saved Nav2 map:"
ls -lh "$MAP_PREFIX.pgm" "$MAP_PREFIX.yaml" "$PARAMS_FILE" "$PCD2PGM_LOG" "$MAP_SAVER_LOG"
echo
echo "Use with Nav2 map_server:"
echo "  $MAP_PREFIX.yaml"
