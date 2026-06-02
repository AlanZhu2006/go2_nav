# Unitree Go2 MID360 Navigation Deployment

This repository is the working backup for our Unitree Go2 navigation deployment. It is not a full clone of the original NYUSH RM sentry stack. We reused useful structure from `nyush_rm_sentry`, but the current objective is narrower and practical:

```text
Unitree Go2 onboard computer
+ external Livox MID360
+ ROS 2 Foxy
+ FAST-LIO mapping/odometry
+ ICP map localization
+ Nav2
+ Go2 high-level SportClient.Move command bridge
```

The current tested control command sheet is:

```text
~/work/go2_nav/command.txt
```

The current deploy scripts and configs live under:

```text
~/work/nyush_rm_sentry/scripts
~/work/nyush_rm_sentry/config
```

The current map artifacts live under:

```text
~/work/go2_nav/maps/mid360_fastlio_latest
```

## Current Status

The current mainline is:

```text
MID360
  -> livox_ros_driver2
  -> FAST-LIO
  -> /Odometry and /cloud_registered_body
  -> ICP registration against saved FAST-LIO PCD
  -> map -> odom
  -> pointcloud_to_laserscan
  -> /scan
  -> Nav2 planner/controller
  -> /cmd_vel
  -> go2_cmd_bridge.py
  -> Unitree SportClient.Move(vx, vy, wz)
```

Known-good current settings:

```text
navigation base frame: livox_frame
odom topic: /Odometry
scan source cloud: /cloud_registered_body
scan target frame: livox_frame
map PCD: ~/work/go2_nav/maps/mid360_fastlio_latest/fastlio_map.pcd
Nav2 map: ~/work/go2_nav/maps/mid360_fastlio_latest/nav2_map/map.yaml
Go2 velocity limit: vx=0.30, vy=0.30, wz=0.70
remote priority: enabled
```

The most important practical lesson from debugging is:

```text
Do not let two localization nodes publish map -> odom.
If two icp_registration_node processes are alive, RViz scan/map will jitter.
Always run stop_mid360_fastlio_nav2.sh before starting the stack.
```

## Hardware And Network

Current robot:

```text
Robot: Unitree Go2
Computer: Go2 onboard Ubuntu 20.04 arm64
ROS: ROS 2 Foxy
External lidar: Livox MID360
Remote GUI: x11vnc/Xvfb/XFCE on :1
```

Current network layout:

| Interface | Address | Purpose |
| --- | --- | --- |
| `wlan0` | `10.209.69.61` | SSH and VNC from laptop |
| `eth0` | `192.168.123.18/24` | Unitree internal network |
| `eth0` | `192.168.1.2/24` | Host IP for MID360 |
| MID360 | `192.168.1.3` | Lidar IP |
| `eth1` | unused | USB dock Ethernet; do not use for MID360 |

We originally tried a USB dock Ethernet adapter for MID360. It produced transmit errors and unreliable communication. The stable connection is the Go2 native Ethernet path on `eth0`.

Check the network:

```bash
ip -br addr show eth0
ip route get 192.168.1.3
ping -I eth0 -c 3 192.168.1.3
```

Expected route:

```text
192.168.1.3 dev eth0 src 192.168.1.2
```

## Repository Layout

This GitHub backup was created from `~/work`, but it intentionally does not track all build products.

Important tracked paths:

```text
go2_nav/README.md
go2_nav/command.txt
go2_nav/maps/mid360_fastlio_latest/fastlio_map.pcd
go2_nav/maps/mid360_fastlio_latest/nav2_map/map.pgm
go2_nav/maps/mid360_fastlio_latest/nav2_map/map.yaml

nyush_rm_sentry/scripts/start_mid360_fastlio_mapping.sh
nyush_rm_sentry/scripts/save_mid360_fastlio_map.sh
nyush_rm_sentry/scripts/pcd2pgm_go2.sh
nyush_rm_sentry/scripts/start_mid360_start_robot_style.sh
nyush_rm_sentry/scripts/start_mid360_fastlio_nav2_with_rviz.sh
nyush_rm_sentry/scripts/stop_mid360_fastlio_nav2.sh
nyush_rm_sentry/scripts/go2_cmd_bridge.py
nyush_rm_sentry/scripts/keyboard_cmd_vel_debug.py
nyush_rm_sentry/scripts/start_go2_cmd_bridge_debug.sh

nyush_rm_sentry/config/go2_nav2_params_light.yaml
nyush_rm_sentry/config/go2_nav2_light.rviz
```

