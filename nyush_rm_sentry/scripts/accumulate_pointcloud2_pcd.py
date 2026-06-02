#!/usr/bin/env python3

import argparse
import math
import os
import select
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


def write_binary_pcd(path, points, with_intensity):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    point_count = len(points)
    if point_count == 0:
        raise RuntimeError("No accumulated points to save")

    if with_intensity:
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
        ).format(points=point_count)
        fmt = "<ffff"
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
        ).format(points=point_count)
        fmt = "<fff"

    with open(path, "wb") as f:
        f.write(header.encode("ascii"))
        for point in points:
            f.write(struct.pack(fmt, *point))


class PointCloudAccumulator(Node):
    def __init__(self, args):
        super().__init__("accumulate_pointcloud2_pcd")
        self.args = args
        self.topic = args.topic
        self.output = os.path.abspath(os.path.expanduser(args.output))
        self.voxel_size = args.voxel_size
        self.max_points = args.max_points
        self.deadline = time.monotonic() + args.duration if args.duration > 0 else None
        self.last_report = time.monotonic()
        self.done = False
        self.error = None
        self.frame_id = ""
        self.msg_count = 0
        self.raw_point_count = 0
        self.has_intensity = False
        self.points_by_voxel = {}
        self.points = []

        qos = QoSProfile(depth=args.qos_depth)
        qos.reliability = (
            ReliabilityPolicy.BEST_EFFORT if args.best_effort else ReliabilityPolicy.RELIABLE
        )
        self.sub = self.create_subscription(PointCloud2, self.topic, self.on_cloud, qos)
        self.timer = self.create_timer(0.2, self.on_timer)
        self.get_logger().info("Accumulating PointCloud2 from %s" % self.topic)
        self.get_logger().info("Type 1 then Enter to save and exit; type q then Enter to exit")
        self.get_logger().info("Output: %s" % self.output)

    def finite_point_from_msg(self, msg, fields, idx, endian_prefix):
        base = idx * msg.point_step
        x = float(unpack_field(msg.data, base, fields["x"], endian_prefix))
        y = float(unpack_field(msg.data, base, fields["y"], endian_prefix))
        z = float(unpack_field(msg.data, base, fields["z"], endian_prefix))
        if not (math.isfinite(x) and math.isfinite(y) and math.isfinite(z)):
            return None

        if self.has_intensity:
            intensity = float(unpack_field(msg.data, base, fields["intensity"], endian_prefix))
            if not math.isfinite(intensity):
                intensity = 0.0
            return (x, y, z, intensity)
        return (x, y, z)

    def add_point(self, point):
        if self.voxel_size > 0:
            key = (
                int(math.floor(point[0] / self.voxel_size)),
                int(math.floor(point[1] / self.voxel_size)),
                int(math.floor(point[2] / self.voxel_size)),
            )
            self.points_by_voxel[key] = point
            return

        if self.max_points > 0 and len(self.points) >= self.max_points:
            return
        self.points.append(point)

    def accumulated_count(self):
        if self.voxel_size > 0:
            return len(self.points_by_voxel)
        return len(self.points)

    def accumulated_points(self):
        if self.voxel_size > 0:
            return list(self.points_by_voxel.values())
        return self.points

    def on_cloud(self, msg):
        fields = field_map(msg)
        missing = [name for name in ("x", "y", "z") if name not in fields]
        if missing:
            self.error = RuntimeError(
                "PointCloud2 is missing required field(s): %s" % ", ".join(missing)
            )
            self.done = True
            return

        for name in ("x", "y", "z"):
            if fields[name].datatype not in FIELD_FORMAT:
                self.error = RuntimeError("Unsupported datatype for field %s" % name)
                self.done = True
                return

        self.has_intensity = "intensity" in fields and fields["intensity"].datatype in FIELD_FORMAT
        endian_prefix = ">" if msg.is_bigendian else "<"
        point_count = msg.width * msg.height
        self.msg_count += 1
        self.raw_point_count += point_count
        self.frame_id = msg.header.frame_id

        for idx in range(point_count):
            point = self.finite_point_from_msg(msg, fields, idx, endian_prefix)
            if point is not None:
                self.add_point(point)

        if self.max_points > 0 and self.accumulated_count() >= self.max_points:
            self.get_logger().warn("Reached max accumulated points; saving now")
            self.save_and_exit()

    def on_timer(self):
        now = time.monotonic()
        if now - self.last_report >= self.args.report_interval:
            self.last_report = now
            self.get_logger().info(
                "frames=%d raw_points=%d accumulated=%d frame_id=%s"
                % (self.msg_count, self.raw_point_count, self.accumulated_count(), self.frame_id)
            )

        if self.deadline is not None and now >= self.deadline:
            self.get_logger().info("Duration reached; saving now")
            self.save_and_exit()
            return

        if select.select([sys.stdin], [], [], 0.0)[0]:
            command = sys.stdin.readline().strip().lower()
            if command == "1":
                self.save_and_exit()
            elif command in ("q", "quit", "exit"):
                self.get_logger().warn("Exit requested without saving")
                self.done = True

    def save_and_exit(self):
        try:
            points = self.accumulated_points()
            write_binary_pcd(self.output, points, self.has_intensity)
            self.get_logger().info(
                "Saved %d accumulated points to %s (frame_id=%s, intensity=%s)"
                % (len(points), self.output, self.frame_id, self.has_intensity)
            )
        except Exception as exc:
            self.error = exc
            self.get_logger().error(str(exc))
        self.done = True


def main():
    parser = argparse.ArgumentParser(
        description="Accumulate ROS2 PointCloud2 messages and save a binary PCD on command."
    )
    parser.add_argument("--topic", default="/utlidar/cloud_deskewed")
    parser.add_argument("--output", required=True)
    parser.add_argument("--voxel-size", type=float, default=0.05)
    parser.add_argument("--max-points", type=int, default=0)
    parser.add_argument("--duration", type=float, default=0.0)
    parser.add_argument("--report-interval", type=float, default=2.0)
    parser.add_argument("--qos-depth", type=int, default=5)
    parser.add_argument("--best-effort", action="store_true")
    args = parser.parse_args()

    rclpy.init()
    node = PointCloudAccumulator(args)
    try:
        while rclpy.ok() and not node.done:
            rclpy.spin_once(node, timeout_sec=0.1)
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
