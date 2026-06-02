#!/usr/bin/env bash

set -euo pipefail

SDK_ROOT="${SDK_ROOT:-$HOME/work/go2_ros2_sdk}"
IMAGE_NAME="${GO2_SDK_IMAGE:-go2_ros2_sdk:minimal}"

if [ ! -f "$SDK_ROOT/docker/Dockerfile.minimal" ]; then
    echo "Error: Dockerfile not found: $SDK_ROOT/docker/Dockerfile.minimal" >&2
    echo "Clone abizovnuralem/go2_ros2_sdk to $SDK_ROOT first." >&2
    exit 1
fi

echo ">>> Building $IMAGE_NAME from $SDK_ROOT"
cd "$SDK_ROOT"
docker build -f docker/Dockerfile.minimal -t "$IMAGE_NAME" .

echo
echo "Built Docker image: $IMAGE_NAME"
