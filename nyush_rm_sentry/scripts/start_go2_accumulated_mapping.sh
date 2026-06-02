#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GO2_DDS_ENV="${GO2_DDS_ENV:-$SCRIPT_DIR/go2_dds_env.sh}"
TOPIC="${GO2_ACCUM_TOPIC:-/utlidar/cloud_deskewed}"
MAP_DIR="${GO2_ACCUM_MAP_DIR:-$HOME/work/go2_nav/maps/go2_builtin_latest}"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUTPUT="${GO2_ACCUM_OUTPUT:-$MAP_DIR/accumulated_cloud_deskewed_${STAMP}.pcd}"
LATEST="$MAP_DIR/accumulated_latest.pcd"
VOXEL_SIZE="${GO2_ACCUM_VOXEL_SIZE:-0.05}"
DURATION="${GO2_ACCUM_DURATION:-0}"
MAX_POINTS="${GO2_ACCUM_MAX_POINTS:-0}"
REPORT_INTERVAL="${GO2_ACCUM_REPORT_INTERVAL:-2}"
BEST_EFFORT="${GO2_ACCUM_BEST_EFFORT:-false}"
START_RVIZ="${START_RVIZ:-true}"
CONVERT_TO_PGM="${CONVERT_TO_PGM:-false}"
PGM_OUT_DIR="${PGM_OUT_DIR:-$MAP_DIR/nav2_map_accumulated}"

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

mkdir -p "$MAP_DIR"

source "$GO2_DDS_ENV"
source_relaxed /opt/ros/foxy/setup.bash

echo ">>> Starting Go2 built-in lidar services"
"$SCRIPT_DIR/start_go2_lidar_services.py"

echo ">>> Switching Go2 built-in lidar ON"
"$SCRIPT_DIR/go2_utlidar_switch.py" ON --repeat 5 --interval 0.2

if [ "$START_RVIZ" = "true" ] || [ "$START_RVIZ" = "1" ]; then
    echo ">>> Starting RViz in VNC"
    "$SCRIPT_DIR/start_go2_builtin_rviz.sh"
fi

cat <<EOF

>>> Accumulating point cloud
    topic:       $TOPIC
    output:      $OUTPUT
    latest link: $LATEST
    voxel size:  $VOXEL_SIZE m
    qos:         $([ "$BEST_EFFORT" = "true" ] || [ "$BEST_EFFORT" = "1" ] && echo best_effort || echo reliable)

Walk the robot through the area now.

Controls:
  1 + Enter  save accumulated PCD and exit
  q + Enter  exit without saving

EOF

ACCUM_ARGS=(
    --topic "$TOPIC" \
    --output "$OUTPUT" \
    --voxel-size "$VOXEL_SIZE" \
    --duration "$DURATION" \
    --max-points "$MAX_POINTS" \
    --report-interval "$REPORT_INTERVAL"
)

if [ "$BEST_EFFORT" = "true" ] || [ "$BEST_EFFORT" = "1" ]; then
    ACCUM_ARGS+=(--best-effort)
fi

python3 "$SCRIPT_DIR/accumulate_pointcloud2_pcd.py" "${ACCUM_ARGS[@]}"

if [ ! -f "$OUTPUT" ]; then
    echo
    echo "No PCD was saved."
    exit 0
fi

ln -sfn "$OUTPUT" "$LATEST"

echo
echo "Saved accumulated PCD:"
ls -lh "$OUTPUT" "$LATEST"

if [ "$CONVERT_TO_PGM" = "true" ] || [ "$CONVERT_TO_PGM" = "1" ]; then
    echo
    echo ">>> Converting accumulated PCD to Nav2 PGM/YAML"
    PCD_INPUT="$OUTPUT" MAP_OUT_DIR="$PGM_OUT_DIR" "$SCRIPT_DIR/pcd2pgm_go2.sh"
fi
