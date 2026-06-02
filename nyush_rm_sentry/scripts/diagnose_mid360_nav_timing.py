#!/usr/bin/env python3

import math
import os
import time
from collections import defaultdict, deque

import rclpy
import tf2_ros
from geometry_msgs.msg import TransformStamped
from nav_msgs.msg import Odometry
from rclpy.duration import Duration
from rclpy.node import Node
from rclpy.qos import DurabilityPolicy, HistoryPolicy, QoSProfile, ReliabilityPolicy
from sensor_msgs.msg import LaserScan, PointCloud2
from tf2_msgs.msg import TFMessage


def stamp_sec(stamp):
    return float(stamp.sec) + float(stamp.nanosec) * 1e-9


def finite_or_none(value):
    if value is None or not math.isfinite(value):
        return None
    return value


def yaw_from_quat(q):
    siny_cosp = 2.0 * (q.w * q.z + q.x * q.y)
    cosy_cosp = 1.0 - 2.0 * (q.y * q.y + q.z * q.z)
    return math.degrees(math.atan2(siny_cosp, cosy_cosp))


class TimingDiag(Node):
    def __init__(self):
        super().__init__("diagnose_mid360_nav_timing")
        self.duration = float(os.environ.get("DIAG_DURATION", "30"))
        self.print_period = float(os.environ.get("DIAG_PRINT_PERIOD", "1.0"))
        self.started_wall = time.time()
        self.latest = {}
        self.arrivals = defaultdict(lambda: deque(maxlen=100))
        self.tf_latest = {}
        self.tf_buffer = tf2_ros.Buffer(cache_time=Duration(seconds=20.0))
        self.tf_listener = tf2_ros.TransformListener(self.tf_buffer, self, spin_thread=False)

        sensor_qos = QoSProfile(
            history=HistoryPolicy.KEEP_LAST,
            depth=20,
            reliability=ReliabilityPolicy.BEST_EFFORT,
            durability=DurabilityPolicy.VOLATILE,
        )
        reliable_qos = QoSProfile(
            history=HistoryPolicy.KEEP_LAST,
            depth=20,
            reliability=ReliabilityPolicy.RELIABLE,
            durability=DurabilityPolicy.VOLATILE,
        )
        static_qos = QoSProfile(
            history=HistoryPolicy.KEEP_LAST,
            depth=20,
            reliability=ReliabilityPolicy.RELIABLE,
            durability=DurabilityPolicy.TRANSIENT_LOCAL,
        )

        self.create_subscription(LaserScan, "/scan", self._scan_cb("/scan"), sensor_qos)
        self.create_subscription(
            PointCloud2,
            os.environ.get("DIAG_BODY_CLOUD_TOPIC", "/cloud_registered_body"),
            self._cloud_cb(os.environ.get("DIAG_BODY_CLOUD_TOPIC", "/cloud_registered_body")),
            sensor_qos,
        )
        self.create_subscription(
            PointCloud2,
            os.environ.get("DIAG_GLOBAL_CLOUD_TOPIC", "/cloud_registered"),
            self._cloud_cb(os.environ.get("DIAG_GLOBAL_CLOUD_TOPIC", "/cloud_registered")),
            sensor_qos,
        )
        self.create_subscription(Odometry, "/Odometry", self._odom_cb("/Odometry"), reliable_qos)
        self.create_subscription(Odometry, "/odom", self._odom_cb("/odom"), reliable_qos)
        self.create_subscription(TFMessage, "/tf", self._tf_cb(False), reliable_qos)
        self.create_subscription(TFMessage, "/tf_static", self._tf_cb(True), static_qos)
        self.create_timer(self.print_period, self.print_report)

        self.get_logger().info(
            "Timing diagnostic running for %.1fs. Move the robot slowly while watching ages." % self.duration
        )

    def now_sec(self):
        return self.get_clock().now().nanoseconds * 1e-9

    def _rate(self, name):
        samples = self.arrivals[name]
        if len(samples) < 2:
            return None
        dt = samples[-1] - samples[0]
        if dt <= 0:
            return None
        return (len(samples) - 1) / dt

    def _record(self, name, stamp, frame, extra=""):
        now = self.now_sec()
        self.latest[name] = {
            "stamp": stamp,
            "age": now - stamp,
            "frame": frame,
            "extra": extra,
            "arrival_age": 0.0,
        }
        self.arrivals[name].append(now)

    def _scan_cb(self, name):
        def cb(msg):
            finite_ranges = sum(1 for r in msg.ranges if math.isfinite(r))
            extra = "ranges=%d finite=%d" % (len(msg.ranges), finite_ranges)
            self._record(name, stamp_sec(msg.header.stamp), msg.header.frame_id, extra)

        return cb

    def _cloud_cb(self, name):
        def cb(msg):
            extra = "points=%d" % (msg.width * msg.height)
            self._record(name, stamp_sec(msg.header.stamp), msg.header.frame_id, extra)

        return cb

    def _odom_cb(self, name):
        def cb(msg):
            frame = "%s->%s" % (msg.header.frame_id, msg.child_frame_id)
            p = msg.pose.pose.position
            yaw = yaw_from_quat(msg.pose.pose.orientation)
            extra = "xyz=(%.2f,%.2f,%.2f) yaw=%.1fdeg" % (p.x, p.y, p.z, yaw)
            self._record(name, stamp_sec(msg.header.stamp), frame, extra)

        return cb

    def _tf_cb(self, is_static):
        def cb(msg):
            now = self.now_sec()
            for tf in msg.transforms:
                key = "%s->%s" % (tf.header.frame_id, tf.child_frame_id)
                stamp = stamp_sec(tf.header.stamp)
                self.tf_latest[key] = {
                    "stamp": stamp,
                    "age": 0.0 if is_static else now - stamp,
                    "static": is_static,
                    "xyz": (
                        tf.transform.translation.x,
                        tf.transform.translation.y,
                        tf.transform.translation.z,
                    ),
                    "yaw": yaw_from_quat(tf.transform.rotation),
                }
                self.arrivals["tf:" + key].append(now)

        return cb

    def print_report(self):
        now = self.now_sec()
        elapsed = time.time() - self.started_wall
        print("\n=== mid360 nav timing t=%.1fs now=%.3f ===" % (elapsed, now), flush=True)
        for name in ["/scan", "/cloud_registered_body", "/cloud_registered", "/Odometry", "/odom"]:
            item = self.latest.get(name)
            rate = finite_or_none(self._rate(name))
            if item is None:
                print("%-24s no message" % name, flush=True)
                continue
            print(
                "%-24s rate=%6sHz stamp=%.3f age=%+.3fs frame=%s %s"
                % (
                    name,
                    "?" if rate is None else "%.1f" % rate,
                    item["stamp"],
                    item["age"],
                    item["frame"],
                    item["extra"],
                ),
                flush=True,
            )

        for key in ["odom->base_link", "odom->livox_frame", "livox_frame->base_link", "map->odom"]:
            item = self.tf_latest.get(key)
            rate = finite_or_none(self._rate("tf:" + key))
            if item is None:
                print("%-24s no tf" % ("tf " + key), flush=True)
                continue
            label = "static" if item["static"] else ("%.1fHz" % rate if rate is not None else "?Hz")
            age = 0.0 if item["static"] else now - item["stamp"]
            arrivals = self.arrivals["tf:" + key]
            rx_age = 0.0 if arrivals else float("nan")
            if arrivals:
                rx_age = now - arrivals[-1]
            stale = " STALE" if (not item["static"] and rx_age > 1.0) else ""
            print(
                "%-24s %-8s stamp=%.3f age=%+.3fs last_rx=%+.3fs%s xyz=(%.2f,%.2f,%.2f) yaw=%.1fdeg"
                % (
                    "tf " + key,
                    label,
                    item["stamp"],
                    age,
                    rx_age,
                    stale,
                    item["xyz"][0],
                    item["xyz"][1],
                    item["xyz"][2],
                    item["yaw"],
                ),
                flush=True,
            )

        for target, source in [("odom", "base_link"), ("map", "base_link")]:
            label = "tf2 %s->%s" % (target, source)
            try:
                tf = self.tf_buffer.lookup_transform(
                    target,
                    source,
                    rclpy.time.Time(),
                    timeout=Duration(seconds=0.02),
                )
                stamp = stamp_sec(tf.header.stamp)
                age = now - stamp
                t = tf.transform.translation
                yaw = yaw_from_quat(tf.transform.rotation)
                print(
                    "%-24s composed stamp=%.3f age=%+.3fs xyz=(%.2f,%.2f,%.2f) yaw=%.1fdeg"
                    % (label, stamp, age, t.x, t.y, t.z, yaw),
                    flush=True,
                )
            except Exception as exc:
                print("%-24s no composed tf: %s" % (label, str(exc).split("\n")[0]), flush=True)

        if elapsed >= self.duration:
            raise KeyboardInterrupt


def main():
    rclpy.init()
    node = TimingDiag()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
