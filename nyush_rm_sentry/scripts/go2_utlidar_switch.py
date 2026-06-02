#!/usr/bin/env python3
import argparse
import sys
import time

SDK_PATH = "/home/unitree/unitree_sdk2_python"
if SDK_PATH not in sys.path:
    sys.path.insert(0, SDK_PATH)

from unitree_sdk2py.core.channel import ChannelFactoryInitialize, ChannelPublisher
from unitree_sdk2py.idl.default import std_msgs_msg_dds__String_
from unitree_sdk2py.idl.std_msgs.msg.dds_ import String_


def main() -> int:
    parser = argparse.ArgumentParser(description="Switch Go2 built-in utlidar ON/OFF.")
    parser.add_argument("status", choices=["ON", "OFF"], help="utlidar switch state")
    parser.add_argument("--iface", default="", help="Unitree DDS network interface; empty means SDK default")
    parser.add_argument("--repeat", type=int, default=5, help="number of messages to send")
    parser.add_argument("--interval", type=float, default=0.2, help="seconds between messages")
    args = parser.parse_args()

    if args.iface:
        ChannelFactoryInitialize(0, args.iface)
    else:
        ChannelFactoryInitialize(0)
    publisher = ChannelPublisher("rt/utlidar/switch", String_)
    publisher.Init()

    msg = std_msgs_msg_dds__String_()
    msg.data = args.status

    for _ in range(max(1, args.repeat)):
        publisher.Write(msg)
        time.sleep(args.interval)

    iface = args.iface if args.iface else "SDK default interface"
    print(f"Sent utlidar switch {args.status} on {iface}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
