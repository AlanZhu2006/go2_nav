#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GO2_DDS_ENV="${GO2_DDS_ENV:-$SCRIPT_DIR/go2_dds_env.sh}"
SOURCE="${GO2_OFFICIAL_MAP_SOURCE:-uslam}"
STAMP="$(date +%Y%m%d-%H%M%S)"
MAP_ROOT="${GO2_OFFICIAL_MAP_ROOT:-$HOME/work/go2_nav/maps}"
START_RVIZ="${START_RVIZ:-true}"
CONVERT_TO_PGM="${CONVERT_TO_PGM:-false}"
SAVE_TIMEOUT="${GO2_OFFICIAL_SAVE_TIMEOUT:-120}"
RVIZ_DISPLAY="${RVIZ_DISPLAY:-:1}"

USLAM_TOPIC="${GO2_USLAM_MAP_TOPIC:-/uslam/cloud_map}"
USLAM_DIR="${GO2_USLAM_MAP_DIR:-$MAP_ROOT/go2_uslam_${STAMP}}"
USLAM_OUTPUT="${GO2_USLAM_MAP_OUTPUT:-$USLAM_DIR/uslam_cloud_map.pcd}"
USLAM_LATEST_PCD="$MAP_ROOT/go2_uslam_latest.pcd"

LIO_SAM_DIR="${GO2_LIO_SAM_MAP_DIR:-$MAP_ROOT/go2_lio_sam_${STAMP}}"
LIO_SAM_LATEST_PCD="$MAP_ROOT/go2_lio_sam_latest.pcd"
START_LIO_SAM="${START_LIO_SAM:-true}"
STOP_LIO_SAM_ON_EXIT="${STOP_LIO_SAM_ON_EXIT:-false}"
UNITREE_SLAM_WS="${UNITREE_SLAM_WS:-/unitree/module/graph_pid_ws}"
LIO_SAM_RVIZ_CONFIG="${LIO_SAM_RVIZ_CONFIG:-$UNITREE_SLAM_WS/src/task/rviz2/build_map.rviz}"
LIO_SAM_LOG_DIR="${UNITREE_MAPPING_LOG_DIR:-/tmp/unitree_lio_sam_mapping}"

PGM_OUT_DIR="${PGM_OUT_DIR:-}"

source_relaxed() {
    local setup_file="$1"
    local had_nounset=0
    case $- in
        *u*) had_nounset=1; set +u ;;
    esac
    source "$setup_file"
    if [ "$had_nounset" = "1" ]; then
        set -u
    fi
}

latest_pcd_in_dir() {
    local dir="$1"
    find "$dir" -maxdepth 2 -type f -name '*.pcd' -printf '%s %p\n' 2>/dev/null \
        | sort -nr \
        | awk 'NR==1 { $1=""; sub(/^ /, ""); print; exit }'
}

convert_map() {
    local input_pcd="$1"
    local output_dir="$2"
    if [ -z "$output_dir" ]; then
        output_dir="$(dirname "$input_pcd")/nav2_map"
    fi
    PCD_INPUT="$input_pcd" MAP_OUT_DIR="$output_dir" "$SCRIPT_DIR/pcd2pgm_go2.sh"
}

start_lio_sam_rviz() {
    mkdir -p "$LIO_SAM_LOG_DIR"

    if ! systemctl --user --quiet is-active rviz-vnc.service; then
        echo ">>> Starting RViz VNC service"
        systemctl --user start rviz-vnc.service
    fi

    if [ ! -S "/tmp/.X11-unix/X${RVIZ_DISPLAY#:}" ]; then
        echo "Warning: X display $RVIZ_DISPLAY is not available; RViz was not started." >&2
        echo "Run: systemctl --user restart rviz-vnc.service" >&2
        return 0
    fi

    if [ ! -f "$LIO_SAM_RVIZ_CONFIG" ]; then
        echo "Warning: LIO-SAM RViz config not found: $LIO_SAM_RVIZ_CONFIG" >&2
        return 0
    fi

    pkill -f "[r]viz2.*build_map.rviz" 2>/dev/null || true

    echo ">>> Starting Unitree LIO-SAM RViz"
    echo "    config:  $LIO_SAM_RVIZ_CONFIG"
    echo "    display: $RVIZ_DISPLAY"
    echo "    log:     $LIO_SAM_LOG_DIR/rviz_lio_sam.log"

    setsid bash -lc "
        source '$GO2_DDS_ENV'
        cd '$UNITREE_SLAM_WS'
        source install/setup.bash
        DISPLAY='$RVIZ_DISPLAY' \
        XAUTHORITY='${XAUTHORITY:-$HOME/.Xauthority}' \
        LIBGL_ALWAYS_SOFTWARE=1 \
        QT_X11_NO_MITSHM=1 \
        exec ros2 run rviz2 rviz2 -d '$LIO_SAM_RVIZ_CONFIG'
    " > "$LIO_SAM_LOG_DIR/rviz_lio_sam.log" 2>&1 < /dev/null &
}

