#!/usr/bin/env bash

set -euo pipefail

ROOT="${REALSENSE_CLEAN_ROOT:-$HOME/work/realsense_stack_clean}"
LRS_VERSION="${REALSENSE_VERSION:-v2.51.1}"
ROS_VERSION="${REALSENSE_ROS_VERSION:-4.51.1}"
JOBS="${JOBS:-$(nproc)}"
RUN_ROSDEP="${RUN_ROSDEP:-false}"

LRS_ROOT="$ROOT/librealsense_rsusb"
LRS_PREFIX="$LRS_ROOT/install"
ROS_WS="$ROOT/ros_ws"
ROS_SRC="$ROS_WS/src/realsense-ros"

echo "Clean RealSense RSUSB stack:"
echo "  root:         $ROOT"
echo "  librealsense: $LRS_VERSION -> $LRS_PREFIX"
echo "  realsense-ros:$ROS_VERSION -> $ROS_WS"
echo "  jobs:         $JOBS"

mkdir -p "$ROOT" "$ROS_WS/src"

echo
echo ">>> Building clean RSUSB librealsense"
REALSENSE_RSUSB_ROOT="$LRS_ROOT" \
REALSENSE_RSUSB_PREFIX="$LRS_PREFIX" \
REALSENSE_VERSION="$LRS_VERSION" \
JOBS="$JOBS" \
"$HOME/work/nyush_rm_sentry/scripts/build_realsense_rsusb.sh"

if [ ! -d "$ROS_SRC/.git" ]; then
    echo
    echo ">>> Cloning realsense-ros"
    git clone https://github.com/IntelRealSense/realsense-ros.git "$ROS_SRC"
fi

echo
echo ">>> Checking out realsense-ros $ROS_VERSION"
git -C "$ROS_SRC" fetch --tags --depth 1 origin "$ROS_VERSION"
git -C "$ROS_SRC" checkout "$ROS_VERSION"

set +u
source /opt/ros/foxy/setup.bash
set -u

export LD_LIBRARY_PATH="$LRS_PREFIX/lib:$LRS_PREFIX/lib/aarch64-linux-gnu:${LD_LIBRARY_PATH:-}"
export CMAKE_PREFIX_PATH="$LRS_PREFIX:${CMAKE_PREFIX_PATH:-}"
export PKG_CONFIG_PATH="$LRS_PREFIX/lib/pkgconfig:$LRS_PREFIX/lib/aarch64-linux-gnu/pkgconfig:${PKG_CONFIG_PATH:-}"

if [ "$RUN_ROSDEP" = "true" ]; then
    echo
    echo ">>> Installing ROS dependencies, skipping apt librealsense2"
    rosdep install --from-paths "$ROS_WS/src" --ignore-src -r -y \
        --rosdistro foxy \
        --skip-keys "librealsense2"
fi

echo
echo ">>> Building clean realsense-ros overlay"
cd "$ROS_WS"
colcon build --symlink-install \
    --packages-select realsense2_camera_msgs realsense2_description realsense2_camera \
    --cmake-args \
        -DCMAKE_BUILD_TYPE=Release \
        -Drealsense2_DIR="$LRS_PREFIX/lib/cmake/realsense2" \
    --parallel-workers "$JOBS"

cat > "$ROOT/env.sh" <<EOF
#!/usr/bin/env bash
set +u
source /opt/ros/foxy/setup.bash
source "$ROS_WS/install/setup.bash"
set -u
export LD_LIBRARY_PATH="$LRS_PREFIX/lib:$LRS_PREFIX/lib/aarch64-linux-gnu:\${LD_LIBRARY_PATH:-}"
export CMAKE_PREFIX_PATH="$LRS_PREFIX:\${CMAKE_PREFIX_PATH:-}"
export PKG_CONFIG_PATH="$LRS_PREFIX/lib/pkgconfig:$LRS_PREFIX/lib/aarch64-linux-gnu/pkgconfig:\${PKG_CONFIG_PATH:-}"
export REALSENSE_RSUSB_PREFIX="$LRS_PREFIX"
EOF
chmod +x "$ROOT/env.sh"

echo
echo "Done."
echo "  source $ROOT/env.sh"
echo "  ros2 pkg prefix realsense2_camera"
echo "  ldd $ROS_WS/install/realsense2_camera/lib/librealsense2_camera.so | grep realsense"
