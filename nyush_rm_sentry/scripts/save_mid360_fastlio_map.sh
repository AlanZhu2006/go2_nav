#!/usr/bin/env bash

set -euo pipefail

NAV_WS_ROOT="${NAV_WS_ROOT:-$HOME/nav_ws}"
MAP_OUTPUT_DIR="${MAP_OUTPUT_DIR:-$HOME/work/go2_nav/maps/mid360_fastlio_latest}"
MAP_FILE="${MAP_FILE:-$MAP_OUTPUT_DIR/fastlio_map.pcd}"
LOG_DIR="${LOG_DIR:-/tmp/mid360_fastlio_mapping}"

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

source_relaxed /opt/ros/foxy/setup.bash
source_relaxed "$NAV_WS_ROOT/install/setup.bash"

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
if [ -s "$MAP_FILE" ]; then
    ln -sfn "$MAP_FILE" "$MAP_OUTPUT_DIR/fastlio_latest.pcd"
    ls -lh "$MAP_FILE" "$MAP_OUTPUT_DIR/fastlio_latest.pcd"
else
    echo "Error: map file was not found or is empty: $MAP_FILE" >&2
    echo "Check FAST-LIO log: $LOG_DIR/fastlio_mapping.log" >&2
    exit 1
fi
