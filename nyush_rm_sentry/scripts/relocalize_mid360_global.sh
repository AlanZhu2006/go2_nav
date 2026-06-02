#!/usr/bin/env bash

set -euo pipefail

source /opt/ros/foxy/setup.bash
if [ -f "$HOME/nav_ws/install/setup.bash" ]; then
    source "$HOME/nav_ws/install/setup.bash"
fi

echo ">>> Requesting AMCL global localization"
if ros2 service list | grep -qx "/reinitialize_global_localization"; then
    ros2 service call /reinitialize_global_localization std_srvs/srv/Empty "{}"
    echo
    echo "Move or rotate the robot slowly until /scan aligns with /map."
else
    echo "Error: /reinitialize_global_localization is not available." >&2
    echo "Check whether AMCL is alive:" >&2
    echo "  pgrep -af 'nav2_amcl|amcl'" >&2
    exit 1
fi
