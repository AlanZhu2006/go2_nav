#!/usr/bin/env python3

import argparse
import math
import struct
import time

import rclpy
from rclpy.node import Node
from rclpy.qos import DurabilityPolicy, HistoryPolicy, QoSProfile, ReliabilityPolicy
from sensor_msgs.msg import PointCloud2


def stamp_sec(stamp):
    return float(stamp.sec) + float(stamp.nanosec) * 1e-9


def read_xyz_points(msg):
    fields = {field.name: field for field in msg.fields}
    if not all(name in fields for name in ("x", "y", "z")):
        return []

    points = []
    for idx in range(int(msg.width * msg.height)):
        base = idx * msg.point_step
        values = []
        ok = True
        for name in ("x", "y", "z"):
            field = fields[name]
            if field.datatype != 7:
                ok = False
                break
            offset = base + field.offset
            if offset + 4 > len(msg.data):
                ok = False
                break
            values.append(struct.unpack_from("<f", msg.data, offset)[0])
        if ok and all(math.isfinite(value) for value in values):
            points.append(tuple(values))
    return points


class ScanQualityProbe(Node):
    def __init__(self, topic, reliability):
        super().__init__("diagnose_go2_scan_quality")
        self.msg = None
        qos = QoSProfile(
            history=HistoryPolicy.KEEP_LAST,
            depth=20,
            reliability=(
                ReliabilityPolicy.BEST_EFFORT
                if reliability == "best_effort"
                else ReliabilityPolicy.RELIABLE
            ),
            durability=DurabilityPolicy.VOLATILE,
        )
        self.create_subscription(PointCloud2, topic, self.on_cloud, qos)

    def on_cloud(self, msg):
        self.msg = msg


def parse_window(text):
    lo, hi = text.split(",", 1)
    return float(lo), float(hi)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--topic", default="/utlidar/cloud_base")
    parser.add_argument("--duration", type=float, default=5.0)
    parser.add_argument("--angle-increment", type=float, default=0.0174533)
    parser.add_argument("--range-min", type=float, default=0.20)
    parser.add_argument("--range-max", type=float, default=10.0)
    parser.add_argument(
        "--window",
        action="append",
        default=[
            "-0.50,-0.10",
            "-0.45,0.05",
            "-0.40,0.10",
            "-0.35,0.15",
            "-0.30,0.20",
            "-0.25,0.25",
            "-0.20,2.00",
        ],
        help="Height window as min,max in cloud frame; may be repeated.",
    )
    parser.add_argument("--reliability", choices=("reliable", "best_effort"), default="reliable")
    args = parser.parse_args()

    rclpy.init()
    node = ScanQualityProbe(args.topic, args.reliability)
    deadline = time.time() + args.duration
    while time.time() < deadline and node.msg is None:
        rclpy.spin_once(node, timeout_sec=0.1)
    for _ in range(10):
        rclpy.spin_once(node, timeout_sec=0.05)

    msg = node.msg
    if msg is None:
        print("No PointCloud2 received on %s" % args.topic)
        node.destroy_node()
        rclpy.shutdown()
        return 1

    points = read_xyz_points(msg)
    beam_count = int((2.0 * math.pi) / args.angle_increment) + 1
    print("Go2 scan quality")
    print(
        "  topic=%s frame=%s stamp=%.6f points=%d fields=%s"
        % (
            args.topic,
            msg.header.frame_id,
            stamp_sec(msg.header.stamp),
            len(points),
            ",".join(field.name for field in msg.fields),
        )
    )
    print(
        "  angle_increment=%.7f beams=%d range=[%.2f, %.2f]"
        % (args.angle_increment, beam_count, args.range_min, args.range_max)
    )

    if points:
        xs, ys, zs = zip(*points)
        print(
            "  xyz: x=[%.2f, %.2f] y=[%.2f, %.2f] z=[%.2f, %.2f] z_mean=%.2f"
            % (min(xs), max(xs), min(ys), max(ys), min(zs), max(zs), sum(zs) / len(zs))
        )

    for window in args.window:
        min_height, max_height = parse_window(window)
        ranges = [math.inf] * beam_count
        used = 0
        for x, y, z in points:
            if z < min_height or z > max_height:
                continue
            distance = math.hypot(x, y)
            if distance < args.range_min or distance > args.range_max:
                continue
            angle = math.atan2(y, x)
            index = int((angle + math.pi) / args.angle_increment)
            if 0 <= index < beam_count:
                used += 1
                if distance < ranges[index]:
                    ranges[index] = distance
        valid = sum(math.isfinite(value) for value in ranges)
        print(
            "  height[%+.2f,%+.2f] points=%4d valid_beams=%3d/%3d coverage=%4.1f%%"
            % (min_height, max_height, used, valid, beam_count, 100.0 * valid / beam_count)
        )

    node.destroy_node()
    rclpy.shutdown()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
