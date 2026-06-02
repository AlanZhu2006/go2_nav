#!/usr/bin/env bash

set -euo pipefail

CONTAINER_NAME="${GO2_SDK_CONTAINER:-go2_sdk_mapping}"

if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    echo "Error: container is not running: $CONTAINER_NAME" >&2
    exit 1
fi

docker exec "$CONTAINER_NAME" bash -lc '
set -e
source /opt/ros/humble/setup.bash
source /ros2_ws/install/setup.bash

echo ">>> Topics"
ros2 topic list -t | sort | grep -E "point_cloud2|pointcloud|scan|map|odom|tf|uslam|utlidar" || true

echo
echo ">>> Rates"
for topic in /point_cloud2 /pointcloud/filtered /scan /map; do
    echo "--- $topic"
    timeout 4 ros2 topic hz "$topic" || true
done

echo
echo ">>> TF odom -> base_link"
timeout 4 ros2 run tf2_ros tf2_echo odom base_link || true

echo
echo ">>> Tail log"
tail -60 /tmp/go2_sdk_mapping.log || true
if [ -f /tmp/go2_sdk_rviz.log ]; then
    echo
    echo ">>> Tail RViz log"
    tail -40 /tmp/go2_sdk_rviz.log || true
fi
'