Large external build trees are not part of the intended backup:

```text
realsense_rsusb/
realsense_stack_clean/
realsense_stack_native/
nav_ws/build/
nav_ws/install/
ROS logs and temporary files
```

## Quick Start

Open a terminal on the Go2 computer:

```bash
ssh unitree@10.209.69.61
```

Open VNC from laptop:

```text
10.209.69.61:5901
```

Start localization and Nav2 without robot motion:

```bash
cd ~/work/nyush_rm_sentry
./scripts/stop_mid360_fastlio_nav2.sh

LOCALIZATION_MODE=icp \
START_NAVIGATION=true \
START_RVIZ=true \
START_GO2_CMD_BRIDGE=false \
NAV_BASE_FRAME=livox_frame \
NAV_ODOM_TOPIC=/Odometry \
ICP_PCD_FILE=~/work/go2_nav/maps/mid360_fastlio_latest/fastlio_map.pcd \
ICP_POINTCLOUD_TOPIC=/cloud_registered_body \
ICP_LASER_FRAME_ID=livox_frame \
ICP_RANGE_ODOM_FRAME_ID=odom \
ICP_ODOM_FRAME_ID=odom \
ICP_INITIAL_POSE_X=0.0 \
ICP_INITIAL_POSE_Y=0.0 \
ICP_INITIAL_POSE_YAW=0.0 \
ICP_THRESH=0.35 \
ICP_XY_OFFSET=0.75 \
ICP_XY_SEARCH_STEPS=3 \
ICP_YAW_OFFSET=180.0 \
ICP_YAW_RESOLUTION=15.0 \
SCAN_TARGET_FRAME=livox_frame \
SCAN_ANGLE_INCREMENT=0.0174533 \
SCAN_RANGE_MIN=0.30 \
SCAN_RANGE_MAX=8.0 \
SCAN_USE_INF=false \
SCAN_MIN_HEIGHT=0.20 \
SCAN_MAX_HEIGHT=1.80 \
SCAN_TRANSFORM_TOLERANCE=0.50 \
./scripts/start_mid360_start_robot_style.sh
```

After RViz shows stable map, scan, and odometry, start with robot motion:

```bash
cd ~/work/nyush_rm_sentry
./scripts/stop_mid360_fastlio_nav2.sh

LOCALIZATION_MODE=icp \
START_NAVIGATION=true \
START_RVIZ=true \
START_GO2_CMD_BRIDGE=true \
NAV2_BT_XML=/opt/ros/foxy/share/nav2_bt_navigator/behavior_trees/navigate_w_replanning_time.xml \
GO2_REMOTE_PRIORITY=true \
GO2_SEND_ZERO_WHEN_IDLE=false \
GO2_LOG_COMMANDS=true \
GO2_LOG_INTERVAL_SEC=0.3 \
GO2_MAX_VX=0.30 \
GO2_MAX_VY=0.30 \
GO2_MAX_WZ=0.70 \
NAV_BASE_FRAME=livox_frame \
NAV_ODOM_TOPIC=/Odometry \
ICP_PCD_FILE=~/work/go2_nav/maps/mid360_fastlio_latest/fastlio_map.pcd \
ICP_POINTCLOUD_TOPIC=/cloud_registered_body \
ICP_LASER_FRAME_ID=livox_frame \
ICP_RANGE_ODOM_FRAME_ID=odom \
ICP_ODOM_FRAME_ID=odom \
ICP_INITIAL_POSE_X=0.0 \
ICP_INITIAL_POSE_Y=0.0 \
ICP_INITIAL_POSE_YAW=0.0 \
ICP_THRESH=0.35 \
ICP_XY_OFFSET=0.75 \
ICP_XY_SEARCH_STEPS=3 \
ICP_YAW_OFFSET=180.0 \
ICP_YAW_RESOLUTION=15.0 \
SCAN_TARGET_FRAME=livox_frame \
SCAN_ANGLE_INCREMENT=0.0174533 \
SCAN_RANGE_MIN=0.30 \
SCAN_RANGE_MAX=8.0 \
SCAN_USE_INF=false \
SCAN_MIN_HEIGHT=0.20 \
SCAN_MAX_HEIGHT=1.80 \
SCAN_TRANSFORM_TOLERANCE=0.50 \
./scripts/start_mid360_start_robot_style.sh
```

