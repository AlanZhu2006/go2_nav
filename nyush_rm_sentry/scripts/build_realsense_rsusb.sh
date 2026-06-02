#!/usr/bin/env bash

set -euo pipefail

VERSION="${REALSENSE_VERSION:-v2.51.1}"
ROOT="${REALSENSE_RSUSB_ROOT:-$HOME/work/realsense_rsusb}"
SRC="$ROOT/librealsense"
BUILD="$ROOT/build"
PREFIX="${REALSENSE_RSUSB_PREFIX:-$ROOT/install}"
JOBS="${JOBS:-$(nproc)}"

echo "RealSense RSUSB build:"
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

echo ">>> Configuring RSUSB backend"
cmake -S "$SRC" -B "$BUILD" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DBUILD_SHARED_LIBS=ON \
    -DFORCE_RSUSB_BACKEND=ON \
    -DBUILD_EXAMPLES=OFF \
    -DBUILD_GRAPHICAL_EXAMPLES=OFF \
    -DBUILD_WITH_OPENMP=ON \
    -DBUILD_TOOLS=ON \
    -DBUILD_UNIT_TESTS=OFF \
    -DBUILD_PYTHON_BINDINGS=OFF

echo ">>> Building librealsense RSUSB"
cmake --build "$BUILD" -j "$JOBS"

echo ">>> Installing into $PREFIX"
cmake --install "$BUILD"

echo
echo "Done. Test with:"
echo "  LD_LIBRARY_PATH=$PREFIX/lib:$PREFIX/lib/aarch64-linux-gnu:\${LD_LIBRARY_PATH:-} $PREFIX/bin/rs-enumerate-devices"
