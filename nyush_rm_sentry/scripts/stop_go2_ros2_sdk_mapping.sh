#!/usr/bin/env bash

set -euo pipefail

CONTAINER_NAME="${GO2_SDK_CONTAINER:-go2_sdk_mapping}"

echo ">>> Stopping $CONTAINER_NAME"
docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
echo "Stopped."
