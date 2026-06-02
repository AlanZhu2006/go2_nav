#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GO2_DDS_ENV="${GO2_DDS_ENV:-$SCRIPT_DIR/go2_dds_env.sh}"
NAV_WS_ROOT="${NAV_WS_ROOT:-$HOME/nav_ws}"
SAMPLE_SECONDS="${SAMPLE_SECONDS:-6}"

source_relaxed() {
    local setup_file="$1"
    local had_nounset=0
    case $- in
        *u*) had_nounset=1; set +u ;;
    esac
    source "$setup_file"
    if [ "$had_nounset" = "1" ]; then
        set -u
    fi
}

if [ ! -f "$GO2_DDS_ENV" ]; then
    echo "Error: Go2 DDS env script not found: $GO2_DDS_ENV" >&2
    exit 1
fi

source "$GO2_DDS_ENV"
if [ -f "$NAV_WS_ROOT/install/setup.bash" ]; then
    source_relaxed "$NAV_WS_ROOT/install/setup.bash"
fi

echo ">>> Process check"
ps -eo pid,comm,args | awk '
    $0 ~ /point_lio\/pointlio_mapping/ && $0 !~ /awk/ {print}
    $0 ~ /rviz2 -d .*loam_livox/ && $0 !~ /awk/ {print}
' || true

echo
echo ">>> Topic check"
for topic in /utlidar/cloud /utlidar/imu /utlidar/robot_odom /cloud_registered /aft_mapped_to_init; do
    echo
    echo "[$topic]"
    ros2 topic info "$topic" 2>/dev/null || true
done

echo
echo ">>> Sampling IMU, raw cloud, official odom, and Point-LIO odom for ${SAMPLE_SECONDS}s"
python3 - "$SAMPLE_SECONDS" <<'PY'
import math
import statistics
import struct
import sys
import time

import rclpy
from nav_msgs.msg import Odometry
from rclpy.node import Node
from rclpy.qos import DurabilityPolicy, HistoryPolicy, QoSProfile, ReliabilityPolicy
from sensor_msgs.msg import Imu, PointCloud2

sample_seconds = float(sys.argv[1])
q_rel = QoSProfile(
    history=HistoryPolicy.KEEP_LAST,
    depth=50,
    reliability=ReliabilityPolicy.RELIABLE,
    durability=DurabilityPolicy.VOLATILE,
)
q_be = QoSProfile(
    history=HistoryPolicy.KEEP_LAST,
    depth=50,
    reliability=ReliabilityPolicy.BEST_EFFORT,
    durability=DurabilityPolicy.VOLATILE,
)

def stamp_sec(stamp):
    return stamp.sec + stamp.nanosec * 1e-9

def read_field(msg, point, field):
    by_name = {item.name: item for item in msg.fields}
    info = by_name.get(field)
    if info is None:
        return None
    offset = info.offset
    if info.datatype == 7:
        return struct.unpack_from("<f", point, offset)[0]
    if info.datatype == 8:
        return struct.unpack_from("<d", point, offset)[0]
    if info.datatype == 4:
        return struct.unpack_from("<H", point, offset)[0]
    if info.datatype == 5:
        return struct.unpack_from("<i", point, offset)[0]
    if info.datatype == 6:
        return struct.unpack_from("<I", point, offset)[0]
    return None

