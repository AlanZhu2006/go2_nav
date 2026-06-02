# Unitree Go2 Built-in Lidar Navigation Deployment

这是我们在 **Unitree Go2 机器狗小电脑** 上部署自主导航的实机记录。这里的 `nyush_rm_sentry` 只是参考开源工程后继续使用的工作目录名；当前目标不是复刻 NYUSH/RM 完整哨兵系统，而是把我们自己的 Go2 导航链路跑通。

现在已经确认：**这台 Go2 用的是机身自带雷达，不是外接 Unitree L2**。因此当前主线不再是“外接 L2 + FAST-LIO”，也暂时不再强推 raw Point-LIO。当前最小正确路线是参考 `go2_ros2_sdk` 的思路：先复用 Go2 官方 odom，把 Go2 内置雷达的 3D 点云转成 2D `/scan`，用 `slam_toolbox` 建 2D 地图，再接 Nav2。

```text
Go2 built-in lidar / official odom
  -> Unitree CycloneDDS ROS2 topics
  -> /utlidar/cloud_base + /utlidar/robot_odom
  -> pointcloud_to_laserscan
  -> slam_toolbox 2D mapping
  -> map.pgm / map.yaml / posegraph
  -> Nav2 map_server + AMCL
  -> Nav2 planner / controller
  -> /cmd_vel
  -> cmd_vel bridge
  -> Unitree Go2 SportClient.Move(vx, vy, wz)
```

当前阶段明确不做：

```text
视觉 autoaim
决策 BehaviorTree
RM 串口裁判系统 / 云台通信
NYUSH Robotics 机器人整栈复刻
外接 L2 雷达路线
```

## 当前进度总览（2026-05-26）

目前已经走过三条建图路线，结论如下。

| 路线 | 当前结论 |
|------|----------|
| Unitree 官方 USLAM / LIO-SAM / 累积点云 | 话题和服务存在，但 `/uslam/cloud_map` 不稳定持续发布；直接累计 `/utlidar/cloud_base` 或 `/utlidar/cloud_deskewed` 得到的 PCD 转 PGM 后容易稀疏、发黑或不像可导航地图。暂时不作为主线。 |
| Point-LIO / FAST-LIO raw LIO | 一启动或轻微移动时坐标系会飞。静止时官方 `/utlidar/robot_odom` 很稳，但 Point-LIO `/aft_mapped_to_init` 会大漂移，核心是 Go2 内置 `/utlidar/*` 输入和 standalone Unitree L1 Point-LIO 期望的 raw cloud/imu/外参/时间字段不完全一致。暂时不作为主线。 |
| Go2 official odom + 2D scan + slam_toolbox | 已经打通 `/scan`、`/map`、TF、map 保存和 Nav2 安全启动，是当前主线。 |

当前已验证的最小闭环：

```text
/utlidar/robot_odom
  -> /odom
  -> TF: odom -> base_link

/utlidar/cloud_base
  -> /go2_slam/cloud_base
  -> pointcloud_to_laserscan
  -> /scan

slam_toolbox
  -> /map
  -> TF: map -> odom
  -> map.pgm / map.yaml / posegraph

Nav2
  -> map_server + AMCL + planner + controller
```

当前已保存的 2D 建图输出：

```text
~/work/go2_nav/maps/go2_slam_toolbox_latest/map.yaml
~/work/go2_nav/maps/go2_slam_toolbox_latest/map.pgm
~/work/go2_nav/maps/go2_slam_toolbox_latest/posegraph.posegraph
```

启动 2D 建图：

```bash
cd ~/work/nyush_rm_sentry
START_RVIZ=true START_GO2_CMD_BRIDGE=false ./scripts/start_go2_slam_toolbox_mapping.sh
```

脚本里：

```text
1 + Enter  保存 map.pgm/map.yaml 和 slam_toolbox posegraph
s + Enter  查看 /scan、/map、TF、服务和日志状态
q + Enter  退出
```

启动 Nav2，先不让机器狗动：

```bash
cd ~/work/nyush_rm_sentry
START_RVIZ=true START_GO2_CMD_BRIDGE=false ./scripts/start_go2_nav2_with_rviz.sh
```

等 RViz 里地图、TF、AMCL、global plan/local plan 都正常后，再打开实际运动桥：

```bash
cd ~/work/nyush_rm_sentry
START_RVIZ=true START_GO2_CMD_BRIDGE=true ./scripts/start_go2_nav2_with_rviz.sh
```

## 当前机器信息

| 项目 | 当前值 |
|------|--------|
| 机器人 | Unitree Go2 |
| 小电脑系统 | Ubuntu 20.04 arm64 |
| ROS 版本 | ROS 2 Foxy |
| DDS | CycloneDDS |
| 雷达 | Go2 机身自带雷达 + 外接 Livox MID360 |
| 建图主线 | 当前可用：`/utlidar/cloud_base -> /scan -> slam_toolbox -> map.pgm/map.yaml`；MID360 已接入原生网口，下一步用于 FAST-LIO/Point-LIO/更稳建图 |
| 定位主线 | Nav2 AMCL + `/scan` + 官方 `/utlidar/robot_odom` |
| 远程 GUI | x11vnc + Xvfb + XFCE |

当前常见 IP：

| 网卡 | IP | 用途 |
|------|----|------|
| `wlan0` | `10.209.69.61` | 我们电脑远程 SSH/VNC 推荐用这个 |
| `eth0` | `192.168.123.18` + `192.168.1.2` | 原生/PCIe 网口；同时保留 Go2 内部网络和 MID360 主机地址 |
| MID360 | `192.168.1.182` | 外接 Livox MID360 雷达 |
| `eth1` | 不使用 | USB 拓展坞 RTL8153 网卡，测试时出现发送错误，不再接 MID360 |

检查 IP：

```bash
ip -br addr show wlan0
ip -br addr show eth0
ip route get 192.168.1.182
```

健康状态应类似：

```text
wlan0 ... 10.209.69.61/19
eth0  ... 192.168.123.18/24 192.168.1.2/24
192.168.1.182 dev eth0 src 192.168.1.2
```

## MID360 网络配置

最终确认的硬件连接：

```text
Go2 原生/PCIe 网口 eth0
  -> 192.168.123.18/24  Go2 内部/Unitree 网络
  -> 192.168.1.2/24     MID360 host IP

MID360
  -> 192.168.1.182
```

不要再把 MID360 接到 USB 拓展坞网卡 `eth1`。测试中该路径是：

```text
Go2 USB -> USB 拓展坞 -> RTL8153/r8152 网卡 eth1 -> MID360
```

它会出现：

```text
r8152 eth1: Tx status -71
tx_errors 持续增长
RX 有数据但 TX 发不出去
```

这种状态下电脑能看到 MID360 的 ARP，但 Livox driver 不能完成握手。

永久 NetworkManager 配置：

```bash
sudo nmcli con mod "Wired connection 1" \
  connection.interface-name eth0 \
  connection.autoconnect yes \
  ipv4.method manual \
  ipv4.addresses "192.168.123.18/24,192.168.1.2/24" \
  ipv4.gateway "" \
  ipv4.never-default yes \
  ipv4.route-metric 500 \
  ipv6.method ignore

sudo nmcli con mod "Wired connection 2" \
  connection.interface-name eth1 \
  connection.autoconnect no \
  ipv4.method disabled \
  ipv4.gateway "" \
  ipv4.never-default yes \
  ipv4.route-metric 500 \
  ipv6.method ignore

sudo nmcli con up "Wired connection 1"
```

