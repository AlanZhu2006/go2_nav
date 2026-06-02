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

echo "MID360 eth driver tuning:"
echo "  interface:  $IFACE"
echo "  connection: $CON_NAME"
echo "  lidar ip:   $LIDAR_IP"
echo

echo ">>> Stopping Livox ROS driver if running"
pkill -f "[l]ivox_ros_driver2_node" 2>/dev/null || true
pkill -f "[r]os2 launch livox_ros_driver2 msg_MID360_launch.py" 2>/dev/null || true

usb_path="$(readlink -f "/sys/class/net/${IFACE}/device" || true)"
if [ -n "$usb_path" ]; then
    echo ">>> USB device path: $usb_path"
    if [ -w "$usb_path/power/control" ]; then
        echo on > "$usb_path/power/control"
        echo "    power/control=on"
    fi
    if [ -w "$usb_path/power/autosuspend" ]; then
        echo -1 > "$usb_path/power/autosuspend" || true
        echo "    power/autosuspend=-1"
    fi
fi

echo
echo ">>> Disabling NIC offloads where supported"
for feature in rx tx sg tso ufo gso gro lro rxvlan txvlan; do
    ethtool -K "$IFACE" "$feature" off >/dev/null 2>&1 || true
done

echo
echo ">>> Disabling EEE where supported"
ethtool --set-eee "$IFACE" eee off >/dev/null 2>&1 || true

echo
echo ">>> Reconnecting NetworkManager profile"
nmcli con down "$CON_NAME" >/dev/null 2>&1 || true
sleep 1
nmcli con up "$CON_NAME"
sleep 2

echo
echo ">>> Current link"
ethtool "$IFACE" 2>/dev/null | grep -E "Speed|Duplex|Auto-negotiation|Link detected" || true
ethtool -k "$IFACE" 2>/dev/null | grep -E "tcp-segmentation-offload|generic-segmentation-offload|generic-receive-offload|tx-checksumming|rx-checksumming|scatter-gather" || true

echo
echo ">>> Before ARP/ping"
ip -s link show "$IFACE" || true
ip neigh flush dev "$IFACE" || true

echo
echo ">>> ARP test"
arping -I "$IFACE" -c 5 "$LIDAR_IP" || true

echo
echo ">>> Ping test"
ping -I "$IFACE" -c 3 -W 1 "$LIDAR_IP" || true

echo
echo ">>> After tests"
ip -s link show "$IFACE" || true
dmesg -T 2>/dev/null | tail -60 | grep -Ei "r8152|${IFACE}|Tx status|usb|reset" || true

echo
echo "If tx_packets barely increases while tx_errors increases, replace the USB Ethernet adapter/cable or insert a small switch between MID360 and this adapter."
