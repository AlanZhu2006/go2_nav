#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GO2_DDS_ENV="${GO2_DDS_ENV:-$SCRIPT_DIR/go2_dds_env.sh}"
MAP_DIR="${MAP_DIR:-$HOME/work/go2_nav/maps/go2_official_odom_latest}"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUTPUT="${OUTPUT:-$MAP_DIR/official_odom_map_${STAMP}.pcd}"
LATEST="${LATEST:-$MAP_DIR/official_odom_latest.pcd}"
LOG_DIR="${LOG_DIR:-/tmp/go2_official_odom_mapping}"

CLOUD_TOPIC="${CLOUD_TOPIC:-/utlidar/cloud_base}"
ODOM_TOPIC="${ODOM_TOPIC:-/utlidar/robot_odom}"
VOXEL_SIZE="${VOXEL_SIZE:-0.05}"
POINT_STRIDE="${POINT_STRIDE:-1}"
BEST_EFFORT="${BEST_EFFORT:-true}"
START_RVIZ="${START_RVIZ:-true}"
CONVERT_TO_PGM="${CONVERT_TO_PGM:-false}"
PGM_OUT_DIR="${PGM_OUT_DIR:-$MAP_DIR/nav2_map}"
OFFICIAL_PGM_Z_MIN="${OFFICIAL_PGM_Z_MIN:--0.3}"
OFFICIAL_PGM_Z_MAX="${OFFICIAL_PGM_Z_MAX:-1.5}"
OFFICIAL_PGM_RADIUS="${OFFICIAL_PGM_RADIUS:-0.10}"
OFFICIAL_PGM_POINT_COUNT="${OFFICIAL_PGM_POINT_COUNT:-2}"

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

mkdir -p "$MAP_DIR" "$LOG_DIR"

source "$GO2_DDS_ENV"
source_relaxed /opt/ros/foxy/setup.bash

echo ">>> Starting Go2 built-in lidar services"
"$SCRIPT_DIR/start_go2_lidar_services.py"

echo ">>> Switching Go2 built-in lidar ON"
"$SCRIPT_DIR/go2_utlidar_switch.py" ON --repeat 5 --interval 0.2

if [ "$START_RVIZ" = "true" ] || [ "$START_RVIZ" = "1" ]; then
    echo ">>> Starting RViz in VNC"
    "$SCRIPT_DIR/start_go2_builtin_rviz.sh" || true
fi

cat <<EOF

>>> Official Go2 odom mapping
    cloud:  $CLOUD_TOPIC
    odom:   $ODOM_TOPIC
    output: $OUTPUT

This route uses Unitree's official Go2 lidar/base/odom processing.
It does not run Point-LIO and does not need third-party lidar-IMU extrinsics.

Walk the robot through the area.
Press:
  1 + Enter  save accumulated PCD and exit
  q + Enter  quit without saving

EOF

ACCUM_ARGS=(
    --cloud-topic "$CLOUD_TOPIC"
    --odom-topic "$ODOM_TOPIC"
    --output "$OUTPUT"
    --voxel-size "$VOXEL_SIZE"
    --point-stride "$POINT_STRIDE"
)

if [ "$BEST_EFFORT" = "true" ] || [ "$BEST_EFFORT" = "1" ]; then
    ACCUM_ARGS+=(--best-effort)
fi

python3 "$SCRIPT_DIR/accumulate_go2_official_odom_pcd.py" "${ACCUM_ARGS[@]}"

if [ ! -f "$OUTPUT" ]; then
    echo "No PCD was saved."
    exit 0
fi

ln -sfn "$OUTPUT" "$LATEST"
echo
echo "Saved official Go2 odom PCD:"
ls -lh "$OUTPUT" "$LATEST"

if [ "$CONVERT_TO_PGM" = "true" ] || [ "$CONVERT_TO_PGM" = "1" ]; then
    echo
    echo ">>> Converting official Go2 odom PCD to Nav2 PGM/YAML"
    PCD_INPUT="$OUTPUT" \
    MAP_OUT_DIR="$PGM_OUT_DIR" \
    PCD2PGM_Z_MIN="$OFFICIAL_PGM_Z_MIN" \
    PCD2PGM_Z_MAX="$OFFICIAL_PGM_Z_MAX" \
    PCD2PGM_RADIUS="$OFFICIAL_PGM_RADIUS" \
    PCD2PGM_POINT_COUNT="$OFFICIAL_PGM_POINT_COUNT" \
    "$SCRIPT_DIR/pcd2pgm_go2.sh"
fi
