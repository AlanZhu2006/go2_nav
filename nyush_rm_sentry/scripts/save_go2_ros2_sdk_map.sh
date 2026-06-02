#!/usr/bin/env bash

set -euo pipefail

CONTAINER_NAME="${GO2_SDK_CONTAINER:-go2_sdk_mapping}"
MAP_NAME="${MAP_NAME:-go2_ros2_sdk_$(date +%Y%m%d-%H%M%S)}"
LATEST_LINK="${LATEST_LINK:-go2_ros2_sdk_latest}"

if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    echo "Error: container is not running: $CONTAINER_NAME" >&2
    echo "Start it first: ~/work/nyush_rm_sentry/scripts/start_go2_ros2_sdk_mapping.sh" >&2
    exit 1
fi

docker exec "$CONTAINER_NAME" bash -lc "
set -e
source /opt/ros/humble/setup.bash
source /ros2_ws/install/setup.bash

MAP_DIR=/maps/$MAP_NAME
mkdir -p \"\$MAP_DIR\"

echo '>>> Saving go2_ros2_sdk slam_toolbox map'
echo \"    output: \$MAP_DIR/map.{pgm,yaml}\"

ros2 run nav2_map_server map_saver_cli \
    -t /map \
    -f \"\$MAP_DIR/map\" \
    --occ 0.65 \
    --free 0.25 \
    --fmt pgm \
    --mode trinary \
    > \"\$MAP_DIR/map_saver.log\" 2>&1

cd /maps
ln -sfn \"$MAP_NAME\" \"$LATEST_LINK\"
chown -R \${HOST_UID:-1000}:\${HOST_GID:-1000} \"$MAP_NAME\" \"$LATEST_LINK\" 2>/dev/null || true
ls -lh \"\$MAP_DIR\"
echo
echo \"Latest link: /maps/$LATEST_LINK -> $MAP_NAME\"
"

echo
echo "Host map path:"
echo "  $HOME/work/go2_nav/maps/$MAP_NAME/map.yaml"
echo "Latest:"
echo "  $HOME/work/go2_nav/maps/$LATEST_LINK/map.yaml"
