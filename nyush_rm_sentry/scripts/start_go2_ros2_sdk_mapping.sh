#!/usr/bin/env bash

set -euo pipefail

SDK_ROOT="${SDK_ROOT:-$HOME/work/go2_ros2_sdk}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="${GO2_SDK_IMAGE:-go2_ros2_sdk:minimal}"
CONTAINER_NAME="${GO2_SDK_CONTAINER:-go2_sdk_mapping}"
MAPS_DIR="${MAPS_DIR:-$HOME/work/go2_nav/maps}"
ROBOT_IP="${ROBOT_IP:-192.168.123.161}"
CONN_TYPE="${CONN_TYPE:-webrtc}"
RMW_IMPLEMENTATION="${RMW_IMPLEMENTATION:-rmw_fastrtps_cpp}"

START_RVIZ="${START_RVIZ:-false}"
RVIZ_MODE="${RVIZ_MODE:-host}"
RVIZ_DISPLAY="${RVIZ_DISPLAY:-:1}"
RVIZ_START_DELAY="${RVIZ_START_DELAY:-12}"
RVIZ_WAIT_TIMEOUT="${RVIZ_WAIT_TIMEOUT:-60}"

GO2_SDK_AGG_DOWNSAMPLE="${GO2_SDK_AGG_DOWNSAMPLE:-3}"
GO2_SDK_AGG_PUBLISH_RATE="${GO2_SDK_AGG_PUBLISH_RATE:-5.0}"
GO2_SDK_SCAN_TIME="${GO2_SDK_SCAN_TIME:-0.2}"
GO2_SDK_SCAN_RANGE_MIN="${GO2_SDK_SCAN_RANGE_MIN:-0.3}"
GO2_SDK_SCAN_RANGE_MAX="${GO2_SDK_SCAN_RANGE_MAX:-20.0}"
GO2_SDK_SCAN_MIN_HEIGHT="${GO2_SDK_SCAN_MIN_HEIGHT:--1.0}"
GO2_SDK_SCAN_MAX_HEIGHT="${GO2_SDK_SCAN_MAX_HEIGHT:-3.0}"

if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
    SDK_ROOT="$SDK_ROOT" GO2_SDK_IMAGE="$IMAGE_NAME" "$SCRIPT_DIR/build_go2_ros2_sdk_minimal.sh"
fi

mkdir -p "$MAPS_DIR"

echo ">>> Stopping old $CONTAINER_NAME container, if any"
docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

echo ">>> Starting go2_ros2_sdk minimal mapping stack"
echo "    image:     $IMAGE_NAME"
echo "    robot ip:  $ROBOT_IP"
echo "    maps dir:  $MAPS_DIR"
echo "    rviz:      $START_RVIZ ($RVIZ_MODE) on DISPLAY=$RVIZ_DISPLAY"
echo "    rmw:       $RMW_IMPLEMENTATION"
echo "    scan:      /pointcloud/filtered -> /scan"
echo "    slam:      slam_toolbox /scan -> /map"

if command -v xhost >/dev/null 2>&1; then
    DISPLAY="$RVIZ_DISPLAY" xhost +SI:localuser:root >/dev/null 2>&1 || true
    DISPLAY="$RVIZ_DISPLAY" xhost +local:docker >/dev/null 2>&1 || true
fi

docker run -d --net=host --privileged \
    -e ROBOT_IP="$ROBOT_IP" \
    -e CONN_TYPE="$CONN_TYPE" \
    -e RMW_IMPLEMENTATION="$RMW_IMPLEMENTATION" \
    -e START_RVIZ="$START_RVIZ" \
    -e DISPLAY="$RVIZ_DISPLAY" \
    -e QT_X11_NO_MITSHM=1 \
    -e LIBGL_ALWAYS_SOFTWARE=1 \
    -e GO2_SDK_AGG_DOWNSAMPLE="$GO2_SDK_AGG_DOWNSAMPLE" \
    -e GO2_SDK_AGG_PUBLISH_RATE="$GO2_SDK_AGG_PUBLISH_RATE" \
    -e GO2_SDK_SCAN_TIME="$GO2_SDK_SCAN_TIME" \
    -e GO2_SDK_SCAN_RANGE_MIN="$GO2_SDK_SCAN_RANGE_MIN" \
    -e GO2_SDK_SCAN_RANGE_MAX="$GO2_SDK_SCAN_RANGE_MAX" \
    -e GO2_SDK_SCAN_MIN_HEIGHT="$GO2_SDK_SCAN_MIN_HEIGHT" \
    -e GO2_SDK_SCAN_MAX_HEIGHT="$GO2_SDK_SCAN_MAX_HEIGHT" \
    -e HOST_UID="$(id -u)" \
    -e HOST_GID="$(id -g)" \
    -v /tmp/.X11-unix:/tmp/.X11-unix:rw \
    -v "$MAPS_DIR:/maps:rw" \
    --name "$CONTAINER_NAME" \
    "$IMAGE_NAME" \
    bash -lc "source /opt/ros/humble/setup.bash && source /ros2_ws/install/setup.bash && ros2 launch go2_robot_sdk mapping_minimal.launch.py rviz:=false > /tmp/go2_sdk_mapping.log 2>&1"

