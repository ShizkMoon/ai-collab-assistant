# 智能家居技术栈（Home Assistant + Zigbee2MQTT + ESPHome）

> 状态：设计定稿（部署待常驻节点落地） · 上位文档：[宿舍智能家居方案](dorm-smart.md)、[网络与设备组网](network-fabric.md)
>
> 本文记录 Home Assistant + Mosquitto + Zigbee2MQTT + ESPHome 的选型、传感器刷机与接线方法、本地自动化分层兜底、密钥管理以及断电断网恢复行为。常驻节点因成本原因暂不采购（[ADR 0007](adr/0007-deferred-resident-node.md)），第 1 节曾记录 NixOS 模块配置，工作站改用 Windows 后已改写为部署形态无关的写法，其余章节与部署形态无关。
>
> **参考资料来源**：Zigbee2MQTT 官方文档、ESPHome 官方文档、`atc1441` / `pvvx` 开源固件仓库、Tailscale 官方文档；早期 NixOS 特定配置项来自当时的 NixOS Wiki 与 `nixpkgs` 模块源码，现已按 Windows / 容器形态改写。

## 0. 核心选型汇总

| 决策项 | 确定方案 |
|---|---|
| 服务部署形态 | **待定**：常驻节点落地时在容器与原生包之间重新选择，需要直通 USB 协调器 |
| Zigbee 协调器 | **SONOFF ZBDongle-E**（EFR32MG21，`ember` 驱动）或 **ZBDongle-P**（CC2652P，`zstack` 驱动），两者均在 Z2M 官方推荐列表中 |
| 温湿度计（LYWSD03MMC） | 通过 TelinkFlasher 网页蓝牙 OTA 刷入 `pvvx` / `ATC` 开源固件，切换为 BTHome 广播格式（支持随时刷回原厂固件） |
| 人体存在传感器（LD2410） | 选用 **LD2410C**（2.54mm 标准排针免焊接），5V 供电，通过硬件 UART（256000 8N1）接入 ESP32 运行 ESPHome 原生 `ld2410` 组件 |
| 自动化兜底分层 | 物理开关控制灯具/插座优先配置 **Zigbee Direct Binding**；单板闭环逻辑写入 **ESPHome**；跨设备与通知逻辑放入 **Home Assistant** |
| Zigbee 网络密钥 | 自定义 16 字节 `network_key` 预先生成并保存在 `secret.yaml` 中；**禁止让 Z2M 自动生成**（否则配置被部署脚本覆盖时会重生成密钥导致全网失联） |
| MQTT 认证管理 | Mosquitto 账号密码使用哈希文件，文件权限收紧到仅服务账号可读 |

## 1. Home Assistant 部署方式对比

> 早在 NixOS 上曾用 `services.home-assistant` 声明式部署（当时方案）。工作站改为 Windows、且常驻节点仍未落地后，部署形态改为在下表三种里重新选择，原 Nix 模块配置不再适用。

| 评估维度 | Windows 原生 Python venv | OCI 容器（HA Container，Docker Desktop / Podman） | 独立 HAOS 镜像 |
|---|---|---|---|
| 配置管理 | `configuration.yaml` + `!include` 目录，整目录纳入 Git 与 Restic | 容器启动参数声明式，`/config` 卷内配置仍手写在同一目录 | 完全依赖 Web UI 手动配置与备份 |
| 升级与回滚 | `pip install --upgrade homeassistant`，回滚靠还原点与备份 | 固定镜像 Tag，回滚即改 Tag | 使用 HAOS 内置更新器 |
| Zigbee 串口权限 | 需直通 COM 口（按 USB 描述符固定端口号，避免 COM 号漂移） | 需映射 `COM3` 之类的主机串口，容器内不能自动发现 | 直插直用 |
| 结论 | 与工作站共用一套 Python 与 `upctl`，适合单机 | 依赖虚拟化层，与「纯 Windows 原生」取向冲突 | 推荐作为常驻节点落地时的首选 |

### 1.1 Home Assistant 常用配置项（`configuration.yaml`）

| 配置项 | 功能说明 | 注意事项 |
|---|---|---|
| `default_config:` | 启用默认集成集合（前端、历史、日志等） | 子项按需显式覆盖 |
| `http.use_x_forwarded_for` | 反向代理场景下记录真实来源 IP | 配合 `tailscale serve` 本地反代 |
| `http.trusted_proxies` | 声明可信代理地址 | 只填本机回环地址，不要放通内网段 |
| `automation: !include automations.yaml` | 自动化与主配置分离 | 自动化仍建议在 Web UI 编辑，主配置只保留 `!include` |

