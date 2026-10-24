# 智能家居落地技术档案(NixOS + Zigbee2MQTT + ESPHome 栈)

技术档案:把 `dorm-smart.md` 已定的拓扑(HA 本地兜底 + MQTT 主干 + Zigbee/BLE 传感)
落到 NixOS 工作站上的实施级细节——部署形态取舍、三个 systemd 服务的真实选项名、
硬件刷机/接线实操、自动化兜底分层、安全面、断电断网行为矩阵。
选型结论不在此重复;本文档只回答"怎么落地、坑在哪、出处是什么"。

**信息源**:NixOS 官方 wiki 与 nixpkgs 模块源码(2026-10,nixos-unstable)、Zigbee2MQTT
官方文档、ESPHome 官方文档、atc1441/pvvx 固件仓、Tailscale 官方文档。出处在文末汇总。

## 0. 决策速查

| 问题 | 结论 |
|---|---|
| HA 部署形态 | **工作站 `services.*` 原生三件套**(HA + Mosquitto + Z2M),声明式最强、Zigbee 直通零配置;容器/独立盒子是降级与迁移路线,不作首选 |
| Zigbee 协调器 | **ZBDongle-E(EFR32MG21,`ember` 驱动)或 ZBDongle-P(CC2652P,`zstack`)都在 Z2M 官方推荐列**;价差大时谁便宜买谁,略偏向 E(SiLabs 生态固件维护最活跃) |
| LYWSD03MMC | TelinkFlasher 网页 OTA 刷 ATC/pvvx 固件,**可逆**(stock 固件可刷回) |
| LD2410 | UART 256000 8N1 + ESPHome 原生 `ld2410` 组件;买 **C 版**(2.54mm 排针免焊),5V 供电 |
| 自动化兜底 | 手动开关→执行器下沉 **Z2M binding**(断网断服务都活);板上逻辑留 **ESPHome**;跨协议/定时/通知必须放 **HA** |
| Zigbee 密钥 | `network_key` 必换;**NixOS 下不能在 `settings` 里写 `GENERATE`**(每次服务启动重生成 → 启动失败) |
| MQTT 认证 | mosquitto 密码用 `passwordFile`/`hashedPasswordFile`(systemd credentials,不落 nix store);匿名监听只配演示 |
| 断电恢复 | Zigbee 不依赖路由器,工作站带电时全自动照常;Wi-Fi 设备靠 ESPHome 板上逻辑自持,恢复时间分钟级 |

## 1. HA 部署形态对比