if [ "$START_RVIZ" = "true" ] || [ "$START_RVIZ" = "1" ]; then
    if [ "$RVIZ_MODE" = "docker" ]; then
        echo ">>> Scheduling Docker RViz after Go2 WebRTC validates"
        docker exec -d \
            -e DISPLAY="$RVIZ_DISPLAY" \
            -e QT_X11_NO_MITSHM=1 \
            -e LIBGL_ALWAYS_SOFTWARE=1 \
            "$CONTAINER_NAME" \
            bash -lc "sleep '$RVIZ_START_DELAY'; for i in \$(seq 1 '$RVIZ_WAIT_TIMEOUT'); do grep -q 'Robot 0 validated and ready' /tmp/go2_sdk_mapping.log 2>/dev/null && break; sleep 1; done; if ! grep -q 'Robot 0 validated and ready' /tmp/go2_sdk_mapping.log 2>/dev/null; then echo 'RViz not started: Go2 WebRTC did not validate before timeout.' > /tmp/go2_sdk_rviz.log; exit 0; fi; source /opt/ros/humble/setup.bash; source /ros2_ws/install/setup.bash; pkill -x rviz2 2>/dev/null || true; rviz2 -d /ros2_ws/install/go2_robot_sdk/share/go2_robot_sdk/config/mapping_minimal.rviz > /tmp/go2_sdk_rviz.log 2>&1"
    else
        echo ">>> Waiting for Go2 WebRTC validation before host Foxy RViz"
        sleep "$RVIZ_START_DELAY"
        rviz_started=0
        for _ in $(seq 1 "$RVIZ_WAIT_TIMEOUT"); do
            if docker exec "$CONTAINER_NAME" bash -lc "grep -q 'Robot 0 validated and ready' /tmp/go2_sdk_mapping.log 2>/dev/null"; then
                RVIZ_DISPLAY="$RVIZ_DISPLAY" RMW_IMPLEMENTATION="$RMW_IMPLEMENTATION" "$SCRIPT_DIR/start_go2_ros2_sdk_host_rviz.sh"
                rviz_started=1
                break
            fi
            sleep 1
        done
        if [ "$rviz_started" = "0" ]; then
            mkdir -p /tmp/go2_ros2_sdk_host_rviz
            echo "RViz not started: Go2 WebRTC did not validate before timeout." > /tmp/go2_ros2_sdk_host_rviz/rviz.log
        fi
    fi
fi

echo
echo "Container started: $CONTAINER_NAME"
echo "Log:"
echo "  docker exec $CONTAINER_NAME bash -lc 'tail -f /tmp/go2_sdk_mapping.log'"
if [ "$START_RVIZ" = "true" ] || [ "$START_RVIZ" = "1" ]; then
    if [ "$RVIZ_MODE" = "docker" ]; then
        echo "  docker exec $CONTAINER_NAME bash -lc 'tail -f /tmp/go2_sdk_rviz.log'"
    else
        echo "  tail -f /tmp/go2_ros2_sdk_host_rviz/rviz.log"
    fi
fi
echo
echo "Check status:"
echo "  ~/work/nyush_rm_sentry/scripts/status_go2_ros2_sdk_mapping.sh"
echo
echo "Save map:"
echo "  ~/work/nyush_rm_sentry/scripts/save_go2_ros2_sdk_map.sh"
