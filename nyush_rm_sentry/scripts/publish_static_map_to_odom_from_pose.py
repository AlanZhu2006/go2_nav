#!/usr/bin/env python3

import math
import sys
import time

import rclpy
from geometry_msgs.msg import TransformStamped
from rclpy.duration import Duration
from rclpy.node import Node
from tf2_ros import Buffer, StaticTransformBroadcaster, TransformListener


def yaw_from_quat(q):
    return math.atan2(
        2.0 * (q.w * q.z + q.x * q.y),
        1.0 - 2.0 * (q.y * q.y + q.z * q.z),
    )


def main():
    if len(sys.argv) != 6:
        print(
            "usage: publish_static_map_to_odom_from_pose.py "
            "<initial_x> <initial_y> <initial_yaw_rad> <odom_frame> <base_frame>",
            file=sys.stderr,
        )
        return 2

    initial_x = float(sys.argv[1])
    initial_y = float(sys.argv[2])
    initial_yaw = float(sys.argv[3])
    odom_frame = sys.argv[4]
    base_frame = sys.argv[5]

    rclpy.init()
    node = Node("static_map_to_odom_from_initial_pose")
    buffer = Buffer()
    listener = TransformListener(buffer, node, spin_thread=False)
    broadcaster = StaticTransformBroadcaster(node)

    deadline = time.time() + 10.0
    odom_to_base = None
    while time.time() < deadline and rclpy.ok():
        rclpy.spin_once(node, timeout_sec=0.1)
        try:
            odom_to_base = buffer.lookup_transform(
                odom_frame,
                base_frame,
                rclpy.time.Time(),
                timeout=Duration(seconds=0.2),
            )
            break
        except Exception:
            time.sleep(0.1)

    if odom_to_base is None:
        print(f"Error: could not lookup {odom_frame} -> {base_frame}", file=sys.stderr)
        node.destroy_node()
        rclpy.shutdown()
        return 1

    t_ob = odom_to_base.transform.translation
    q_ob = odom_to_base.transform.rotation
    odom_base_yaw = yaw_from_quat(q_ob)

    # map_T_odom = map_T_base_desired * inverse(odom_T_base_current)
    map_odom_yaw = initial_yaw - odom_base_yaw
    c = math.cos(map_odom_yaw)
    s = math.sin(map_odom_yaw)
    map_odom_x = initial_x - (c * t_ob.x - s * t_ob.y)
    map_odom_y = initial_y - (s * t_ob.x + c * t_ob.y)

    msg = TransformStamped()
    msg.header.stamp = node.get_clock().now().to_msg()
    msg.header.frame_id = "map"
    msg.child_frame_id = odom_frame
    msg.transform.translation.x = map_odom_x
    msg.transform.translation.y = map_odom_y
    msg.transform.translation.z = 0.0
    msg.transform.rotation.z = math.sin(map_odom_yaw * 0.5)
    msg.transform.rotation.w = math.cos(map_odom_yaw * 0.5)

    print(
        "Publishing static map -> odom from initial pose: "
        f"map_odom=({map_odom_x:.4f}, {map_odom_y:.4f}, {map_odom_yaw:.4f}) "
        f"using current {odom_frame}->{base_frame}=({t_ob.x:.4f}, {t_ob.y:.4f}, {odom_base_yaw:.4f})",
        flush=True,
    )
    broadcaster.sendTransform(msg)

    try:
        while rclpy.ok():
            rclpy.spin_once(node, timeout_sec=1.0)
    except KeyboardInterrupt:
        pass

    node.destroy_node()
    rclpy.shutdown()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
