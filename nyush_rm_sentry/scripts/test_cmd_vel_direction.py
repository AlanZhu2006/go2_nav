#!/usr/bin/env python3
"""Publish simple cmd_vel probes and report odometry deltas."""

from __future__ import annotations

import argparse
import math
import sys
import time
from dataclasses import dataclass
from typing import Optional

import rclpy
from geometry_msgs.msg import Twist
from nav_msgs.msg import Odometry


@dataclass
class Pose2D:
    stamp: float
    x: float
    y: float
    yaw: float


def yaw_from_quat(q) -> float:
    siny_cosp = 2.0 * (q.w * q.z + q.x * q.y)
    cosy_cosp = 1.0 - 2.0 * (q.y * q.y + q.z * q.z)
    return math.atan2(siny_cosp, cosy_cosp)


def angle_diff(a: float, b: float) -> float:
    return math.atan2(math.sin(a - b), math.cos(a - b))


def make_twist(vx: float, vy: float, wz: float) -> Twist:
    msg = Twist()
    msg.linear.x = float(vx)
    msg.linear.y = float(vy)
    msg.angular.z = float(wz)
    return msg


class DirectionProbe:
    def __init__(self, args: argparse.Namespace) -> None:
        self.args = args
        self.node = rclpy.create_node("cmd_vel_direction_probe")
        self.pub = self.node.create_publisher(Twist, args.cmd_topic, 10)
        self.latest_odom: Optional[Pose2D] = None
        self.node.create_subscription(Odometry, args.odom_topic, self.on_odom, 10)

    def on_odom(self, msg: Odometry) -> None:
        p = msg.pose.pose.position
        q = msg.pose.pose.orientation
        self.latest_odom = Pose2D(time.monotonic(), float(p.x), float(p.y), yaw_from_quat(q))

    def spin_for(self, seconds: float) -> None:
        end = time.monotonic() + seconds
        while rclpy.ok() and time.monotonic() < end:
            rclpy.spin_once(self.node, timeout_sec=0.05)

    def wait_for_odom(self, timeout: float) -> Optional[Pose2D]:
        end = time.monotonic() + timeout
        while rclpy.ok() and time.monotonic() < end:
            rclpy.spin_once(self.node, timeout_sec=0.05)
            if self.latest_odom is not None:
                return self.latest_odom
        return None

    def publish_for(self, cmd: Twist, seconds: float) -> None:
        period = 1.0 / max(self.args.rate, 1.0)
        end = time.monotonic() + seconds
        while rclpy.ok() and time.monotonic() < end:
            self.pub.publish(cmd)
            rclpy.spin_once(self.node, timeout_sec=0.0)
            time.sleep(period)

    def zero(self, seconds: float = 0.5) -> None:
        self.publish_for(make_twist(0.0, 0.0, 0.0), seconds)

    def run_one(self, name: str, vx: float, vy: float, wz: float) -> None:
        if self.args.interactive:
            print(f"\nReady to test {name}: cmd_vel(vx={vx:.3f}, vy={vy:.3f}, wz={wz:.3f})")
            input("Press Enter to run, or Ctrl-C to stop...")

        self.zero(self.args.settle)
        before = self.wait_for_odom(self.args.odom_timeout)
        if before is None:
            print(f"{name}: no odom received on {self.args.odom_topic}", file=sys.stderr)
            return

        self.publish_for(make_twist(vx, vy, wz), self.args.duration)
        self.zero(self.args.settle)
        after = self.wait_for_odom(self.args.odom_timeout)
        if after is None:
            print(f"{name}: odom disappeared", file=sys.stderr)
            return

        dx = after.x - before.x
        dy = after.y - before.y
        dyaw = angle_diff(after.yaw, before.yaw)
        print(
            f"{name}: odom delta dx={dx:+.3f} m, dy={dy:+.3f} m, "
            f"dyaw={math.degrees(dyaw):+.1f} deg"
        )

    def close(self) -> None:
        self.zero(0.5)
        self.node.destroy_node()


def main() -> int:
    parser = argparse.ArgumentParser(description="Probe cmd_vel direction against odometry")
    parser.add_argument("--cmd-topic", default="/cmd_vel")
    parser.add_argument("--odom-topic", default="/Odometry")
    parser.add_argument("--vx", type=float, default=0.20)
    parser.add_argument("--vy", type=float, default=0.20)
    parser.add_argument("--wz", type=float, default=0.40)
    parser.add_argument("--duration", type=float, default=1.5)
    parser.add_argument("--settle", type=float, default=0.6)
    parser.add_argument("--rate", type=float, default=20.0)
    parser.add_argument("--odom-timeout", type=float, default=5.0)
    parser.add_argument("--interactive", action="store_true")
    args = parser.parse_args()

    rclpy.init()
    probe = DirectionProbe(args)
    try:
        print(f"Waiting for odom on {args.odom_topic} ...")
        if probe.wait_for_odom(args.odom_timeout) is None:
            print(f"No odom received on {args.odom_topic}", file=sys.stderr)
            return 2

        tests = [
            ("+x forward", args.vx, 0.0, 0.0),
            ("-x backward", -args.vx, 0.0, 0.0),
            ("+y left", 0.0, args.vy, 0.0),
            ("-y right", 0.0, -args.vy, 0.0),
            ("+wz ccw", 0.0, 0.0, args.wz),
            ("-wz cw", 0.0, 0.0, -args.wz),
        ]
        for name, vx, vy, wz in tests:
            probe.run_one(name, vx, vy, wz)
    finally:
        probe.close()
        rclpy.shutdown()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
