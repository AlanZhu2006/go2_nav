# Unitree Go2 + MID360 导航部署记录

这个仓库是我们当前 Go2 导航部署的工作备份。它不是原始 `nyush_rm_sentry` 的完整复刻，而是在参考其中可用结构的基础上，围绕我们自己的 Unitree Go2 机器狗、外接 Livox MID360、ROS 2 Foxy、FAST-LIO、ICP 定位和 Nav2 做出的实际部署记录。

当前最重要的命令手册在：

```text
~/work/go2_nav/command.txt
```

当前主要脚本和配置在：

```text
~/work/nyush_rm_sentry/scripts
~/work/nyush_rm_sentry/config
```

当前地图文件在：

```text
~/work/go2_nav/maps/mid360_fastlio_latest
```

## 当前状态

目前已经跑通的主线是：

```text
外接 MID360
  -> livox_ros_driver2
  -> FAST-LIO
  -> /Odometry 和 /cloud_registered_body
  -> ICP registration 对齐保存好的 FAST-LIO PCD
  -> 发布 map -> odom
  -> pointcloud_to_laserscan
  -> /scan
  -> Nav2 planner/controller
  -> /cmd_vel
  -> go2_cmd_bridge.py
  -> Unitree SportClient.Move(vx, vy, wz)
```

当前稳定参数：

```text
导航 base frame: livox_frame
里程计 topic: /Odometry
scan 来源点云: /cloud_registered_body
scan target frame: livox_frame
原始全局 PCD 地图: ~/work/go2_nav/maps/mid360_fastlio_latest/fastlio_map.pcd
ICP 专用过滤 PCD: ~/work/go2_nav/maps/mid360_fastlio_latest/fastlio_map_icp_zm020_150.pcd
Nav2 2D 地图: ~/work/go2_nav/maps/mid360_fastlio_latest/nav2_map/map.yaml
Go2 速度上限: vx=0.30, vy=0.30, wz=0.70
遥控器优先: 开启
```

目前最关键的经验：

```text
不要同时存在两个定位节点发布 map -> odom。
如果有两个 icp_registration_node，RViz 里的 scan/map 会抖动、跳变、看起来像定位坏掉。
每次启动前都先运行 stop_mid360_fastlio_nav2.sh。
```

## 硬件和网络

当前硬件：

```text
机器人: Unitree Go2
计算机: Go2 自带 Ubuntu 20.04 arm64 小电脑
ROS: ROS 2 Foxy
外接雷达: Livox MID360
远程图形界面: x11vnc + Xvfb + XFCE，显示号 :1
```

当前网络：

| 接口 | 地址 | 用途 |
| --- | --- | --- |
| `wlan0` | `10.209.69.61` | 笔记本 SSH 和 VNC 连接 |
| `eth0` | `192.168.123.18/24` | Unitree 内部网络 |
| `eth0` | `192.168.1.2/24` | MID360 主机接收地址 |
| MID360 | `192.168.1.3` | 雷达地址 |
| `eth1` | 不使用 | USB 拓展坞网口，不再用于 MID360 |

我们之前试过用 USB 拓展坞网口接 MID360，但出现过 TX error、链路不稳定、ping 不可靠等问题。现在稳定方案是把 MID360 接在 Go2 原生网口链路上，也就是 `eth0`。

检查网络：

```bash
ip -br addr show eth0
ip route get 192.168.1.3
ping -I eth0 -c 3 192.168.1.3
```

期望看到类似：

```text
192.168.1.3 dev eth0 src 192.168.1.2
```

## 仓库结构

Git 备份仓库根目录是：

```text
~/work
```

这个仓库故意没有追踪全部 build 产物，只追踪当前部署需要的关键文件。

重点文件：

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

不作为主要备份内容的目录：

```text
realsense_rsusb/
realsense_stack_clean/
realsense_stack_native/
nav_ws/build/
nav_ws/install/
ROS 日志和临时文件
```

## 快速启动

先 SSH 到 Go2：

```bash
ssh unitree@10.209.69.61
```

VNC 从笔记本连接：

```text
10.209.69.61:5901
```

