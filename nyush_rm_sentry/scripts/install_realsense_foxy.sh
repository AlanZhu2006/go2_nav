#!/usr/bin/env bash

set -euo pipefail

echo ">>> Installing ROS 2 Foxy RealSense driver"
sudo apt update
sudo apt install -y \
    ros-foxy-realsense2-camera \
    ros-foxy-realsense2-description \
    ros-foxy-librealsense2

echo
echo "RealSense Foxy packages installed."
echo "Next:"
echo "  source /opt/ros/foxy/setup.bash"
echo "  ros2 pkg prefix realsense2_camera"