| 维度 | `services.home-assistant`(原生) | OCI 容器(HA Container) | 独立小盒子(HAOS) |
|---|---|---|---|
| 声明式程度 | **最高**:`config` attrset 即 configuration.yaml;`lovelaceConfig`/`themes`/`customComponents` 全部入 nix | 仅容器参数声明式;`/config` 卷内 YAML 是黑盒,HA 自己管 | 零:完整 HAOS 用户体验,全靠 UI |
| 升级路径 | 随 `nixos-rebuild` 滚动;nixpkgs 跟 HA 月度版本紧;回滚=选旧 generation(注意 recorder DB 跨版本迁移不可逆,回滚前备份 `/var/lib/hass`) | pin image tag;**`oci-containers` 不会因 rebuild 自动 pull**,改 tag 才更新 | HAOS 内置更新;addons 随上游 |
| Zigbee USB 直通 | 无需直通——Z2M 原生跑,模块内建 `SupplementaryGroups=dialout` + `DeviceAllow` 按 `serial.port` 放行 | `--device=/dev/serial/by-id/...` + 挂 `/dev/serial/by-id` 卷;**已知坑:rootless docker 下容器内 ttyUSB 权限拒绝**,禁用 rootless 需整机重启生效(nixpkgs issue #416817) | USB 直接插盒子,零配置 |
| 上游支持 | NixOS 社区(nixpkgs issue / #homeautomation:nixos.org);**不支持 addons**(改用 `services.*` 原生模块等价物) | 上游支持 | 上游一等公民,addons 全可用 |
| 失效面 | 工作站关机即失明 | 同上 | 独立电源域,工作站开关无感 |
| 适用 | **本站首选**:单机房、工作站即服务器 | 从既有 HA 配置迁移、或想要"UI 可配置"体验 | 断电时段长/工作站常关时迁过去 |

**本站建议**:先按 dorm-smart.md 未决项落地工作站原生栈;若实测"工作站关机 → 宿舍失明"
不可接受,再迁到旧手机/盒子跑 HAOS 或同款 NixOS——迁移成本就是 HA 备份恢复 +
把 zigbee2mqtt/mosquitto 的 dataDir 搬过去,Zigbee 网络凭 `coordinator_backup.json` 可平移。
OCI 容器形态在本站收益最低(丢声明式还踩 USB 权限坑),除非要保留一份既有 `/config` 配置。

### 1.1 原生模块关键选项(`services.home-assistant.*`)

| 选项 | 作用 | 备注 |
|---|---|---|
| `config` | configuration.yaml 的 attrset 形式 | 模块解析 root/platform 级自动装依赖;`config = null` + `configDir` 走 imperative 迁移模式(官方明确"不大可能继续支持",别新用) |
| `extraComponents` | 手动追加组件依赖 | onboarding 需要 `"analytics" "google_translate" "met" "radio_browser" "shopping_list" "isal"` |
| `extraPackages` / `customComponents` / `customLovelaceModules` | Python 包 / HACS 组件 / Lovelace 卡 | 2026.5.1 起内置集成 100% 覆盖(1450/1450) |
| `configWritable` | configuration.yaml 可写 | UI 改配置想持久化就开;代价是与 nix 配置漂移 |
| `openFirewallForComponents` | 按启用组件自动开端口 | 8123 仍默认不对外开放,自行 `networking.firewall.allowedTCPPorts` 或走反代 |
| `lovelaceConfig` / `themes` / `blueprints` | 仪表盘/主题/蓝图 | 全部声明式 |

```nix
# 最小骨架(融合 Mosquitto + Z2M,真实选项名)
services.home-assistant = {
  enable = true;
  extraComponents = [ "isal" "met" "radio_browser" "google_translate" "shopping_list" "analytics" ];
  config = {
    default_config = {};
    # UI 管理的自动化/场景仍走 automations.yaml(放 configDir)
    "automation" = "!include automations.yaml";
    # 或全声明式:config.automation = [ { alias = "..."; triggers = [...]; actions = [...]; } ];
    http.use_x_forwarded_for = true;      # 反代/Tailscale serve 时
    http.trusted_proxies = [ "127.0.0.1" ];
  };
};
```

**secrets 注意**:`config` attrset 渲染进 `/nix/store`(全员可读),凭据类字段别写进去;
要密码的集成(MQTT broker、Tailscale 相关)留给 UI 配置流,secret 落在
`/var/lib/hass/.storage` 而非 store。HA 的 `!secret` 语法在 nix 生成的文件里不可用。

## 2. 三件套 NixOS 模块

### 2.1 Mosquitto(`services.mosquitto.*`)

模块是"listener 列表 + 全局 settings"两层:

| 选项 | 类型 | 要点 |
|---|---|---|
| `listeners` | list | 每项:`port`(默认 1883)/`address`(绑 IP)/`users`/`acl`/`omitPasswordAuth`/`settings`(per-listener freeform,如 `allow_anonymous`、`protocol = "websockets"`、`mount_point`) |
| `users.<name>` | attrset | `password` / `passwordFile` / `hashedPassword` / `hashedPasswordFile`(四选一,assert 强制) + `acl`(topic 级读写) |
| `settings` | freeform | 全局 mosquitto.conf 键值(`persistence`、`log_type` 等);`persistence` 另有专用 bool 选项 |
| `bridges.<name>` | attrset | 桥接到别的 broker(AWS IoT 等),topics 双向映射,宿舍用不到 |

**凭证落盘机制**:四种密码选项里,`*File` 变体经 **systemd credentials** 注入——
秘密文件不进 nix store;而 `password`/`hashedPassword` 内联值会出现在
systemd unit 的 LoadCredential 字面量里=**落 store 全员可读**。
所以:密码一律 `hashedPasswordFile`/`passwordFile` 指到 `/etc/`、`/var/lib/` 或 sops 路径;
hash 用 `nix shell nixpkgs#mosquitto -c mosquitto_passwd -c /tmp/pw <user>` 生成。

```nix
services.mosquitto = {
  enable = true;
  listeners = [{
    address = "127.0.0.1";               # 全栈同机:只绑回环,LAN 面零暴露
    users.zigbee2mqtt = {
      hashedPasswordFile = "/var/lib/mosquitto-secrets/z2m.pwhash";
      acl = [ "readwrite zigbee2mqtt/#" ];
    };
    users.ha = {
      hashedPasswordFile = "/var/lib/mosquitto-secrets/ha.pwhash";
      acl = [ "read homeassistant/#" "readwrite zigbee2mqtt/#" ];
    };
  }];
};
```

### 2.2 Zigbee2MQTT(`services.zigbee2mqtt.*`)

**模块机制**(nixpkgs `zigbee2mqtt.nix` 源码):

- `settings` attrset → 渲染成 yaml → **每次 `ExecStartPre` 拷到 `${dataDir}/configuration.yaml`**
  (`cp --no-preserve=mode`),即 z2m/前端对该文件的一切运行时改写会在下次启动被覆盖。
- 服务用户 `zigbee2mqtt`,`SupplementaryGroups = ["dialout"]`,
  `DeviceAllow` 按 `settings.serial.port` 自动放行——**串口直通零配置**,
  但 `serial.port` 须是绝对路径才进 DeviceAllow。
- 预设(mkDefault):`mqtt.server = mqtt://localhost:1883`、`base_topic = zigbee2mqtt`、
  `serial.port = /dev/ttyACM0`、`permit_join = false`、
  `homeassistant.enabled = config.services.home-assistant.enable`、
  `devices`/`groups` 分离到 `devices.yaml`/`groups.yaml`。
- hardening 全家桶:`PrivateUsers`/`ProtectSystem=strict`/`ReadWritePaths=dataDir` 等。

**`settings` 关键键**(z2m configuration.yaml schema):

| 键 | 值 | 备注 |
|---|---|---|
| `serial.port` | `/dev/serial/by-id/usb-...` | **必须用 by-id**,换口不重配;也是 DeviceAllow 依据 |
| `serial.adapter` | `ember` / `zstack` | E=ember,P=zstack;`ezsp` 已废弃 |
| `serial.baudrate` / `serial.rtscts` | 数/bool | 仅硬流控适配器(ZBT-1/2、SLZB-07)开 `rtscts`;ZBDongle-E/P 都不开 |
| `mqtt.server` / `user` / `password` | — | 密码用 `'!secret.yaml mqtt_password'` 引用,不落 store(见下) |
| `frontend` | `{enabled, port=8080, host, auth_token}` | z2m 2.x 默认启用;`auth_token` 必填或绑 127.0.0.1 |
| `advanced.network_key` | 16B 数组 或 `GENERATE` | **NixOS 陷阱,见下** |
| `advanced.channel` / `pan_id` / `ext_pan_id` | — | 信道建议 15/20/25,改动部分设备需重配对 |
| `permit_join` | bool | 模块默认 false;临时入网走前端或 `zigbee2mqtt/bridge/request/permit_join` |
| `availability.enabled` | bool | 设备在线探测,建议开 |
| `homeassistant.enabled` | bool | HA MQTT discovery;模块默认跟随 HA 开关 |
| `devices`/`groups` | 路径 | 指向 dataDir 内文件——**设备/组定义在 dataDir 不在 nix**,前端可改 |

**两个 NixOS 特有陷阱**:

1. **`network_key: GENERATE` 会每次服务启动重生成**。z2m 的机制是启动时把 `GENERATE`
   回写进 configuration.yaml;NixOS 模块每次 start 又从 store 覆盖回 `GENERATE`,
   于是每次重启都生成新 key → 与协调器 NVRAM 不一致 →
   `startup failed - configuration-adapter mismatch` → 需删 `coordinator_backup.json`
   并重配全网。**正确姿势**:先让 z2m 裸跑一次生成,或 `openssl rand 16` 手搓,
   然后固定写进 `secret.yaml`(放 dataDir,不进 git/store):
   `settings.advanced.network_key = "!secret.yaml network_key";`
   (`pan_id`/`ext_pan_id` 的 `GENERATE` 同坑同治)。
2. **`settings` 整体落 store**,凡是秘密(MQTT 密码、network_key)一律
   `'!secret.yaml key'` 引用,dataDir 里的 `secret.yaml` 才是运行时真值。

### 2.3 ESPHome(`services.esphome.*`)

nixpkgs 现在打的是 **esphome-device-builder**(新版 dashboard):

| 选项 | 默认 | 要点 |
|---|---|---|
| `address`/`port` | `0.0.0.0`/`6052` | dashboard 监听面;`enableUnixSocket` 可改走 `/run/esphome/esphome.sock` |
| `allowedDevices` | `["char-ttyS" "char-ttyUSB"]` | DeviceAllow 清单;按绝对路径列的设备**需在服务启动时已插好** |
| `environmentFile` | null | dashboard 密码/secret 走这里 |
| `remoteBuildOnly`/`remoteBuildAddress`/`remoteBuildPort` | — | 无头远程编译服务器模式 |
| `openFirewall` / `usePing` | false / **已移除** | usePing 对新 dashboard 无效已被模块删除 |

- 状态目录 `/var/lib/esphome`(设备 YAML、PlatformIO 缓存在这,**非声明式**,备份/迁移别漏)。
- dashboard 认证薄弱——宿舍共享网络下绑回环或走反代/Tailscale,别裸开 LAN。

## 3. 硬件落地细节

### 3.1 ZBDongle-E vs ZBDongle-P

| 项 | ZBDongle-P | ZBDongle-E("Plus V2") |
|---|---|---|
| 芯片 | TI **CC2652P**(+20dBm PA) | SiLabs **EFR32MG21**(外置天线) |
| Z2M `serial.adapter` | `zstack` | `ember`(固件 7.4.x–9.1.x;`ezsp` 已 deprecated) |
| 流控 | — | **仅软件流控,不可开 `rtscts`** |
| 刷机 | BSL 模式(按住 boot 插 USB)→ web flasher / XZG Multi-Tool | web:SONOFF Dongle Flasher / Silabs Firmware Flasher;CLI:NabuCasa `universal-silabs-flasher`;固件取 darkxst/Nerivec 构建的 **NCP 7.4.4+**(厂商固件多年未更) |
| 现状 | 老牌稳定,2023 前 Koenkk 唯一推荐 | ember 已转正进 Z2M 官方"推荐"列表;与 HA Connect ZBT-1/2 同门,SiLabs 生态固件更新最勤 |

**通用要点**(z2m 官方建议):
- `serial.port` 用 `/dev/serial/by-id/...` 持久路径;换适配器时 z2m 备份/恢复可免重配对(部分情形仍需重配)。
- 协调器**插 ≥50cm 屏蔽 USB 延长线**,远离 USB3 口/SSD/Wi-Fi 路由器——干扰比换棒子更影响体验。
- 宿舍单房间直连子设备足够;信号差时加 Zigbee 插座当 router(市电设备天然是中继)。

### 3.2 LYWSD03MMC 刷 ATC 固件

- 硬件版本 B1.4/B1.5/B1.6/B1.9 全兼容(atc1441 README 明示;更早批次看 pvvx 仓支持表)。
- **流程**(全程只需 Chrome/Edge,靠 Web Bluetooth):
  1. 下载 `ATC_Thermometer.bin`(atc1441 release;**pvvx 分支功能更多**——NV 存储/更省电/BTHome 广播,社区推荐)
  2. 开 `atc1441.github.io/TelinkFlasher.html` → Connect(广播稀疏需等)
  3. **Do Activation** 授权连接 → 选 bin → Start Flashing
  4. 刷完自动重启;屏不亮就拔电池重上
- **可逆性**:README 底链 stock 固件 zip(`LYWSD03MMC_0130_...zip`)同流程刷回;
  activation 后若要回米家 App 需重新激活。
- **刷后形态**:广播格式可选 ATC 自定义/BTHome/Mi-like;广告间隔 10s–10min 可调;
  屏显 smiley/温湿度;CR2032 续航官方宣称优于原厂固件。
- **接收链路**:BTHome 广播 → ESP32 刷 ESPHome `bluetooth_proxy` → HA 原生 BTHome 集成;
  或 OEPL AP 的 BLE 扫描顺带收(广播格式 ATC_BLE_OEPL 是价签线,温湿度走前一条路更正)。

### 3.3 LD2410 存在传感器 + ESP32

| 项 | 细节 |
|---|---|
| 变体 | LD2410/B/C:协议近似,B 带 BLE(手机 App 调参);**C 是 2.54mm 排针**免焊,A/B 是 1.25mm 小座——买 1.25→2.54 转接线,别硬焊 |
| 供电 | **5V**(VCC/GND 共地),非 3.3V |
| 接线 | 传感器 TX→ESP32 RX、RX→TX(交叉);可选 OUT 脚→GPIO 当直接存在电平 |
| UART | **256000 baud,8N1(parity NONE/stop 1)**;强烈建议硬件 UART——WROOM 用 GPIO16/17(UART2),WROVER 上 16/17 被 PSRAM 占用改选别的 UART 脚 |
| 固件 | ESPHome 原生 `ld2410` 组件:`ld2410:` hub + `binary_sensor`/`sensor`(运动/静止目标距离/能量)/`number`(各门控阈值)/`select`(距离分辨率 0.75m/0.2m、baud_rate)/`switch`(工程模式) |
| 调试 | 工程模式(engineering mode)看 per-gate 能量调阈值,调完关掉;版本号 sensor 为空=线接反/波特率错 |
| 替代 | LD2410B 的 BLE 也可直连 HA bluetooth_proxy,社区报告不稳,**UART 是正道** |

```yaml
uart: { id: ld_uart, tx_pin: GPIO17, rx_pin: GPIO16, baud_rate: 256000, parity: NONE, stop_bits: 1 }
ld2410: { uart_id: ld_uart }
binary_sensor:
  - platform: ld2410
    has_target: { name: "Presence" }
    has_still_target: { name: "Presence still" }
```

### 3.4 Zigbee/Wi-Fi 信道规划

Zigbee 与 2.4G Wi-Fi 同频段,信道按 ZLL 集合选(11/15/20/25,兼容性最好;26 非 ZLL 部分老设备不支持):

| 宿舍 Wi-Fi 信道 | 避让的 Zigbee 信道 | 推荐 |
|---|---|---|
| ch1 | ZB 11–14 | ZB **20/25** |
| ch6 | ZB 16–19 | ZB **11/25** |
| ch11 | ZB 21–24 | ZB **11/15** |

改已有网信道:z2m 会广播网络更新,**睡眠中的电池设备下次唤醒才换**,个别设备需重配对;
仅 `zstack`/`ember` 支持在线换信道。建网时一次选对省得折腾。

## 4. 自动化兜底分层

| 层 | 范围 | 存活条件 | 失效边界 | 该放什么 |
|---|---|---|---|---|
| **Z2M binding** | Zigbee 设备→设备/组直连 | 仅两端设备在线 | 仅限 Zigbee 原生 cluster:`genOnOff`/`genLevelCtrl`/`genScenes`/`lightingColorCtrl`/`closuresWindowCovering`;源端多是遥控器/开关类 | **遥控器/门磁直连灯、插座**——z2m、HA、工作站全挂也活 |
| **ESPHome on-device** | 单板内 GPIO/传感器→板上输出 | 板子有电(连 Wi-Fi 都不需要) | 只看得见本板;调外部设备要 `homeassistant.*` 动作=又回到依赖 HA | 板上按钮→继电器、传感器阈值→板上输出、IR 发射的本地定时 |
| **Z2M groups** | Zigbee 组播控制 | 协调器+z2m 活 | z2m/协调器挂即失效 | 一键控多灯(效率用途>兜底用途) |
| **HA automation** | 跨协议/跨设备/时间/sun/通知/webhook | HA+MQTT+对应链路全活 | 重启丢 delay/wait;错过期间的触发不补发;unavailable 实体的动作被跳过 | 场景编排(回宿/入睡/离宿)、跨协议联动、推送、→agent webhook |

**分配原则**:保命/高频手动的下沉 binding 或板上;**凡是要看"别的设备状态"的必须放 HA**;
agent 只接 HA webhook 做增强判断,不当开关(dorm-smart.md 已定)。

binding 配置(`zigbee2mqtt/bridge/request/device/bind`,或前端 Bind 页):
```json
{"from": "my_remote", "to": "my_bulb"}
# 限定 cluster:{"from": "...", "to": "...", "clusters": ["genOnOff"]}
```

## 5. 安全与权限

### 5.1 Zigbee 网络密钥

- `network_key` **默认值是公知常量**(`[1,3,5,...,13]`),官方明确"strongly suggested you change it";改 key = 全网重配对。
- 密钥本体三处存:`configuration.yaml`/`secret.yaml`(运行配置)、`coordinator_backup.json`
  (协调器状态备份,含 key)、前端 onboarding 生成。
- **备份对象**:`dataDir` 整目录(configuration.yaml、secret.yaml、coordinator_backup.json、
  devices.yaml、database.db)——迁移协调器/换机器全靠它;**secret.yaml 不进 git**。
- Trust Center link key 是协议公知的 `ZigBeeAlliance09`(入网分发用,Zigbee 安全模型如此);
  实际防护靠 network_key + `permit_join` 常态关闭。

### 5.2 MQTT 认证与暴露面

| 面 | 措施 |
|---|---|
| 监听面 | 全栈同机 → listener 只绑 `127.0.0.1`(LAN 零暴露);确有外部客户端再绑 LAN IP + ACL |
| 账号 | 每服务独立账号(z2m/ha/工具脚本),**不要共享**;匿名(`allow_anonymous`)只用于首次联通验证 |
| ACL | 按 base_topic 收窄:`readwrite zigbee2mqtt/#`、`read homeassistant/#`;ESPHome 走 native API 不需要 MQTT 账号 |
| 密码 | `hashedPasswordFile`/`passwordFile`(systemd credentials);生成用 `mosquitto_passwd` |
| 防火墙 | `networking.firewall` 不开 1883;远程订阅走 Tailscale 内网 |

### 5.3 面板暴露面

- Z2M frontend(默认 8080):绑 `127.0.0.1` 或设 `frontend.auth_token`;反代出域名时 `frontend.url` 填对外 URL。
- ESPHome dashboard(6052):弱认证,绑回环/Tailscale。
- HA(8123):`ip_ban` 默认开;`http` 配 `use_x_forwarded_for` + `trusted_proxies` 才认反代。

### 5.4 Tailscale 远程访问 HA(推荐姿势)

- NixOS:`services.tailscale.enable = true`;节点在 tailnet 内直接 `http://<host>.<tailnet>.ts.net:8123`。
- 要 HTTPS/干净域名:`tailscale serve --bg 8123`(tailnet 内代理,需 tailnet 开 HTTPS certificates);
  serve 走回环代理 → HA 端 `trusted_proxies = [ "127.0.0.1" ]` + `use_x_forwarded_for = true`。
- **Funnel(公网暴露)宿舍场景不需要**,别开;ACL 把 8123 收窄到个人设备 tag;节点 `Disable key expiry`。
- 断电语义:远程入口随宿舍路由器一起死,Tailscale 只是"网在时怎么安全地进",不解决断网。

## 6. 断电/断网行为矩阵

| 故障场景 | Wi-Fi 设备(ESPHome/S31/红外) | Zigbee 设备 | BLE(LYWSD03MMC) | 本地自动化存活 |
|---|---|---|---|---|
| **路由器断电**(工作站带电) | 全离线;板上自动化继续;`wifi.ap` 90s 起 fallback 热点;`wifi.reboot_timeout` 15min 重启重连 | **不受影响**(链路不经过路由器):协调器→z2m→mosquitto→HA 全在本机 | 不受影响(广播→ESP32 若同网断则数据滞留板内) | Z2M/binding/HA 全活 |
| **工作站断电**(路由器带电) | 设备在线但无人消费;ESPHome 本地逻辑继续 | mesh 仍在;**binding 直连仍工作**;传感器上报无人收 | 广播继续无人收 | 仅 binding + ESPHome 板上 |
| **全宿舍断电** | 全灭 | 协调器/市电路由灭;电池传感器休眠攒事件 | 广播继续(电池) | 仅设备端逻辑 |
| **恢复供电** | ESP 秒级启动;`wifi` 重连 AP(秒-分钟);`api` 自动重连 HA | z2m systemd 拉起;市电 router 数十秒归网;**电池端设备下个唤醒周期归队(分钟级)** | 恢复上报 | HA/mosquitto/z2m 自启 |

**恢复语义细节**:

- **HA automation**:启动恢复各 automation 上次 on/off(`initial_state` 可强制);
  **变化触发不补发**——HA 停机期间开过的门不会重触发"门磁开";
  运行中的 `delay`/`wait`/`for` 重启即丢,长等待改用 time trigger +
  `homeassistant.start` 触发补偿(HA 官方 troubleshooting 建议)。
- **Zigbee 执行器上电态**:`power_on_behavior`(on/off/toggle/previous)逐设备可配;
  不支持该属性的设备(Hue 用 `hue_power_on_behavior`,部分杂牌没有)断电恢复可能全亮——
  宿舍断电频繁的话,插座/灯选型时把"支持 power_on_behavior"列为硬指标。
- **ESPHome**:`switch.restore_mode`(`ALWAYS_OFF` 默认/`RESTORE_DEFAULT_*` 记忆态/
  `ALWAYS_ON`)决定上电输出;`api.reboot_timeout` 15min 无客户端会重启
  (宿舍常态断网环境可设 `0s` 牺牲 watchdog 换不折腾,或保持默认拿它当自愈);
  `wifi.ap` fallback 热点让断网期仍可救砖。
- **z2m**:启动即恢复 mesh(协调器 NVRAM 有全网态);`availability` 标记
  未及时归队的设备为 offline,方便排查"哪只没醒"。

**对宿舍断电时段的对策**(回 dorm-smart.md 未决项):
若断电时段覆盖夜间(拉闸限电)——关键传感器选电池 Zigbee(断电不影响感知),
执行器接受"来电后按 power_on_behavior 复位"而非记忆态;
若工作站也会断电,HA 迁移到带电池/常电小盒子(§1)的优先级上调。

## 出处汇总

- NixOS 官方 wiki Home Assistant:https://wiki.nixos.org/wiki/Home-assistant
- NixOS 官方 wiki Mosquitto:https://wiki.nixos.org/wiki/Mosquitto
- nixpkgs 模块源码:`nixos/modules/services/home-automation/{home-assistant,zigbee2mqtt,esphome}.nix`、`services/networking/mosquitto.nix`(nixos-unstable)
- MyNixOS 选项索引:https://mynixos.com/nixpkgs/options/services.{home-assistant,mosquitto,zigbee2mqtt,esphome}
- nixpkgs issue #416817(rootless docker ttyUSB 权限):https://github.com/NixOS/nixpkgs/issues/416817
- nixpkgs issue #439276(z2m settings.homeassistant.enabled):https://github.com/NixOS/nixpkgs/issues/439276
- Zigbee2MQTT 文档:adapters README / emberznet / zstack、binding、groups、zigbee-network(密钥/信道)、securing、improve range、mqtt topics:https://www.zigbee2mqtt.io/
- darkxst silabs-firmware-builder(ZBDongle-E NCP 固件):https://github.com/darkxst/silabs-firmware-builder
- ATC_MiThermometer(atc1441 及 pvvx 分支):https://github.com/atc1441/ATC_MiThermometer、https://github.com/pvvx/ATC_MiThermometer、TelinkFlasher:https://atc1441.github.io/TelinkFlasher.html
- ESPHome 文档:ld2410、api(reboot_timeout)、wifi(reboot_timeout/ap_timeout)、switch restore_mode:https://esphome.io/components/
- Home Assistant 文档:http 集成(trusted_proxies)、automation yaml/modes/troubleshooting、zha:https://www.home-assistant.io/docs/
- Tailscale 文档:serve/funnel CLI:https://tailscale.com/docs/features/tailscale-serve
- Zigbee/Wi-Fi 共存:NXP AN 与 Signify Interact 共存指南(zigbeefordomoticz wiki 转引)