先启动定位和 Nav2，但不让机器人运动：

```bash
cd ~/work/nyush_rm_sentry
./scripts/stop_mid360_fastlio_nav2.sh

LOCALIZATION_MODE=icp \
START_NAVIGATION=true \
START_RVIZ=true \
START_GO2_CMD_BRIDGE=false \
NAV_BASE_FRAME=livox_frame \
NAV_ODOM_TOPIC=/Odometry \
ICP_PCD_FILE=~/work/go2_nav/maps/mid360_fastlio_latest/fastlio_map_icp_zm020_150.pcd \
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

确认 RViz 中 map、scan、odom 稳定后，再启动带运动桥接的完整导航：

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
ICP_PCD_FILE=~/work/go2_nav/maps/mid360_fastlio_latest/fastlio_map_icp_zm020_150.pcd \
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

查看实际发给 Go2 的运动命令：

```bash
tail -f /tmp/mid360_fastlio_nav2/go2_cmd_bridge.log
```

停止整套导航：

```bash
cd ~/work/nyush_rm_sentry
./scripts/stop_mid360_fastlio_nav2.sh
```

只停止运动桥接：

```bash
pkill -TERM -f '[/]go2_cmd_bridge.py'
```

## 建图流程

建图使用 MID360 + FAST-LIO。

启动建图：

```bash
cd ~/work/nyush_rm_sentry
./scripts/stop_mid360_fastlio_nav2.sh

START_RVIZ=true ./scripts/start_mid360_fastlio_mapping.sh
```

脚本启动后可以在交互提示里输入：

```text
1 + Enter  保存 FAST-LIO PCD
s + Enter  查看状态
q + Enter  退出
```

期望输出：

```text
~/work/go2_nav/maps/mid360_fastlio_latest/fastlio_map.pcd
~/work/go2_nav/maps/mid360_fastlio_latest/fastlio_latest.pcd
```

如果需要手动保存：

```bash
cd ~/work/nyush_rm_sentry
./scripts/save_mid360_fastlio_map.sh
ls -lh ~/work/go2_nav/maps/mid360_fastlio_latest/fastlio_map.pcd
```

将 FAST-LIO PCD 转成 Nav2 需要的 2D `map.pgm` 和 `map.yaml`：

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

期望输出：

```text
~/work/go2_nav/maps/mid360_fastlio_latest/nav2_map/map.pgm
~/work/go2_nav/maps/mid360_fastlio_latest/nav2_map/map.yaml
```

这一步的高度过滤很关键。我们现在使用：

```text
Z_MIN=0.20
Z_MAX=1.80
RADIUS=0.15
POINT_COUNT=5
```

原因是 MID360 的点云里会包含地面、桌面、天花板、支架附近点。过滤范围太宽会让天花板或地面错误投影到 2D 地图里，范围太窄又会让墙体太稀疏。

注意：Nav2 不直接读取 PCD。Nav2 的 `map_server` 读取的是：

```text
~/work/go2_nav/maps/mid360_fastlio_latest/nav2_map/map.yaml
```

而 ICP 定位直接读取 PCD。为了减少天花板、高处杂点和长墙误匹配，我们给 ICP 单独生成一张过滤后的 PCD：

```bash
cd ~/work/nyush_rm_sentry

./scripts/filter_pcd_for_icp.py \
  --input ~/work/go2_nav/maps/mid360_fastlio_latest/fastlio_map.pcd \
  --output ~/work/go2_nav/maps/mid360_fastlio_latest/fastlio_map_icp_zm020_150.pcd \
  --z-min -0.20 \
  --z-max 1.50 \
  --voxel 0.05 \
  --stat-nb 20 \
  --stat-std 2.0
```

当前推荐：

```text
Nav2 map_server:
  nav2_map/map.yaml

ICP registration:
  fastlio_map_icp_zm020_150.pcd

原始 fastlio_map.pcd:
  只作为备份和重新生成地图的源文件
```

## 导航架构

当前定位没有走 AMCL 作为主线，而是走更接近原始 `start_robot.sh` 的 3D ICP 对齐路线。

整体关系：

```text
FAST-LIO:
  odom -> livox_frame
  /Odometry
  /cloud_registered_body

