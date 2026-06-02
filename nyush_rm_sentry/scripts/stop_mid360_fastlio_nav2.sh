#!/usr/bin/env bash

set -euo pipefail

patterns=(
    "/home/unitree/work/nyush_rm_sentry/scripts/go2_cmd_bridge.py"
    "/opt/ros/foxy/lib/rviz2/rviz2"
    "ros2 run rviz2 rviz2"
    "nav2_bringup bringup_launch.py"
    "nav2_bringup navigation_launch.py"
    "/home/unitree/work/nyush_rm_sentry/scripts/publish_static_map_to_odom_from_pose.py"
    "/home/unitree/work/nyush_rm_sentry/rm_navigation_ws/install/icp_registration/lib/icp_registration/icp_registration_node"
    "ros2 run icp_registration icp_registration_node"
    "/opt/ros/foxy/lib/nav2_controller/controller_server"
    "/opt/ros/foxy/lib/nav2_planner/planner_server"
    "/opt/ros/foxy/lib/nav2_bt_navigator/bt_navigator"
    "/opt/ros/foxy/lib/nav2_amcl/amcl"
    "/opt/ros/foxy/lib/nav2_map_server/map_server"
    "/opt/ros/foxy/lib/nav2_behaviors/behavior_server"
    "/opt/ros/foxy/lib/nav2_waypoint_follower/waypoint_follower"
    "/opt/ros/foxy/lib/nav2_lifecycle_manager/lifecycle_manager"
    "/opt/ros/foxy/lib/pointcloud_to_laserscan/pointcloud_to_laserscan_node"
    "/pointcloud_to_laserscan/lib/pointcloud_to_laserscan/pointcloud_to_laserscan_node"
    "static_transform_publisher .* livox_frame base_link"
    "/home/unitree/nav_ws/install/fast_lio/lib/fast_lio/fastlio_mapping"
    "/home/unitree/nav_ws/install/livox_ros_driver2/lib/livox_ros_driver2/livox_ros_driver2_node"
    "ros2 launch livox_ros_driver2 msg_MID360_launch.py"
    "/home/unitree/work/nyush_rm_sentry/scripts/start_mid360_fastlio_nav2_with_rviz.sh"
)

echo ">>> Stopping MID360 FAST-LIO Nav2 stack"
for pattern in "${patterns[@]}"; do
    pkill -TERM -f "$pattern" 2>/dev/null || true
done

sleep 1

for pattern in "${patterns[@]}"; do
    pkill -KILL -f "$pattern" 2>/dev/null || true
done

echo ">>> Remaining matching processes:"
pgrep -af 'start_mid360_fastlio_nav2|livox_ros_driver2|fastlio_mapping|static_transform_publisher .* livox_frame base_link|publish_static_map_to_odom_from_pose|icp_registration|pointcloud_to_laserscan|nav2_bringup|nav2_.*server|bt_navigator|amcl|rviz2|go2_cmd_bridge' || true