class Probe(Node):
    def __init__(self):
        super().__init__("go2_pointlio_diagnose")
        self.imu = []
        self.cloud = []
        self.official = []
        self.pointlio = []
        self.create_subscription(Imu, "/utlidar/imu", self.imu_cb, q_rel)
        self.create_subscription(PointCloud2, "/utlidar/cloud", self.cloud_cb, q_be)
        self.create_subscription(Odometry, "/utlidar/robot_odom", self.official_cb, q_rel)
        self.create_subscription(Odometry, "/aft_mapped_to_init", self.pointlio_cb, q_rel)

    def imu_cb(self, msg):
        acc = msg.linear_acceleration
        gyro = msg.angular_velocity
        self.imu.append((
            stamp_sec(msg.header.stamp),
            acc.x, acc.y, acc.z,
            gyro.x, gyro.y, gyro.z,
            msg.header.frame_id,
        ))

    def cloud_cb(self, msg):
        count = msg.width * msg.height
        sample_count = min(count, 2000)
        times = []
        rings = []
        for i in range(sample_count):
            point = msg.data[i * msg.point_step:(i + 1) * msg.point_step]
            t = read_field(msg, point, "time")
            r = read_field(msg, point, "ring")
            if t is not None:
                times.append(t)
            if r is not None:
                rings.append(r)
        self.cloud.append((
            stamp_sec(msg.header.stamp),
            msg.header.frame_id,
            count,
            msg.point_step,
            [field.name for field in msg.fields],
            min(times) if times else None,
            max(times) if times else None,
            sorted(set(rings))[:20] if rings else [],
        ))

    def official_cb(self, msg):
        self.official.append(self.odom_tuple(msg))

    def pointlio_cb(self, msg):
        self.pointlio.append(self.odom_tuple(msg))

    @staticmethod
    def odom_tuple(msg):
        pos = msg.pose.pose.position
        vel = msg.twist.twist.linear
        return (
            stamp_sec(msg.header.stamp),
            pos.x, pos.y, pos.z,
            vel.x, vel.y, vel.z,
            msg.header.frame_id,
            msg.child_frame_id,
        )

def print_odom(label, data):
    print(f"\n{label}: count={len(data)}")
    if not data:
        return
    first = data[0]
    last = data[-1]
    dx = last[1] - first[1]
    dy = last[2] - first[2]
    dz = last[3] - first[3]
    dt = last[0] - first[0]
    dist = math.sqrt(dx * dx + dy * dy + dz * dz)
    print(f"  frame={last[7]} child={last[8]}")
    print(f"  first xyz=({first[1]:.4f}, {first[2]:.4f}, {first[3]:.4f})")
    print(f"  last  xyz=({last[1]:.4f}, {last[2]:.4f}, {last[3]:.4f})")
    print(f"  delta_dist={dist:.4f} m over {dt:.3f}s")
    print(f"  last linear_vel=({last[4]:.4f}, {last[5]:.4f}, {last[6]:.4f})")

rclpy.init()
node = Probe()
deadline = time.time() + sample_seconds
while time.time() < deadline:
    rclpy.spin_once(node, timeout_sec=0.1)

print(f"IMU: count={len(node.imu)}")
if node.imu:
    ax = [item[1] for item in node.imu]
    ay = [item[2] for item in node.imu]
    az = [item[3] for item in node.imu]
    gx = [item[4] for item in node.imu]
    gy = [item[5] for item in node.imu]
    gz = [item[6] for item in node.imu]
    norms = [math.sqrt(item[1] ** 2 + item[2] ** 2 + item[3] ** 2) for item in node.imu]
    print(f"  frame={node.imu[-1][7]}")
    print(f"  acc_mean=({statistics.mean(ax):.4f}, {statistics.mean(ay):.4f}, {statistics.mean(az):.4f})")
    print(f"  acc_norm_mean={statistics.mean(norms):.4f} std={statistics.pstdev(norms):.4f}")
    print(f"  gyro_mean=({statistics.mean(gx):.5f}, {statistics.mean(gy):.5f}, {statistics.mean(gz):.5f})")

print(f"\nCloud: count={len(node.cloud)}")
if node.cloud:
    cloud = node.cloud[-1]
    print(f"  frame={cloud[1]} points={cloud[2]} point_step={cloud[3]}")
    print(f"  fields={cloud[4]}")
    print(f"  sample_time_range=({cloud[5]}, {cloud[6]})")
    print(f"  sample_ring_values={cloud[7]}")

print_odom("Official /utlidar/robot_odom", node.official)
print_odom("Point-LIO /aft_mapped_to_init", node.pointlio)

node.destroy_node()
rclpy.shutdown()
PY
