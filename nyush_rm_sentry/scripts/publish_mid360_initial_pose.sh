#!/usr/bin/env bash

set -euo pipefail

ROS_SETUP="${ROS_SETUP:-/opt/ros/foxy/setup.bash}"
NAV_WS_SETUP="${NAV_WS_SETUP:-$HOME/nav_ws/install/setup.bash}"

X="${1:-${INITIAL_POSE_X:-0.0}}"
Y="${2:-${INITIAL_POSE_Y:-0.0}}"
YAW="${3:-${INITIAL_POSE_YAW:-0.0}}"

source_relaxed() {
    local setup_file="$1"
    local had_nounset=0
    case $- in
        *u*) had_nounset=1; set +u ;;
    esac
    source "$setup_file"
    if [ "$had_nounset" = "1" ]; then
        set -u
    fi
}

source_relaxed "$ROS_SETUP"
if [ -f "$NAV_WS_SETUP" ]; then
    source_relaxed "$NAV_WS_SETUP"
fi

echo "Publishing safe /initialpose: x=$X y=$Y yaw=$YAW stamp=0"
python3 - "$X" "$Y" "$YAW" <<'PY'
import math
import sys
import time

import rclpy
from geometry_msgs.msg import PoseWithCovarianceStamped
from rclpy.node import Node

x = float(sys.argv[1])
y = float(sys.argv[2])
yaw = float(sys.argv[3])

rclpy.init()
node = Node("publish_mid360_initial_pose")
pub = node.create_publisher(PoseWithCovarianceStamped, "/initialpose", 10)

deadline = time.time() + 1.0
while pub.get_subscription_count() == 0 and time.time() < deadline:
    rclpy.spin_once(node, timeout_sec=0.05)

msg = PoseWithCovarianceStamped()
msg.header.frame_id = "map"
msg.header.stamp.sec = 0
msg.header.stamp.nanosec = 0
msg.pose.pose.position.x = x
msg.pose.pose.position.y = y
msg.pose.pose.position.z = 0.0
msg.pose.pose.orientation.z = math.sin(yaw * 0.5)
msg.pose.pose.orientation.w = math.cos(yaw * 0.5)
msg.pose.covariance[0] = 0.25
msg.pose.covariance[7] = 0.25
msg.pose.covariance[35] = 0.06853891945200942

pub.publish(msg)
rclpy.spin_once(node, timeout_sec=0.1)
time.sleep(0.1)

node.destroy_node()
rclpy.shutdown()
PY

echo
echo "Check TF:"
echo "  ros2 run tf2_ros tf2_echo map base_link"
