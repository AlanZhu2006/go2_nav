# Unitree Go2 + MID360 Nav2 Deployment Notes

Last updated: 2026-06-03

This directory is the main working record for the current Unitree Go2 navigation deployment. The repository is not a clean copy of `nyush_rm_sentry`; instead, `go2_nav` is the Go2 navigation project record, while `~/work/nyush_rm_sentry` is currently used as a practical script/config workspace borrowed from another project.

The most important files are:

```text
~/work/go2_nav/README.md
~/work/go2_nav/command.txt
~/work/go2_nav/env.sh
~/work/go2_nav/maps/mid360_fastlio_latest

~/work/nyush_rm_sentry/scripts/start_mid360_start_robot_style.sh
~/work/nyush_rm_sentry/scripts/start_mid360_fastlio_nav2_with_rviz.sh
~/work/nyush_rm_sentry/scripts/stop_mid360_fastlio_nav2.sh
~/work/nyush_rm_sentry/scripts/go2_cmd_bridge.py
~/work/nyush_rm_sentry/scripts/republish_odom_base_link.py

~/work/nyush_rm_sentry/config/go2_nav2_params_head_forward.yaml
~/work/nyush_rm_sentry/config/go2_nav2_base_link.rviz
```

`command.txt` remains the copy-paste command sheet. This README explains what those commands are doing, why the current parameters are shaped this way, and what we changed during recent debugging.

## Current Recommended Stack

The current recommended stack is:

```text
Livox MID360
  -> livox_ros_driver2
  -> FAST-LIO
  -> /Odometry and /cloud_registered_body
  -> ICP registration against saved FAST-LIO PCD
  -> map -> odom
  -> static livox_frame -> base_link yaw +90 deg
  -> republish /Odometry as /odom_base_link
  -> pointcloud_to_laserscan in base_link
  -> /scan
  -> Nav2 with robot_base_frame=base_link
  -> /cmd_vel
  -> go2_cmd_bridge.py
  -> Unitree SportClient.Move(vx, vy, wz)
```

The current preferred model is the `head-forward` model:

```text
Nav2 robot_base_frame: base_link
Nav2 odom_topic:      /odom_base_link
Scan target frame:    base_link
Lidar body frame:     livox_frame
Lidar -> base yaw:    +90 deg
Go2 bridge mapping:   no vx/vy swap
Go2 lateral speed:    GO2_MAX_VY=0.00
```

This replaced the earlier temporary model:

```text
Nav2 robot_base_frame: livox_frame
Nav2 odom_topic:      /Odometry
Scan target frame:    livox_frame
Go2 bridge mapping:   swap vx/vy and rotate command by 90 deg
```

The old `livox_frame` model was useful to get the first closed loop running, but it made Nav2 reason in the lidar/body frame and then patched the velocity at the last step. The current `base_link/head-forward` model is cleaner because Nav2 now plans in the robot body frame.

## Hardware And Network

Current hardware:

```text
Robot:        Unitree Go2
Computer:     Go2 onboard Ubuntu 20.04 arm64 computer
ROS:          ROS 2 Foxy
External lidar: Livox MID360
Remote GUI:   Xvfb + x11vnc + XFCE on DISPLAY=:1
VNC port:     5901
```

Current network:

| Interface | Address | Purpose |
| --- | --- | --- |
| `wlan0` | `10.209.69.61` | SSH and VNC from laptop |
| `eth0` | `192.168.123.18/24` | Unitree internal network |
| `eth0` | `192.168.1.2/24` | MID360 host address |
| MID360 | `192.168.1.3` | Lidar address |
| `eth1` | unused | USB ethernet adapter; no longer used for MID360 |

We tried the USB ethernet adapter for MID360 earlier, but it showed TX errors, unstable route behavior, and unreliable ping. The stable choice is to use Go2's native `eth0`, with both Unitree internal network and MID360 subnet on the same interface.

Basic network check:

```bash
ip -br addr show eth0
ip route get 192.168.1.3
ping -I eth0 -c 3 192.168.1.3
```

Expected route:

```text
192.168.1.3 dev eth0 src 192.168.1.2
```

## Shell Environment

Use:

```bash
source ~/work/go2_nav/env.sh
```

