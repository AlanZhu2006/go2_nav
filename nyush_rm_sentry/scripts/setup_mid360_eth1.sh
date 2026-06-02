#!/usr/bin/env bash

set -euo pipefail

CON_NAME="${MID360_CON_NAME:-Wired connection 2}"
IFACE="${MID360_IFACE:-eth1}"
HOST_IP="${MID360_HOST_IP:-192.168.1.2}"
LIDAR_IP="${MID360_LIDAR_IP:-192.168.1.182}"
NAV_WS_ROOT="${NAV_WS_ROOT:-$HOME/nav_ws}"
CONFIG_JSON="${MID360_CONFIG_JSON:-$NAV_WS_ROOT/src/livox_ros_driver2/config/MID360_config.json}"
APPLY="${1:-}"

echo "MID360 network target:"
echo "  connection: $CON_NAME"
echo "  interface:  $IFACE"
echo "  host ip:    $HOST_IP/24"
echo "  lidar ip:   $LIDAR_IP"
echo "  config:     $CONFIG_JSON"
echo

if [ "$APPLY" = "--apply" ]; then
    echo ">>> Applying NetworkManager profile"
    sudo nmcli con mod "$CON_NAME" \
        connection.interface-name "$IFACE" \
        connection.autoconnect yes \
        ipv4.method manual \
        ipv4.addresses "$HOST_IP/24" \
        ipv4.gateway "" \
        ipv4.never-default yes \
        ipv6.method ignore

    sudo nmcli con up "$CON_NAME"

    echo
    echo ">>> Applying Livox UDP receive buffer"
    sudo sysctl -w net.core.rmem_max=26214400
    sudo sysctl -w net.core.rmem_default=26214400
else
    echo "Dry run only. To apply:"
    echo "  $0 --apply"
fi

echo
echo ">>> Interface state"
nmcli -f GENERAL.DEVICE,GENERAL.STATE,GENERAL.CONNECTION,IP4.ADDRESS,IP4.ROUTE device show "$IFACE" || true
ip -br addr show "$IFACE" || true
ip route show dev "$IFACE" || true
ip neigh show dev "$IFACE" || true

echo
echo ">>> Link state"
if command -v ethtool >/dev/null 2>&1; then
    ethtool "$IFACE" 2>/dev/null | grep -E "Speed|Duplex|Auto-negotiation|Link detected" || true
else
    echo "ethtool is not installed"
fi

echo
echo ">>> Livox config IPs"
if [ -f "$CONFIG_JSON" ]; then
    grep -nE '"(cmd_data_ip|push_msg_ip|point_data_ip|imu_data_ip|ip)"' "$CONFIG_JSON" || true
else
    echo "Missing config: $CONFIG_JSON"
fi

echo
echo ">>> Ping MID360"
if ping -I "$IFACE" -c 3 -W 1 "$LIDAR_IP"; then
    echo
    echo "MID360 ping OK. Next:"
    echo "  source /opt/ros/foxy/setup.bash"
    echo "  source $NAV_WS_ROOT/install/setup.bash"
    echo "  ros2 launch livox_ros_driver2 msg_MID360_launch.py"
    echo
    echo "Check topics:"
    echo "  ros2 topic list | grep livox"
    echo "  ros2 topic hz /livox/lidar"
    echo "  ros2 topic hz /livox/imu"
else
    echo
    echo "MID360 ping failed."
    echo "NetworkManager/IP looks separate from lidar reachability. Check MID360 power/boot, cable,"
    echo "whether the lidar IP is really $LIDAR_IP, and whether another device owns 192.168.1.2."
fi
