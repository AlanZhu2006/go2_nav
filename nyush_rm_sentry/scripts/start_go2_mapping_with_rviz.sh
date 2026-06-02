#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! systemctl --user --quiet is-active rviz-vnc.service; then
    echo ">>> Starting RViz VNC service"
    systemctl --user start rviz-vnc.service
fi

exec env START_RVIZ=1 "$SCRIPT_DIR/start_go2_fastlio_mapping.sh"