```yaml
# configuration.yaml
default_config:
automation: !include automations.yaml
http:
  use_x_forwarded_for: true
  trusted_proxies: [127.0.0.1, "::1"]
```

**凭据安全注意事项**：`configuration.yaml` 与 `automations.yaml` 纳入 Git 时**不得出现明文密码或 Token**。需要认证的集成（MQTT、ESPHome 加密密钥等）统一通过 Web UI 的配置向导（Config Flow）录入，密钥保存在 `config/.storage/` 下，该目录只做 Restic 备份、不进 Git。

## 2. Mosquitto、Zigbee2MQTT 与 ESPHome 配置

以下路径用 `{{dataDir}}` 表示各服务自身的数据目录，具体位置随部署形态而定（容器挂载卷或 Windows 原生服务的 `%ProgramData%\<service>\`）。

### 2.1 Mosquitto

由于 Home Assistant、Zigbee2MQTT 与本地桥接脚本均运行在同一台主机上，Mosquitto 默认仅监听本地回环地址 `127.0.0.1`，并为每个服务分配独立账号与 Topic ACL。密码用 `mosquitto_passwd -c <file> <user>` 生成哈希文件，权限收紧到仅服务账号可读：

```conf
# mosquitto.conf
listener 1883 127.0.0.1
allow_anonymous false
password_file {{dataDir}}/passwd
acl_file      {{dataDir}}/acl
```

```
# acl
user zigbee2mqtt
topic readwrite zigbee2mqtt/#
topic readwrite homeassistant/#
user ha
topic readwrite homeassistant/#
topic readwrite zigbee2mqtt/#
```

### 2.2 Zigbee2MQTT

Z2M 原生配置放在 `{{dataDir}}/configuration.yaml`。**Windows 下串口必须按 USB 设备描述符固定，不能用 COM 号**——换个接口 COM 号就会漂移，用 `serial.port` 写 COM 号等于把配对状态绑死在物理插口上。稳妥做法是在设备管理器里按硬件 ID 查端口，或让 Z2M 使用 `by-id` 等价的目标（Windows 侧可借助 `usbip` / 固定端口映射实现）。

| 配置键 | 设定值 | 说明 |
|---|---|---|
| `serial.port` | 协调器的固定串口标识 | **不要写裸 COM 号**，防止更换 USB 接口或重启后设备号漂移 |
| `serial.adapter` | `ember`（ZBDongle-E）或 `zstack`（ZBDongle-P） | ZBDongle-E 使用新版 `ember` 驱动（旧名 `ezsp` 已废弃） |
| `serial.rtscts` | `false` | ZBDongle-E / P 均不使用硬件流控，保持关闭 |
| `mqtt.password` | `"!secret.yaml mqtt_password"` | 从 `{{dataDir}}/secret.yaml` 读取密码 |
| `advanced.network_key` | `"!secret.yaml network_key"` | **切勿写 `"GENERATE"`**（见下方说明） |
| `advanced.channel` | `15` / `20` / `25` | 避开宿舍 2.4GHz Wi-Fi 主信道（见 §3.4） |
| `permit_join` | `false` | 日常保持关闭，仅在添加新设备时通过 Web 前端临时开启 |

**配置 `zigbee2mqtt` 的两项关键注意事项**：

1. **预先生成 `network_key` 再写死，不要交给 Z2M 自动生成。** Z2M 首次启动时若没有密钥会随机生成并回写 `configuration.yaml`；一旦 `configuration.yaml` 被部署脚本或模板覆盖、又恰好回到 `"GENERATE"`，就会重新生成密钥，与协调器 NVRAM 中保存的网络状态冲突（报错 `configuration-adapter mismatch`），全网失联。正确做法是预先生成 16 字节随机密钥写入 `{{dataDir}}/secret.yaml`，`configuration.yaml` 里只保留 `advanced.network_key: "!secret.yaml network_key"`，部署脚本不覆盖该文件。
2. **设备别名与分组保存在数据目录**：把 `devices` 与 `groups` 指向 `{{dataDir}}` 内部文件（默认就是），在 Z2M Web 前端重命名设备即可持久化，升级镜像或重装服务不会丢。

### 2.3 ESPHome

ESPHome 仅在编译与 OTA 更新固件时需要开启 Dashboard 服务（默认端口 `6052`）；日常运行时，已刷好固件的 ESP32 节点直接通过 ESPHome Native API（加密 TCP 长连接）与 Home Assistant 通信，不依赖常驻的 `esphome` 服务。

## 3. 硬件选购、刷机与接线指南

### 3.1 Zigbee 协调器：ZBDongle-P 与 ZBDongle-E 对比

| 参数项 | SONOFF ZBDongle-P | SONOFF ZBDongle-E |
|---|---|---|
| 主控芯片 | TI **CC2652P**（内置 +20dBm 功放） | SiLabs **EFR32MG21** |
| Z2M 驱动名 | `zstack` | `ember`（需配合 NCP 7.4.x+ 固件） |
| 硬件流控 | 关闭 | 关闭（仅软件流控，开启 `rtscts` 会导致无法通信） |
| 固件刷写工具 | 按住 Boot 键插电进 BSL，使用 Web Flasher 或 `cc2538-bsl` | 免拆壳，直接使用 SONOFF 官方网页刷机工具或 `universal-silabs-flasher` |

**抗干扰安装要求**：协调器必须通过 **0.5 米以上的屏蔽 USB 2.0 延长线**引出，远离迷你主机的 USB 3.0 接口、金属机箱与 Wi-Fi 路由器天线，以减少 2.4GHz 底噪干扰。

### 3.2 小米温湿度计 2（LYWSD03MMC）刷入开源固件

1. 使用桌面或安卓端 Chrome / Edge 浏览器打开 [`atc1441.github.io/TelinkFlasher.html`](https://atc1441.github.io/TelinkFlasher.html)，下载 `pvvx` 分支的最新固件 `.bin` 文件。
2. 点击 `Connect` 配对温湿度计，点击 `Do Activation` 获取原始密钥，随后选择固件文件点击 `Start Flashing`（全程约 30 秒，无线完成无需拆壳）。
3. 刷入后在同一网页将广播格式设为 **BTHome v2**，广播间隔设为 30–60 秒。
4. 宿舍内任一运行 ESPHome `bluetooth_proxy` 的 ESP32 节点收到广播后，Home Assistant 会通过内置 BTHome 集成自动发现并添加设备。

### 3.3 LD2410C 毫米波人体存在传感器 + ESP32 接线与配置

| 项目 | 规范说明 |
|---|---|
| 型号选择 | 选择 **HLK-LD2410C**（标准 2.54mm 排针，可直接插杜邦线，免去焊接 1.25mm 小间距端子） |
| 供电要求 | **必须接 ESP32 的 5V（VIN）引脚**与 GND（LD2410 内部稳压要求 5V 输入，接 3.3V 无法稳定工作） |
| 串口接线 | 传感器 `TX` 接 ESP32 `GPIO16 (RX2)`，传感器 `RX` 接 ESP32 `GPIO17 (TX2)`（交叉连接，使用硬件 UART2） |
| 串口参数 | 波特率 **256000**，数据位 8，校验位 NONE，停止位 1 |

ESPHome 节点配置片段：

```yaml
uart:
  id: ld_uart
  tx_pin: GPIO17
  rx_pin: GPIO16
  baud_rate: 256000
  parity: NONE
  stop_bits: 1