This loads the Foxy/navigation environment and forces ROS 2 tooling to use FastDDS/FastRTPS:

```text
RMW_IMPLEMENTATION=rmw_fastrtps_cpp
CYCLONEDDS_URI unset
CYCLONEDDS_HOME unset
DISPLAY=:1
```

Why this matters:

```text
ROS 2 Foxy CLI/Nav2/FAST-LIO/ICP should use rmw_fastrtps_cpp on this machine.
Unitree SportClient internally needs CycloneDDS libraries for the Go2 SDK path.
Those are separate concerns.
```

We previously had a `~/.bashrc` fishros block that defaulted Foxy terminals to `rmw_cyclonedds_cpp` and exported `CYCLONEDDS_HOME`. That caused confusing behavior where the navigation stack used FastDDS but diagnostic terminals used CycloneDDS. `~/.bashrc` has now been adjusted to automatically source:

```text
~/work/go2_nav/env.sh
```

New terminals should therefore default to FastDDS and `DISPLAY=:1`. To opt out and use the old ROS chooser:

```bash
GO2_NAV_AUTO_ENV=0 bash
```

## Quick Start: Safe Head-Forward Test

Always stop the old stack first:

```bash
cd ~/work/nyush_rm_sentry
./scripts/stop_mid360_fastlio_nav2.sh
```

First run without Go2 motion:

```bash
cd ~/work/nyush_rm_sentry
./scripts/stop_mid360_fastlio_nav2.sh

LOCALIZATION_MODE=icp \
START_NAVIGATION=true \
START_RVIZ=true \
START_GO2_CMD_BRIDGE=false \
NAV2_PARAMS_FILE=~/work/nyush_rm_sentry/config/go2_nav2_params_head_forward.yaml \
RVIZ_CONFIG=~/work/nyush_rm_sentry/config/go2_nav2_base_link.rviz \
NAV_BASE_FRAME=base_link \
FASTLIO_ODOM_TOPIC=/Odometry \
NAV_ODOM_TOPIC=/odom_base_link \
LIDAR_TO_BASE_YAW_DEG=90 \
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
SCAN_TARGET_FRAME=base_link \
SCAN_ANGLE_INCREMENT=0.0174533 \
SCAN_RANGE_MIN=0.30 \
SCAN_RANGE_MAX=8.0 \
SCAN_USE_INF=false \
SCAN_MIN_HEIGHT=0.20 \
SCAN_MAX_HEIGHT=1.50 \
SCAN_TRANSFORM_TOLERANCE=0.50 \
./scripts/start_mid360_start_robot_style.sh
```

Check RViz:

```text
Fixed Frame = map
Map visible
LaserScan aligns with map
Odom display topic = /odom_base_link
GlobalPlan looks sane after sending a goal
No Go2 movement because START_GO2_CMD_BRIDGE=false
```

Only after RViz alignment is sane, enable Go2 motion:

```bash
cd ~/work/nyush_rm_sentry
./scripts/stop_mid360_fastlio_nav2.sh

LOCALIZATION_MODE=icp \
START_NAVIGATION=true \
START_RVIZ=true \
START_GO2_CMD_BRIDGE=true \
NAV2_BT_XML=/opt/ros/foxy/share/nav2_bt_navigator/behavior_trees/navigate_w_replanning_time.xml \
NAV2_PARAMS_FILE=~/work/nyush_rm_sentry/config/go2_nav2_params_head_forward.yaml \
RVIZ_CONFIG=~/work/nyush_rm_sentry/config/go2_nav2_base_link.rviz \
GO2_REMOTE_PRIORITY=true \
GO2_SEND_ZERO_WHEN_IDLE=false \
GO2_LOG_COMMANDS=true \
GO2_LOG_INTERVAL_SEC=0.3 \
GO2_MAX_VX=0.30 \
GO2_MAX_VY=0.00 \
GO2_MAX_WZ=0.70 \
GO2_DEADBAND_V=0.02 \
GO2_DEADBAND_W=0.04 \
GO2_MIN_CMD_V=0.10 \
GO2_MIN_CMD_W=0.20 \
GO2_SWAP_XY=false \
GO2_X_SIGN=1.0 \
GO2_Y_SIGN=1.0 \
GO2_WZ_SIGN=1.0 \
NAV_BASE_FRAME=base_link \
FASTLIO_ODOM_TOPIC=/Odometry \
NAV_ODOM_TOPIC=/odom_base_link \
LIDAR_TO_BASE_YAW_DEG=90 \
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
SCAN_TARGET_FRAME=base_link \
SCAN_ANGLE_INCREMENT=0.0174533 \
SCAN_RANGE_MIN=0.30 \
SCAN_RANGE_MAX=8.0 \
SCAN_USE_INF=false \
SCAN_MIN_HEIGHT=0.20 \
SCAN_MAX_HEIGHT=1.50 \
SCAN_TRANSFORM_TOLERANCE=0.50 \
./scripts/start_mid360_start_robot_style.sh
```