Watch what is actually sent to the robot:

```bash
tail -f /tmp/mid360_fastlio_nav2/go2_cmd_bridge.log
```

Stop the stack:

```bash
cd ~/work/nyush_rm_sentry
./scripts/stop_mid360_fastlio_nav2.sh
```

Stop motion bridge only:

```bash
pkill -TERM -f '[/]go2_cmd_bridge.py'
```

## Mapping Workflow

### 1. Start FAST-LIO Mapping

```bash
cd ~/work/nyush_rm_sentry
./scripts/stop_mid360_fastlio_nav2.sh
START_RVIZ=true ./scripts/start_mid360_fastlio_mapping.sh
```

Interactive controls:

```text
1 + Enter  save map
s + Enter  show status
q + Enter  quit
```

Expected output:

```text
~/work/go2_nav/maps/mid360_fastlio_latest/fastlio_map.pcd
~/work/go2_nav/maps/mid360_fastlio_latest/fastlio_latest.pcd
```

### 2. Save FAST-LIO Map Manually

```bash
cd ~/work/nyush_rm_sentry
./scripts/save_mid360_fastlio_map.sh
ls -lh ~/work/go2_nav/maps/mid360_fastlio_latest/fastlio_map.pcd
```

### 3. Convert PCD To Nav2 Map

```bash
cd ~/work/nyush_rm_sentry

PCD_INPUT=~/work/go2_nav/maps/mid360_fastlio_latest/fastlio_map.pcd \
MAP_OUT_DIR=~/work/go2_nav/maps/mid360_fastlio_latest/nav2_map \
MAP_NAME=map \
MAP_RESOLUTION=0.05 \
PCD2PGM_FLAG_PASS_THROUGH=false \
PCD2PGM_Z_MIN=0.20 \
PCD2PGM_Z_MAX=1.80 \
PCD2PGM_RADIUS=0.15 \
PCD2PGM_POINT_COUNT=5 \
./scripts/pcd2pgm_go2.sh
```

Expected output:

```text
~/work/go2_nav/maps/mid360_fastlio_latest/nav2_map/map.pgm
~/work/go2_nav/maps/mid360_fastlio_latest/nav2_map/map.yaml
```

Current map files:

```text
fastlio_map.pcd: about 848 KB
nav2_map/map.pgm: about 35 KB
nav2_map/map.yaml: map metadata
```

## Navigation Architecture

### Frames

Current navigation uses `livox_frame` as the Nav2 base frame.

This is intentional. We tried injecting a lidar-to-dog-body yaw correction into the live Nav2 frame tree, but that made scan/map alignment worse. The FAST-LIO map is built in the lidar body frame, and ICP localization is most stable when the navigation base is also `livox_frame`.

Current frame chain:

```text
map
  -> odom               published by icp_registration
  -> livox_frame         published by FAST-LIO
```

`base_link` can still be used later for robot body display or command transform logic, but the current stable localization path does not require it.

### ICP Localization

ICP matches the live `/cloud_registered_body` against:

```text
~/work/go2_nav/maps/mid360_fastlio_latest/fastlio_map.pcd
```

Then it publishes:

```text
map -> odom
```

Important:

```text
Only one icp_registration_node may run at a time.
Two ICP nodes publish two map -> odom transforms, causing scan jitter.
```

Check:

```bash
pgrep -af icp_registration
```

If more than one node appears:

```bash
cd ~/work/nyush_rm_sentry
./scripts/stop_mid360_fastlio_nav2.sh
```

### LaserScan

Nav2 uses a 2D scan made from FAST-LIO body cloud:

```text
/cloud_registered_body -> pointcloud_to_laserscan -> /scan
```

Current scan settings:

```text
target_frame: livox_frame
angle_increment: 0.0174533
range_min: 0.30
range_max: 8.0
min_height: 0.20
max_height: 1.80
use_inf: false
transform_tolerance: 0.50
```

The PGM map conversion should use a compatible height range:

```text
PCD2PGM_Z_MIN=0.20
PCD2PGM_Z_MAX=1.80
```

If scan and map look impossible to align, first check whether mapping and runtime scan use different height slicing.

### Nav2

Current params:

```text
~/work/nyush_rm_sentry/config/go2_nav2_params_light.yaml
```

Important controller settings:

```text
controller_frequency: 10.0
max_vel_x: 0.30
min_vel_y: -0.30
max_vel_y: 0.30
max_vel_theta: 0.70
vy_samples: 7
```

