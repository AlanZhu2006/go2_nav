#!/usr/bin/env python3

import math
import struct
import sys

import rclpy
from rclpy.node import Node
from rclpy.qos import QoSProfile, ReliabilityPolicy
from sensor_msgs.msg import Imu, PointCloud2, PointField


class Go2LioSamTopicBridge(Node):
    def __init__(self):
        super().__init__("go2_lio_sam_topic_bridge")

        qos = QoSProfile(depth=10)
        qos.reliability = ReliabilityPolicy.RELIABLE

        self.cloud_in = self.declare_parameter("cloud_in", "/utlidar/cloud").value
        self.cloud_out = self.declare_parameter("cloud_out", "/rslidar_points").value
        self.imu_in = self.declare_parameter("imu_in", "/utlidar/imu").value
        self.imu_out = self.declare_parameter("imu_out", "/dog_imu_raw").value
        self.synthesize_ring = bool(
            self.declare_parameter("synthesize_ring", True).value
        )
        self.synthetic_scan_lines = int(
            self.declare_parameter("synthetic_scan_lines", 16).value
        )
        self.override_frame = self.declare_parameter("override_frame", "").value

        self.cloud_pub = self.create_publisher(PointCloud2, self.cloud_out, qos)
        self.imu_pub = self.create_publisher(Imu, self.imu_out, qos)
        self.cloud_sub = self.create_subscription(PointCloud2, self.cloud_in, self.on_cloud, qos)
        self.imu_sub = self.create_subscription(Imu, self.imu_in, self.on_imu, qos)

        self.cloud_count = 0
        self.imu_count = 0
        self.synthesized_count = 0
        self.timer = self.create_timer(2.0, self.report)

        self.get_logger().info("Bridge cloud: %s -> %s" % (self.cloud_in, self.cloud_out))
        self.get_logger().info("Bridge imu:   %s -> %s" % (self.imu_in, self.imu_out))
        if self.synthesize_ring:
            self.get_logger().warn(
                "Synthetic ring is ON: rewriting PointCloud2 ring into %d scan lines"
                % self.synthetic_scan_lines
            )
        if self.override_frame:
            self.get_logger().info("Override cloud frame_id -> %s" % self.override_frame)

    def on_cloud(self, msg):
        self.cloud_count += 1
        out = self.prepare_cloud(msg)
        self.cloud_pub.publish(out)

    def on_imu(self, msg):
        self.imu_count += 1
        self.imu_pub.publish(msg)

    def report(self):
        self.get_logger().info(
            "relayed cloud=%d imu=%d synthetic_ring=%d"
            % (self.cloud_count, self.imu_count, self.synthesized_count)
        )

    def prepare_cloud(self, msg):
        out = msg

        if self.synthesize_ring:
            out = self.with_synthetic_ring(out)

        if self.override_frame:
            if out is msg:
                out = self.copy_cloud(msg)
            out.header.frame_id = self.override_frame

        return out

    def with_synthetic_ring(self, msg):
        fields = {field.name: field for field in msg.fields}
        required = ("x", "y", "z", "ring")
        if any(name not in fields for name in required):
            return msg

        ring_field = fields["ring"]
        if ring_field.datatype != PointField.UINT16:
            return msg

        angles = []
        for index in range(msg.width * msg.height):
            offset = index * msg.point_step
            x = struct.unpack_from("<f", msg.data, offset + fields["x"].offset)[0]
            y = struct.unpack_from("<f", msg.data, offset + fields["y"].offset)[0]
            z = struct.unpack_from("<f", msg.data, offset + fields["z"].offset)[0]
            horizontal = math.hypot(x, y)
            if horizontal > 1e-6 and math.isfinite(z):
                angles.append(math.atan2(z, horizontal))

        if not angles:
            return msg

        angle_min = min(angles)
        angle_max = max(angles)
        span = angle_max - angle_min
        if span < 1e-6:
            return msg

        out = self.copy_cloud(msg)
        data = bytearray(out.data)
        max_ring = max(0, self.synthetic_scan_lines - 1)

        for index in range(out.width * out.height):
            offset = index * out.point_step
            x = struct.unpack_from("<f", out.data, offset + fields["x"].offset)[0]
            y = struct.unpack_from("<f", out.data, offset + fields["y"].offset)[0]
            z = struct.unpack_from("<f", out.data, offset + fields["z"].offset)[0]
            horizontal = math.hypot(x, y)
            if horizontal <= 1e-6 or not math.isfinite(z):
                ring = 0
            else:
                angle = math.atan2(z, horizontal)
                normalized = (angle - angle_min) / span
                ring = int(round(normalized * max_ring))
                ring = min(max(ring, 0), max_ring)
            struct.pack_into("<H", data, offset + ring_field.offset, ring)

        out.data = bytes(data)
        self.synthesized_count += 1
        return out

    @staticmethod
    def copy_cloud(msg):
        out = PointCloud2()
        out.header = msg.header
        out.height = msg.height
        out.width = msg.width
        out.fields = msg.fields
        out.is_bigendian = msg.is_bigendian
        out.point_step = msg.point_step
        out.row_step = msg.row_step
        out.data = msg.data
        out.is_dense = msg.is_dense
        return out


def main():
    rclpy.init()
    node = Go2LioSamTopicBridge()
    try:
        rclpy.spin(node)
    finally:
        node.destroy_node()
        rclpy.shutdown()
    return 0


if __name__ == "__main__":
    sys.exit(main())
