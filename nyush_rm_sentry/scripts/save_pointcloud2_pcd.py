#!/usr/bin/env python3

import argparse
import math
import os
import struct
import sys
import time

import rclpy
from rclpy.node import Node
from rclpy.qos import QoSProfile, ReliabilityPolicy
from sensor_msgs.msg import PointCloud2, PointField


FIELD_FORMAT = {
    PointField.INT8: ("b", 1),
    PointField.UINT8: ("B", 1),
    PointField.INT16: ("h", 2),
    PointField.UINT16: ("H", 2),
    PointField.INT32: ("i", 4),
    PointField.UINT32: ("I", 4),
    PointField.FLOAT32: ("f", 4),
    PointField.FLOAT64: ("d", 8),
}


def field_map(msg):
    return {field.name: field for field in msg.fields}


def unpack_field(data, base, field, endian_prefix):
    fmt, _ = FIELD_FORMAT[field.datatype]
    return struct.unpack_from(endian_prefix + fmt, data, base + field.offset)[0]


def save_xyz_i_binary_pcd(msg, path):
    fields = field_map(msg)
    missing = [name for name in ("x", "y", "z") if name not in fields]
    if missing:
        raise RuntimeError("PointCloud2 is missing required field(s): %s" % ", ".join(missing))

    for name in ("x", "y", "z"):
        if fields[name].datatype not in FIELD_FORMAT:
            raise RuntimeError("Unsupported datatype for field %s: %s" % (name, fields[name].datatype))

    has_intensity = "intensity" in fields and fields["intensity"].datatype in FIELD_FORMAT
    endian_prefix = ">" if msg.is_bigendian else "<"
    point_count = msg.width * msg.height
    packed_points = bytearray()

    for idx in range(point_count):
        base = idx * msg.point_step
        x = float(unpack_field(msg.data, base, fields["x"], endian_prefix))
        y = float(unpack_field(msg.data, base, fields["y"], endian_prefix))
        z = float(unpack_field(msg.data, base, fields["z"], endian_prefix))
        if not (math.isfinite(x) and math.isfinite(y) and math.isfinite(z)):
            continue

        if has_intensity:
            intensity = float(unpack_field(msg.data, base, fields["intensity"], endian_prefix))
            if not math.isfinite(intensity):
                intensity = 0.0
            packed_points.extend(struct.pack("<ffff", x, y, z, intensity))
        else:
            packed_points.extend(struct.pack("<fff", x, y, z))

    saved_points = len(packed_points) // (16 if has_intensity else 12)
    if saved_points == 0:
        raise RuntimeError("PointCloud2 contains no finite xyz points")

    if has_intensity:
        header = (
            "# .PCD v0.7 - Point Cloud Data file format\n"
            "VERSION 0.7\n"
            "FIELDS x y z intensity\n"
            "SIZE 4 4 4 4\n"
            "TYPE F F F F\n"
            "COUNT 1 1 1 1\n"
            "WIDTH {points}\n"
            "HEIGHT 1\n"
            "VIEWPOINT 0 0 0 1 0 0 0\n"
            "POINTS {points}\n"
            "DATA binary\n"
        ).format(points=saved_points)
    else:
        header = (
            "# .PCD v0.7 - Point Cloud Data file format\n"
            "VERSION 0.7\n"
            "FIELDS x y z\n"
            "SIZE 4 4 4\n"
            "TYPE F F F\n"
            "COUNT 1 1 1\n"
            "WIDTH {points}\n"
            "HEIGHT 1\n"
            "VIEWPOINT 0 0 0 1 0 0 0\n"
            "POINTS {points}\n"
            "DATA binary\n"
        ).format(points=saved_points)

    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "wb") as f:
        f.write(header.encode("ascii"))
        f.write(packed_points)

    return saved_points, has_intensity


class PointCloudSaver(Node):
    def __init__(self, topic, output, timeout_sec):
        super().__init__("save_pointcloud2_pcd")
        self.topic = topic
        self.output = output
        self.deadline = time.monotonic() + timeout_sec if timeout_sec > 0 else None
        self.done = False
        self.error = None

        qos = QoSProfile(depth=1)
        qos.reliability = ReliabilityPolicy.RELIABLE

        self.sub = self.create_subscription(PointCloud2, topic, self.on_cloud, qos)
        self.timer = self.create_timer(0.5, self.on_timer)
        self.get_logger().info("Waiting for PointCloud2 on %s" % topic)

    def on_cloud(self, msg):
        try:
            points, has_intensity = save_xyz_i_binary_pcd(msg, self.output)
            self.get_logger().info(
                "Saved %d points to %s (frame_id=%s, intensity=%s)"
                % (points, self.output, msg.header.frame_id, has_intensity)
            )
        except Exception as exc:
            self.error = exc
            self.get_logger().error(str(exc))
        self.done = True

    def on_timer(self):
        if self.deadline is not None and time.monotonic() > self.deadline:
            self.error = TimeoutError("Timed out waiting for %s" % self.topic)
            self.get_logger().error(str(self.error))
            self.done = True


def main():
    parser = argparse.ArgumentParser(description="Save one ROS2 PointCloud2 message as binary PCD.")
    parser.add_argument("--topic", default="/uslam/cloud_map")
    parser.add_argument("--output", required=True)
    parser.add_argument("--timeout", type=float, default=120.0)
    args = parser.parse_args()

    rclpy.init()
    node = PointCloudSaver(args.topic, args.output, args.timeout)

    try:
        while rclpy.ok() and not node.done:
            rclpy.spin_once(node, timeout_sec=0.2)
    finally:
        error = node.error
        node.destroy_node()
        rclpy.shutdown()

    if error is not None:
        print("ERROR: %s" % error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