ld2410:
  uart_id: ld_uart

binary_sensor:
  - platform: ld2410
    has_target:
      name: "Dorm Presence"
    has_still_target:
      name: "Dorm Still Presence"
```

首次安装后可在 Home Assistant 中临时开启传感器的"工程模式（Engineering Mode）"开关，观察无人状态下各距离门的底噪能量值，将各门静止灵敏度阈值设在底噪上方 10–15% 处，以过滤风扇或窗帘摆动引起的误报；调校完毕后关闭工程模式以减少串口与无线报文流量。

### 3.4 Zigbee 与 2.4GHz Wi-Fi 信道避让

Zigbee 与 2.4GHz Wi-Fi 共用频段，建网时按宿舍主 Wi-Fi 信道选择不重叠的 Zigbee 信道（优先在 11、15、20、25 四个 ZLL 标准信道中选择）：

| 宿舍 2.4GHz Wi-Fi 信道 | 重叠的 Zigbee 信道 | 推荐选择的 Zigbee 信道 |
|---|---|---|
| Wi-Fi 信道 1 | Zigbee 11–14 | **20 或 25** |
| Wi-Fi 信道 6 | Zigbee 16–19 | **11 或 25** |
| Wi-Fi 信道 11 | Zigbee 21–24 | **11 或 15** |

## 4. 自动化四层兜底设计

为保证系统在网络中断、服务重启或工作站关机时仍具备基础可用性，自动化逻辑按依赖范围从底向上分为四层：

| 层级 | 作用范围 | 正常运行前提 | 适用场景 |
|---|---|---|---|
| **1. Zigbee Direct Binding** | Zigbee 无线开关/遥控器直连控制 Zigbee 灯具或插座 | 仅需开关与受控灯具/插座带电（Z2M 与 HA 全部停机仍可工作） | 床头与门口无线开关控制主照明 |
| **2. ESPHome 板载自动化** | 单个 ESP32 开发板内部的传感器输入与 GPIO / 红外输出 | 仅需开发板带电（无需 Wi-Fi 与 HA） | 板载物理按键切换继电器、过温保护断电 |
| **3. Home Assistant 本地自动化** | 跨协议设备联动（Zigbee + BLE + Wi-Fi）、定时控制、高危安全告警 | 常驻节点、Mosquitto、Z2M 与 HA 正常运行（无需外网与工作站） | 回宿亮灯、离宿断电、入睡关灯、水浸告警 |
| **4. 派发器与 Agent 场景** | 结合日历、外部信息、墨水屏渲染与自然语言摘要的跨领域编排 | 常驻节点与工作站 `evd` 正常运行 | 晨间早报推送、出门携物清单渲染、异常用电判断 |

Zigbee 设备直连绑定（Direct Binding）可在 Z2M Web 前端的"绑定（Bind）"标签页配置，或向 `zigbee2mqtt/bridge/request/device/bind` 发布 JSON：

```json
{"from": "bedside_switch", "to": "desk_light_strip", "clusters": ["genOnOff", "genLevelCtrl"]}
```

## 5. 断电与断网场景下的恢复行为

| 故障场景 | Wi-Fi 设备（ESPHome / 红外） | Zigbee 设备网络 | BLE 温湿度计 | 自动化可用范围 |
|---|---|---|---|---|
| **仅路由器断电 / 外网中断**（常驻节点带电） | 暂时离线（ESPHome 板载逻辑继续运行） | **完全正常**（USB 协调器、Z2M、Mosquitto、HA 均在常驻节点本地闭环） | ESP32 代理随 Wi-Fi 离线暂停转发 | Zigbee 传感器、开关与 HA 本地自动化全部正常 |
| **常驻节点关机或重启** | 在线但无 HA 接收 | **Zigbee Direct Binding 直连开关仍可正常控灯** | 持续广播 | 物理开关直连控灯与 ESPHome 板载逻辑可用 |
| **全宿舍拉闸停电后恢复供电** | ESP32 秒级启动并自动重连 Wi-Fi 与 HA | 常驻节点开机自启 Z2M 恢复网络；市电插座数十秒内归队，电池传感器在下个唤醒周期归队 | 持续广播，零恢复时间 | 供电恢复后约 1–2 分钟全栈自动恢复 |

**断电恢复配置细节**：

- **灯具与插座上电状态（`power_on_behavior`）**：在 Z2M 中将宿舍灯具的 `power_on_behavior` 统一设为 `off`（或 `previous`），防止夜间宿舍恢复供电时所有灯光突然全亮；将路由器、常驻节点与充电器所在插座设为 `on`（来电自动导通）。
- **Home Assistant 重启补偿**：HA 重启期间错过的边沿事件不会自动重放，且正在执行中的长时间 `delay` 或 `wait_template` 会被中断。因此，超过 5 分钟的延迟操作统一改为基于时间戳的定时触发，或在 `homeassistant.start` 事件触发时检查当前传感器状态进行补偿。
- **Z2M 数据目录备份**：将 Z2M 数据目录（包含 `configuration.yaml`、`secret.yaml`、`coordinator_backup.json`、`devices.yaml`、`database.db`）纳入每日 Restic 备份，更换协调器硬件或重装系统时可直接恢复全网配对状态。
