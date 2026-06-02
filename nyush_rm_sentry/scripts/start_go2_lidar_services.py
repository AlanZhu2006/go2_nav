#!/usr/bin/env python3
import argparse
import sys
import time

SDK_PATH = "/home/unitree/unitree_sdk2_python"
if SDK_PATH not in sys.path:
    sys.path.insert(0, SDK_PATH)

from unitree_sdk2py.core.channel import ChannelFactoryInitialize
from unitree_sdk2py.go2.robot_state.robot_state_client import RobotStateClient


DEFAULT_SERVICES = ["unitree_lidar", "unitree_lidar_slam", "voxel_height_mapping"]


def main() -> int:
    parser = argparse.ArgumentParser(description="Start Go2 built-in lidar related robot services.")
    parser.add_argument("--iface", default="", help="Unitree SDK interface; empty means SDK default")
    parser.add_argument("--timeout", type=float, default=5.0)
    parser.add_argument("--settle", type=float, default=1.0)
    parser.add_argument("services", nargs="*", default=DEFAULT_SERVICES)
    args = parser.parse_args()

    if args.iface:
        ChannelFactoryInitialize(0, args.iface)
    else:
        ChannelFactoryInitialize(0)

    client = RobotStateClient()
    client.SetTimeout(args.timeout)
    client.Init()

    for name in args.services:
        code = client.ServiceSwitch(name, True)
        print(f"ServiceSwitch({name}, True) -> code {code}")
        time.sleep(args.settle)

    code, services = client.ServiceList()
    print(f"ServiceList -> code {code}")
    wanted = set(args.services)
    for service in services or []:
        if service.name in wanted:
            print(f"{service.name}: status={service.status}, protect={service.protect}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
