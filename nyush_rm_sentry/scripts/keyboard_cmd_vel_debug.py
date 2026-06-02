#!/usr/bin/env python3
"""Small keyboard teleop publisher for debugging /cmd_vel."""

from __future__ import annotations

import argparse
import select
import sys
import termios
import time
import tty

import rclpy
from geometry_msgs.msg import Twist


HELP = """\
Keyboard cmd_vel debug

  w/s  forward/back
  a/d  left/right
  q/e  +wz/-wz
  space or x  stop
  Ctrl-C      exit
"""


def read_key(timeout: float) -> str | None:
    ready, _, _ = select.select([sys.stdin], [], [], timeout)
    if not ready:
        return None
    return sys.stdin.read(1)


def make_twist(vx: float, vy: float, wz: float) -> Twist:
    msg = Twist()
    msg.linear.x = vx
    msg.linear.y = vy
    msg.angular.z = wz
    return msg


def main() -> int:
    parser = argparse.ArgumentParser(description="Publish keyboard commands to /cmd_vel")
    parser.add_argument("--topic", default="/cmd_vel")
    parser.add_argument("--vx", type=float, default=0.08)
    parser.add_argument("--vy", type=float, default=0.05)
    parser.add_argument("--wz", type=float, default=0.20)
    parser.add_argument("--rate", type=float, default=20.0)
    parser.add_argument(
        "--hold-sec",
        type=float,
        default=0.30,
        help="Keep the last key command alive for this long; then publish zero.",
    )
    parser.add_argument(
        "--latch",
        action="store_true",
        help="Keep the last command until another key or stop is pressed.",
    )
    args = parser.parse_args()

    rclpy.init()
    node = rclpy.create_node("keyboard_cmd_vel_debug")
    pub = node.create_publisher(Twist, args.topic, 10)

    old_settings = termios.tcgetattr(sys.stdin)
    current = make_twist(0.0, 0.0, 0.0)
    last_key_time = 0.0
    period = 1.0 / max(args.rate, 1.0)

    print(HELP)
    print(
        f"Publishing {args.topic}: vx={args.vx:.3f}, vy={args.vy:.3f}, wz={args.wz:.3f}. "
        + ("Latch mode: press space/x to stop." if args.latch else "Hold a key for continuous motion.")
    )

    try:
        tty.setraw(sys.stdin.fileno())
        while rclpy.ok():
            key = read_key(period)
            now = time.monotonic()

            if key:
                if key == "\x03":
                    break
                if key == "w":
                    current = make_twist(args.vx, 0.0, 0.0)
                elif key == "s":
                    current = make_twist(-args.vx, 0.0, 0.0)
                elif key == "a":
                    current = make_twist(0.0, args.vy, 0.0)
                elif key == "d":
                    current = make_twist(0.0, -args.vy, 0.0)
                elif key == "q":
                    current = make_twist(0.0, 0.0, args.wz)
                elif key == "e":
                    current = make_twist(0.0, 0.0, -args.wz)
                elif key in (" ", "x"):
                    current = make_twist(0.0, 0.0, 0.0)
                last_key_time = now

            if not args.latch and now - last_key_time > args.hold_sec:
                current = make_twist(0.0, 0.0, 0.0)

            pub.publish(current)
            rclpy.spin_once(node, timeout_sec=0.0)
    finally:
        pub.publish(make_twist(0.0, 0.0, 0.0))
        termios.tcsetattr(sys.stdin, termios.TCSADRAIN, old_settings)
        node.destroy_node()
        rclpy.shutdown()
        print("\nStopped; published zero cmd_vel.")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
