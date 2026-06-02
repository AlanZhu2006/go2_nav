#!/usr/bin/env bash

set -euo pipefail

VERSION="${REALSENSE_NATIVE_VERSION:-v2.55.1}"
ROOT="${REALSENSE_NATIVE_ROOT:-$HOME/work/realsense_stack_native}"
SRC="$ROOT/librealsense"
BUILD="$ROOT/build"
PREFIX="${REALSENSE_NATIVE_PREFIX:-$ROOT/install}"
JOBS="${JOBS:-$(nproc)}"

echo "RealSense native V4L build:"
echo "  version: $VERSION"
echo "  source:  $SRC"
echo "  build:   $BUILD"
echo "  prefix:  $PREFIX"
echo "  jobs:    $JOBS"

mkdir -p "$ROOT"

if [ ! -d "$SRC/.git" ]; then
    echo ">>> Cloning librealsense"
    git clone https://github.com/IntelRealSense/librealsense.git "$SRC"
fi

echo ">>> Checking out $VERSION"
git -C "$SRC" fetch --tags --depth 1 origin "$VERSION"
git -C "$SRC" checkout "$VERSION"

echo ">>> Configuring native V4L backend"
cmake -S "$SRC" -B "$BUILD" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DBUILD_SHARED_LIBS=ON \
    -DFORCE_RSUSB_BACKEND=OFF \
    -DBUILD_EXAMPLES=OFF \
    -DBUILD_GRAPHICAL_EXAMPLES=OFF \
    -DBUILD_WITH_OPENMP=ON \
    -DBUILD_TOOLS=ON \
    -DBUILD_UNIT_TESTS=OFF \
    -DBUILD_PYTHON_BINDINGS=OFF

echo ">>> Building librealsense native"
cmake --build "$BUILD" -j "$JOBS"

echo ">>> Installing into $PREFIX"
cmake --install "$BUILD"

cat > "$ROOT/env.sh" <<EOF
source /opt/ros/foxy/setup.bash
export REALSENSE_NATIVE_ROOT="$ROOT"
export REALSENSE_NATIVE_PREFIX="$PREFIX"
export LD_LIBRARY_PATH="$PREFIX/lib:$PREFIX/lib/aarch64-linux-gnu:\${LD_LIBRARY_PATH:-}"
export CMAKE_PREFIX_PATH="$PREFIX:\${CMAKE_PREFIX_PATH:-}"
export PATH="$PREFIX/bin:\${PATH:-}"
EOF

echo
echo "Done. Test with:"
echo "  source $ROOT/env.sh"
echo "  rs-enumerate-devices -s"