We initially ran Go2 as pseudo-differential by setting `max_vel_y=0`. After keyboard testing, the robot responded well to:

```text
vx=0.30
vy=0.30
wz=0.70
```

So the current Nav2 config allows omnidirectional motion.

## Go2 Command Bridge

The bridge is:

```text
~/work/nyush_rm_sentry/scripts/go2_cmd_bridge.py
```

It subscribes to `/cmd_vel` and sends:

```text
SportClient.Move(vx, vy, wz)
```

Safety settings used in current full stack:

```text
GO2_REMOTE_PRIORITY=true
GO2_SEND_ZERO_WHEN_IDLE=false
GO2_LOG_COMMANDS=true
GO2_MAX_VX=0.30
GO2_MAX_VY=0.30
GO2_MAX_WZ=0.70
```

`GO2_REMOTE_PRIORITY=true` means remote controller input temporarily pauses the bridge. This is important during testing.

### Keyboard Bridge Test

Use this to test robot motion without Nav2:

```bash
cd ~/work/nyush_rm_sentry
./scripts/stop_mid360_fastlio_nav2.sh
./scripts/start_go2_cmd_bridge_debug.sh

source /opt/ros/foxy/setup.bash
source ~/nav_ws/install/setup.bash
source ~/work/nyush_rm_sentry/rm_navigation_ws/install/setup.bash
export RMW_IMPLEMENTATION=rmw_fastrtps_cpp
unset CYCLONEDDS_URI

./scripts/keyboard_cmd_vel_debug.py --vx 0.30 --vy 0.30 --wz 0.70 --latch
```

Keys:

```text
w/s      forward/back
a/d      left/right
q/e      positive/negative yaw
space/x  stop
Ctrl-C   exit
```

Watch actual commands:

```bash
tail -f /tmp/go2_cmd_bridge_debug.log
```

The `--latch` option means the last key command continues until another command or stop key is pressed. Keep your hand ready on space.

## VNC And RViz

Current VNC:

```text
10.209.69.61:5901
```

Check service:

```bash
systemctl --user status rviz-vnc.service --no-pager
tail -n 80 /tmp/rviz-vnc/x11vnc.log 2>/dev/null || true
```

RViz config:

```text
~/work/nyush_rm_sentry/config/go2_nav2_light.rviz
```

Keep RViz light on the Go2 computer. Heavy displays such as full PointCloud and full costmap can make Foxy/RViz slow and create misleading MessageFilter warnings.

Recommended displays:

```text
Map
LaserScan
Odom
TF when debugging only
GlobalPlan when testing goals
```

## Diagnostics

Source environment:

```bash
source /opt/ros/foxy/setup.bash
source ~/nav_ws/install/setup.bash
source ~/work/nyush_rm_sentry/rm_navigation_ws/install/setup.bash
```

Topic rates:

```bash
timeout 5 ros2 topic hz /livox/lidar
timeout 5 ros2 topic hz /livox/imu
timeout 5 ros2 topic hz /cloud_registered_body
timeout 5 ros2 topic hz /scan
timeout 5 ros2 topic hz /Odometry
timeout 5 ros2 topic hz /cmd_vel
```

TF:

```bash
ros2 run tf2_ros tf2_echo odom livox_frame
ros2 run tf2_ros tf2_echo map livox_frame
```

Lifecycle:

```bash
ros2 lifecycle get /map_server
ros2 lifecycle get /controller_server
ros2 lifecycle get /planner_server
ros2 lifecycle get /bt_navigator
```

Process check:

```bash
pgrep -af 'livox_ros_driver2|fastlio_mapping|pointcloud_to_laserscan|icp_registration|nav2|rviz2|go2_cmd_bridge'
```

Logs:

```bash
tail -n 120 /tmp/mid360_fastlio_nav2/livox_driver.log 2>/dev/null || true
tail -n 120 /tmp/mid360_fastlio_nav2/fastlio_mapping.log 2>/dev/null || true
tail -n 120 /tmp/mid360_fastlio_nav2/icp_registration.log 2>/dev/null || true
tail -n 120 /tmp/mid360_fastlio_nav2/go2_cmd_bridge.log 2>/dev/null || true
```

## What We Tried

### Go2 Built-In Lidar Official Topics

We inspected and tested:

