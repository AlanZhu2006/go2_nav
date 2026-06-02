#!/usr/bin/env bash

# Source this file before talking to Unitree Go2 DDS/ROS2 topics.
# It follows the official unitree_ros2 pattern but uses the config that already
# exists on this robot computer.

ROS_SETUP="${ROS_SETUP:-/opt/ros/foxy/setup.bash}"
UNITREE_CYCLONEDDS_SETUP="${UNITREE_CYCLONEDDS_SETUP:-/home/unitree/cyclonedds_ws/install/setup.sh}"
UNITREE_CYCLONEDDS_URI="${UNITREE_CYCLONEDDS_URI:-file:///home/unitree/cyclonedds_ws/cyclonedds.xml}"
LEGACY_CYCLONEDDS_LIB="${LEGACY_CYCLONEDDS_LIB:-/home/unitree/cyclonedds/install/lib}"

_go2_remove_path_entry() {
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
    return 1 2>/dev/null || exit 1
fi

if [ ! -f "$UNITREE_CYCLONEDDS_SETUP" ]; then
    echo "Error: Unitree CycloneDDS setup not found: $UNITREE_CYCLONEDDS_SETUP" >&2
    return 1 2>/dev/null || exit 1
fi

_go2_dds_had_nounset=0
case $- in
    *u*) _go2_dds_had_nounset=1; set +u ;;
esac

source "$ROS_SETUP"
source "$UNITREE_CYCLONEDDS_SETUP"

if [ "$_go2_dds_had_nounset" = "1" ]; then
    set -u
fi
unset _go2_dds_had_nounset

export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
export CYCLONEDDS_URI="$UNITREE_CYCLONEDDS_URI"
unset CYCLONEDDS_HOME
export LD_LIBRARY_PATH="$(_go2_remove_path_entry "${LD_LIBRARY_PATH:-}" "$LEGACY_CYCLONEDDS_LIB")"

unset -f _go2_remove_path_entry