启动 MID360 前检查：

```bash
ip -br addr show eth0
ip route get 192.168.1.182
arping -I eth0 -c 5 192.168.1.182
```

Livox 配置文件：

```text
~/nav_ws/src/livox_ros_driver2/config/MID360_config.json
```

关键值：

```json
"cmd_data_ip": "192.168.1.2",
"point_data_ip": "192.168.1.2",
"imu_data_ip": "192.168.1.2",
"ip": "192.168.1.182",
"pcl_data_type": 0
```

启动驱动：

```bash
source /opt/ros/foxy/setup.bash
source ~/nav_ws/install/setup.bash
ros2 launch livox_ros_driver2 msg_MID360_launch.py
```

正常日志应继续出现：

```text
GetFreeIndex
begin to change work mode to Normal
livox/lidar publish use livox custom format
```

检查点云：

```bash
ros2 topic hz /livox/lidar
ros2 topic hz /livox/imu
```

## 目录约定

| 路径 | 用途 |
|------|------|
| `~/work/nyush_rm_sentry` | 当前部署脚本所在仓库 |
| `~/work/go2_nav/README.md` | 本文档 |
| `~/work/go2_nav/command.txt` | 当前阶段最小命令记录 |
| `~/cyclonedds_ws` | Unitree 官方 CycloneDDS/ROS2 环境 |
| `~/nav_ws` | 外部导航依赖 workspace，历史上包含 FAST-LIO 等 |
| `~/work/go2_nav/maps/go2_slam_toolbox_latest` | 当前主线保存的 2D SLAM 地图 |
| `~/work/go2_nav/maps/go2_builtin_latest` | 早期内置雷达点云累计实验地图 |

## SSH 配置

从自己的电脑连接机器狗：

```bash
ssh unitree@10.209.69.61
```

推荐在自己电脑的 `~/.ssh/config` 添加：

```sshconfig
Host go2
    HostName 10.209.69.61
    User unitree
    Port 22
    ServerAliveInterval 30
    ServerAliveCountMax 3
    TCPKeepAlive yes
```

之后可以直接：

```bash
ssh go2
scp local_file go2:~/work/
rsync -av ./some_dir/ go2:~/work/some_dir/
```

更安全的 VNC 方式是 SSH 隧道：

```sshconfig
Host go2-vnc
    HostName 10.209.69.61
    User unitree
    Port 22
    LocalForward 5901 localhost:5901
    ServerAliveInterval 30
    ServerAliveCountMax 3
```

使用时先开隧道：

```bash
ssh go2-vnc
```

然后 VNC Viewer 连接：

```text
localhost:5901
```

当前为了实验室调试方便，VNC 也可以直接连：

```text
10.209.69.61:5901
```

直接暴露 VNC 到 Wi-Fi 有风险，稳定后建议改成只监听 localhost，再固定使用 SSH tunnel。

## 远程 RViz GUI

TigerVNC 在这台 Ubuntu 20.04 arm64 上和 RealVNC Viewer 的握手不稳定，之前会出现 timeout 或 connection closed。现在已经切换到：

```text
Xvfb :1
  -> XFCE desktop
  -> x11vnc
  -> TCP 5901
```

已安装：

```bash
cd ~/work/nyush_rm_sentry
./scripts/install_x11vnc_rviz.sh
```

已启用 systemd user service：

```bash
cd ~/work/nyush_rm_sentry
./scripts/install_rviz_vnc_autostart.sh
```

常用命令：

```bash
systemctl --user status rviz-vnc.service
systemctl --user restart rviz-vnc.service
systemctl --user stop rviz-vnc.service
systemctl --user enable rviz-vnc.service
```

确认端口：

```bash
ss -ltnp | grep 5901
```

本机握手测试：

```bash
timeout 3 bash -lc 'exec 3<>/dev/tcp/10.209.69.61/5901; dd bs=12 count=1 <&3 2>/dev/null'
```

正常返回：

```text
RFB 003.008
```

如果希望开机后、用户没登录也启动 VNC：

```bash
sudo loginctl enable-linger unitree
loginctl show-user unitree | grep Linger
```

期望：

```text
Linger=yes
```

## Unitree Go2 DDS 环境

进入 Go2 DDS/ROS2 环境：

```bash
cd ~/work/nyush_rm_sentry
source scripts/go2_dds_env.sh
```

脚本核心配置：

```bash
source /opt/ros/foxy/setup.bash
source /home/unitree/cyclonedds_ws/install/setup.sh
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
export CYCLONEDDS_URI=file:///home/unitree/cyclonedds_ws/cyclonedds.xml
```

检查内置雷达和官方 SLAM 话题：

```bash
ros2 topic list -t | grep -E 'utlidar|uslam|lio_sam'
```

当前已确认存在：

```text
/utlidar/cloud [sensor_msgs/msg/PointCloud2]
/utlidar/cloud_base [sensor_msgs/msg/PointCloud2]
/utlidar/cloud_deskewed [sensor_msgs/msg/PointCloud2]
/utlidar/imu [sensor_msgs/msg/Imu]
/utlidar/lidar_state [unitree_go/msg/LidarState]
/utlidar/robot_odom [nav_msgs/msg/Odometry]
/utlidar/robot_pose [geometry_msgs/msg/PoseStamped]
/uslam/cloud_map [sensor_msgs/msg/PointCloud2]
/uslam/frontend/odom [nav_msgs/msg/Odometry]
/uslam/localization/odom [nav_msgs/msg/Odometry]
/lio_sam_ros2/mapping/odometry [nav_msgs/msg/Odometry]
```

关键观察：

```text
/utlidar/cloud          frame_id = utlidar_lidar
/utlidar/cloud_base     frame_id = base_link
/utlidar/cloud_deskewed frame_id = odom
/utlidar/imu            frame_id = utlidar_imu
/utlidar/robot_odom     odom -> base_link
```

这说明 Go2 内置栈已经在发布：

```text
原始雷达点云
转换到 base_link 的点云
去畸变/里程计坐标系下的点云
IMU
机器人 odom
可能还有官方 uslam 地图/定位结果
```

因此当前阶段不需要手工给 Go2 内置雷达写 `base_link -> lidar` 外参。官方内置栈已经在 `/utlidar/cloud_base` 和 `/utlidar/robot_odom` 里体现了这部分关系。

## 为什么 FAST-LIO 会飞

之前按照“外接 Unitree L2 + FAST-LIO”做过配置。这个路线现在应当视为历史/实验分支，因为它假设我们直接拿一个外接雷达的原始点云和 IMU 去给 FAST-LIO。

但现在实际输入是 Go2 内置雷达栈发布的混合话题：

```text
/utlidar/cloud          原始 lidar frame
/utlidar/cloud_base     已经转到 base_link
/utlidar/cloud_deskewed 已经在 odom frame
/utlidar/robot_odom     官方 odom -> base_link
```

如果再把这些话题喂给 FAST-LIO，很容易出现以下问题：

```text
重复去畸变
重复积分 IMU
frame_id 与 FAST-LIO 假设不一致
时间戳单位/点云字段假设不一致
官方 odom 和 FAST-LIO odom 同时存在
```

所以现象会是：静止拿着还行，一旦加速度变大或机器狗运动，坐标系直接飘走/飞走。

结论：

