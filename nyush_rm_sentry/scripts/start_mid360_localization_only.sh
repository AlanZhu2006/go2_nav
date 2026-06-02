#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export START_NAVIGATION="${START_NAVIGATION:-false}"
export START_RVIZ="${START_RVIZ:-false}"
export START_GO2_CMD_BRIDGE="${START_GO2_CMD_BRIDGE:-false}"
export PUBLISH_INITIAL_POSE="${PUBLISH_INITIAL_POSE:-false}"
export LOCALIZATION_MODE="${LOCALIZATION_MODE:-amcl}"
export BODY_CLOUD_TOPIC="${BODY_CLOUD_TOPIC:-/cloud_registered_body}"
export SCAN_TRANSFORM_TOLERANCE="${SCAN_TRANSFORM_TOLERANCE:-0.50}"
export INITIAL_POSE_X="${INITIAL_POSE_X:-0.0}"
export INITIAL_POSE_Y="${INITIAL_POSE_Y:-0.0}"
export INITIAL_POSE_YAW_DEG="${INITIAL_POSE_YAW_DEG:-0}"
export LIDAR_TO_BASE_YAW_DEG="${LIDAR_TO_BASE_YAW_DEG:-90}"

exec "$SCRIPT_DIR/start_mid360_fastlio_nav2_with_rviz.sh" "$@"