```text
/utlidar/cloud
/utlidar/cloud_base
/utlidar/cloud_deskewed
/utlidar/robot_odom
/utlidar/robot_pose
/uslam/cloud_map
/lio_sam_ros2/mapping/*
```

The official topics exist, but the useful full global map topics/services were not reliable enough for our current navigation workflow. Saving one frame or accumulated deskewed clouds gave sparse or over-dark PGM maps. This route is kept as reference, not the current mainline.

### Point-LIO With Go2 Built-In Lidar

We tried using Go2 built-in `/utlidar/cloud` and `/utlidar/imu` with Point-LIO and compared against `unitreerobotics/point_lio_unilidar`. The result was unstable:

```text
stationary looks acceptable briefly
motion causes frame to fly
acc_norm tuning changes the symptom but does not solve it
```

The likely cause is mismatch between Go2 official processed lidar/IMU topics and the raw Unitree L1 assumptions expected by Point-LIO.

### go2_ros2_sdk + slam_toolbox

We reproduced a minimal `go2_ros2_sdk`-style route:

```text
Go2 SDK point cloud
-> pointcloud_to_laserscan
-> slam_toolbox
-> Nav2
```

It was useful as a reference, especially for command bridging and Go2 high-level control, but map quality was not better than the MID360 route.

### RealSense D435i

We also tested RealSense D435i for possible FAST-LIVO/visual mapping. Current conclusion:

```text
RealSense is not part of the navigation mainline.
```

Findings:

```text
RSUSB clean stack can publish some profiles sometimes.
Native backend on Jetson can fail at VIDIOC_S_FMT.
Depth/color profile support is sensitive to firmware/backend/USB topology.
```

Until RealSense passes stable 30-60 minute streaming tests, it should not be included in the navigation startup path.

## Known Problems And Fixes

### Scan jitters or map alignment jumps

Most likely:

```text
two ICP nodes are publishing map -> odom
```

Fix:

```bash
cd ~/work/nyush_rm_sentry
./scripts/stop_mid360_fastlio_nav2.sh
pgrep -af icp_registration
```

Expected after stop:

```text
no icp_registration_node
```

### Remote controller is being overridden

Use:

```text
GO2_REMOTE_PRIORITY=true
```

Or stop the bridge:

```bash
pkill -TERM -f '[/]go2_cmd_bridge.py'
```

### RViz says no TF data

Check:

```bash
ros2 run tf2_ros tf2_echo odom livox_frame
ros2 run tf2_ros tf2_echo map livox_frame
pgrep -af icp_registration
```

If `map -> livox_frame` is missing, ICP did not publish `map -> odom` yet or multiple localization nodes are conflicting.

### Nav2 gives path but robot does not move

Check `/cmd_vel`:

```bash
timeout 5 ros2 topic hz /cmd_vel
ros2 topic echo /cmd_vel
```

Check bridge:

```bash
tail -f /tmp/mid360_fastlio_nav2/go2_cmd_bridge.log
```

If `/cmd_vel` exists but no `Move(...)` log appears, the bridge is not running or is subscribed to the wrong topic.

### Robot moves with keyboard but not Nav2

Then the command bridge is fine. Check Nav2 controller output, goal validity, costmaps, and whether Nav2 is choosing only tiny angular commands.

### ROS2 CLI shows `bad_alloc`

This happened several times on Foxy/Jetson under high load. It did not always mean true OOM. Reduce RViz displays and avoid launching duplicate heavy nodes.

## Git Backup

The current backup repository is:

```text
git@github.com:AlanZhu2006/go2_nav.git
```

Local root:

```text
~/work
```

Check sync:

```bash
cd ~/work
git status --short --branch
git log --oneline --decorate -3
git ls-remote origin refs/heads/main
```

Commit and push updates:

```bash
cd ~/work
git add -A
git commit -m "Update Go2 navigation deployment"
git push origin main
```

The initial backup commit was:

```text
42ae1a1 Initial Go2 navigation backup
```

## Current Next Steps

1. Keep using the MID360 FAST-LIO + ICP + Nav2 route as the mainline.
2. Run with `START_GO2_CMD_BRIDGE=false` first after every map/config change.
3. Verify exactly one ICP process before trusting RViz alignment.
4. Only enable the Go2 motion bridge after map/scan/TF look stable.
5. Tune Nav2 controller and footprint conservatively after repeated low-speed tests.
6. Keep RealSense and Point-LIO as research branches, not blockers for the current navigation loop.