```text
Go2 内置雷达路线先不要启动 FAST-LIO。
先观察和复用官方 /utlidar 与 /uslam 输出。
只有在官方 uslam 不满足需求时，再单独研究 raw cloud + raw imu 的自建 LIO。
```

## 当前正确的 RViz 启动

启动 Go2 内置雷达观察界面：

```bash
cd ~/work/nyush_rm_sentry
./scripts/start_go2_builtin_rviz.sh
```

然后从自己的电脑连：

```text
10.209.69.61:5901
```

这个脚本会：

```text
确认 rviz-vnc.service 已经启动
source Go2 DDS 环境
source ROS 2 Foxy
启动 /utlidar/robot_odom -> /tf 桥接
打开 DISPLAY=:1 上的 RViz
加载 config/go2_builtin_lidar.rviz
显示 TF、/utlidar/cloud_base、/utlidar/cloud_deskewed、/utlidar/robot_odom、/uslam/cloud_map
```

日志：

```bash
tail -f /tmp/go2_builtin_rviz/rviz.log
tail -f /tmp/go2_builtin_rviz/odom_to_tf.log
```

如果 RViz 黑屏或 OpenGL 报错，确认：

```bash
export LIBGL_ALWAYS_SOFTWARE=1
```

## 当前最小检查流程

1. 启动 RViz：

```bash
cd ~/work/nyush_rm_sentry
./scripts/start_go2_builtin_rviz.sh
```

2. 检查官方雷达话题频率：

```bash
source ~/work/nyush_rm_sentry/scripts/go2_dds_env.sh
ros2 topic hz /utlidar/cloud_base
ros2 topic hz /utlidar/cloud_deskewed
ros2 topic hz /utlidar/robot_odom
```

3. 检查 frame：

```bash
ros2 topic echo /utlidar/cloud_base --once | head -40
ros2 topic echo /utlidar/robot_odom --once | head -60
```

4. 在 RViz 里观察：

```text
Fixed Frame = odom
/utlidar/cloud_base 应该跟着 base_link
/utlidar/cloud_deskewed 应该在 odom 里相对稳定
/uslam/cloud_map 如果官方 uslam 正常，应逐渐形成地图
```

如果现在移动机器狗仍然“飞”，优先检查 `/utlidar/robot_odom` 本身是否跳变，而不是先改 FAST-LIO。

### RViz 显示 no tf data

当前实测 Go2 会发布 `/utlidar/robot_odom`，但不一定会同时把它广播到 `/tf`。如果 RViz 显示 `No tf data`，原因通常是：

```text
/utlidar/robot_odom 有 odom -> base_link
/tf 没有 odom -> base_link
```

已添加脚本自动处理：

```bash
~/work/nyush_rm_sentry/scripts/go2_odom_to_tf.py
```

`start_go2_builtin_rviz.sh` 会自动启动它。手动检查：

```bash
source ~/work/nyush_rm_sentry/scripts/go2_dds_env.sh
timeout 4 ros2 topic echo /tf
```

正常应看到：

```text
frame_id: odom
child_frame_id: base_link
```

## 建图路线

当前建议路线：

```text
第一优先级：启动 Unitree 官方 graph_pid_ws / lio_sam_ros2 建图并保存 PCD
第二优先级：如果 /uslam/cloud_map 在官方建图状态下开始发布，再直接保存 /uslam/cloud_map
第三优先级：累计 /utlidar/cloud_deskewed
第四优先级：重新研究 raw /utlidar/cloud + /utlidar/imu 的自建 LIO
```

短期目标不是直接保存 FAST-LIO PCD，而是先确认官方地图/odom 是否稳定：

```bash
source ~/work/nyush_rm_sentry/scripts/go2_dds_env.sh
ros2 topic hz /uslam/cloud_map
ros2 topic echo /uslam/localization/odom --once
```

后续需要补一个保存脚本，把 `/uslam/cloud_map` 或累计后的 deskewed cloud 保存成：

```text
~/work/go2_nav/maps/go2_builtin_latest/map.pcd
```

然后再转成 Nav2 使用的 2D 地图：

```text
map.yaml
map.pgm
```

PCD 转 2D map 时需要确认：

```text
地图分辨率
地面高度过滤范围
障碍物高度过滤范围
膨胀半径
map frame 是否统一为 map
```

### 保存 PCD

已添加通用 PointCloud2 保存脚本：

```bash
~/work/nyush_rm_sentry/scripts/save_pointcloud2_pcd.py
~/work/nyush_rm_sentry/scripts/save_go2_builtin_pcd.sh
~/work/nyush_rm_sentry/scripts/start_go2_lidar_services.py
~/work/nyush_rm_sentry/scripts/go2_utlidar_switch.py
```

重启后如果能看到 `/utlidar/*` topic，但所有 `topic hz` 都 timeout，通常是机器人侧内置雷达服务没有启动。先执行：

```bash
cd ~/work/nyush_rm_sentry
./scripts/start_go2_lidar_services.py
./scripts/go2_utlidar_switch.py ON --repeat 5 --interval 0.2
```

这会通过 Unitree SDK 打开：

```text
unitree_lidar
unitree_lidar_slam
voxel_height_mapping
rt/utlidar/switch = ON
```

默认保存 `/uslam/cloud_map`：

```bash
cd ~/work/nyush_rm_sentry
./scripts/save_go2_builtin_pcd.sh
```

默认输出：

```text
~/work/go2_nav/maps/go2_builtin_latest/go2_builtin_<timestamp>.pcd
~/work/go2_nav/maps/go2_builtin_latest/latest.pcd
```

当前测试结果：

```text
/utlidar/cloud_base 可以保存，说明 PointCloud2 -> PCD 工具链正常。
/utlidar/cloud_deskewed 可以保存，frame_id=odom，更适合作为后续累计建图输入。
/utlidar/voxel_map、/utlidar/grid_map、/uslam/cloud_map 当前仍 timeout，需要进入官方 3D LiDAR Mapping 状态后再试。
```

这说明当前不是保存器问题，而是官方 uslam 地图还没有开始持续发布，或者地图发布是事件式/低频的。需要先让 Go2 进入官方 3D LiDAR Mapping/SLAM 建图状态，再保存 `/uslam/cloud_map`。

### 官方 Go2 建图入口

现在已经在本机找到 Unitree 自带的建图栈：

```text
/unitree/module/graph_pid_ws
```

关键入口：

```text
/unitree/module/graph_pid_ws/0_unitree_slam.sh
/unitree/module/graph_pid_ws/src/QT_Server/shell/mapping.sh
/unitree/module/graph_pid_ws/src/task/launch/mapping_qt_test.launch.py
/unitree/module/graph_pid_ws/src/lio_sam_ros2/launch/lio_mapping_qt_test.launch.py
```

`mapping.sh` 实际启动的是：

```text
ros2 run send_cmd high_rate_state
ros2 run go2_control_by_sdk send_cmd
ros2 launch task mapping_qt_test.launch.py
```

`mapping_qt_test.launch.py` 会启动 Unitree 自带的 `dog_control_B1_one`，再启动 `lio_sam_ros2` 建图节点：

```text
lio_sam_ros2_dogOdomForMapping
lio_sam_ros2_imuPreintegration
lio_sam_ros2_imageProjection
lio_sam_ros2_featureExtraction
lio_sam_ros2_mapOptmization
lio_sam_ros2_lidar_checkout
```

