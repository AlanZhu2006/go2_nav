#!/usr/bin/env python3

import argparse
import math
import select
import signal
import struct
import sys
import time
from collections import deque
from pathlib import Path

import rclpy
from nav_msgs.msg import Odometry
from rclpy.node import Node
from rclpy.qos import DurabilityPolicy, HistoryPolicy, QoSProfile, ReliabilityPolicy
from sensor_msgs.msg import PointCloud2


DATATYPES = {
    1: ("b", 1),
    2: ("B", 1),
    3: ("h", 2),
    4: ("H", 2),
    5: ("i", 4),
    6: ("I", 4),
    7: ("f", 4),
    8: ("d", 8),
}


def stamp_seconds(stamp):
    return float(stamp.sec) + float(stamp.nanosec) * 1e-9


def quat_to_matrix(q):
    x, y, z, w = q.x, q.y, q.z, q.w
    n = x * x + y * y + z * z + w * w
    if n < 1e-12:
        return ((1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0))
    s = 2.0 / n
    xx, yy, zz = x * x * s, y * y * s, z * z * s
    xy, xz, yz = x * y * s, x * z * s, y * z * s
    wx, wy, wz = w * x * s, w * y * s, w * z * s
    return (
        (1.0 - yy - zz, xy - wz, xz + wy),
        (xy + wz, 1.0 - xx - zz, yz - wx),
        (xz - wy, yz + wx, 1.0 - xx - yy),
    )


def transform_point(point, pose):
    x, y, z = point
    r = quat_to_matrix(pose.orientation)
    t = pose.position
    return (
        r[0][0] * x + r[0][1] * y + r[0][2] * z + t.x,
        r[1][0] * x + r[1][1] * y + r[1][2] * z + t.y,
        r[2][0] * x + r[2][1] * y + r[2][2] * z + t.z,
    )


def field_reader(msg):
    fields = {field.name: field for field in msg.fields}
    missing = [name for name in ("x", "y", "z") if name not in fields]
    if missing:
        raise RuntimeError(f"PointCloud2 is missing fields: {', '.join(missing)}")

    def read(name, base, default=0.0):
        field = fields.get(name)
        if field is None:
            return default
        fmt, _size = DATATYPES[field.datatype]
        return struct.unpack_from("<" + fmt, msg.data, base + field.offset)[0]

    return read


def write_pcd(path, points):
    path = Path(path).expanduser()
    path.parent.mkdir(parents=True, exist_ok=True)
    header = (
        "# .PCD v0.7 - Point Cloud Data file format\n"
        "VERSION 0.7\n"
        "FIELDS x y z intensity\n"
        "SIZE 4 4 4 4\n"
        "TYPE F F F F\n"
        "COUNT 1 1 1 1\n"
        f"WIDTH {len(points)}\n"
        "HEIGHT 1\n"
        "VIEWPOINT 0 0 0 1 0 0 0\n"
        f"POINTS {len(points)}\n"
        "DATA binary\n"
    ).encode("ascii")
    with path.open("wb") as handle:
        handle.write(header)
        for x, y, z, intensity in points:
            handle.write(struct.pack("<ffff", x, y, z, intensity))


