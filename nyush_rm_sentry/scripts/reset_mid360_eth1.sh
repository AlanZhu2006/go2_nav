#!/usr/bin/env bash

set -euo pipefail

IFACE="${MID360_IFACE:-eth1}"
CON_NAME="${MID360_CON_NAME:-Wired connection 2}"
LIDAR_IP="${MID360_LIDAR_IP:-192.168.1.182}"

if [ "$(id -u)" -ne 0 ]; then
    echo "Run with sudo:"
    echo "  sudo $0"
    exit 1
fi

usb_path="$(readlink -f "/sys/class/net/${IFACE}/device")"
usb_dev="$(basename "$usb_path" | cut -d: -f1)"
authorized="/sys/bus/usb/devices/${usb_dev}/authorized"

if [ ! -w "$authorized" ]; then
    echo "Error: cannot write $authorized" >&2
    echo "Resolved ${IFACE} device path: $usb_path" >&2
    exit 1
fi

echo "MID360 eth reset target:"
echo "  interface:  $IFACE"
echo "  connection: $CON_NAME"
echo "  usb device: $usb_dev"
echo "  lidar ip:   $LIDAR_IP"
echo

echo ">>> Stopping Livox ROS driver if running"
pkill -f "[l]ivox_ros_driver2_node" 2>/dev/null || true
pkill -f "[r]os2 launch livox_ros_driver2 msg_MID360_launch.py" 2>/dev/null || true

echo
echo ">>> Before reset"
ip -s link show "$IFACE" || true
ethtool "$IFACE" 2>/dev/null | grep -E "Speed|Duplex|Link detected" || true

echo
echo ">>> Bringing NetworkManager connection down"
nmcli con down "$CON_NAME" || true
sleep 1

echo
echo ">>> USB deauthorize/authorize $usb_dev"
echo 0 > "$authorized"
sleep 3
echo 1 > "$authorized"
sleep 5

echo
echo ">>> Reapplying MID360 NetworkManager profile"
nmcli con mod "$CON_NAME" \
    connection.interface-name "$IFACE" \
    connection.autoconnect yes \
    ipv4.method manual \
    ipv4.addresses 192.168.1.2/24 \
    ipv4.gateway "" \
    ipv4.never-default yes \
    ipv4.route-metric 500 \
    ipv6.method ignore
nmcli con up "$CON_NAME"
sleep 2

echo
echo ">>> After reset"
ip -s link show "$IFACE" || true
ethtool "$IFACE" 2>/dev/null | grep -E "Speed|Duplex|Link detected" || true
ip neigh show dev "$IFACE" || true

echo
echo ">>> ARP test"
arping -I "$IFACE" -c 5 "$LIDAR_IP" || true

echo
echo "Next, if arping receives responses and tx_errors stop increasing:"
echo "  source /opt/ros/foxy/setup.bash"
echo "  source /home/unitree/nav_ws/install/setup.bash"
echo "  ros2 launch livox_ros_driver2 msg_MID360_launch.py"
