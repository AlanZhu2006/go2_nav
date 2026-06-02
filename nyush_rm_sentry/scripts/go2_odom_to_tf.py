#!/usr/bin/env python3

import os

import rclpy
from geometry_msgs.msg import TransformStamped
from nav_msgs.msg import Odometry
from rclpy.node import Node
from rclpy.qos import QoSProfile, ReliabilityPolicy
from tf2_ros import TransformBroadcaster


class OdomToTf(Node):
    def __init__(self):
        super().__init__("go2_odom_to_tf")

        self.odom_topic = os.environ.get("GO2_ODOM_TOPIC", "/utlidar/robot_odom")
        self.parent_override = os.environ.get("GO2_TF_PARENT", "")
        self.child_override = os.environ.get("GO2_TF_CHILD", "")
        self.stamp_mode = os.environ.get("GO2_TF_STAMP_MODE", "now")
        self.republished_odom_topic = os.environ.get("GO2_RESTAMPED_ODOM_TOPIC", "/odom")

        qos = QoSProfile(depth=20)
        qos.reliability = ReliabilityPolicy.RELIABLE

        self.br = TransformBroadcaster(self)
        self.sub = self.create_subscription(Odometry, self.odom_topic, self.on_odom, qos)
        self.odom_pub = self.create_publisher(Odometry, self.republished_odom_topic, qos)
        self.seen_first_msg = False

        self.get_logger().info(
            "Broadcasting TF from odom topic %s (parent override=%s, child override=%s, stamp_mode=%s, repub=%s)"
            % (
                self.odom_topic,
                self.parent_override or "<message header.frame_id>",
                self.child_override or "<message child_frame_id>",
                self.stamp_mode,
                self.republished_odom_topic,
            )
        )

    def on_odom(self, msg):
        parent = self.parent_override or msg.header.frame_id
        child = self.child_override or msg.child_frame_id
        if not parent or not child:
            self.get_logger().warn("Skipping odom message with empty parent/child frame")
            return
        stamp = self.get_clock().now().to_msg() if self.stamp_mode == "now" else msg.header.stamp

        tf_msg = TransformStamped()
        tf_msg.header.stamp = stamp
        tf_msg.header.frame_id = parent
        tf_msg.child_frame_id = child
        tf_msg.transform.translation.x = msg.pose.pose.position.x
        tf_msg.transform.translation.y = msg.pose.pose.position.y
        tf_msg.transform.translation.z = msg.pose.pose.position.z
        tf_msg.transform.rotation = msg.pose.pose.orientation

        self.br.sendTransform(tf_msg)
        odom_msg = Odometry()
        odom_msg.header = msg.header
        odom_msg.header.stamp = stamp
        odom_msg.header.frame_id = parent
        odom_msg.child_frame_id = child
        odom_msg.pose = msg.pose
        odom_msg.twist = msg.twist
        self.odom_pub.publish(odom_msg)

        if not self.seen_first_msg:
            self.get_logger().info("Publishing TF %s -> %s" % (parent, child))
            self.seen_first_msg = True


def main():
    rclpy.init()
    node = OdomToTf()
    try:
        rclpy.spin(node)
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