所以这一路线本质上是 **Unitree 官方 LIO-SAM ROS2 建图栈**，不是 Point-LIO，也不是我们之前外接 L2 时准备跑的 FAST-LIO。

关于几个容易误判的话题：

```text
/utlidar/mapping_cmd     有 publisher、没有 subscriber，更像状态/输出，不是启动入口
/utlidar/client_cmd      有 subscriber，但命令字符串目前未知
/uslam/client_command    有 publisher 和 subscriber，但没有公开确认的安全命令格式
```

因此当前不要盲发 `/utlidar/client_cmd` 或 `/uslam/client_command`。先使用 Unitree 本机已经写好的 shell/launch 入口。

已添加 wrapper：

```bash
~/work/nyush_rm_sentry/scripts/start_unitree_lio_sam_mapping.sh
~/work/nyush_rm_sentry/scripts/save_unitree_lio_sam_map.sh
~/work/nyush_rm_sentry/scripts/stop_unitree_lio_sam_mapping.sh
```

启动官方建图：

```bash
cd ~/work/nyush_rm_sentry
./scripts/start_unitree_lio_sam_mapping.sh
```

这个脚本会启动 `go2_control_by_sdk send_cmd`，实机测试时请把机器狗放在安全空间，手边准备遥控器/急停。

检查输出：

```bash
source /opt/ros/foxy/setup.bash
source /unitree/module/graph_pid_ws/install/setup.bash

ros2 topic list -t | grep -E 'lio_sam_ros2|dog_imu|rslidar|utlidar'
ros2 topic hz /lio_sam_ros2/mapping/odometry
ros2 topic hz /lio_sam_ros2/mapping/map_local
ros2 service list | grep /lio_sam_ros2/save_map
```

保存官方 LIO-SAM 地图：

```bash
cd ~/work/nyush_rm_sentry
./scripts/save_unitree_lio_sam_map.sh ~/work/go2_nav/maps/go2_lio_sam_latest
```

更推荐现在使用统一的官方地图脚本：

```bash
cd ~/work/nyush_rm_sentry
GO2_OFFICIAL_MAP_SOURCE=lio_sam \
CONVERT_TO_PGM=true \
STOP_LIO_SAM_ON_EXIT=false \
./scripts/start_go2_official_map.sh
```

它会：

```text
启动 Go2 内置雷达服务
打开 rt/utlidar/switch
启动 Unitree 官方 graph_pid_ws / LIO-SAM 建图栈
在 VNC 的 :1 display 上打开 Unitree build_map.rviz
等待终端输入
```

交互：

```text
s + Enter  查看 /lio_sam_ros2/mapping/map_local 和 /lio_sam_ros2/save_map 状态
1 + Enter  调用 /lio_sam_ros2/save_map 保存官方全局 PCD
q + Enter  退出
```

输出：

```text
~/work/go2_nav/maps/go2_lio_sam_<timestamp>/*.pcd
~/work/go2_nav/maps/go2_lio_sam_<timestamp>/latest.pcd
~/work/go2_nav/maps/go2_lio_sam_<timestamp>/nav2_map/map.pgm
~/work/go2_nav/maps/go2_lio_sam_<timestamp>/nav2_map/map.yaml
~/work/go2_nav/maps/go2_lio_sam_latest.pcd
```

注意：这条路线使用 Unitree 官方 `lio_sam_ros2/config/params.yaml`，当前配置里输入话题是：

```text
rslidar_points
dog_imu_raw
```

而 Go2 内置雷达实际发布的是：

```text
/utlidar/cloud
/utlidar/imu
```

因此已添加桥接脚本：

```bash
~/work/nyush_rm_sentry/scripts/go2_lio_sam_topic_bridge.py
```

`start_unitree_lio_sam_mapping.sh` 会默认启动它，把话题转成官方 LIO-SAM 期望的名字：

```text
/utlidar/cloud -> /rslidar_points
/utlidar/imu   -> /dog_imu_raw
```

如果 RViz 里看到 `Fixed Frame [map] does not exist`，说明 LIO-SAM 还没有成功发布 `map` frame。先看：

```bash
tail -80 /tmp/unitree_lio_sam_mapping/mapping_qt_test.log
tail -80 /tmp/unitree_lio_sam_mapping/go2_lio_sam_topic_bridge.log
```

之前已观察到的失败原因是：

```text
LidarCheckOut Faild!
/rslidar_points 和 /dog_imu_raw 没有输入
go2_control_by_sdk/send_cmd 载入旧 libddsc 后 undefined symbol: free_iox_chunk
```

现在启动脚本已把 `/usr/local/lib` 放在 `LD_LIBRARY_PATH` 前面，用于修正 `free_iox_chunk`；同时启动 Go2->LIO-SAM 话题桥。

保存服务接口已经确认存在于本机安装包：

```text
/lio_sam_ros2/save_map [lio_sam_ros2/srv/SaveMap]

request:
  float32 resolution
  string destination

response:
  bool success
```

如果服务暂时不存在，保存脚本会 fallback 到：

```bash
ros2 topic pub /lio_sam_ros2/savepcd/savepcd_flag std_msgs/msg/Bool "{data: true}" -1
```

停止官方建图：

```bash
cd ~/work/nyush_rm_sentry
./scripts/stop_unitree_lio_sam_mapping.sh
```

临时验证保存器：

```bash
GO2_MAP_TOPIC=/utlidar/cloud_base \
GO2_MAP_OUTPUT=/tmp/go2_cloud_base_test.pcd \
GO2_SAVE_TIMEOUT=10 \
./scripts/save_go2_builtin_pcd.sh
```

正式保存地图：

```bash
GO2_MAP_TOPIC=/uslam/cloud_map \
GO2_SAVE_TIMEOUT=120 \
./scripts/save_go2_builtin_pcd.sh
```

### 交互式累计 PCD

如果 `/uslam/cloud_map` 暂时不发布完整地图，可以先累计 Go2 内置栈已经去畸变并放到 `odom` frame 的点云：

```text
/utlidar/cloud_deskewed
```

已添加脚本：

```bash
~/work/nyush_rm_sentry/scripts/accumulate_pointcloud2_pcd.py
~/work/nyush_rm_sentry/scripts/start_go2_accumulated_mapping.sh
```

一键启动：

```bash
cd ~/work/nyush_rm_sentry
./scripts/start_go2_accumulated_mapping.sh
```

这个脚本会依次执行：

```text
source Go2 DDS 环境
启动 Go2 内置雷达服务
发送 rt/utlidar/switch = ON
默认打开 RViz 到 VNC
持续订阅 /utlidar/cloud_deskewed 并累计点云
```

终端交互：

```text
1 + Enter  保存当前累计 PCD 并退出
q + Enter  不保存退出
```

默认输出：

```text
~/work/go2_nav/maps/go2_builtin_latest/accumulated_cloud_deskewed_<timestamp>.pcd
~/work/go2_nav/maps/go2_builtin_latest/accumulated_latest.pcd
```

默认使用 `0.05 m` 体素去重，避免长时间累计后文件和内存过大：

```bash
GO2_ACCUM_VOXEL_SIZE=0.05
```

如果希望保存后自动转成 Nav2 `map.pgm/map.yaml`：

```bash
cd ~/work/nyush_rm_sentry
CONVERT_TO_PGM=true ./scripts/start_go2_accumulated_mapping.sh
```

可调参数示例：

