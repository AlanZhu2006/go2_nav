#!/usr/bin/env bash

set -euo pipefail

USB_ID="${REALSENSE_USB_ID:-8086:0b3a}"

device_path=""
for dev in /sys/bus/usb/devices/*; do
    [ -f "$dev/idVendor" ] || continue
    [ -f "$dev/idProduct" ] || continue
    id="$(cat "$dev/idVendor"):$(cat "$dev/idProduct")"
    if [ "$id" = "$USB_ID" ]; then
        device_path="$dev"
        break
    fi
done

if [ -z "$device_path" ]; then
    echo "Error: RealSense USB device $USB_ID was not found under /sys/bus/usb/devices." >&2
    echo "Check: lsusb | grep -Ei '8086|realsense'" >&2
    exit 1
fi

echo "RealSense USB device: $(basename "$device_path") ($USB_ID)"
echo ">>> Stopping existing RealSense ROS processes"
pkill -f "[r]ealsense2_camera" 2>/dev/null || true
pkill -f "[r]s_launch.py" 2>/dev/null || true

echo ">>> USB deauthorize/authorize"
echo 0 | sudo tee "$device_path/authorized" >/dev/null
sleep 2
echo 1 | sudo tee "$device_path/authorized" >/dev/null
sleep 4

echo ">>> Current USB state"
lsusb | grep -Ei '8086|realsense' || true
lsusb -t
ls -l /dev/video* /dev/media* 2>/dev/null || true
