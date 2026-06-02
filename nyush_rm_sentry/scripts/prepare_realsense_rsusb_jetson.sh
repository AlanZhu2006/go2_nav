#!/usr/bin/env bash

set -euo pipefail

USB_ID="${REALSENSE_USB_ID:-8086:0b3a}"
USBFS_MEMORY_MB="${USBFS_MEMORY_MB:-1000}"
USB_AUTOSUSPEND="${USB_AUTOSUSPEND:--1}"
UNBIND_UVC="${UNBIND_UVC:-true}"

if [ "$(id -u)" -ne 0 ]; then
    echo "This script needs root because it writes USB kernel parameters." >&2
    echo "Run:" >&2
    echo "  sudo $0" >&2
    exit 1
fi

echo ">>> Stopping RealSense ROS processes"
pkill -f '[r]ealsense2_camera_node' 2>/dev/null || true
pkill -f '[r]os2 launch realsense2_camera' 2>/dev/null || true

echo ">>> Applying Jetson USB parameters"
if [ -w /sys/module/usbcore/parameters/usbfs_memory_mb ]; then
    echo "$USBFS_MEMORY_MB" > /sys/module/usbcore/parameters/usbfs_memory_mb
fi
if [ -w /sys/module/usbcore/parameters/autosuspend ]; then
    echo "$USB_AUTOSUSPEND" > /sys/module/usbcore/parameters/autosuspend
fi

mapfile -t devices < <(
    for dev in /sys/bus/usb/devices/*; do
        [ -f "$dev/idVendor" ] || continue
        [ -f "$dev/idProduct" ] || continue
        id="$(tr '[:upper:]' '[:lower:]' < "$dev/idVendor"):$(tr '[:upper:]' '[:lower:]' < "$dev/idProduct")"
        if [ "$id" = "$(echo "$USB_ID" | tr '[:upper:]' '[:lower:]')" ]; then
            basename "$dev"
        fi
    done
)

if [ "${#devices[@]}" -eq 0 ]; then
    echo "Error: RealSense USB device $USB_ID was not found." >&2
    lsusb
    exit 1
fi

for dev in "${devices[@]}"; do
    echo ">>> Preparing USB device $dev"
    if [ -w "/sys/bus/usb/devices/$dev/power/control" ]; then
        echo on > "/sys/bus/usb/devices/$dev/power/control"
    fi

    if [ "$UNBIND_UVC" = "true" ] && [ -d /sys/bus/usb/drivers/uvcvideo ]; then
        for iface in /sys/bus/usb/devices/"$dev":*; do
            [ -e "$iface" ] || continue
            iface_name="$(basename "$iface")"
            if [ -L "/sys/bus/usb/drivers/uvcvideo/$iface_name" ]; then
                echo "    unbind uvcvideo $iface_name"
                echo "$iface_name" > /sys/bus/usb/drivers/uvcvideo/unbind
            fi
        done
    fi
done

echo
echo "Current USB parameters:"
printf "  autosuspend="; cat /sys/module/usbcore/parameters/autosuspend 2>/dev/null || true
printf "  usbfs_memory_mb="; cat /sys/module/usbcore/parameters/usbfs_memory_mb 2>/dev/null || true

echo
echo "USB tree:"
lsusb -t

echo
echo "Next:"
echo "  cd /home/unitree/work/nyush_rm_sentry"
echo "  ./scripts/check_realsense_rsusb.sh"
echo "  ENABLE_IMU=false ALIGN_DEPTH=false ./scripts/start_realsense_rsusb_foxy.sh"
