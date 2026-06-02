#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAV_WS_ROOT="${NAV_WS_ROOT:-$HOME/nav_ws}"

set +u
source /opt/ros/foxy/setup.bash
if [ -f "$NAV_WS_ROOT/install/setup.bash" ]; then
    source "$NAV_WS_ROOT/install/setup.bash"
fi
set -u

export RMW_IMPLEMENTATION="${GO2_NAV_RMW_IMPLEMENTATION:-rmw_fastrtps_cpp}"
unset CYCLONEDDS_URI CYCLONEDDS_HOME

exec python3 "$SCRIPT_DIR/diagnose_mid360_nav_timing.py"
