#!/usr/bin/env bash

set -euo pipefail

ROS_DISTRO_NAME="${ROS_DISTRO_NAME:-foxy}"
ROS_SETUP="${ROS_SETUP:-/opt/ros/$ROS_DISTRO_NAME/setup.bash}"
NAV_WS_ROOT="${NAV_WS_ROOT:-$HOME/nav_ws}"
INSTALL_LIO_SOURCES="${INSTALL_LIO_SOURCES:-1}"

if [ ! -f "$ROS_SETUP" ]; then
    echo "Error: ROS setup not found: $ROS_SETUP"
    echo "Install ROS 2 Foxy first, or set ROS_SETUP=/path/to/setup.bash"
    exit 1
fi

echo ">>> Updating apt metadata..."
sudo apt update

echo ">>> Installing ROS/system dependencies for $ROS_DISTRO_NAME..."
sudo apt install -y \
    build-essential \
    cmake \
    git \
    libeigen3-dev \
    libpcl-dev \
    python3-colcon-common-extensions \
    python3-pip \
    python3-rosdep \
    python3-vcstool \
    ros-"$ROS_DISTRO_NAME"-ament-cmake-clang-format \
    ros-"$ROS_DISTRO_NAME"-camera-calibration \
    ros-"$ROS_DISTRO_NAME"-camera-info-manager \
    ros-"$ROS_DISTRO_NAME"-gazebo-ros \
    ros-"$ROS_DISTRO_NAME"-gazebo-ros-pkgs \
    ros-"$ROS_DISTRO_NAME"-image-transport-plugins \
    ros-"$ROS_DISTRO_NAME"-joint-state-publisher \
    ros-"$ROS_DISTRO_NAME"-nav2-bringup \
    ros-"$ROS_DISTRO_NAME"-navigation2 \
    ros-"$ROS_DISTRO_NAME"-pcl-ros \
    ros-"$ROS_DISTRO_NAME"-pointcloud-to-laserscan \
    ros-"$ROS_DISTRO_NAME"-rmw-cyclonedds-cpp \
    ros-"$ROS_DISTRO_NAME"-robot-state-publisher \
    ros-"$ROS_DISTRO_NAME"-rviz2 \
    ros-"$ROS_DISTRO_NAME"-serial-driver \
    ros-"$ROS_DISTRO_NAME"-slam-toolbox \
    ros-"$ROS_DISTRO_NAME"-spatio-temporal-voxel-layer \
    ros-"$ROS_DISTRO_NAME"-tf2-tools \
    ros-"$ROS_DISTRO_NAME"-vision-opencv \
    ros-"$ROS_DISTRO_NAME"-xacro

if [ "$INSTALL_LIO_SOURCES" = "1" ]; then
    echo ">>> Preparing navigation source workspace: $NAV_WS_ROOT/src"
    mkdir -p "$NAV_WS_ROOT/src"

    if ! ldconfig -p 2>/dev/null | grep -q liblivox_lidar_sdk_shared; then
        echo ">>> Installing Livox-SDK2 to /usr/local..."
        tmp_dir="$(mktemp -d /tmp/livox-sdk2.XXXXXX)"
        git clone --depth=1 https://github.com/Livox-SDK/Livox-SDK2.git "$tmp_dir/Livox-SDK2"
        cmake -S "$tmp_dir/Livox-SDK2" -B "$tmp_dir/Livox-SDK2/build"
        cmake --build "$tmp_dir/Livox-SDK2/build" -j"$(nproc)"
        sudo cmake --install "$tmp_dir/Livox-SDK2/build"
        rm -rf "$tmp_dir"
    else
        echo ">>> Livox-SDK2 already appears to be installed."
    fi

    if [ ! -d "$NAV_WS_ROOT/src/livox_ros_driver2" ]; then
        git clone --depth=1 https://github.com/Livox-SDK/livox_ros_driver2.git \
            "$NAV_WS_ROOT/src/livox_ros_driver2"
    else
        echo ">>> livox_ros_driver2 already exists, skipping clone."
    fi
    cp -f "$NAV_WS_ROOT/src/livox_ros_driver2/package_ROS2.xml" \
        "$NAV_WS_ROOT/src/livox_ros_driver2/package.xml"
    rm -rf "$NAV_WS_ROOT/src/livox_ros_driver2/launch"
    cp -rf "$NAV_WS_ROOT/src/livox_ros_driver2/launch_ROS2" \
        "$NAV_WS_ROOT/src/livox_ros_driver2/launch"

    if [ ! -d "$NAV_WS_ROOT/src/FAST_LIO" ]; then
        git clone --depth=1 --branch ROS2 --recursive https://github.com/LihanChen2004/FAST_LIO.git \
            "$NAV_WS_ROOT/src/FAST_LIO"
    else
        echo ">>> FAST_LIO already exists, skipping clone."
    fi
    git -C "$NAV_WS_ROOT/src/FAST_LIO" submodule update --init --recursive
fi

echo ">>> Updating rosdep, including EOL Foxy metadata..."
rosdep update --include-eol-distros

echo ">>> Installing Python user dependencies..."
python3 -m pip install --user -U \
    open3d \
    pyserial

echo ">>> Done. Source ROS before building:"
echo "    source $ROS_SETUP"
echo "    cd $NAV_WS_ROOT && colcon build --symlink-install"
