#!/usr/bin/env bash
set -euo pipefail

UNITREE_SLAM_WS="${UNITREE_SLAM_WS:-/unitree/module/graph_pid_ws}"
GO2_DDS_ENV="${GO2_DDS_ENV:-/home/unitree/work/nyush_rm_sentry/scripts/go2_dds_env.sh}"
LOG_DIR="${UNITREE_MAPPING_LOG_DIR:-/tmp/unitree_lio_sam_mapping}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
START_GO2_LIO_SAM_BRIDGE="${START_GO2_LIO_SAM_BRIDGE:-1}"
LIO_SAM_SKIP_CHECKOUT="${LIO_SAM_SKIP_CHECKOUT:-1}"
LIO_SAM_PARAMS_FILE="${LIO_SAM_PARAMS_FILE:-${UNITREE_SLAM_WS}/install/lio_sam_ros2/share/lio_sam_ros2/config/params.yaml}"
LIO_SAM_USE_SIM_TIME="${LIO_SAM_USE_SIM_TIME:-false}"
LIO_SAM_SAVE_DIR="${LIO_SAM_SAVE_DIR:-${HOME}/work/go2_nav/maps/go2_lio_sam_runtime/default/}"
GO2_LIO_SAM_SYNTHETIC_RING="${GO2_LIO_SAM_SYNTHETIC_RING:-1}"
LIO_SAM_POINT_CLOUD_TOPIC="${LIO_SAM_POINT_CLOUD_TOPIC:-/go2_lio_sam/rslidar_points}"
LIO_SAM_IMU_TOPIC="${LIO_SAM_IMU_TOPIC:-/go2_lio_sam/dog_imu_raw}"
LIO_SAM_SENSOR="${LIO_SAM_SENSOR:-velodyne}"

mkdir -p "${LOG_DIR}"

if [[ ! -d "${UNITREE_SLAM_WS}" ]]; then
  echo "Unitree SLAM workspace not found: ${UNITREE_SLAM_WS}" >&2
  exit 1
fi

if [[ ! -f "${UNITREE_SLAM_WS}/install/setup.bash" ]]; then
  echo "Unitree SLAM setup not found: ${UNITREE_SLAM_WS}/install/setup.bash" >&2
  exit 1
fi

if [[ ! -f "${GO2_DDS_ENV}" ]]; then
  echo "Go2 DDS env script not found: ${GO2_DDS_ENV}" >&2
  exit 1
fi

if [[ "${CLEAN_OLD_MAPPING:-0}" == "1" ]]; then
  pkill -f "[h]igh_rate_state" 2>/dev/null || true
  pkill -f "[g]o2_control_by_sdk.*send_cmd" 2>/dev/null || true
  pkill -f "[g]o2_lio_sam_topic_bridge.py" 2>/dev/null || true
  pkill -f "[r]os2 launch task mapping_qt_test.launch.py" 2>/dev/null || true
  pkill -f "[l]io_sam_ros2_" 2>/dev/null || true
  pkill -f "[d]og_control_B1_one" 2>/dev/null || true
fi

if [[ ! -f "${LIO_SAM_PARAMS_FILE}" ]]; then
  echo "LIO-SAM params file not found: ${LIO_SAM_PARAMS_FILE}" >&2
  exit 1
fi

case "${LIO_SAM_SAVE_DIR}" in
  */) ;;
  *) LIO_SAM_SAVE_DIR="${LIO_SAM_SAVE_DIR}/" ;;
esac
mkdir -p "${LIO_SAM_SAVE_DIR}"

start_bg() {
  local name="$1"
  shift
  local log_file="${LOG_DIR}/${name}.log"
  local cmd

  printf -v cmd '%q ' "$@"

  setsid bash -lc "
    source '${GO2_DDS_ENV}'
    cd '${UNITREE_SLAM_WS}'
    source install/setup.bash
    export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
    export LD_LIBRARY_PATH=/usr/local/lib:\${LD_LIBRARY_PATH:-}
    exec ${cmd}
  " >"${log_file}" 2>&1 &

  echo "$!" >"${LOG_DIR}/${name}.pid"
  echo "started ${name}: pid=$(cat "${LOG_DIR}/${name}.pid"), log=${log_file}"
}

echo "Starting Unitree official LIO-SAM mapping stack."
echo "Workspace: ${UNITREE_SLAM_WS}"
echo "Logs:      ${LOG_DIR}"
echo "Params:    ${LIO_SAM_PARAMS_FILE}"
echo "Save dir:  ${LIO_SAM_SAVE_DIR}"
echo "Mode:      LIO_SAM_SKIP_CHECKOUT=${LIO_SAM_SKIP_CHECKOUT}, GO2_LIO_SAM_SYNTHETIC_RING=${GO2_LIO_SAM_SYNTHETIC_RING}"
echo "Input:     cloud=${LIO_SAM_POINT_CLOUD_TOPIC}, imu=${LIO_SAM_IMU_TOPIC}, sensor=${LIO_SAM_SENSOR}"
echo
echo "Safety note: this starts Unitree's go2_control_by_sdk send_cmd bridge."
echo "Keep the robot in a safe area and have the controller/e-stop ready."
echo