Watch Go2 commands:

```bash
tail -f /tmp/mid360_fastlio_nav2/go2_cmd_bridge.log
```

Stop everything:

```bash
cd ~/work/nyush_rm_sentry
./scripts/stop_mid360_fastlio_nav2.sh
```

Emergency stop only the motion bridge:

```bash
pkill -TERM -f '[/]go2_cmd_bridge.py'
```

## Map Files

Current map directory:

```text
~/work/go2_nav/maps/mid360_fastlio_latest
```

Important files:

```text
fastlio_map.pcd
fastlio_latest.pcd -> fastlio_map.pcd
fastlio_map_icp_z020_150.pcd
fastlio_map_icp_zm020_150.pcd
nav2_map/map.yaml
nav2_map/map.pgm
nav2_map/pcd2pgm_go2.yaml
```

Current recommendation:

```text
Nav2 map_server:
  ~/work/go2_nav/maps/mid360_fastlio_latest/nav2_map/map.yaml

ICP registration:
  ~/work/go2_nav/maps/mid360_fastlio_latest/fastlio_map.pcd
```

Earlier we generated filtered PCDs for ICP:

```text
fastlio_map_icp_z020_150.pcd
fastlio_map_icp_zm020_150.pcd
```

However, a 2026-06-02 ICP sweep showed the filtered PCD was not reliable at the current site, while the raw `fastlio_map.pcd` produced the best score then. Keep the filtered PCDs as experiments, not the current default.

## Mapping Workflow

Start MID360 FAST-LIO mapping:

```bash
cd ~/work/nyush_rm_sentry
./scripts/stop_mid360_fastlio_nav2.sh

START_RVIZ=true ./scripts/start_mid360_fastlio_mapping.sh
```

Interactive prompt:

```text
1 + Enter  save FAST-LIO PCD
s + Enter  show status
q + Enter  quit
```

Expected output:

```text
~/work/go2_nav/maps/mid360_fastlio_latest/fastlio_map.pcd
~/work/go2_nav/maps/mid360_fastlio_latest/fastlio_latest.pcd
```

Manual save:

```bash
cd ~/work/nyush_rm_sentry
./scripts/save_mid360_fastlio_map.sh
ls -lh ~/work/go2_nav/maps/mid360_fastlio_latest/fastlio_map.pcd
```

Convert FAST-LIO PCD into Nav2 PGM/YAML:

```bash
cd ~/work/nyush_rm_sentry

PCD_INPUT=~/work/go2_nav/maps/mid360_fastlio_latest/fastlio_map.pcd \
MAP_OUT_DIR=~/work/go2_nav/maps/mid360_fastlio_latest/nav2_map \
MAP_NAME=map \
MAP_RESOLUTION=0.05 \
PCD2PGM_FLAG_PASS_THROUGH=false \
PCD2PGM_Z_MIN=0.20 \
PCD2PGM_Z_MAX=1.50 \
PCD2PGM_RADIUS=0.15 \
PCD2PGM_POINT_COUNT=5 \
./scripts/pcd2pgm_go2.sh
```

Height filtering matters. The MID360 point cloud can include ground, ceiling, furniture, brackets, and stray long-range points. Too wide a Z range projects junk into the 2D map; too narrow a Z range makes walls sparse.

## Coordinate Frames

The important frames are:

```text
map
  -> odom                         published by icp_registration
    -> livox_frame                published by FAST-LIO
      -> base_link                static yaw +90 deg
```

Current static transform:

```text
livox_frame -> base_link
xyz = (0, 0, 0)
rpy = (0, 0, +90 deg)
```

In Foxy `static_transform_publisher`, the script passes arguments in yaw/pitch/roll order for this usage. The startup script handles:

```text
LIDAR_TO_BASE_YAW_DEG=90
```

### Why `/odom_base_link` Exists

FAST-LIO publishes `/Odometry`, but that odometry describes the FAST-LIO body/lidar frame, effectively:

```text
header.frame_id = odom
child_frame_id = livox_frame
pose = odom -> livox_frame
```

RViz's `Odometry` display does not automatically draw `odom -> base_link` just because TF can compose it. It draws the pose carried by the selected `nav_msgs/Odometry` topic.

Therefore, for the head-forward model we add:

```text
/Odometry          original FAST-LIO odom for livox_frame
/odom_base_link    republished odom whose pose is odom -> base_link
```

The republisher is:

```text
~/work/nyush_rm_sentry/scripts/republish_odom_base_link.py
```

The startup script launches it automatically when:

```text
NAV_BASE_FRAME != FASTLIO_BODY_FRAME
NAV_ODOM_TOPIC != FASTLIO_ODOM_TOPIC
```

Current command uses:

```text
FASTLIO_ODOM_TOPIC=/Odometry
NAV_ODOM_TOPIC=/odom_base_link
NAV_BASE_FRAME=base_link
```

RViz config:

```text
~/work/nyush_rm_sentry/config/go2_nav2_base_link.rviz
```

In that RViz config, the red `Odom` display subscribes to:

```text
/odom_base_link
```

This was added because we initially changed Nav2 to `base_link`, but RViz still showed the old `/Odometry` arrow. That made it look like nothing had changed. The actual issue was that the RViz `Odometry` display topic and Nav2 odom topic had to be changed separately.

## ICP Localization

The ICP node:

```text
~/work/nyush_rm_sentry/rm_navigation_ws/src/rm_localization/icp_registration
```

Current runtime config is generated at:

```text
/tmp/mid360_fastlio_nav2/icp_registration_runtime.yaml
```

Important current parameters:

```text
pcd_path:              ~/work/go2_nav/maps/mid360_fastlio_latest/fastlio_map.pcd
pointcloud_topic:      /cloud_registered_body
map_frame_id:          map
odom_frame_id:         odom
range_odom_frame_id:   odom
laser_frame_id:        livox_frame
thresh:                0.35
xy_offset:             0.75
xy_search_steps:       3
yaw_offset:            180.0 deg
yaw_resolution:        15.0 deg
initial_pose:          [0, 0, 0, 0, 0, 0]
```

The ICP node publishes:

```text
map -> odom
```

It receives current geometry from:

```text
/cloud_registered_body
```

It receives manual relocalization triggers from:

```text
/initialpose
```

### 2026-06-03 ICP Bug And Fix

We hit a recurring issue where RViz showed scan/map misalignment, and ICP score was much worse than previous good runs.

Observed before the fix:

```text
score: 0.179041
score after retriggering /initialpose: 0.180563
score after stack restart: 0.156628
```

This was not just a stale RViz display. The score was genuinely high and the TF yaw was wrong. One observed bad TF was:

```text
map -> base_link yaw ~= 131.4 deg
```

The old code had two search-window problems:

```text
ICP_XY_SEARCH_STEPS was declared in runtime YAML but ignored in C++.
The code always searched only i,j = -1..1.

ICP_YAW_OFFSET was converted from degrees to radians, then used as an int loop bound.
With ICP_YAW_OFFSET=180 deg, the actual loop searched only about +/-45 deg.
```

The relevant broken loop was logically:

```cpp
for (int i = -1; i <= 1; i++) {
  for (int j = -1; j <= 1; j++) {
    for (int k = -yaw_offset_; k <= yaw_offset_; k++) {
      yaw = initial_yaw + k * yaw_resolution_;
    }
  }
}
```

Now it uses the real configured search window:

```text
xy_steps = ICP_XY_SEARCH_STEPS
yaw_steps = ceil(yaw_offset / yaw_resolution)
```

