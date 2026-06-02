#!/usr/bin/env bash
set -euo pipefail

pkill -f "[r]os2 launch task mapping_qt_test.launch.py" 2>/dev/null || true
pkill -f "[l]io_sam_ros2_" 2>/dev/null || true
pkill -f "[d]og_control_B1_one" 2>/dev/null || true
pkill -f "[g]o2_control_by_sdk.*send_cmd" 2>/dev/null || true
pkill -f "[h]igh_rate_state" 2>/dev/null || true
pkill -f "[g]o2_lio_sam_topic_bridge.py" 2>/dev/null || true

echo "Stopped Unitree official LIO-SAM mapping processes if they were running."
