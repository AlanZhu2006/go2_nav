#!/usr/bin/env bash
set -euo pipefail

UNITREE_SLAM_WS="${UNITREE_SLAM_WS:-/unitree/module/graph_pid_ws}"
GO2_DDS_ENV="${GO2_DDS_ENV:-/home/unitree/work/nyush_rm_sentry/scripts/go2_dds_env.sh}"
DEST="${1:-${UNITREE_LIO_SAM_MAP_DIR:-${HOME}/work/go2_nav/maps/go2_lio_sam_latest}}"
RESOLUTION="${UNITREE_LIO_SAM_SAVE_RESOLUTION:-0.0}"

source "${GO2_DDS_ENV}"
source "${UNITREE_SLAM_WS}/install/setup.bash"
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp

mkdir -p "${DEST}"

echo "Saving Unitree LIO-SAM map to: ${DEST}"

if ros2 service list | grep -qx "/lio_sam_ros2/save_map"; then
  ros2 service call /lio_sam_ros2/save_map lio_sam_ros2/srv/SaveMap \
    "{resolution: ${RESOLUTION}, destination: '${DEST}'}"
else
  echo "Service /lio_sam_ros2/save_map is not available yet." >&2
  echo "Falling back to lio_sam_ros2/savepcd/savepcd_flag publish." >&2
  echo "This fallback uses the savePCDDirectory configured in Unitree's params/launch files." >&2
  ros2 topic pub /lio_sam_ros2/savepcd/savepcd_flag std_msgs/msg/Bool "{data: true}" -1
fi

echo
echo "Generated files, if the mapper accepted the save request:"
find "${DEST}" -maxdepth 1 -type f -name '*.pcd' -printf '  %p\n' 2>/dev/null || true