if [[ "${START_GO2_LIO_SAM_BRIDGE}" == "1" || "${START_GO2_LIO_SAM_BRIDGE}" == "true" ]]; then
  start_bg go2_lio_sam_topic_bridge \
    python3 "${SCRIPT_DIR}/go2_lio_sam_topic_bridge.py" \
    --ros-args \
    -p cloud_out:="${LIO_SAM_POINT_CLOUD_TOPIC}" \
    -p imu_out:="${LIO_SAM_IMU_TOPIC}" \
    -p synthesize_ring:="${GO2_LIO_SAM_SYNTHETIC_RING}" \
    -p synthetic_scan_lines:=16
  sleep 1
fi

start_bg high_rate_state ros2 run send_cmd high_rate_state
sleep 1
start_bg go2_send_cmd ros2 run go2_control_by_sdk send_cmd
sleep 1

if [[ "${LIO_SAM_SKIP_CHECKOUT}" == "1" || "${LIO_SAM_SKIP_CHECKOUT}" == "true" ]]; then
  start_bg dog_control ros2 run dog_control dog_control_B1_one
  sleep 1
  start_bg lio_sam_dog_odom ros2 run lio_sam_ros2 lio_sam_ros2_dogOdomForMapping \
    --ros-args --params-file "${LIO_SAM_PARAMS_FILE}" -p pointCloudTopic:="${LIO_SAM_POINT_CLOUD_TOPIC}" -p imuTopic:="${LIO_SAM_IMU_TOPIC}" -p sensor:="${LIO_SAM_SENSOR}" -p use_sim_time:="${LIO_SAM_USE_SIM_TIME}"
  start_bg lio_sam_imu_preintegration ros2 run lio_sam_ros2 lio_sam_ros2_imuPreintegration \
    --ros-args --params-file "${LIO_SAM_PARAMS_FILE}" -p pointCloudTopic:="${LIO_SAM_POINT_CLOUD_TOPIC}" -p imuTopic:="${LIO_SAM_IMU_TOPIC}" -p sensor:="${LIO_SAM_SENSOR}" -p use_sim_time:="${LIO_SAM_USE_SIM_TIME}"
  start_bg lio_sam_image_projection ros2 run lio_sam_ros2 lio_sam_ros2_imageProjection \
    --ros-args --params-file "${LIO_SAM_PARAMS_FILE}" -p pointCloudTopic:="${LIO_SAM_POINT_CLOUD_TOPIC}" -p imuTopic:="${LIO_SAM_IMU_TOPIC}" -p sensor:="${LIO_SAM_SENSOR}" -p use_sim_time:="${LIO_SAM_USE_SIM_TIME}"
  start_bg lio_sam_feature_extraction ros2 run lio_sam_ros2 lio_sam_ros2_featureExtraction \
    --ros-args --params-file "${LIO_SAM_PARAMS_FILE}" -p pointCloudTopic:="${LIO_SAM_POINT_CLOUD_TOPIC}" -p imuTopic:="${LIO_SAM_IMU_TOPIC}" -p sensor:="${LIO_SAM_SENSOR}" -p use_sim_time:="${LIO_SAM_USE_SIM_TIME}"
  start_bg lio_sam_map_optimization ros2 run lio_sam_ros2 lio_sam_ros2_mapOptmization \
    --ros-args --params-file "${LIO_SAM_PARAMS_FILE}" -p pointCloudTopic:="${LIO_SAM_POINT_CLOUD_TOPIC}" -p imuTopic:="${LIO_SAM_IMU_TOPIC}" -p sensor:="${LIO_SAM_SENSOR}" -p savePCDDirectory:="${LIO_SAM_SAVE_DIR}" -p use_sim_time:="${LIO_SAM_USE_SIM_TIME}"
else
  start_bg mapping_qt_test ros2 launch task mapping_qt_test.launch.py
fi

cat <<EOF

Check mapping topics:
  source ${GO2_DDS_ENV}
  source ${UNITREE_SLAM_WS}/install/setup.bash
  export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
  ros2 topic list -t | grep -E 'lio_sam_ros2|go2_lio_sam|dog_imu|rslidar|utlidar'
  ros2 topic hz /lio_sam_ros2/mapping/odometry
  ros2 topic hz /lio_sam_ros2/mapping/map_local

Tail logs:
  tail -f ${LOG_DIR}/lio_sam_map_optimization.log
  tail -f ${LOG_DIR}/lio_sam_image_projection.log
  tail -f ${LOG_DIR}/go2_lio_sam_topic_bridge.log

Save map:
  ~/work/nyush_rm_sentry/scripts/save_unitree_lio_sam_map.sh

Stop mapping:
  ~/work/nyush_rm_sentry/scripts/stop_unitree_lio_sam_mapping.sh
EOF