After rebuilding `icp_registration`, the log shows:

```text
search window: xy_steps=3 xy_offset=0.750 yaw_steps=12 yaw_resolution=0.262 rad
align used: 70419.312253 ms
score: 0.032467
```

The first search is now slower, around 70 seconds in the observed run, because it actually searches:

```text
xy candidates: 7 x 7
yaw candidates: 25
total rough candidates: 1225
```

This is slower but much safer than accepting the wrong yaw. After the fix, observed TF was:

```text
map -> odom:      xyz=(2.989, 2.291, -0.350) yaw=-104.9 deg
odom -> base_link xyz=(-0.029, -0.027, -0.027) yaw=90.0 deg
map -> base_link: xyz=(2.969, 2.321, -0.381) yaw=-14.9 deg
```

This matched RViz much better.

Build command used after the fix:

```bash
source ~/work/go2_nav/env.sh
cd ~/work/nyush_rm_sentry/rm_navigation_ws
colcon build --symlink-install --packages-select icp_registration
```

### ICP Score Interpretation

Use ICP score as a warning signal:

```text
~0.003   excellent; seen in an earlier good sweep
~0.03    acceptable/current after search-window fix
~0.15+   suspicious; likely wrong alignment or weak geometry
~0.35+   above current threshold; should fail
```

Current threshold is still:

```text
ICP_THRESH=0.35
```

This threshold is intentionally loose enough to avoid startup failure, but the practical warning threshold should be much lower. If score is `0.15` or worse, do not trust navigation even if the node says it succeeded.

Check the score:

```bash
tail -n 120 /tmp/mid360_fastlio_nav2/icp_registration.log
```

Look for:

```text
search window: ...
score: ...
```

## Nav2 Controller And Costmap

Current head-forward parameter file:

```text
~/work/nyush_rm_sentry/config/go2_nav2_params_head_forward.yaml
```

The head-forward DWB model treats Go2 more like a pseudo-differential robot:

```text
min_vel_x: 0.0
min_vel_y: 0.0
max_vel_x: 0.30
max_vel_y: 0.0
max_vel_theta: 0.70
vy_samples: 1
```

This avoids Nav2 planning sideways motion once it is working in `base_link`.

### Go2 Footprint And Wall Clearance

We found that Go2 would try to pass through spaces that the lidar/2D map considered open but the body/legs could hit. The fix is to give Nav2 a larger robot footprint and stronger inflation.

Current local/global costmap footprint:

```yaml
footprint: "[[0.45, 0.30], [0.45, -0.30], [-0.45, -0.30], [-0.45, 0.30]]"
footprint_padding: 0.08
```

Meaning:

```text
nominal planning body length: 0.90 m
nominal planning body width:  0.60 m
extra safety padding:         0.08 m
```

Current inflation:

```yaml
cost_scaling_factor: 3.0
inflation_radius: 0.75
```

Current DWB obstacle critic:

```yaml
BaseObstacle.scale: 0.08
```

This is deliberately conservative. Go2 static width is smaller than this, but a walking quadruped has leg swing, body sway, and recovery motion. It should not plan like a perfectly rigid small circle.

If it becomes too conservative and refuses a passage that is physically safe, tune down in this order:

```yaml
footprint_padding: 0.05
inflation_radius: 0.60
cost_scaling_factor: 4.0
BaseObstacle.scale: 0.05
```

Do not shrink the footprint first unless the physical clearance has been measured.

## Go2 Command Bridge

Bridge script:

```text
~/work/nyush_rm_sentry/scripts/go2_cmd_bridge.py
```

Input:

```text
/cmd_vel
```

Output:

```text
Unitree SportClient.Move(vx, vy, wz)
```

Current head-forward motion parameters:

```text
GO2_MAX_VX=0.30
GO2_MAX_VY=0.00
GO2_MAX_WZ=0.70
GO2_SWAP_XY=false
GO2_X_SIGN=1.0
GO2_Y_SIGN=1.0
GO2_WZ_SIGN=1.0
```

Earlier, when Nav2 ran in `livox_frame`, the Go2 command bridge had to rotate Nav2 velocity commands:

```text
GO2_SWAP_XY=true
GO2_X_SIGN=1.0
GO2_Y_SIGN=-1.0
```

That old mapping meant:

```text
vx_go2 =  vy_nav
vy_go2 = -vx_nav
wz_go2 =  wz_nav
```

In the current `base_link/head-forward` model, this swap is no longer needed.

### Go2 Deadband And Minimum Command

Go2 high-level `Move()` behaves differently from a wheeled chassis. Very small speed commands often make the body sway or prepare gait without actually stepping. We therefore added command floors:

```text
GO2_DEADBAND_V=0.02
GO2_DEADBAND_W=0.04
GO2_MIN_CMD_V=0.10
GO2_MIN_CMD_W=0.20
```

Meaning:

```text
abs(command) < deadband:
  send 0

deadband <= abs(command) < min_cmd:
  lift to min_cmd with same sign
```

This reduces the "hesitate in place" behavior where Nav2 keeps outputting tiny commands that do not make Go2 step.

If movement is too abrupt near the goal:

```text
GO2_MIN_CMD_V=0.08
GO2_MIN_CMD_W=0.15
```

If Go2 still only sways and does not step:

```text
GO2_MIN_CMD_V=0.12
GO2_MIN_CMD_W=0.25
```

### Remote Priority

Keep this on:

```text
GO2_REMOTE_PRIORITY=true
```

If the remote controller input exceeds the configured deadband, the bridge releases Nav2 control so the remote can take over.

## Keyboard Debug

This tests only:

```text
/cmd_vel -> go2_cmd_bridge.py -> SportClient.Move()
```

It does not require Nav2.

```bash
cd ~/work/nyush_rm_sentry
./scripts/stop_mid360_fastlio_nav2.sh
./scripts/start_go2_cmd_bridge_debug.sh

source ~/work/go2_nav/env.sh

./scripts/keyboard_cmd_vel_debug.py --vx 0.30 --vy 0.30 --wz 0.70 --latch
```

Keys:

```text
w/s      forward/back
a/d      left/right
q/e      positive/negative angular velocity
space/x  stop
```

Watch bridge output:

```bash
tail -f /tmp/go2_cmd_bridge_debug.log
```

If keyboard works but Nav2 does not, the Unitree command bridge is probably not the problem. Check Nav2 planner/controller/costmap/goal.

## VNC, RViz, And Screenshots

VNC:

```text
10.209.69.61:5901
DISPLAY=:1
```

Current RViz config:

```text
~/work/nyush_rm_sentry/config/go2_nav2_base_link.rviz
```

Useful RViz display items:

```text
Map
LaserScan
Odom
GlobalPlan
TF
LocalCostmap / GlobalCostmap only when actively debugging
```

Do not leave heavy point cloud displays enabled for long periods on the Jetson.

We saw a paste-image failure:

```text
clipboard unavailable
Unknown error while interacting with the clipboard: X11 server connection timed out
```

The X server itself was verified good:

```text
Xvfb :1 running
x11vnc :5901 running
xdpyinfo -display :1 works
RViz running on :1
```

The practical fix was to make `env.sh` set:

```text
DISPLAY=:1
```

If a terminal still has no display:

```bash
source ~/work/go2_nav/env.sh
echo $DISPLAY
xdpyinfo -display :1 | head
```

Clipboard paste may still depend on the client UI. For reliable sharing, save a screenshot file and upload it rather than relying on clipboard paste.

## Diagnostics

Load environment:

```bash
source ~/work/go2_nav/env.sh
```

Topic list:

```bash
ros2 topic list -t | grep -E 'livox|cloud|scan|odom|Odometry|tf|map|cmd_vel'
```

Key topic frequencies:

```bash
timeout 5 ros2 topic hz /livox/lidar
timeout 5 ros2 topic hz /livox/imu
timeout 5 ros2 topic hz /cloud_registered_body
timeout 5 ros2 topic hz /scan
timeout 5 ros2 topic hz /Odometry
timeout 5 ros2 topic hz /odom_base_link
timeout 5 ros2 topic hz /cmd_vel
```

ROS 2 CLI on this machine can still print:

```text
bad_alloc caught: std::bad_alloc
```