```bash
GO2_ACCUM_TOPIC=/utlidar/cloud_deskewed \
GO2_ACCUM_VOXEL_SIZE=0.05 \
GO2_ACCUM_MAP_DIR=~/work/go2_nav/maps/go2_builtin_latest \
START_RVIZ=true \
CONVERT_TO_PGM=true \
./scripts/start_go2_accumulated_mapping.sh
```

注意：这条路线依赖 Go2 官方 `/utlidar/cloud_deskewed` 已经在 `odom` frame 内稳定。如果建图时 `odom` 漂移，累计地图也会跟着变形。最终最理想输入仍然是官方完整地图 `/uslam/cloud_map` 或官方 LIO-SAM 保存出的全局 PCD。

### PCD 转 Nav2 PGM/YAML

已接入开源包：

```text
LihanChen2004/pcd2pgm
```

本机位置：

```text
~/nav_ws/src/pcd2pgm
```

Foxy/arm64 上已经做过兼容处理：

```text
PCL 1.10 使用 boost 风格 PointCloud::Ptr
原代码里的 std::shared_ptr 已改成 pcl::PointCloud<pcl::PointXYZ>::Ptr
```

已添加 wrapper：

```bash
~/work/nyush_rm_sentry/scripts/pcd2pgm_go2.sh
```

默认输入：

```text
~/work/go2_nav/maps/go2_builtin_latest/cloud_deskewed_latest.pcd
```

默认输出：

```text
~/work/go2_nav/maps/go2_builtin_latest/nav2_map/map.pgm
~/work/go2_nav/maps/go2_builtin_latest/nav2_map/map.yaml
~/work/go2_nav/maps/go2_builtin_latest/nav2_map/latest.pgm
~/work/go2_nav/maps/go2_builtin_latest/nav2_map/latest.yaml
```

执行：

```bash
cd ~/work/nyush_rm_sentry
./scripts/pcd2pgm_go2.sh
```

当前实测已成功生成：

```text
map.pgm  153 x 141, 0.05 m/pixel
map.yaml origin = [-0.22, -0.866, 0]
```

当前默认转换参数：

```bash
MAP_RESOLUTION=0.05
PCD2PGM_Z_MIN=0.60
PCD2PGM_Z_MAX=1.80
PCD2PGM_RADIUS=0.15
PCD2PGM_POINT_COUNT=5
```

这组参数是为 Go2 内置 `/utlidar/cloud_deskewed` 累计点云调过的：过低的 `z_min=0.05` 会把地面、机身附近点和低矮噪声一起投影成障碍，导致可走区域变黑。当前累计 PCD 上，黑色占用格从约 `21.4%` 降到了约 `6.3%`。

如果墙体丢得太多，可以逐步降低：

```bash
PCD2PGM_Z_MIN=0.45
```

如果可走区域仍然发黑，可以逐步提高：

```bash
PCD2PGM_Z_MIN=0.80
PCD2PGM_POINT_COUNT=8
```

如果要转换另一个 PCD：

```bash
cd ~/work/nyush_rm_sentry
PCD_INPUT=~/work/go2_nav/maps/go2_builtin_latest/cloud_deskewed_latest.pcd \
MAP_OUT_DIR=~/work/go2_nav/maps/go2_builtin_latest/nav2_map \
MAP_NAME=map \
./scripts/pcd2pgm_go2.sh
```

注意：这个转换是离线工具链，不应该混进 Go2 实时 DDS 通讯域。脚本内部默认使用：

```bash
RMW_IMPLEMENTATION=rmw_fastrtps_cpp
ROS_LOCALHOST_ONLY=1
ROS_DOMAIN_ID=88
```

并清理 `~/cyclonedds/install/lib`，否则 `pcd2pgm` 或 `map_saver_cli` 可能会出现：

```text
bad_alloc caught: std::bad_alloc
map_saver timeout
```

现在这张 `cloud_deskewed_latest.pcd` 只是一段去畸变点云，不是完整走完整场地后的全局地图，所以 `map.pgm` 可以用于验证 Nav2 `map_server` 链路，但还不应当当作最终导航地图。最终需要先走完场地，保存更完整的 PCD，再重新执行 `pcd2pgm_go2.sh`。

## 定位与 Nav2 计划

目标 TF：

```text
map -> odom -> base_link
```

当前优先采用：

```text
odom -> base_link 由 Go2 官方 /utlidar/robot_odom 或 /uslam/localization/odom 提供
map -> odom 后续由 AMCL 或官方 localization 提供
```

不要让多个节点重复发布同一条 TF。尤其要避免：

```text
FAST-LIO 发布 odom -> base_link
Go2 官方栈也发布 odom -> base_link
AMCL/Nav2 又被配置成发布重复 TF
```

Nav2 第一版应尽量简单：

```text
map_server 加载 2D map
localization 使用官方 odom 或 AMCL
planner_server 负责全局路径
controller_server 输出 /cmd_vel
costmap 障碍物来源先用 /utlidar/cloud_base 或 pointcloud_to_laserscan
```

## Go2 cmd_vel 转换

最终 Nav2 会输出：

```text
/cmd_vel
```

需要转换到 Unitree Go2 SDK：

```text
geometry_msgs/Twist
  -> vx, vy, wz
  -> SportClient.Move(vx, vy, wz)
```

已有脚本：

```bash
~/work/nyush_rm_sentry/scripts/go2_cmd_bridge.py
```

后续联调重点：

| 项目 | 说明 |
|------|------|
| `UNITREE_NET_IF` | Go2 SDK 通讯网卡，可能是 `eth0` |
| `GO2_CMD_TOPIC` | bridge 订阅的话题 |
| `GO2_MAX_VX` | 前后速度限幅 |
| `GO2_MAX_VY` | 横移速度限幅 |
| `GO2_MAX_WZ` | 角速度限幅 |
| `GO2_X_SIGN` | X 方向正负 |
| `GO2_Y_SIGN` | Y 方向正负 |
| `GO2_WZ_SIGN` | 角速度正负 |
| `GO2_SWAP_XY` | 如坐标系轴反了再启用 |

测试时必须低速：

```bash
GO2_MAX_VX=0.15 GO2_MAX_VY=0.10 GO2_MAX_WZ=0.25
```

先不用 Nav2，直接发小速度：

```bash
ros2 topic pub /cmd_vel geometry_msgs/msg/Twist \
  '{linear: {x: 0.05, y: 0.0, z: 0.0}, angular: {x: 0.0, y: 0.0, z: 0.0}}' -r 2
```

确认方向正确后再接 Nav2。

## start_robot.sh 的目标

最终希望一条命令启动导航：

```bash
cd ~/work/nyush_rm_sentry
./start_robot.sh
```

新的目标行为：

```text
1. source ROS Foxy / Unitree DDS / navigation workspace
2. 检查 Go2 内置雷达官方话题
3. 启动 map_server / localization / Nav2
4. 启动 pointcloud_to_laserscan 或 cloud obstacle 输入
5. 启动 cmd_vel -> Go2 bridge
6. 可选启动 RViz 到 VNC
7. 默认不启动视觉、不启动决策、不启动 FAST-LIO
```

建议脚本开关：

```bash
NAV_ONLY=true
USE_GO2_BUILTIN_LIDAR=true
START_RVIZ=true
START_FASTLIO=false
START_VISION=false
START_DECISION=false
START_GO2_CMD_BRIDGE=false   # 调试默认不让机器狗动，确认方向后再改 true
```

## 历史 FAST-LIO/L2 分支

仓库里仍可能存在：

