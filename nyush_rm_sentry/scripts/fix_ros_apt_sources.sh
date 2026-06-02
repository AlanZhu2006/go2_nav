#!/usr/bin/env bash

set -euo pipefail

ROS1_LIST="/etc/apt/sources.list.d/ros-latest.list"
ROS2_LIST="/etc/apt/sources.list.d/ros2-latest.list"
LEGACY_DUP_LIST="/etc/apt/sources.list.d/ros-fish.list"
KEYRING="/usr/share/keyrings/ros-archive-keyring.gpg"

if [ ! -f "$KEYRING" ]; then
    echo "Error: ROS keyring not found: $KEYRING"
    echo "Install ros-archive-keyring first or restore your ROS apt setup."
    exit 1
fi

if [ -f "$LEGACY_DUP_LIST" ]; then
    echo ">>> Disabling duplicate ROS source: $LEGACY_DUP_LIST"
    sudo mv "$LEGACY_DUP_LIST" "$LEGACY_DUP_LIST.disabled.$(date +%Y%m%d-%H%M%S)"
fi

echo ">>> Writing ROS 1 source:"
echo "    $ROS1_LIST"
printf 'deb [signed-by=%s] http://packages.ros.org/ros/ubuntu focal main\n' "$KEYRING" \
    | sudo tee "$ROS1_LIST" >/dev/null

echo ">>> Writing ROS 2 source:"
echo "    $ROS2_LIST"
printf 'deb [signed-by=%s] http://packages.ros.org/ros2/ubuntu focal main\n' "$KEYRING" \
    | sudo tee "$ROS2_LIST" >/dev/null

echo ">>> Cleaning stale ROS apt lists..."
sudo rm -f /var/lib/apt/lists/*ros_ubuntu* /var/lib/apt/lists/*ros2_ubuntu* || true
sudo apt clean

echo ">>> Updating apt metadata..."
sudo apt update

echo ">>> Done. Re-run:"
echo "    ./scripts/install_foxy_deps.sh"