Do not immediately conclude that the robot is out of memory or that a node died. We have seen this from Foxy CLI under load. Cross-check with RViz, logs, and process list.

TF checks:

```bash
ros2 run tf2_ros tf2_echo map odom
ros2 run tf2_ros tf2_echo odom livox_frame
ros2 run tf2_ros tf2_echo odom base_link
ros2 run tf2_ros tf2_echo livox_frame base_link
ros2 run tf2_ros tf2_echo map base_link
```

Expected static relation:

```text
odom -> base_link yaw ~= +90 deg relative to odom -> livox_frame
livox_frame -> base_link yaw ~= +90 deg
```

After the ICP search-window fix, one observed good-ish run had:

```text
map->odom:      xyz=(2.989, 2.291, -0.350) yaw=-104.9 deg
odom->base_link xyz=(-0.029, -0.027, -0.027) yaw=90.0 deg
map->base_link xyz=(2.969, 2.321, -0.381) yaw=-14.9 deg
ICP score: 0.032467
```

Lifecycle:

```bash
ros2 lifecycle get /map_server
ros2 lifecycle get /controller_server
ros2 lifecycle get /planner_server
ros2 lifecycle get /bt_navigator
```

Processes:

```bash
pgrep -af 'livox_ros_driver2|fastlio_mapping|pointcloud_to_laserscan|icp_registration|nav2|rviz2|go2_cmd_bridge'
```

Logs:

```bash
tail -n 120 /tmp/mid360_fastlio_nav2/livox_driver.log 2>/dev/null || true
tail -n 120 /tmp/mid360_fastlio_nav2/fastlio_mapping.log 2>/dev/null || true
tail -n 120 /tmp/mid360_fastlio_nav2/icp_registration.log 2>/dev/null || true
tail -n 120 /tmp/mid360_fastlio_nav2/odom_base_link.log 2>/dev/null || true
tail -n 120 /tmp/mid360_fastlio_nav2/pointcloud_to_laserscan.log 2>/dev/null || true
tail -n 120 /tmp/mid360_fastlio_nav2/go2_cmd_bridge.log 2>/dev/null || true
```

## Common Failure Modes

### Two ICP Nodes

Symptom:

```text
scan/map jitters
map alignment appears to jump
RViz looks like localization is unstable
```

Cause:

```text
two localization nodes publish map -> odom
```

Fix:

```bash
cd ~/work/nyush_rm_sentry
./scripts/stop_mid360_fastlio_nav2.sh
pgrep -af icp_registration
```

There should be no old `icp_registration_node` before restarting.

### ICP Score Is High But Node "Succeeds"

Symptom:

```text
score around 0.15 to 0.18
scan and map visibly rotated or offset
Nav2 still starts because threshold is 0.35
```

Fix status:

```text
The search-window C++ bug has been fixed and rebuilt.
If this returns, first confirm the log contains:
  search window: xy_steps=3 ... yaw_steps=12 ...
```

If the log does not show `search window`, the running binary is old. Rebuild:

```bash
source ~/work/go2_nav/env.sh
cd ~/work/nyush_rm_sentry/rm_navigation_ws
colcon build --symlink-install --packages-select icp_registration
```

Then restart the stack.

### RViz Odom Arrow Did Not Change

Symptom:

```text
You switched Nav2 to base_link but the red Odom arrow looks unchanged.
```

Cause:

```text
RViz Odometry display still subscribes to /Odometry.
/Odometry is FAST-LIO's livox_frame odom.
```

Fix:

```text
Use go2_nav2_base_link.rviz.
Odom display topic must be /odom_base_link.
```

### Nav2 Thinks It Can Pass But Go2 Hits Wall

Cause:

```text
Robot footprint / inflation too small.
Legged robot needs more clearance than the static body width.
```

Current fix:

```text
head_forward footprint = 0.90 m x 0.60 m
padding = 0.08 m
inflation_radius = 0.75 m
BaseObstacle.scale = 0.08
```

If still too close to walls, increase:

```text
footprint_padding
inflation_radius
BaseObstacle.scale
```

If it refuses real openings, reduce only after measuring physical clearance.

### Go2 Hesitates Before Walking

Cause:

```text
Nav2 emits small nonzero velocities.
Go2 high-level gait may not step below a practical speed floor.
```

Current fix:

```text
GO2_DEADBAND_V=0.02
GO2_DEADBAND_W=0.04
GO2_MIN_CMD_V=0.10
GO2_MIN_CMD_W=0.20
```

### Direction Is Rotated 90 Degrees

Old temporary solution:

```text
Run Nav2 in livox_frame and rotate vx/vy in bridge.
```

Current solution:

```text
Run Nav2 in base_link.
Use /odom_base_link.
Use LIDAR_TO_BASE_YAW_DEG=90.
Do not swap vx/vy in Go2 bridge.
```

### ROS 2 CLI `bad_alloc`

We saw this repeatedly:

```text
bad_alloc caught: std::bad_alloc
```

It appeared in `ros2 topic hz`, `ros2 topic echo`, and sometimes logs from launch processes. It does not always mean the process is dead. Use these checks together:

```text
RViz visual refresh
process list
node info
log timestamps
custom Python subscriber if CLI fails
```

Also reduce RViz load where possible.

## Routes We Tried And Parked

### Go2 Built-In Lidar Official Topics

Observed topics included:

```text
/utlidar/cloud
/utlidar/cloud_base
/utlidar/cloud_deskewed
/utlidar/robot_odom
/utlidar/robot_pose
/uslam/cloud_map
/lio_sam_ros2/mapping/*
```

They are useful references, but the global map/save flow was not stable enough for this deployment. The current mainline uses external MID360.

### Point-LIO With Go2 Built-In Lidar

We tried feeding Go2 built-in lidar/imu topics to Point-LIO. It could look plausible while static, but moving caused drift or failure. The likely reason is that the processed Go2 lidar/imu topics do not match Point-LIO's assumptions about raw Unitree L1 data.

This is parked.

### go2_ros2_sdk + slam_toolbox

We also tested a route closer to:

```text
Go2 SDK point cloud
-> pointcloud_to_laserscan
-> slam_toolbox
-> Nav2
```

It helped understand the Go2 SDK and motion bridge, but the map quality did not beat external MID360 + FAST-LIO.

This is parked.

### RealSense D435i

RealSense was investigated for possible future FAST-LIVO/visual mapping work. Current status:

```text
RSUSB clean stack can produce data under some profiles.
Native backend on Jetson can fail VIDIOC_S_FMT.
Depth/color/IMU stability depends heavily on firmware, backend, USB topology, and profile.
```

RealSense is not part of the current navigation mainline.

## Git And Backup

Remote:

```text
git@github.com:AlanZhu2006/go2_nav.git
```

Repository root:

```text
~/work
```

Check:

```bash
cd ~/work
git status --short --branch
git log --oneline --decorate -5
```

This repository intentionally ignores many files by default, so key scripts/docs sometimes need force-add:

```bash
cd ~/work
git add -f go2_nav/README.md go2_nav/command.txt go2_nav/env.sh
git add -f nyush_rm_sentry/scripts/republish_odom_base_link.py
git add -f nyush_rm_sentry/config/go2_nav2_base_link.rviz
git add -f nyush_rm_sentry/config/go2_nav2_params_head_forward.yaml
git add -f nyush_rm_sentry/rm_navigation_ws/src/rm_localization/icp_registration/src/icp_registration.cpp
git add -f nyush_rm_sentry/rm_navigation_ws/src/rm_localization/icp_registration/include/icp_registration/icp_registration.hpp
git commit -m "Update Go2 MID360 Nav2 deployment notes"
git push origin main
```

## Current Next Steps

1. Use the head-forward `base_link` stack as the mainline.
2. Start with `START_GO2_CMD_BRIDGE=false` after any localization/map/TF parameter change.
3. Check ICP log for `search window` and score before trusting RViz.
4. Treat score around `0.15+` as suspicious even if below `ICP_THRESH=0.35`.
5. Verify RViz `Odom` topic is `/odom_base_link`.
6. Verify scan/map alignment and global plan before enabling Go2 motion.
7. Test conservative footprint/inflation near walls.
8. Only after alignment and clearance are correct, restart with `START_GO2_CMD_BRIDGE=true`.