```text
config/fastlio_go2_l2.yaml
scripts/start_go2_fastlio_mapping.sh
scripts/start_go2_mapping_with_rviz.sh
scripts/save_go2_fastlio_map.sh
```

这些现在只适用于“外接 Unitree L2 或重新做 raw LIO 实验”的情况，不是当前 Go2 内置雷达主线。当前不要用它们启动建图，否则很容易再次出现移动后坐标系飞走。

## 可选 FAST-LIVO2 分支

FAST-LIVO2 可以作为后续研究分支，但不建议作为当前 Nav2 最小闭环的第一步。

FAST-LIVO2 的输入不是只有雷达和 IMU，而是：

```text
LiDAR
IMU
Camera image
LiDAR-IMU 外参
LiDAR-Camera 外参
Camera 内参
可靠时间同步
```

当前 Go2 上已经有：

```text
/utlidar/cloud
/utlidar/imu
/frontvideostream [unitree_go/msg/Go2FrontVideoData]
```

但 `/frontvideostream` 不是标准 `sensor_msgs/Image`，所以要先做：

```text
Unitree Go2FrontVideoData
  -> 解码
  -> sensor_msgs/Image
  -> camera_info
  -> 与 /utlidar/cloud 和 /utlidar/imu 对齐
```

还需要拿到或标定：

```text
camera intrinsics
lidar -> camera extrinsics
camera timestamp offset
```

此外，FAST-LIVO2 官方代码当前是 ROS1/catkin 风格。我们机器主环境是 ROS 2 Foxy，所以有三种方案：

```text
1. 单独开 ROS1 Noetic workspace 跑 FAST-LIVO2，再用 ros1_bridge 接结果
2. 用 Docker 跑 ROS1 Noetic + FAST-LIVO2
3. 移植 FAST-LIVO2 到 ROS2，工作量最大
```

因此当前建议：

```text
导航闭环：先用 Go2 官方 odom + 2D scan + slam_toolbox
研究/高质量彩色三维建图：另开 FAST-LIVO2 分支
```

## 已试路线与结论

### 1. Unitree 官方 USLAM / LIO-SAM / 累积点云

我们已经试过 Go2 官方内置雷达栈相关话题和服务。机器上可以看到：

```text
/utlidar/cloud
/utlidar/cloud_base
/utlidar/cloud_deskewed
/utlidar/grid_map
/utlidar/height_map
/utlidar/robot_odom
/utlidar/robot_pose
/utlidar/voxel_map
/uslam/cloud_map
/lio_sam_ros2/mapping/map_global
/lio_sam_ros2/mapping/map_local
/lio_sam_ros2/mapping/odometry
/lio_sam_ros2/save_map
```

官方路线的优点是：它确实是 Go2 内置雷达官方支持的方向，理论上最不需要我们手动猜雷达和底盘外参。

但当前实测遇到的问题是：

```text
1. /uslam/cloud_map 并不总是持续发布。
   在没有进入 Unitree App 的官方 3D LiDAR Mapping/SLAM 状态时，
   保存脚本会一直等待 PointCloud2。

2. 官方 LIO-SAM 话题和 save_map 服务存在，
   但 RViz 固定 frame、map frame、TF 发布时序和保存流程还没有稳定收敛。

3. 直接累计 /utlidar/cloud_base 或 /utlidar/cloud_deskewed 可以生成 PCD，
   但这不是一个经过全局优化的正式地图。

4. 用累计 PCD 转 PGM 时，地图容易出现两类问题：
   - 太稀疏：只看到零散黑点，不能作为 Nav2 地图。
   - 过黑：可通行区域被大量投影点染黑，Nav2 会把路也当障碍。
```

所以官方全局点云/官方 LIO-SAM 路线目前保留为后续研究分支，不作为当前 Nav2 最小闭环主线。后面如果继续做这条线，优先要解决的是：

```text
1. 明确如何稳定进入 Unitree 官方 3D LiDAR Mapping/SLAM 状态
2. 确认 /uslam/cloud_map 的真实发布时间和触发条件
3. 打通 /lio_sam_ros2/save_map 的稳定保存路径
4. 用官方全局 PCD 重新调 pcd2pgm 投影高度、分辨率和滤波参数
```

### 2. Point-LIO / FAST-LIO 当前结论

现在已经确认，当前这台 Go2 的内置 `/utlidar/*` topic 不能直接当成 Unitree standalone L1 SDK 的 `/unilidar/cloud` + `/unilidar/imu` 输入喂给 Point-LIO。

实测结果：

```text
/utlidar/robot_odom 静止 5s 漂移约 0.0002 m
Point-LIO /aft_mapped_to_init 静止 5s 漂移约 389 m
```

同时诊断显示：

```text
/utlidar/cloud      frame_id = utlidar_lidar
/utlidar/cloud_base frame_id = base_link
/utlidar/imu        frame_id = utlidar_imu

/utlidar/cloud 的 ring 字段恒为 1
/utlidar/imu 静止加速度均值约为 [3.30, 0.00, 9.81]
/utlidar/cloud_deskewed 当前样本为 odom frame，但 xyz 全 0
```

所以现在的问题不是 `pcd2pgm`，也不是保存地图；是 Point-LIO 的状态估计本身已经在输入阶段发散。单独改 `acc_norm` 只能改变发散形态，不能解决根因。

当前已加入保护：

```bash
cd ~/work/nyush_rm_sentry
./scripts/diagnose_go2_pointlio_inputs.py --duration 5

# start_go2_pointlio_mapping.sh 现在会默认做静止漂移检查。
# 如果静止阶段 /aft_mapped_to_init 漂移超过 0.5m，会自动停止，不保存坏图。
./scripts/start_go2_pointlio_mapping.sh
```

如果要继续研究 Point-LIO，下一步不是继续调 PGM 参数，而是做一个真正的 Go2 L1 adapter：

```text
1. 明确 utlidar_imu -> utlidar_lidar 或 base_link 的旋转外参
2. 把 IMU 数据旋转到 Point-LIO 期望的雷达/IMU坐标系
3. 确认 /utlidar/cloud 的每点 time 字段和 Point-LIO timestamp_unit 完全一致
4. 确认输入点云不是官方栈二次处理/降采样后破坏了 Point-LIO 需要的几何约束
```

在这个 adapter 做好之前，导航主线先不要依赖 Point-LIO 建图。更稳的路线是：

```text
Go2 官方 /utlidar/robot_odom
  -> pointcloud_to_laserscan
  -> slam_toolbox 2D mapping
  -> Nav2 map_server + AMCL
```

### 3. go2_ros2_sdk / slam_toolbox 当前主线

现在已按 `abizovnuralem/go2_ros2_sdk` 的工程思路补了一条稳定 2D SLAM 主线：

```text
/utlidar/robot_odom
  -> /odom
  -> TF: odom -> base_link

/utlidar/cloud_base
  -> /go2_slam/cloud_base
  -> pointcloud_to_laserscan
  -> /scan

slam_toolbox
  -> /map
  -> TF: map -> odom
```

启动建图：

```bash
cd ~/work/nyush_rm_sentry
START_RVIZ=true START_GO2_CMD_BRIDGE=false ./scripts/start_go2_slam_toolbox_mapping.sh
```

脚本交互：

```text
1 + Enter  保存 map.pgm/map.yaml 和 posegraph
s + Enter  查看 /scan、/map、TF、服务和日志状态
q + Enter  退出
```

输出位置：