class OfficialOdomAccumulator(Node):
    def __init__(self, args):
        super().__init__("go2_official_odom_accumulator")
        self.args = args
        self.odom_queue = deque(maxlen=args.odom_queue_size)
        self.voxels = {}
        self.raw_points = []
        self.cloud_count = 0
        self.accepted_points = 0
        self.last_report = time.monotonic()
        self.done = False

        qos = QoSProfile(
            history=HistoryPolicy.KEEP_LAST,
            depth=10,
            reliability=ReliabilityPolicy.BEST_EFFORT if args.best_effort else ReliabilityPolicy.RELIABLE,
            durability=DurabilityPolicy.VOLATILE,
        )
        self.create_subscription(Odometry, args.odom_topic, self.odom_cb, qos)
        self.create_subscription(PointCloud2, args.cloud_topic, self.cloud_cb, qos)

    def odom_cb(self, msg):
        self.odom_queue.append(msg)

    def nearest_odom(self, stamp):
        if not self.odom_queue:
            return None
        target = stamp_seconds(stamp)
        return min(self.odom_queue, key=lambda msg: abs(stamp_seconds(msg.header.stamp) - target))

    def cloud_cb(self, msg):
        odom = self.nearest_odom(msg.header.stamp)
        if odom is None:
            return
        try:
            read = field_reader(msg)
        except RuntimeError as exc:
            self.get_logger().error(str(exc))
            return

        total = msg.width * msg.height
        for index in range(0, total, max(1, self.args.point_stride)):
            base = index * msg.point_step
            x = float(read("x", base))
            y = float(read("y", base))
            z = float(read("z", base))
            intensity = float(read("intensity", base, 0.0))
            if not all(math.isfinite(v) for v in (x, y, z)):
                continue
            if x * x + y * y + z * z < self.args.min_range * self.args.min_range:
                continue

            if msg.header.frame_id == odom.child_frame_id or msg.header.frame_id == "base_link":
                wx, wy, wz = transform_point((x, y, z), odom.pose.pose)
            else:
                wx, wy, wz = x, y, z

            if self.args.voxel_size > 0.0:
                key = (
                    math.floor(wx / self.args.voxel_size),
                    math.floor(wy / self.args.voxel_size),
                    math.floor(wz / self.args.voxel_size),
                )
                self.voxels.setdefault(key, (wx, wy, wz, intensity))
            else:
                self.raw_points.append((wx, wy, wz, intensity))
            self.accepted_points += 1

        self.cloud_count += 1
        now = time.monotonic()
        if now - self.last_report >= self.args.report_interval:
            self.last_report = now
            stored = len(self.voxels) if self.args.voxel_size > 0.0 else len(self.raw_points)
            self.get_logger().info(
                f"clouds={self.cloud_count} accepted={self.accepted_points} stored={stored} "
                f"cloud_frame={msg.header.frame_id} odom_frame={odom.header.frame_id}->{odom.child_frame_id}"
            )

    def points(self):
        return list(self.voxels.values()) if self.args.voxel_size > 0.0 else self.raw_points

    def save(self):
        points = self.points()
        if not points:
            raise RuntimeError("no accumulated points to save")
        write_pcd(self.args.output, points)
        print(f"Saved official Go2 odom PCD: {self.args.output} ({len(points)} points)")


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--cloud-topic", default="/utlidar/cloud_base")
    parser.add_argument("--odom-topic", default="/utlidar/robot_odom")
    parser.add_argument("--output", required=True)
    parser.add_argument("--voxel-size", type=float, default=0.05)
    parser.add_argument("--point-stride", type=int, default=1)
    parser.add_argument("--min-range", type=float, default=0.25)
    parser.add_argument("--report-interval", type=float, default=2.0)
    parser.add_argument("--odom-queue-size", type=int, default=200)
    parser.add_argument("--best-effort", action="store_true")
    return parser.parse_args()


def main():
    args = parse_args()
    rclpy.init()
    node = OfficialOdomAccumulator(args)

    def request_save(_signum=None, _frame=None):
        node.done = True

    signal.signal(signal.SIGINT, request_save)
    signal.signal(signal.SIGTERM, request_save)

    print("Accumulating official Go2 odom map.")
    print("Controls: 1 + Enter = save and exit, q + Enter = quit without saving")

    try:
        while rclpy.ok() and not node.done:
            rclpy.spin_once(node, timeout_sec=0.1)
            ready, _w, _x = select.select([sys.stdin], [], [], 0.0)
            if ready:
                cmd = sys.stdin.readline().strip().lower()
                if cmd == "1":
                    node.done = True
                elif cmd in ("q", "quit"):
                    return 0
        node.save()
    except Exception as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1
    finally:
        if rclpy.ok():
            node.destroy_node()
            rclpy.shutdown()
    return 0


if __name__ == "__main__":
    sys.exit(main())
