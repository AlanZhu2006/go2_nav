#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export START_RVIZ="${START_RVIZ:-true}"
export PUBLISH_INITIAL_POSE="${PUBLISH_INITIAL_POSE:-false}"
export AMCL_GLOBAL_LOCALIZATION="${AMCL_GLOBAL_LOCALIZATION:-true}"
export AMCL_GLOBAL_LOCALIZATION_DELAY="${AMCL_GLOBAL_LOCALIZATION_DELAY:-3}"

exec "$SCRIPT_DIR/start_mid360_fastlio_nav2_with_rviz.sh" "$@"