save_uslam() {
    mkdir -p "$USLAM_DIR"
    echo ">>> Saving official Go2 USLAM map"
    echo "    topic:  $USLAM_TOPIC"
    echo "    output: $USLAM_OUTPUT"

    GO2_MAP_TOPIC="$USLAM_TOPIC" \
    GO2_MAP_OUTPUT="$USLAM_OUTPUT" \
    GO2_SAVE_TIMEOUT="$SAVE_TIMEOUT" \
        "$SCRIPT_DIR/save_go2_builtin_pcd.sh"

    ln -sfn "$USLAM_OUTPUT" "$USLAM_DIR/latest.pcd"
    ln -sfn "$USLAM_OUTPUT" "$USLAM_LATEST_PCD"

    echo
    echo "Official USLAM PCD saved:"
    ls -lh "$USLAM_OUTPUT" "$USLAM_DIR/latest.pcd" "$USLAM_LATEST_PCD"

    if [ "$CONVERT_TO_PGM" = "true" ] || [ "$CONVERT_TO_PGM" = "1" ]; then
        convert_map "$USLAM_OUTPUT" "${PGM_OUT_DIR:-$USLAM_DIR/nav2_map}"
    fi
}

save_lio_sam() {
    mkdir -p "$LIO_SAM_DIR"
    echo ">>> Saving Unitree official LIO-SAM map"
    echo "    output dir: $LIO_SAM_DIR"

    "$SCRIPT_DIR/save_unitree_lio_sam_map.sh" "$LIO_SAM_DIR"

    local pcd
    pcd="$(latest_pcd_in_dir "$LIO_SAM_DIR")"
    if [ -z "$pcd" ]; then
        echo "Error: no .pcd files were generated in $LIO_SAM_DIR" >&2
        echo "Check mapper status and logs: /tmp/unitree_lio_sam_mapping/*.log" >&2
        return 1
    fi

    ln -sfn "$pcd" "$LIO_SAM_DIR/latest.pcd"
    ln -sfn "$pcd" "$LIO_SAM_LATEST_PCD"

    echo
    echo "Official LIO-SAM PCD saved:"
    find "$LIO_SAM_DIR" -maxdepth 2 -type f -name '*.pcd' -printf '  %s %p\n' | sort -nr
    echo
    echo "Selected for pcd2pgm:"
    ls -lh "$pcd" "$LIO_SAM_DIR/latest.pcd" "$LIO_SAM_LATEST_PCD"

    if [ "$CONVERT_TO_PGM" = "true" ] || [ "$CONVERT_TO_PGM" = "1" ]; then
        convert_map "$pcd" "${PGM_OUT_DIR:-$LIO_SAM_DIR/nav2_map}"
    fi
}

if [ ! -f "$GO2_DDS_ENV" ]; then
    echo "Error: Go2 DDS env script not found: $GO2_DDS_ENV" >&2
    exit 1
fi

source "$GO2_DDS_ENV"
source_relaxed /opt/ros/foxy/setup.bash

echo ">>> Starting Go2 built-in lidar services"
"$SCRIPT_DIR/start_go2_lidar_services.py"

echo ">>> Switching Go2 built-in lidar ON"
"$SCRIPT_DIR/go2_utlidar_switch.py" ON --repeat 5 --interval 0.2

