#!/usr/bin/env python3

import os

import rclpy
from rclpy.node import Node
from rclpy.qos import DurabilityPolicy, HistoryPolicy, QoSProfile, ReliabilityPolicy
from sensor_msgs.msg import PointCloud2


class RestampPointCloud2(Node):
    def __init__(self):
        super().__init__("restamp_pointcloud2")
        self.input_topic = os.environ.get("RESTAMP_CLOUD_INPUT", "/utlidar/cloud_base")
        self.output_topic = os.environ.get("RESTAMP_CLOUD_OUTPUT", "/go2_nav/cloud_base")
        self.frame_id = os.environ.get("RESTAMP_CLOUD_FRAME", "")

        qos = QoSProfile(
            history=HistoryPolicy.KEEP_LAST,
            depth=10,
            reliability=ReliabilityPolicy.RELIABLE,
            durability=DurabilityPolicy.VOLATILE,
        )
        self.pub = self.create_publisher(PointCloud2, self.output_topic, qos)
        self.sub = self.create_subscription(PointCloud2, self.input_topic, self.on_cloud, qos)
        self.seen_first_msg = False
        self.get_logger().info(
            "Restamping PointCloud2 %s -> %s (frame override=%s)"
            % (self.input_topic, self.output_topic, self.frame_id or "<message frame>")
        )

    def on_cloud(self, msg):
        out = PointCloud2()
        out.header = msg.header
        out.header.stamp = self.get_clock().now().to_msg()
        if self.frame_id:
            out.header.frame_id = self.frame_id
        out.height = msg.height
        out.width = msg.width
        out.fields = msg.fields
        out.is_bigendian = msg.is_bigendian
        out.point_step = msg.point_step
        out.row_step = msg.row_step
        out.data = msg.data
        out.is_dense = msg.is_dense
        self.pub.publish(out)
        if not self.seen_first_msg:
            self.get_logger().info("Publishing restamped cloud in frame %s" % out.header.frame_id)
            self.seen_first_msg = True


def main():
    rclpy.init()
    node = RestampPointCloud2()
    try:
        rclpy.spin(node)
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
