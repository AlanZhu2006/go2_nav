#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAV_WS_ROOT="${NAV_WS_ROOT:-$HOME/nav_ws}"
GO2_DDS_ENV="${GO2_DDS_ENV:-$SCRIPT_DIR/go2_dds_env.sh}"
MAP_OUTPUT_DIR="${MAP_OUTPUT_DIR:-$HOME/maps/fastlio_mapping_latest}"
MAP_FILE="${MAP_FILE:-$MAP_OUTPUT_DIR/fastlio_map.pcd}"
LOG_DIR="${LOG_DIR:-/tmp/go2_fastlio_mapping}"

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

source "$GO2_DDS_ENV"
if [ -f "$NAV_WS_ROOT/install/setup.bash" ]; then
    source_relaxed "$NAV_WS_ROOT/install/setup.bash"
fi

echo ">>> Checking /map_save service"
if ! ros2 service list | grep -qx "/map_save"; then
    echo "Error: /map_save service is not available. Is fastlio_mapping running?" >&2
    echo "Log: $LOG_DIR/fastlio_mapping.log" >&2
    exit 1
fi

echo ">>> Calling /map_save"
ros2 service call /map_save std_srvs/srv/Trigger "{}"

echo ">>> Checking map file"
sleep 1
if [ -f "$MAP_FILE" ]; then
    ls -lh "$MAP_FILE"
else
    echo "Error: map file was not found: $MAP_FILE" >&2
    echo "Check FAST-LIO log: $LOG_DIR/fastlio_mapping.log" >&2
    exit 1
fi