case "$SOURCE" in
    uslam)
        if [ "$START_RVIZ" = "true" ] || [ "$START_RVIZ" = "1" ]; then
            echo ">>> Starting RViz in VNC"
            "$SCRIPT_DIR/start_go2_builtin_rviz.sh"
        fi
        cat <<EOF

>>> Official map source: Go2 built-in USLAM
    map topic: $USLAM_TOPIC

Walk the robot in Unitree official 3D LiDAR Mapping/SLAM mode.
When the map looks ready:

  1 + Enter  save one full $USLAM_TOPIC message as PCD
  s + Enter  show topic status
  q + Enter  quit

EOF
        ;;
    lio_sam)
        if [ "$START_LIO_SAM" = "true" ] || [ "$START_LIO_SAM" = "1" ]; then
            CLEAN_OLD_MAPPING="${CLEAN_OLD_MAPPING:-1}" "$SCRIPT_DIR/start_unitree_lio_sam_mapping.sh"
        fi
        if [ "$START_RVIZ" = "true" ] || [ "$START_RVIZ" = "1" ]; then
            start_lio_sam_rviz
        fi
        cat <<EOF

>>> Official map source: Unitree LIO-SAM
    save service: /lio_sam_ros2/save_map
    output dir:   $LIO_SAM_DIR

Walk the robot while /lio_sam_ros2/mapping/map_local is updating.
When the map looks ready:

  1 + Enter  call /lio_sam_ros2/save_map and save global PCD
  s + Enter  show topic/service status
  q + Enter  quit

EOF
        ;;
    *)
        echo "Error: GO2_OFFICIAL_MAP_SOURCE must be uslam or lio_sam, got: $SOURCE" >&2
        exit 1
        ;;
esac

while true; do
    printf "official-map[%s]> " "$SOURCE"
    read -r command
    case "$command" in
        1)
            if [ "$SOURCE" = "uslam" ]; then
                save_uslam
            else
                save_lio_sam
            fi
            break
            ;;
        s|status)
            if [ "$SOURCE" = "uslam" ]; then
                echo ">>> USLAM topics"
                ros2 topic list -t | grep -E 'uslam|utlidar' || true
                echo
                echo ">>> Frequency check: $USLAM_TOPIC"
                timeout 5 ros2 topic hz "$USLAM_TOPIC" || true
            else
                echo ">>> LIO-SAM topics"
                ros2 topic list -t | grep -E 'lio_sam_ros2|go2_lio_sam|rslidar|dog_imu|utlidar' || true
                echo
                echo ">>> Save service"
                ros2 service list | grep -E '/lio_sam_ros2/save_map' || true
                echo
                echo ">>> Frequency checks"
                for topic in \
                    /go2_lio_sam/rslidar_points \
                    /go2_lio_sam/dog_imu_raw \
                    /lio_sam_ros2/mapping/map_local \
                    /lio_sam_ros2/mapping/odometry \
                    /lio_sam_ros2/mapping/map_global; do
                    echo "--- $topic"
                    timeout 5 ros2 topic hz "$topic" || true
                done
                echo
                echo ">>> Recent mapper log"
                tail -50 /tmp/unitree_lio_sam_mapping/lio_sam_map_optimization.log 2>/dev/null || \
                    tail -50 /tmp/unitree_lio_sam_mapping/mapping_qt_test.log 2>/dev/null || true
                echo
                echo ">>> Recent image projection log"
                tail -30 /tmp/unitree_lio_sam_mapping/lio_sam_image_projection.log 2>/dev/null || true
                echo
                echo ">>> Recent bridge log"
                tail -20 /tmp/unitree_lio_sam_mapping/go2_lio_sam_topic_bridge.log 2>/dev/null || true
            fi
            ;;
        q|quit|exit)
            echo "Quit without saving."
            break
            ;;
        *)
            echo "Commands: 1=save, s=status, q=quit"
            ;;
    esac
done

if [ "$SOURCE" = "lio_sam" ] && { [ "$STOP_LIO_SAM_ON_EXIT" = "true" ] || [ "$STOP_LIO_SAM_ON_EXIT" = "1" ]; }; then
    "$SCRIPT_DIR/stop_unitree_lio_sam_mapping.sh"
fi
