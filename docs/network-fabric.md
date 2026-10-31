# 网络与设备组网

> 状态：设计中 · 上位文档：[总体架构设计 §6 故障域与降级策略](architecture-north-star.md#6-故障域与降级策略)
>
> 本文定义跨设备虚拟局域网（Tailscale）拓扑、路由器多出口状态的感知机制、智能家居与外设接入规范，以及工作站睡眠唤醒（WoL）和 UPS 断电保护联动方案。

## 1. 局域网与 Tailnet 拓扑

```
        校园网物理网口
             │
         AX6000 (rt)  192.168.31.1     局域网默认网关 + 校园网认证 + mwan3 + OpenClash + Wi-Fi
             │ 192.168.31.0/24 (LAN)
     ┌───────┴─────────┬──────────────────┐
   N100 (n100)     工作站 (ws)        手机 / 墨水屏 / 传感器
  100.64.x.2       100.64.x.3         (Wi-Fi 接入 LAN，手机同时加入 Tailnet)
  常驻入口 + HA     Orca + 任务库
  Tailscale 子网路由 + Exit Node
```

| 节点 | Tailnet 主机名 | 网络角色 | 部署说明 |
|---|---|---|---|
| Redmi AX6000 | `rt`（可选） | 局域网唯一默认网关 | 512MB 内存已运行 OpenClash 与 mwan3，不承担 Tailscale 子网路由转发 |
| N100 迷你主机 | `n100` | **Tailscale 子网路由 + Exit Node** | 24 小时常开，通过 SNAT 将 `192.168.31.0/24` 暴露给 Tailnet |
| 工作站 | `ws` | 核心计算与执行节点 | 闲置自动休眠，通过有线网口接收 `n100` 发出的 WoL 唤醒包（见 §7） |
| Kindle KPW5 | `kpw` | 只出站客户端 | 运行 Userspace 网络栈，仅支持主动向 `ws` 发起出站拉取请求 |
| 手机 | `phone` | 移动客户端 | 在校外蜂窝网络下可使用 `n100` 作为 Exit Node 访问校园内网 |

## 2. 主机命名、MagicDNS 与内网 HTTPS

| 配置项 | 设定值 |
|---|---|
| MagicDNS 域名后缀 | `shizuku.ts` |
| 主机命名规范 | 统一使用简短角色名（`n100`、`ws`、`kpw`、`phone`） |
| 服务暴露方式 | 统一使用 `tailscale serve`（自动签发内网 HTTPS 证书），不开公网端口映射 |
| 核心服务端口 | Home Assistant `8123`、渲染服务 `7777`、DS-Bot `13080`、LiteLLM `4000` |

NixOS 通用与分主机网络配置：

```nix
# modules/net/tailscale.nix：工作站与 N100 共用基础模块
services.tailscale = {
  enable = true;
  extraUpFlags = [ "--ssh" ];
  authKeyFile  = "/run/secrets/ts-authkey";
};
networking.firewall.checkReversePath = "loose";   # 启用子网路由或 Exit Node 时必须设为 loose
```

```nix
# hosts/n100/net.nix
services.tailscale.useRoutingFeatures = "server";
services.tailscale.extraUpFlags = [
  "--advertise-routes=192.168.31.0/24"
  "--advertise-exit-node"
  "--advertise-tags=tag:infra"
];
# 为 Tailnet 访问局域网设备开启源地址转换（SNAT），无需修改 AX6000 静态路由
networking.nat = {
  enable = true;
  internalInterfaces = [ "tailscale0" ];
  externalInterface  = "enp1s0";      # 以本机实际有线网卡名称为准
};
services.tailscale-serve = {
  wantedBy = [ "multi-user.target" ];
  after    = [ "tailscaled.service" ];
  serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
  script = "tailscale serve --bg --https=443 http://127.0.0.1:8123";
};
```

```nix
# hosts/workstation/net.nix
services.tailscale.useRoutingFeatures = "client";
services.tailscale.extraUpFlags = [ "--accept-routes" ];
```

Tailnet ACL 策略配置：

```jsonc
{
  "tagOwners": { "tag:infra": ["autogroup:admin"], "tag:iot": ["autogroup:admin"] },
  "autoApprovers": { "routes": { "192.168.31.0/24": ["tag:infra"] } },
  "grants": [{ "src": ["autogroup:admin"], "dst": ["*"], "ip": ["*"] }],
  "ssh": [{ "action": "check", "src": ["autogroup:admin"], "dst": ["tag:infra"], "users": ["root", "shizuku"] }]
}
```

由于 Kindle KPW5 运行在 Userspace 网络模式下无法接收外部主动入站连接，图像同步采用拉取模式：由 KPW5 定时执行 `wget https://ws.shizuku.ts:8443/render/today.png`。

## 3. 子网路由与 Exit Node 选型对比

| 候选方案 | 优势 | 局限 | 结论 |
|---|---|---|---|
| 在 AX6000 上运行 Tailscale 子网路由 | 直接位于默认网关，少一跳中转 | 512MB 内存已由 OpenClash + mwan3 占满，易触发内存不足 | 不采用 |
| **在 N100 上运行子网路由与 Exit Node** | 16GB 内存充裕，NixOS 一行配置即可开启 SNAT 转发 | 局域网转发增加一次千兆内网跳数（延迟 < 0.5ms） | **采用** |
| 在工作站上运行子网路由 | 无需额外设备 | 工作站睡眠期间远程无法访问局域网 | 不采用 |

## 4. 节点失效影响与恢复阶梯

| 故障场景 | 仍可正常工作的模块 | 受影响不可用的模块 | 恢复方式 |
|---|---|---|---|
| **N100 断电或离线** | 工作站本地 Orca、任务库、`evd` 正常运行；局域网内手机可直连 `ws` | 远程 IM 入口（DS-Bot）、n8n 外部采集、Home Assistant、Tailnet 子网路由 | 恢复供电后自动拉起；离线期间工作站本地可照常执行任务 |
| **工作站休眠或关机** | N100 入口正常接收指令并写入排队队列，Home Assistant 本地自动化照常运行 | 依赖工作站本地文件、GPU 或 Orca 的任务 | N100 自动发送有线 WoL 唤醒包；连续 3 次失败后通知人工处理 |
| **AX6000 路由器故障** | Zigbee 设备间直连绑定（Binding）与 ESPHome 板载本地逻辑 | 局域网 Wi-Fi / LAN 通信及全部外网连接 | 本地网线或串口登录路由器恢复 |
| **Tailscale 控制面不可达** | 宿舍局域网内 `192.168.31.0/24` 直连通信与本地自动化 | 校外远程访问 | 等待控制面恢复，不在无人值守时自动执行 `--reset` |
| **校园网外网中断** | 局域网通信、任务库流转、本地模型推理与家居控制 | 云端模型 API、外部订阅源、公网发布 | AX6000 热插拔脚本发出 `system.net.egress` 事件，自动将 `needs = ["net.*"]` 的任务挂起（`parked`） |

## 5. 出口状态感知与任务挂起恢复

为使派发器感知校园网多出口与透明代理状态，采用"路由器上报状态事件 + 能力声明网络依赖 + 规则表自动挂起恢复"三步机制：

### 5.1 路由器侧边沿上报脚本（`/etc/hotplug.d/iface/50-ev-egress`）

```sh
#!/bin/sh
# 仅在接口 up/down 边沿触发上报
[ "$ACTION" = "ifup" ] || [ "$ACTION" = "ifdown" ] || exit 0
STATUS=$(ubus call mwan3 status 2>/dev/null | jsonfilter -e '@.interfaces.*.online' | tr '\n' ' ')
PROXY=$(/etc/init.d/openclash status 2>/dev/null | grep -q running && echo on || echo off)
mosquitto_pub -h 192.168.31.20 -t ev/ingest -q 1 -m "{\"kind\":\"system.net.egress\",
  \"source\":\"rt\",\"subject\":\"网络出口状态变化\",\"severity\":\"info\",
  \"payload\":{\"wan_online\":\"$STATUS\",\"proxy\":\"$PROXY\"}}"
```

### 5.2 能力声明网络依赖

```toml
# capabilities/work.repo.patrol.toml
kind = "work.repo.patrol"
needs = ["net.github"]        # 声明语义依赖名，不硬编码 IP 地址

# maps/net.toml
[net.github]
require = "egress.proxy == \"on\""
on_unmet = "park"             # park | fail | fallback:local
fallback = { egress = "any", model = "ollama:qwen3-8b" }
```

### 5.3 派发器自动挂起与恢复

当某条任务的 `needs` 条件未满足时，派发器将其状态设为 `parked`，并注册监听 `system.net.egress` 事件；待网络恢复后自动解除挂起（`unpark`）并重新派发。Agent 仅读取网络与代理状态，不直接自动重启 AX6000 上的 OpenClash 或修改路由表，以免中断正在进行的网络连接。

## 6. 外部设备接入方式汇总

各类硬件设备接入系统的统一标准是：**状态变化可转化为 `ev add` 任务，或动作可由派发器执行器调用**。

| 设备或协议类型 | 协议栈承载方 | 事件接入链路 | 适用设备 | 复用组件 |
|---|---|---|---|---|
| **Matter（Wi-Fi / Thread）** | HA Matter Server + OTBR | 设备 → Thread/Wi-Fi → Matter Server → HA | 新购智能插座、灯具、传感器 | `services.matter-server` |
| **BLE 传感器广播** | ESPHome `bluetooth_proxy` | BLE 广播 → ESP32 代理节点 → HA 原生 BTHome 集成 | 小米温湿度计 LYWSD03MMC（ATC/pvvx 固件） | ESPHome |
| **Zigbee 传感器与开关** | Zigbee2MQTT + Mosquitto | Zigbee 协调器 → Z2M → MQTT → HA | 门磁、水浸传感器、计量插座、无线开关 | `services.zigbee2mqtt` |
| **USB HID / 串口设备** | Linux `udev` + 守护进程 | 插拔或状态事件 → `systemd` 规则 → `ev add` | UPS 电源（NUT）、数位板、读卡器 | `udev`、`nut` |
| **Linux / OpenWrt 远端主机** | 目标主机 `sshd` | 执行器通过 Tailscale SSH 调用远端命令 | N100、AX6000、`orca-pool` 云服务器 | Tailscale SSH |
| **局域网新设备发现** | Avahi（mDNS / DNS-SD） | 定时运行 `avahi-browse` 比对已知列表 → `meta.device.discovered` | 检测新入网设备或 IP 变化 | `avahi` |
| **网络与热敏打印机** | CUPS / `python-escpos` | 派发器调用 CLI 打印当日清单 | 热敏小票机、常规打印机 | CUPS、`python-escpos` |
| **自定义物联网节点** | Mosquitto MQTT Broker | 设备向 `ev/ingest` 主题发布 JSON 消息 | ESP32 自制节点、OpenEPaperLink AP | Mosquitto |
| **本地文件目录监听** | `systemd.path`（基于 `inotify`） | 指定目录新增文件 → 触发服务执行 `ev add` | 扫描件归档、下载目录、新电子书入库 | `systemd.path` |

ESPHome 蓝牙代理（`bluetooth_proxy`）的最小配置（单块 ESP32 即可覆盖整间宿舍的 BLE 传感器广播）：

```yaml
esphome:
  name: ble-proxy-dorm
esp32:
  board: esp32dev
  framework: { type: esp-idf }
wifi:
  ssid: !secret wifi_ssid
  password: !secret wifi_password
api:
  encryption: { key: !secret esphome_api_key }
esp32_ble_tracker:
  scan_parameters: { interval: 1100ms, window: 1100ms }
bluetooth_proxy:
  active: true
```

## 7. 睡眠唤醒（WoL）、NUT UPS 与夜间批处理

### 7.1 有线 Wake-on-LAN 配置

工作站通过有线网口连接至 AX6000 局域网，睡眠期间由 N100 发送魔术包唤醒：

```nix
# hosts/workstation/hw.nix
networking.interfaces.enp2s0.wakeOnLan.enable = true;   # 网卡名称以本机实测为准
```

```bash
# N100 侧唤醒与连通性确认脚本
wakeonlan -i 192.168.31.255 <ws-mac>
timeout 90 tailscale ping -c 1 ws || wakeonlan -i 192.168.31.255 <ws-mac>
```

### 7.2 NUT UPS 断电保护联动

UPS 通过 USB 数据线连接至常开的 N100（作为 NUT `primary` 主节点），工作站通过局域网以 `secondary` 从节点模式订阅 UPS 状态：

```nix
# hosts/n100/ups.nix：直连 UPS USB 接口
power.ups = {
  enable = true;
  mode = "standalone";
  ups."dorm" = { driver = "usbhid-ups"; port = "auto"; description = "Dorm UPS"; };
  upsmon.monitor."dorm" = {
    user = "upsmon"; passwordFile = "/run/secrets/upsmon"; type = "primary";
  };
  schedulerRules = ''
    RUN 20 NORMAL dorm@localhost "ev add --kind system.power.low --source nut 'UPS 电量剩余 20%'"
    SHUTDOWN 15 dorm@localhost
  '';
  notifyCmd = "/run/current-system/sw/bin/ev add --kind system.power.onbattery --source nut '市电中断，已切换至 UPS 供电'";
};

# hosts/workstation/ups.nix：通过网络监听 N100 上的 UPS 状态
power.ups = {
  enable = true;
  mode = "netclient";
  upsmon.monitor."n100" = {
    system = "dorm@n100"; user = "upsmon";
    passwordFile = "/run/secrets/upsmon"; type = "secondary";
  };
};
```

| 电源事件 | 系统联动处理 |
|---|---|
| 市电中断（切换至电池） | 生成 `system.power.onbattery`，暂停夜间 `batch` 批处理队列 |
| UPS 电量低于 50% | 发送告警推送，工作站保存状态并在 5 分钟内进入挂起或休眠以降低功耗 |
| UPS 电量低于 20% | N100 执行安全关机（此时工作站已完成挂起） |
| 市电恢复供电 | 生成 `system.power.restored`，解除批处理队列暂停并按需唤醒工作站 |

### 7.3 夜间批处理唤醒链路

```toml
# rules/60-batch.toml
[[rule]]
name  = "batch.lane"
order = 500
match = { kind = ["work.video.*", "work.music.*", "work.game.build", "media.*"], lane = "batch" }
to    = "agent:orca"
gate  = { window = "23:00-07:00" }   # 窗口外到达的批处理任务自动转入 parked 状态
```

```nix
systemd.services.ev-batch = {
  script = ''
    exec ${pkgs.systemd}/bin/systemd-inhibit --what=sleep:idle --who=ev-batch \
      --why="Running nightly batch queue" ${pkgs.ev}/bin/ev run --lane=batch --until=07:00
  '';
  serviceConfig = { Restart = "on-failure"; TimeoutStopSec = "30"; };
};
systemd.timers.ev-batch = {
  wantedBy = [ "timers.target" ];
  timerConfig = { OnCalendar = "*-*-* 22:55:00"; Persistent = true; };
};
```

执行流程：若批处理队列非空，N100 在夜间窗口开启时唤醒工作站，工作站启动 `ev-batch.service` 并在持有 `systemd-inhibit` 锁的保护下消费 `batch` 队列；队列排空或到达 07:00 后自动释放锁，工作站按空闲策略恢复休眠。

## 8. N100 内存预算与 OOM 优先级（16GB RAM）

| 常驻服务 | 常驻内存（RSS） | 峰值内存 | 备注 |
|---|---|---|---|
| NixOS 基础系统 + `sshd` + `tailscaled` | 380 MB | 500 MB | 系统底座 |
| Home Assistant Core + SQLite Recorder（保留 10 天） | 700 MB | 1.2 GB | 不额外部署重型时序库 |
| Mosquitto MQTT Broker | 20 MB | 40 MB | 消息中枢 |
| Zigbee2MQTT | 120 MB | 200 MB | 接入 USB 协调器 |
| Matter Server + OTBR（按需启用） | 350 MB | 500 MB | 仅在购入 Matter 设备后开启 |
| n8n 工作流服务 | 450 MB | 900 MB | 外部 Webhook 与 IMAP 采集 |
| LiteLLM 模型网关 | 350 MB | 700 MB | 统一 API 路由与计费 |
| ntfy 推送服务 | 30 MB | 60 MB | 手机消息推送 |
| Litestream | 40 MB | 80 MB | 任务库实时复制 |
| DS-Bot + DSH 容器 | 1.2 GB | 3.0 GB | 常驻对话入口 |
| IM 接入插件 / AstrBot | 300 MB | 1.5 GB | 多平台消息收发 |
| `node_exporter` | 25 MB | 40 MB | 主机指标导出 |
| **常驻服务合计** | **≈ 4.0 GB** | - | 剩余约 12 GB 可用内存 |
| `agent-reach` + 无头 Chromium（按需拉起） | 0（非常驻） | 2.0–4.0 GB | 任务执行完即释放 |

为防止按需启动的浏览器或工作流异常膨胀影响核心家居控制，在 NixOS 中配置 `systemd-oomd` 优先级保护：

```nix
systemd.oomd.enable = true;
systemd.services.n8n.serviceConfig.OOMScoreAdjust = 500;
systemd.services."oci-containers".serviceConfig.OOMScoreAdjust = 300;
systemd.services.home-assistant.serviceConfig.OOMScoreAdjust = -200;
```

N100 整机日常空闲功耗约 7–9W，配合 AX6000（约 10W）全年 24 小时运行总耗电量约 150 kWh。