```text
~/work/go2_nav/maps/go2_slam_toolbox_<timestamp>/map.yaml
~/work/go2_nav/maps/go2_slam_toolbox_<timestamp>/map.pgm
~/work/go2_nav/maps/go2_slam_toolbox_<timestamp>/posegraph.posegraph
~/work/go2_nav/maps/go2_slam_toolbox_latest -> 最新保存的地图目录
```

当前实测已打通：

```text
/scan 有数据
/map 有数据
odom -> base_link OK
map -> odom OK
map -> base_link OK
map_saver_cli 保存成功
slam_toolbox posegraph 保存成功
```

保存地图后启动 Nav2：

```bash
cd ~/work/nyush_rm_sentry
START_RVIZ=true START_GO2_CMD_BRIDGE=false ./scripts/start_go2_nav2_with_rviz.sh
```

`start_go2_nav2_with_rviz.sh` 现在会优先使用：

```text
~/work/go2_nav/maps/go2_slam_toolbox_latest/map.yaml
```

Nav2 里 `map` 这个 TF frame 不是 `map_server` 直接发布的，而是 AMCL 收到初始位姿后发布 `map -> odom`。如果没有初始位姿，RViz/global costmap 会报：

```text
Frame [map] does not exist
Timed out waiting for transform from base_link to map
AMCL cannot publish a pose or update the transform. Please set the initial pose
```

所以脚本现在默认会发布一次初始位姿：

```text
PUBLISH_INITIAL_POSE=true
INITIAL_POSE_X=0.0
INITIAL_POSE_Y=0.0
INITIAL_POSE_YAW=0.0
```

如果机器人在地图里的位置不对，在 RViz 里用 `2D Pose Estimate` 重新点一次即可。调试时先保持：

```bash
START_GO2_CMD_BRIDGE=false
```

还有一个很关键的约束：**建图时生成 `/map` 用的 `/scan`，必须和 Nav2/AMCL 定位时使用的 `/scan` 是同一套参数**。否则 RViz 里会看到 scan 和 2D map 怎么点都对不上，移动后也不会自然收敛。

当前 slam_toolbox 建图和 Nav2 定位已经统一为：

```text
cloud topic:      /utlidar/cloud_base
scan frame:       base_link
min_height:       -0.20
max_height:       2.00
angle_increment:  0.00872665
range_min:        0.10
range_max:        8.0
```

如果改过建图脚本里的 pointcloud_to_laserscan 参数，必须同步改 Nav2 启动脚本里的 `SCAN_*` 参数，并重新建图或重新启动 Nav2。

等 RViz 里地图、定位、global/local plan 都正常，再打开实际运动桥：

```bash
cd ~/work/nyush_rm_sentry
START_RVIZ=true START_GO2_CMD_BRIDGE=true ./scripts/start_go2_nav2_with_rviz.sh
```

## 下一步计划

1. 用 `start_go2_slam_toolbox_mapping.sh` 正式走完整场地，保存一版可用的 `go2_slam_toolbox_latest/map.yaml` 和 `map.pgm`。

2. 用 `START_GO2_CMD_BRIDGE=false ./scripts/start_go2_nav2_with_rviz.sh` 先只启动 Nav2，不让机器狗动，在 RViz 里检查 map、TF、AMCL 粒子、global plan、local plan。

3. 低速打开 `START_GO2_CMD_BRIDGE=true`，测试短距离 2D Goal。先只测 0.5m 到 1m 的小目标，确认 `/cmd_vel` 转 Go2 `SportClient.Move(vx, vy, wz)` 的方向、速度和停止逻辑都正确。

4. 把当前可用流程收敛进 `start_robot.sh`：默认启动 DDS、Go2 内置雷达服务、VNC RViz、Nav2、cmd bridge；默认不启动视觉、不启动决策、不启动 Point-LIO。

5. 如果 2D SLAM + AMCL 精度不够，再回头研究官方 `/uslam/cloud_map` 或重新做 Go2 L1 adapter 给 Point-LIO。这个是精度提升分支，不阻塞当前 Nav2 闭环。

6. 等导航闭环稳定后，再决定是否恢复更高质量的 3D 建图路线，例如官方 LIO-SAM 全局 PCD、FAST-LIVO2 或 Point-LIO 专用适配。

## RealSense D435i 状态与结论

当前 RealSense 不作为导航主线，只作为后续 FAST-LIVO/视觉增强分支保留。原因不是 ROS2 Foxy 单纯坏了，而是 Jetson/Go2 USB 拓扑、RealSense firmware、librealsense backend、realsense-ros wrapper 之间的组合不稳定。

已经验证过的事实：

```text
D435i 可以被 USB 识别，USB type 是 3.2。
RSUSB 版 librealsense 可以枚举设备和 profile。
最小 C++ RSUSB depth 流测试里，部分 profile 可以出帧：
  640x480@15 OK
  640x480@30 OK
  848x480@6/15 OK
部分 profile 会失败：
  424x240@6 FAIL
  640x480@6 FAIL
apt 版 realsense2_camera 或混装 wrapper 启动时会出现：
  control_transfer returned error
  Depth stream start failure
  uvc streamer watchdog triggered
  usb device disconnected
```

所以现在判断为：

```text
不是单个 ROS 参数或 QoS 问题。
不是简单的“ROS 环境老 bug”。
是 RealSense stack 版本/backend/USB 拓扑组合不稳定。
```

当前项目里保留两条修复路线：

```text
Candidate A: clean RSUSB stack
  不 patch Jetson kernel
  在 ~/work/realsense_stack_clean 下从源码构建 librealsense RSUSB + realsense-ros
  不 source ~/nav_ws
  不依赖 apt 版 realsense2_camera

Candidate B: native V4L backend + Jetson L4T kernel patch
  后续备选
  需要按 Jetson/L4T 版本 patch kernel module
  风险和维护成本更高
```

当前优先走 Candidate A：

```bash
cd ~/work/nyush_rm_sentry

# 构建干净 RSUSB stack，默认组合：
#   librealsense v2.51.1
#   realsense-ros 4.51.1
./scripts/build_realsense_clean_rsusb_foxy.sh

# 每次测试前，准备 Jetson USB 参数。
sudo ./scripts/prepare_realsense_rsusb_jetson.sh

# 检查 clean stack 是否真的使用源码 RSUSB librealsense。
./scripts/check_realsense_clean_rsusb.sh

# 先只开 depth，固定已验证过的 profile。
ENABLE_COLOR=false \
ENABLE_DEPTH=true \
ENABLE_IMU=false \
ALIGN_DEPTH=false \
INITIAL_RESET=false \
DEPTH_PROFILE=640,480,15 \
./scripts/start_realsense_clean_rsusb_foxy.sh

source ~/work/realsense_stack_clean/env.sh
timeout 10 ros2 topic hz /camera/depth/image_rect_raw
```

RealSense 分支的验收标准：

```text
1. RSUSB SDK 枚举稳定。
2. 最小 C++ depth-only 流 30 分钟稳定。
3. clean realsense-ros depth-only 30 分钟稳定。
4. color-only 30 分钟稳定。
5. color+depth 30 分钟稳定。
6. align_depth 30 分钟稳定。
7. pointcloud 30 分钟稳定。
8. IMU 30 分钟稳定。
```

在第 3 步通过之前，不接 FAST-LIVO，不把 RealSense 放进主导航启动脚本。

## 常用排障命令

