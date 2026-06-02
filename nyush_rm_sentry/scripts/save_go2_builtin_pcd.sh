#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GO2_DDS_ENV="${GO2_DDS_ENV:-$SCRIPT_DIR/go2_dds_env.sh}"
TOPIC="${GO2_MAP_TOPIC:-/uslam/cloud_map}"
MAP_DIR="${GO2_MAP_DIR:-$HOME/work/go2_nav/maps/go2_builtin_latest}"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUTPUT="${GO2_MAP_OUTPUT:-$MAP_DIR/go2_builtin_${STAMP}.pcd}"
LATEST="$MAP_DIR/latest.pcd"
TIMEOUT="${GO2_SAVE_TIMEOUT:-120}"

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

echo ">>> Saving one PointCloud2 message as PCD"
echo "    topic:   $TOPIC"
echo "    output:  $OUTPUT"
echo "    timeout: ${TIMEOUT}s"

python3 "$SCRIPT_DIR/save_pointcloud2_pcd.py" \
    --topic "$TOPIC" \
    --output "$OUTPUT" \
    --timeout "$TIMEOUT"

case "$(readlink -f "$(dirname "$OUTPUT")")/" in
    "$(readlink -f "$MAP_DIR")/"*)
        ln -sfn "$OUTPUT" "$LATEST"
        ;;
    *)
        echo ">>> Output is outside $MAP_DIR, not updating latest.pcd"
        ;;
esac

echo
echo "Saved:"
ls -lh "$OUTPUT"
if [ -e "$LATEST" ] || [ -L "$LATEST" ]; then
    ls -lh "$LATEST"
fi
