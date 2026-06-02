#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# This entry mirrors the useful navigation behavior of start_robot.sh:
# FAST-LIO body-frame registered cloud -> LaserScan, AMCL map->odom localization,
# publish an initial pose, then start Nav2/RViz. It intentionally keeps the
# decision/vision/BT layers out of the Go2 deployment path.

export START_RVIZ="${START_RVIZ:-true}"
export BODY_CLOUD_TOPIC="${BODY_CLOUD_TOPIC:-/cloud_registered_body}"
export SCAN_MIN_HEIGHT="${SCAN_MIN_HEIGHT:--0.4}"
export SCAN_MAX_HEIGHT="${SCAN_MAX_HEIGHT:-1.0}"
export SCAN_TRANSFORM_TOLERANCE="${SCAN_TRANSFORM_TOLERANCE:-0.50}"
export LOCALIZATION_MODE="${LOCALIZATION_MODE:-amcl}"
export PUBLISH_INITIAL_POSE="${PUBLISH_INITIAL_POSE:-false}"
export INITIAL_POSE_STAMP_MODE="${INITIAL_POSE_STAMP_MODE:-now}"
export INITIAL_POSE_STAMP_BACKDATE="${INITIAL_POSE_STAMP_BACKDATE:-1.5}"
export INITIAL_POSE_REPEAT="${INITIAL_POSE_REPEAT:-1}"
export AMCL_GLOBAL_LOCALIZATION="${AMCL_GLOBAL_LOCALIZATION:-false}"
export INITIAL_POSE_X="${INITIAL_POSE_X:-0.0}"
export INITIAL_POSE_Y="${INITIAL_POSE_Y:-0.0}"
export INITIAL_POSE_YAW_DEG="${INITIAL_POSE_YAW_DEG:-0}"
export START_GO2_CMD_BRIDGE="${START_GO2_CMD_BRIDGE:-false}"
export GO2_SEND_ZERO_WHEN_IDLE="${GO2_SEND_ZERO_WHEN_IDLE:-false}"
export GO2_REMOTE_PRIORITY="${GO2_REMOTE_PRIORITY:-true}"
export GO2_REMOTE_DEADBAND="${GO2_REMOTE_DEADBAND:-0.12}"
export GO2_REMOTE_HOLD_SEC="${GO2_REMOTE_HOLD_SEC:-0.8}"
export GO2_MAX_VX="${GO2_MAX_VX:-0.15}"
export GO2_MAX_VY="${GO2_MAX_VY:-0.00}"
export GO2_MAX_WZ="${GO2_MAX_WZ:-0.30}"
export LIDAR_TO_BASE_YAW_DEG="${LIDAR_TO_BASE_YAW_DEG:-90}"

exec "$SCRIPT_DIR/start_mid360_fastlio_nav2_with_rviz.sh" "$@"