```bash
# VNC
systemctl --user status rviz-vnc.service
ss -ltnp | grep 5901

# DDS
source ~/work/nyush_rm_sentry/scripts/go2_dds_env.sh
ros2 topic list -t | grep -E 'utlidar|uslam'

# 里程计
ros2 topic echo /utlidar/robot_odom --once
ros2 topic hz /utlidar/robot_odom

# 点云
ros2 topic hz /utlidar/cloud_base
ros2 topic hz /utlidar/cloud_deskewed
ros2 topic hz /uslam/cloud_map

# RViz
tail -f /tmp/go2_builtin_rviz/rviz.log
```

## 当前 MID360 + FAST-LIO + Nav2 状态

这部分是当前 Go2 外接 MID360 导航主线的最新进度。目标是先稳定：

```text
MID360
-> Livox driver
-> FAST-LIO
-> /cloud_registered_body
-> pointcloud_to_laserscan /scan
-> map_server + AMCL
-> Nav2
-> Go2 cmd_vel bridge
```

### 已经打通

```text
MID360 驱动能启动，Livox driver 正常。
FAST-LIO 能跑，并发布 odom -> livox_frame 和点云。
livox_frame -> base_link 静态 TF 已经有。
/cloud_registered_body -> /scan 已经改好，不再用 /cloud_registered 依赖动态 odom 转 scan。
map_server 现在改为手动 lifecycle 启动，可以保持 active。
AMCL 也改为手动 lifecycle 启动。
AMCL 初始位姿改为启动参数 set_initial_pose，不再外部发布 /initialpose。
启动脚本现在会按 start_robot 风格逐步等待：
  map_server node -> configure -> active
  AMCL node -> configure -> active
  /scan fresh message
  map -> base_link TF
  可选检查 /particle_cloud 和 /amcl_pose
Nav2 能启动到 active，Foxy BT 插件问题通过 go2_nav2_params_light.yaml 绕开。
```

### 已经踩过并绕开的坑

```text
nav2_bringup localization_launch.py 在这台 Foxy/Jetson 上曾导致 map_server exit -11。
现在绕开 localization_launch.py，脚本手动启动 map_server + amcl。

外部发布 /initialpose 会让 Foxy AMCL 触发：
  Lookup would require extrapolation into the future
然后 AMCL 进程消失。
现在禁用外部 /initialpose，用 AMCL 参数设置初始位姿。

my_nav2_params.yaml 不是当前 Foxy 环境完全兼容的参数文件。
里面有 Humble/新版 Nav2 BT 插件，不能直接用于 Go2 Foxy 主线。
当前使用：
  ~/work/nyush_rm_sentry/config/go2_nav2_params_light.yaml
```

### 当前剩余问题

```text
静止启动看起来正常，但机器人一动 RViz/scan/定位会卡。
当前更像运行时负载或 TF 时间问题，而不是启动问题。

典型日志：
  planner_server: Extrapolation Error looking up robot pose
  requested time 太旧，TF buffer earliest data 已经更新到后面

同时 Jetson 负载很高：
  RViz、AMCL、Livox driver、FAST-LIO 都在抢 CPU。
ROS2 CLI、TF MessageFilter、RViz 显示都可能因此表现为卡住。

如果 /amcl 没死，但 RViz 里的 scan/地图不动，大概率是 TF MessageFilter/drop。
如果 ros2 topic hz /scan 也掉到 0，才是 pointcloud_to_laserscan 或 FAST-LIO 点云链路卡住。
```

### 当前推荐测试顺序

先不要直接跑完整 Nav2。先只跑定位，不跑 navigation，不开重 RViz：

```bash
cd ~/work/nyush_rm_sentry
./scripts/stop_mid360_fastlio_nav2.sh

START_NAVIGATION=false \
START_RVIZ=false \
START_GO2_CMD_BRIDGE=false \
PUBLISH_INITIAL_POSE=false \
AMCL_STRICT_STARTUP=true \
AMCL_REQUIRE_OUTPUT_TOPICS=false \
MAP_SERVER_SETTLE_SEC=2 \
AMCL_SETTLE_SEC=4 \
INITIAL_POSE_X=0.0 \
INITIAL_POSE_Y=0.0 \
INITIAL_POSE_YAW_DEG=0 \
SCAN_TRANSFORM_TOLERANCE=0.50 \
LIDAR_TO_BASE_YAW_DEG=90 \
./scripts/start_mid360_localization_only.sh
```

另开一个终端跑时间戳诊断。慢慢移动或原地转动机器人，观察 `/scan`、FAST-LIO odom、TF 的 age/rate 是否跳变：

```bash
cd ~/work/nyush_rm_sentry
DIAG_DURATION=60 ./scripts/diagnose_mid360_nav_timing.sh
```

诊断里重点看这些行：

```text
/scan
/cloud_registered_body
/Odometry
tf odom->livox_frame
tf livox_frame->base_link
tf map->odom
tf2 odom->base_link
tf2 map->base_link
```

`tf odom->base_link` 如果显示 `no tf` 不一定是错，因为当前 TF 是组合链：

```text
odom -> livox_frame -> base_link
```

所以要看 `tf2 odom->base_link composed` 和 `tf2 map->base_link composed`。

如果 `/scan` 还在 10Hz 左右，但 `tf2 map->base_link` 断，问题在 AMCL/TF。
如果 `/scan` 自己掉到 0Hz，问题在 pointcloud_to_laserscan 或 FAST-LIO 点云链。
如果 `/scan`、`/Odometry`、TF 的 age 明显滞后 ROS now，再测试：

```bash
RESTAMP_BODY_CLOUD=true
```

这只会把给 AMCL/Nav2 用的 body cloud 改成 ROS now 时间，不改 FAST-LIO 本体。

定位-only 验收：

```bash
ros2 topic hz /scan
ros2 run tf2_ros tf2_echo odom base_link
ros2 run tf2_ros tf2_echo map base_link
ros2 node list | grep amcl
timeout 5 ros2 lifecycle get /map_server
timeout 5 ros2 lifecycle get /amcl
```

机器人移动时这些都不能断。确认定位稳定后，再开完整 Nav2：

```bash
cd ~/work/nyush_rm_sentry
./scripts/stop_mid360_fastlio_nav2.sh

START_NAVIGATION=true \
START_RVIZ=true \
START_GO2_CMD_BRIDGE=false \
PUBLISH_INITIAL_POSE=false \
AMCL_STRICT_STARTUP=true \
AMCL_REQUIRE_OUTPUT_TOPICS=false \
MAP_SERVER_SETTLE_SEC=2 \
AMCL_SETTLE_SEC=4 \
INITIAL_POSE_X=0.0 \
INITIAL_POSE_Y=0.0 \
INITIAL_POSE_YAW_DEG=0 \
SCAN_TRANSFORM_TOLERANCE=0.50 \
LIDAR_TO_BASE_YAW_DEG=90 \
./scripts/start_mid360_start_robot_style.sh
```

RViz 只保留轻量显示：

```text
Map
LaserScan
TF
Odom
```

先不要打开 PointCloud、GlobalCostmap、LocalCostmap 的重显示。等定位稳定后，再考虑：

```bash
START_GO2_CMD_BRIDGE=true
```

当前最可能的综合原因：

```text
Foxy + Jetson 高负载
+ FAST-LIO TF 时间略滞后
+ AMCL/Nav2 对 TF 时间敏感
+ RViz/Costmap 显示负担较重
```