ICP registration:
  输入当前 /cloud_registered_body
  输入过滤后的 fastlio_map_icp_zm020_150.pcd
  输出 map -> odom

pointcloud_to_laserscan:
  输入 /cloud_registered_body
  输出 /scan
  frame 使用 livox_frame

Nav2:
  base_frame 使用 livox_frame
  odom_topic 使用 /Odometry
  map 使用 nav2_map/map.yaml
```

为什么当前用 `livox_frame` 作为导航 base：

```text
FAST-LIO 地图是在 livox_frame/body 坐标逻辑下构建的。
如果过早把 lidar -> base_link 的 90 度旋转注入 AMCL/Nav2，scan-map 对齐会更容易混乱。
因此当前先用 livox_frame 打通定位和导航主链路。
```

我们试过 `base_link`、`LIDAR_TO_BASE_YAW_DEG=90`、AMCL global localization 等组合，但目前最稳定的是：

```text
LOCALIZATION_MODE=icp
NAV_BASE_FRAME=livox_frame
SCAN_TARGET_FRAME=livox_frame
```

## Go2 运动桥接

Nav2 输出：

```text
/cmd_vel
```

Go2 实际控制使用 Unitree high-level SportClient：

```text
SportClient.Move(vx, vy, wz)
```

桥接脚本：

```text
~/work/nyush_rm_sentry/scripts/go2_cmd_bridge.py
```

当前速度上限：

```text
GO2_MAX_VX=0.30
GO2_MAX_VY=0.30
GO2_MAX_WZ=0.70
```

我们用键盘测试过，`vx=0.30, vy=0.30, wz=0.70` 对当前 Go2 响应比较合理。更小的速度会出现需要长按很久、姿态轻微变化但不明显移动的问题。

Go2 和轮式底盘不太一样。轮式底盘收到很小的 `/cmd_vel` 往往也会缓慢动起来，但 Go2 的 high-level 步态控制存在明显的实际起步死区：速度太小的时候可能只是身体晃动、原地犹豫，不会立刻迈步。因此当前 bridge 支持最小有效命令：

```text
GO2_DEADBAND_V=0.02
GO2_DEADBAND_W=0.04
GO2_MIN_CMD_V=0.10
GO2_MIN_CMD_W=0.20
```

含义是：

```text
小于 deadband 的命令直接视为 0
大于 deadband 但小于 min_cmd 的非零命令，会抬到 min_cmd
```

这样可以减少 Nav2 输出很小速度时 Go2 只晃不走的问题。与此同时，`go2_nav2_params_light.yaml` 里也把 DWB 的 `min_speed_xy/min_speed_theta` 设成非零，并降低了 `RotateToGoal` 权重，避免每次开始走之前先原地转很久。

如果键盘脚本方向正确，但 Nav2 自动导航方向像整体偏了 90 度，可以先不改定位和地图，直接在 Go2 command bridge 里测试二维速度映射：

```text
中性映射:
  vx_go2 = vx_nav
  vy_go2 = vy_nav

+90 度逆时针映射:
  vx_go2 = -vy_nav
  vy_go2 =  vx_nav
  GO2_SWAP_XY=true
  GO2_X_SIGN=-1.0
  GO2_Y_SIGN=1.0

-90 度顺时针映射:
  vx_go2 =  vy_nav
  vy_go2 = -vx_nav
  GO2_SWAP_XY=true
  GO2_X_SIGN=1.0
  GO2_Y_SIGN=-1.0
