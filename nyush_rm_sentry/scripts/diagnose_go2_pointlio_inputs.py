#!/usr/bin/env python3

import argparse
import math
import struct
import sys
import time

import rclpy
from nav_msgs.msg import Odometry
from rclpy.node import Node
from rclpy.qos import DurabilityPolicy, HistoryPolicy, QoSProfile, ReliabilityPolicy
from sensor_msgs.msg import Imu, PointCloud2


def stamp_sec(stamp):
    return float(stamp.sec) + float(stamp.nanosec) * 1e-9


def quat_to_rpy_deg(q):
    x, y, z, w = q.x, q.y, q.z, q.w
    sinr_cosp = 2.0 * (w * x + y * z)
    cosr_cosp = 1.0 - 2.0 * (x * x + y * y)
    roll = math.atan2(sinr_cosp, cosr_cosp)
    sinp = 2.0 * (w * y - z * x)
    pitch = math.asin(max(-1.0, min(1.0, sinp)))
    siny_cosp = 2.0 * (w * z + x * y)
    cosy_cosp = 1.0 - 2.0 * (y * y + z * z)
    yaw = math.atan2(siny_cosp, cosy_cosp)
    return tuple(v * 180.0 / math.pi for v in (roll, pitch, yaw))


class Probe(Node):
    def __init__(self, args):
        super().__init__("diagnose_go2_pointlio_inputs")
        self.args = args
        qos = QoSProfile(
            history=HistoryPolicy.KEEP_LAST,
            depth=200,
            reliability=ReliabilityPolicy.RELIABLE,
            durability=DurabilityPolicy.VOLATILE,
        )
        self.clouds = {}
        self.imus = []
        self.official_odom = []
        self.pointlio_odom = []

        for topic in (args.cloud_topic, args.cloud_base_topic, args.cloud_deskewed_topic):
            self.create_subscription(PointCloud2, topic, lambda msg, t=topic: self.on_cloud(t, msg), qos)
        self.create_subscription(Imu, args.imu_topic, self.on_imu, qos)
        self.create_subscription(Odometry, args.official_odom_topic, self.on_official_odom, qos)
        self.create_subscription(Odometry, args.pointlio_odom_topic, self.on_pointlio_odom, qos)

    def on_cloud(self, topic, msg):
        self.clouds[topic] = msg

    def on_imu(self, msg):
        a = msg.linear_acceleration
        g = msg.angular_velocity
        self.imus.append((stamp_sec(msg.header.stamp), msg.header.frame_id, a.x, a.y, a.z, g.x, g.y, g.z))
        self.imus = self.imus[-5000:]

    def on_official_odom(self, msg):
        p = msg.pose.pose.position
        q = msg.pose.pose.orientation
        self.official_odom.append(
            (stamp_sec(msg.header.stamp), msg.header.frame_id, msg.child_frame_id, p.x, p.y, p.z, q)
        )
        self.official_odom = self.official_odom[-1000:]

    def on_pointlio_odom(self, msg):
        p = msg.pose.pose.position
        q = msg.pose.pose.orientation
        self.pointlio_odom.append(
            (stamp_sec(msg.header.stamp), msg.header.frame_id, msg.child_frame_id, p.x, p.y, p.z, q)
        )
        self.pointlio_odom = self.pointlio_odom[-3000:]

    def summarize_cloud(self, topic):
        msg = self.clouds.get(topic)
        if msg is None:
            return "missing"

        fields = {field.name: field for field in msg.fields}
        stats = []
        for name in ("x", "y", "z", "intensity", "ring", "time", "timestamp", "offset_time"):
            field = fields.get(name)
            if field is None:
                continue
            fmt = {2: "B", 4: "H", 6: "I", 7: "f", 8: "d"}.get(field.datatype)
            if fmt is None:
                continue
            values = []
            size = struct.calcsize(fmt)
            for idx in range(min(int(msg.width * msg.height), 5000)):
                offset = idx * msg.point_step + field.offset
                if offset + size <= len(msg.data):
                    values.append(struct.unpack_from("<" + fmt, msg.data, offset)[0])
            if values:
                stats.append("%s=[%.6g, %.6g] mean=%.6g" % (name, min(values), max(values), sum(values) / len(values)))

        return "%s stamp=%.6f n=%d fields=%s %s" % (
            msg.header.frame_id,
            stamp_sec(msg.header.stamp),
            msg.width * msg.height,
            ",".join(field.name for field in msg.fields),
            "; ".join(stats),
        )

    def summarize_imu(self):
        if not self.imus:
            return "missing"
        values = self.imus
        labels = ("acc_x", "acc_y", "acc_z", "gyr_x", "gyr_y", "gyr_z")
        cols = list(zip(*[(row[2], row[3], row[4], row[5], row[6], row[7]) for row in values]))
        lines = []
        for label, col in zip(labels, cols):
            lines.append("%s mean=%.6f min=%.6f max=%.6f" % (label, sum(col) / len(col), min(col), max(col)))
        norms = [math.sqrt(row[2] ** 2 + row[3] ** 2 + row[4] ** 2) for row in values]
        dts = [values[i + 1][0] - values[i][0] for i in range(len(values) - 1)]
        if dts:
            mean_dt = sum(dts) / len(dts)
            lines.append("imu_dt mean=%.6f min=%.6f max=%.6f hz=%.1f" % (mean_dt, min(dts), max(dts), 1.0 / mean_dt))
        lines.append("acc_norm mean=%.6f min=%.6f max=%.6f" % (sum(norms) / len(norms), min(norms), max(norms)))
        lines.append("last_frame=%s last_stamp=%.6f" % (values[-1][1], values[-1][0]))
        return "\n  ".join(lines)

    def odom_drift(self, rows):
        if len(rows) < 2:
            return None
        first = rows[0]
        last = rows[-1]
        drift = math.sqrt((last[3] - first[3]) ** 2 + (last[4] - first[4]) ** 2 + (last[5] - first[5]) ** 2)
        return first, last, drift


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--duration", type=float, default=8.0)
    parser.add_argument("--max-static-drift", type=float, default=0.5)
    parser.add_argument("--require-pointlio", action="store_true")
    parser.add_argument("--cloud-topic", default="/utlidar/cloud")
    parser.add_argument("--cloud-base-topic", default="/utlidar/cloud_base")
    parser.add_argument("--cloud-deskewed-topic", default="/utlidar/cloud_deskewed")
    parser.add_argument("--imu-topic", default="/utlidar/imu")
    parser.add_argument("--official-odom-topic", default="/utlidar/robot_odom")
    parser.add_argument("--pointlio-odom-topic", default="/aft_mapped_to_init")
    args = parser.parse_args()

    rclpy.init()
    node = Probe(args)
    deadline = time.time() + args.duration
    while time.time() < deadline:
        rclpy.spin_once(node, timeout_sec=0.05)

    now = node.get_clock().now().nanoseconds * 1e-9
    print("Go2 Point-LIO input diagnosis")
    print("  ros_now=%.6f duration=%.1fs" % (now, args.duration))
    print("  cloud_raw:      %s" % node.summarize_cloud(args.cloud_topic))
    print("  cloud_base:     %s" % node.summarize_cloud(args.cloud_base_topic))
    print("  cloud_deskewed: %s" % node.summarize_cloud(args.cloud_deskewed_topic))
    print("  imu_samples=%d" % len(node.imus))
    print("  %s" % node.summarize_imu())

    official = node.odom_drift(node.official_odom)
    if official:
        first, last, drift = official
        print(
            "  official_odom drift=%.4fm first=(%.3f,%.3f,%.3f) last=(%.3f,%.3f,%.3f) rpy_last=%s"
            % (
                drift,
                first[3],
                first[4],
                first[5],
                last[3],
                last[4],
                last[5],
                tuple(round(v, 3) for v in quat_to_rpy_deg(last[6])),
            )
        )
    else:
        print("  official_odom missing")

    pointlio = node.odom_drift(node.pointlio_odom)
    exit_code = 0
    if pointlio:
        first, last, drift = pointlio
        print(
            "  pointlio_odom drift=%.4fm first=(%.3f,%.3f,%.3f) last=(%.3f,%.3f,%.3f) rpy_last=%s"
            % (
                drift,
                first[3],
                first[4],
                first[5],
                last[3],
                last[4],
                last[5],
                tuple(round(v, 3) for v in quat_to_rpy_deg(last[6])),
            )
        )
        if drift > args.max_static_drift:
            print(
                "  ERROR: Point-LIO odometry drifted %.3fm while the robot should be static; threshold is %.3fm."
                % (drift, args.max_static_drift),
                file=sys.stderr,
            )
            exit_code = 2
    else:
        print("  pointlio_odom missing")
        if args.require_pointlio:
            print("  ERROR: no Point-LIO odometry received.", file=sys.stderr)
            exit_code = 2

    node.destroy_node()
    rclpy.shutdown()
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