```

如果键盘 `q/e` 的旋转方向已经正确，先保持：

```text
GO2_WZ_SIGN=1.0
```

遥控器优先很重要：

```text
GO2_REMOTE_PRIORITY=true
```

含义是遥控器有输入时，命令桥接会暂停或让出控制，避免 Nav2 和遥控器抢控制。

## 键盘控制调试

键盘调试用于验证：

```text
/cmd_vel -> go2_cmd_bridge.py -> SportClient.Move
```

不需要 Nav2。

命令：

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

按键：

```text
w/s = 前进/后退
a/d = 左移/右移
q/e = 正/负角速度
space 或 x = 停止
```

另开一个终端看桥接日志：

```bash
tail -f /tmp/go2_cmd_bridge_debug.log
```

如果键盘能动，说明 Go2 command bridge 是通的。如果 Nav2 不能动，就应该查 Nav2 controller、路径、costmap、goal 和 `/cmd_vel`，而不是先怀疑 Unitree SDK。

## VNC 和 RViz

VNC 连接：

```text
10.209.69.61:5901
```

检查 VNC 服务：

```bash
systemctl --user status rviz-vnc.service --no-pager
tail -n 80 /tmp/rviz-vnc/x11vnc.log 2>/dev/null || true
```

RViz 配置：

```text
~/work/nyush_rm_sentry/config/go2_nav2_light.rviz
```

为了减轻 Jetson 负载，RViz 里不要长期打开太多显示项。优先保留：

```text
Map
LaserScan
Odom
GlobalPlan
TF
```

尽量少开：

```text
大点云显示
高频 costmap 显示
多个历史轨迹显示
```

Foxy + Jetson 在高负载时容易出现 CLI 卡顿、RViz 卡顿、`bad_alloc` 或 MessageFilter drop，看起来像 TF 坏了，但实际可能只是负载过高或重复节点导致。

## 诊断命令

加载环境：

```bash
source /opt/ros/foxy/setup.bash
source ~/nav_ws/install/setup.bash
source ~/work/nyush_rm_sentry/rm_navigation_ws/install/setup.bash
```

Topic 频率：

```bash
timeout 5 ros2 topic hz /livox/lidar
timeout 5 ros2 topic hz /livox/imu
timeout 5 ros2 topic hz /cloud_registered_body
timeout 5 ros2 topic hz /scan
timeout 5 ros2 topic hz /Odometry
timeout 5 ros2 topic hz /cmd_vel
```

TF：

```bash
ros2 run tf2_ros tf2_echo odom livox_frame
ros2 run tf2_ros tf2_echo map livox_frame
```

Nav2 lifecycle：

```bash
ros2 lifecycle get /map_server
ros2 lifecycle get /controller_server
ros2 lifecycle get /planner_server
ros2 lifecycle get /bt_navigator
```

进程检查：

```bash
pgrep -af 'livox_ros_driver2|fastlio_mapping|pointcloud_to_laserscan|icp_registration|nav2|rviz2|go2_cmd_bridge'
```

日志：

```bash
tail -n 120 /tmp/mid360_fastlio_nav2/livox_driver.log 2>/dev/null || true
tail -n 120 /tmp/mid360_fastlio_nav2/fastlio_mapping.log 2>/dev/null || true
tail -n 120 /tmp/mid360_fastlio_nav2/icp_registration.log 2>/dev/null || true
tail -n 120 /tmp/mid360_fastlio_nav2/go2_cmd_bridge.log 2>/dev/null || true
```

## 我们试过的路线

### Go2 内置雷达官方 topic

我们检查和尝试过：

```text
/utlidar/cloud
/utlidar/cloud_base
/utlidar/cloud_deskewed
/utlidar/robot_odom
/utlidar/robot_pose
/uslam/cloud_map
/lio_sam_ros2/mapping/*
```

这些 topic 确实存在，但完整全局地图和保存流程不够稳定。单帧点云或简单累计点云转 PGM 后，要么太稀疏，要么把可走区域也投成障碍。

结论：

```text
Go2 内置雷达官方链路保留为参考，不作为当前主线。
```

### Point-LIO + Go2 内置雷达

我们尝试过用 Go2 内置：

```text
/utlidar/cloud
/utlidar/imu
```

接 Point-LIO，也对比过 `unitreerobotics/point_lio_unilidar`。

现象：

```text
静止时短时间看起来可以
一移动或有加速度就容易飞
调整 acc_norm 可以缓解表象，但不是根治
```

判断：

```text
Go2 内置官方处理后的 lidar/imu topic 和 Point-LIO 对原始 Unitree L1 数据的假设不完全一致。
```

### go2_ros2_sdk + slam_toolbox

我们复现过类似 `go2_ros2_sdk` 的路线：

```text
Go2 SDK 点云
-> pointcloud_to_laserscan
-> slam_toolbox
-> Nav2
```

它对理解 Go2 command bridge 和 high-level SDK 有帮助，但建图质量没有超过外接 MID360 + FAST-LIO。

结论：

```text
作为参考路线保留，不作为当前主线。
```

### RealSense D435i

我们也测试过 RealSense D435i，希望未来可能用于 FAST-LIVO 或视觉建图。

当前结论：

```text
RealSense 暂时不进入导航主线。
```

已经观察到：

```text
RSUSB clean stack 某些 profile 可以出数据
Native backend 在 Jetson 上可能 VIDIOC_S_FMT 失败
depth/color/IMU 稳定性和 firmware、backend、USB 拓扑强相关
```

在 RealSense 能稳定连续运行 30 到 60 分钟之前，不把它接入主导航流程。

## 已知问题和处理

### scan 抖动或 map 对齐跳变

最可能原因：

```text
存在两个 ICP 节点同时发布 map -> odom
```

处理：

```bash
cd ~/work/nyush_rm_sentry
./scripts/stop_mid360_fastlio_nav2.sh
pgrep -af icp_registration
```

期望停止后没有 `icp_registration_node`。

### 遥控器被 Nav2 抢控制

确保启动时使用：

```text
GO2_REMOTE_PRIORITY=true
```

或者只停止桥接：

```bash
pkill -TERM -f '[/]go2_cmd_bridge.py'
```

### RViz 显示 no TF data

检查：

```bash
ros2 run tf2_ros tf2_echo odom livox_frame
ros2 run tf2_ros tf2_echo map livox_frame
pgrep -af icp_registration
```

如果 `map -> livox_frame` 不存在，通常是 ICP 没发布 `map -> odom`，或者多个定位节点冲突。

### Nav2 有路径但机器人不动

先看 `/cmd_vel`：

```bash
timeout 5 ros2 topic hz /cmd_vel
ros2 topic echo /cmd_vel
```

再看桥接：

```bash
tail -f /tmp/mid360_fastlio_nav2/go2_cmd_bridge.log
```

如果 `/cmd_vel` 有，但没有 `Move(...)` 日志，说明桥接没有运行或订阅 topic 不对。

如果键盘可以控制 Go2，但 Nav2 goal 不动，说明 Unitree 运动桥接是通的，问题更可能在 Nav2 controller、路径、costmap 或 goal。

### ROS2 CLI 出现 bad_alloc

我们在 Foxy + Jetson 高负载下遇到过几次。它不一定是真正内存耗尽，也可能是 ROS2/Foxy 在高负载下的表现。

处理原则：

```text
减少 RViz 显示项
不要重复启动重节点
先关运动桥接，只验证定位
确认没有重复 ICP
```

## Git 备份

远端仓库：

```text
git@github.com:AlanZhu2006/go2_nav.git
```

本地仓库根目录：

```text
~/work
```

检查同步状态：

```bash
cd ~/work
git status --short --branch
git log --oneline --decorate -3
git ls-remote origin refs/heads/main
```

提交和推送：

```bash
cd ~/work
git add -f go2_nav/README.md go2_nav/command.txt
git commit -m "Update Go2 navigation docs"
git push origin main
```

当前备份采用 `.gitignore` 默认忽略所有文件，只强制加入关键文件。因此更新文档或新脚本时，经常需要：

```bash
git add -f <file>
```

## 当前下一步

1. 继续把 MID360 + FAST-LIO + ICP + Nav2 作为主线。
2. 每次改地图、参数或 TF 后，先用 `START_GO2_CMD_BRIDGE=false` 验证定位和 RViz。
3. 确认只存在一个 ICP 进程后，再相信 scan-map 对齐结果。
4. 确认 map、scan、odom、global plan 稳定后，再开启 `START_GO2_CMD_BRIDGE=true`。
5. 继续微调 Nav2 controller、footprint 和 costmap，让 Go2 行走更顺。
6. RealSense、Point-LIO、Go2 内置雷达官方建图路线暂时作为研究分支，不阻塞当前导航闭环。
