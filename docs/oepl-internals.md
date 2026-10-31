# OpenEPaperLink 内部机制解析

> 状态：技术参考档案 · 关联文档：[墨水屏硬件选型](eink-display-modules.md)、[墨水屏交互设计](eink-modules-ux.md)、[电子价签刷机与验收](esl-tag-ops.md)
>
> 本文梳理 OpenEPaperLink（OEPL）开源电子价签系统的底层架构，涵盖 AP 固件设计、三条无线射频通道的协议细节、各标签主控芯片家族、推图与 OTA 传输流程、低功耗睡眠模型及已知硬件限制。
>
> **资料来源**：OpenEPaperLink GitHub 主仓库源码（`oepl-proto.h`、`oepl-radio-v2.h`、`tag_types.h`、`ble_writer.cpp`、`od_session.cpp`、`powermgt.h` 等）、官方 Wiki 及各 `Tag_FW_*` 子仓库。

## 1. 系统三平面拓扑

```
上层内容源（渲染服务 HTTP API / Home Assistant 集成 / 内置模板）
    │
    ▼  ESP32-S3 主控板（运行 AP 固件：Wi-Fi 接入 + LittleFS 存储 + 图像量化 + WebUI）
    │    │
    │    ├──► 串口协处理器通道（UART 115200 bps v1 ASCII / 2 Mbaud v2 COBS 帧）：
    │    │     · ESP32-C6 / H2  → IEEE 802.15.4 @ 2.4GHz（自定义裸 MAC 协议，非 Zigbee）
    │    │     · TLSR825x       → IEEE 802.15.4 或 2.4GHz GFSK（hwType 0xF8/0xF9）
    │    │     · CC1101 模块    → Sub-GHz GFSK @ 868 / 915 MHz
    │    │
    │    └──► ESP32-S3 内置 BLE 射频（与 Wi-Fi 分时复用）→ BLE 电子价签
    ▼
电子价签终端（Tag：深度休眠 → 定时唤醒发起 Check-in → 按块拉取图像并刷屏）
```

核心通信原则：

- **标签永远主动发起通信（Pull 模型）**：为实现单颗纽扣电池数年续航，价签在绝大多数时间内关闭射频处于 1–2µA 深度睡眠，仅按设定周期唤醒并发送查询帧（Check-in），AP 收到后立即在 5ms 窗口内应答（见 [Tag protocol timing](https://github.com/OpenEPaperLink/OpenEPaperLink/wiki/Tag-protocol-timing)）。
- **多射频并存**：单台 ESP32-S3 AP 可同时运行内置 BLE 扫描与外挂 ESP32-C6 的 802.15.4 射频，同时管理汉朔 BLE 标签与 Solum M2/M3 标签。
- **多 AP 协同**：同一局域网内的多个 OEPL AP 通过 UDP 组播自动发现并同步 `tagDB.json`（见 [Multiple Access Points](https://github.com/OpenEPaperLink/OpenEPaperLink/wiki/Multiple-Access-Points)）。

## 2. AP 固件架构（`ESP32_AP-Flasher`）

AP 固件基于 Arduino / PlatformIO 构建，主力硬件目标为 **ESP32-S3 N16R8**（16MB Flash + 8MB PSRAM；其中 PSRAM 为处理 4.2" 及以上多色位图缓冲的硬性要求）。

| 模块 | 实现机制 | 对应源码文件 |
|---|---|---|
| 任务调度 | 基于 FreeRTOS 多任务：`ledTask`、`APTask`、`BLETask`、`usbFlasherTask`、`webFlasherTask` | `main.cpp` |
| HTTP 与 WebSocket 接口 | 基于 `AsyncWebServer`，提供 `/imgupload`、`/jsonupload`、`/get_db`、`/tag_cmd`、`/led_flash`、`/flash_tlsr`、`/update_c6` 等约 40 个端点 | `web.cpp` |
| 文件系统存储 | LittleFS：保存 `tagDB.json`、`/tagtypes/*.json`（屏幕硬件参数定义）及待下发图像缓存 | `storage.cpp` |
| 内容生成与模板 | `contentmanager.cpp` 支持约 28 种内置卡片模式，或直接接收外部渲染服务上传的图像 | `contentmanager.cpp` |
| 图像量化与压缩 | 解码 Baseline JPEG → 缩放至目标分辨率 → 量化至 `colortable` → 打包为 1bpp/2bpp 位图 → 可选 G5 或 zlib 压缩 | `makeimage.cpp` |
| 射频接口层 | `zbs_interface.cpp`（串口协处理器）、`cc_interface.cpp`（CC1101）、`ble_writer.cpp`（BLE）、`v2transport.cpp`（串口 v2 协议） | `src/` |

### 2.1 `tagtypes` 屏幕参数定义结构

`resources/tagtypes/NN.json`（`NN` 为十六进制 `hwType` 编号）定义了每款价签的物理规格：

| 字段名 | 含义 | 示例（`01.json`：Solum M2 2.9"） |
|---|---|---|
| `width` / `height` | 屏幕物理像素分辨率 | `296` × `128` |
| `bpp` | 每像素位深 | `2`（支持黑白红三色） |
| `colortable` | 逻辑色名到 RGB 的映射表 | `white` / `black` / `red` |
| `rotatebuffer` | 帧缓冲预旋转角度（0–3 对应 0°–270°） | `1`（旋转 90°） |
| `g5_compression` / `zlib_compression` | 该型号首次支持对应压缩算法的标签固件版本号 | `"29"` / `"27"` |
| `shortlut` | 是否支持快速刷新短波形表（Short LUT） | `2` |
| `options` | 附加外设列表（如按键、LED、NFC） | `["button"]` |

## 3. 射频通道一：IEEE 802.15.4 @ 2.4GHz（Solum M2 / M3 主力协议）

该通道直接使用 **IEEE 802.15.4 裸 MAC 帧（非 Zigbee 协议栈）**，固定 PAN ID 为 `0x4447`，采用 8 字节扩展 MAC 地址，单帧最大载荷 ≤ 125 字节（定义于 `oepl-proto.h`）。

### 3.1 无线数据包交互流程

| 数据包宏名 | 标识值 | 传输方向 | 协议作用 |
|---|---|---|---|
| `PKT_PING` / `PKT_PONG` | `0xED` / `0xEE` | Tag ↔ AP | 标签首次入网时扫描 11–26 信道，选择信号最强的 AP |
| `PKT_AVAIL_DATA_REQ`（ADR） | `0xE5` | Tag → AP | **周期唤醒报到（Check-in）**：上报电池电压（mV）、温度、RSSI、LQI、`hwType`、唤醒原因与当前固件版本 |
| `PKT_AVAIL_DATA_INFO` | `0xE6` | AP → Tag | **AP 应答**：返回待下发数据的 `dataVer`（MD5 低 8 字节）、`dataSize`、`dataType`、`dataTypeArgument` 与下次睡眠时长 `nextCheckIn` |
| `PKT_BLOCK_REQUEST`（RQB） | `0xE4` | Tag → AP | 标签按 4KB 块（Block）请求数据，附带 42 片的请求位图（Bitmap） |
| `PKT_BLOCK_PART` | `0xE8` | AP → Tag | 下发数据分片（每片有效载荷 99 字节，42 片组成 1 个 4KB Block） |
| `PKT_XFER_COMPLETE` / `_ACK` | `0xEA` / `0xEB` | Tag ↔ AP | 标签确认所有分块接收完毕并校验通过，开始驱动墨水屏刷新 |
| `PKT_TAG_RETURN_DATA` | `0xE1` / `0xE2` | Tag → AP | 标签向 AP 回传自定义上行数据（如按键触发、NFC 读取结果） |

关键时序机制：

- **5ms 极短接收窗**：标签发出 `ADR` 后仅开启接收机 **5ms**（`DATA_REQ_RX_WINDOW_SIZE`）；若无数据更新则立即关断射频继续休眠。
- **动态睡眠时长控制**：`nextCheckIn` 最高位 `bit15 = 0` 时表示按分钟休眠，`bit15 = 1` 时表示按秒休眠（用于多块连续传输时命令标签 5 秒后立即重连）。
- **分片重传与保电放弃**：若某个 4KB 块中丢失个别分片，标签仅在位图中置位缺失的分片请求重传；连续 14 次（`DATA_REQ_MAX_ATTEMPTS`）请求失败则触发 `XTO` 超时放弃，退避休眠以保护纽扣电池。

### 3.2 主控 ESP32-S3 与射频协处理器之间的串口协议（v1 与 v2）

| 协议版本 | 串口速率与成帧方式 | 核心特性 |
|---|---|---|
| **v1（传统版）** | `115200` baud，ASCII 短命令（`ADR>` / `RQB>` / `SDA>`） | 每次标签请求数据块时需实时经串口向 S3 索取，串口传输耗时直接计入标签射频开启时间 |
| **v2（高速缓存版）** | **2 Mbaud**，COBS 字节填充 + CRC16 + 滑动窗口重传 | S3 预先将待下发图像通过 `DATA_CHUNK` 灌入 ESP32-C6 协处理器的 **256KB 内存块缓存（Block Cache）**；标签唤醒请求时由 C6 直接从本地内存毫秒级应答，大幅缩短标签唤醒耗电时间 |

## 4. 射频通道二：BLE 蓝牙（汉朔 TLSR / Gicisky / OpenDisplay）

AP 利用 **ESP32-S3 自身内置的 BLE 射频**进行被动扫描（与 Wi-Fi 分时复用，扫描参数为 `interval = 320ms`、`window = 30ms`）。BLE 价签日常通过周期性**广播包（Advertising）**上报状态（默认约 60 秒一次），平时不维持蓝牙连接；仅当 AP 存在待下发的新图像时，才在收到广播后主动向标签发起临时 GATT 连接并写入图像分片。

AP 的 `ble_filter.cpp` 原生识别以下三种 BLE 广播与传输协议：

| 固件协议族 | 广播厂商标识（Manufacturer ID） | GATT 传输与安全机制 | 适用标签硬件 |
|---|---|---|---|
| **`ATC_BLE_OEPL` / `OpenEPaperLink_TLSR`** | `0x1337`（小端字节序 `0x37 0x13`） | 连接 GATT 服务 `0x1337`，通过控制特征发送命令字与 240B 图像分片（明文传输） | 刷入开源固件的**汉朔 Stellar / Nebular（TLSR8359/8258）**系列 |
| **Gicisky / Picksmart 原厂协议** | `0x5053`（ASCII `"SP"`） | 连接 GATT `0xFEF0 / 0xFEF1 / 0xFEF2` 传输图像 | 电商在售的 Gicisky 蓝牙价签（无需拆机，原厂即支持） |
| **OpenDisplay 协议** | `0x2446` | 支持 **AES-128-CMAC 握手与 AES-CCM 加密会话**（密钥保存在 AP NVS 中，实现于 `od_session.cpp`） | 刷入新一代 OpenDisplay 开源固件的 BLE 标签 |

**BLE 通道限制**：ESP32-S3 同一时刻只能与 1 个 BLE 标签建立 GATT 连接传输图像（传输期间暂停被动广播扫描），适合房间内十余个标签的低频更新场景。

## 5. 射频通道三：Sub-GHz @ 868 / 915MHz（Chroma 系列）

针对采用 TI `CC1110` 或 `CC1310` 芯片的 DisplayData Chroma 系列价签，AP 通过外挂 **CC1101 射频模块**（官方推荐选用晶振稳定的 **亿佰特 Ebyte E07-900M10S** 模块，避开廉价绿色公版模块）在 868MHz 或 915MHz 频段以 GFSK 调制通信，具备更强的穿墙能力且完全避开 2.4GHz 频段干扰。

## 6. 标签端主控芯片家族汇总

| 芯片家族 | CPU 内核与存储规格 | 射频通道 | 对应开源固件仓库 | 代表价签型号 |
|---|---|---|---|---|
| **ZBS243 / SEM9110** | 三星定制 8051 @ 16MHz，64KB Flash / 8KB XRAM，休眠电流 ~1µA | 802.15.4 (2.4GHz) | [`Tag_FW_ZBS243`](https://github.com/OpenEPaperLink/Tag_FW_ZBS243)（SDCC 编译） | Solum M2 全系（`ST-GR16000` / `29000` / `42000` / `750BN`） |
| **nRF52811** | ARM Cortex-M4，192KB Flash / 24KB RAM | 802.15.4 (2.4GHz) | [`Tag_FW_nRF52811`](https://github.com/OpenEPaperLink/Tag_FW_nRF52811)（含独立 Bootloader） | Solum M3 Newton（`EL022H3WRA` / `EL029H3WRA`） |
| **EFR32xG22** | ARM Cortex-M33 | 802.15.4 (2.4GHz) | [`Tag_FW_EFR32xG22`](https://github.com/OpenEPaperLink/Tag_FW_EFR32xG22) | Solum M3 SiLabs 版（`EL0xxF5` / `F6`，序列号末尾印有 `"Silabs"`） |
| **TLSR8359 / 8258** | Telink 32-bit RISC / 类 ARM 核，512KB Flash / 64KB RAM | **BLE**（或 802.15.4） | 主仓 `ARM_Tag_FW/OpenEPaperLink_TLSR` 及 [`ATC_TLSR_Paper`](https://github.com/atc1441/ATC_TLSR_Paper) | **汉朔 Stellar-M / L / XL、Nebular 全系**（白框 4.9V 批次） |
| **CC1110** | TI 8051 @ 26MHz，32KB Flash / 4KB RAM | Sub-GHz | [`Tag_FW_Chroma`](https://github.com/OpenEPaperLink/Tag_FW_Chroma) | DisplayData Chroma 29 / 42 / 60 / 74 |
| **CC1310 / 1311** | ARM Cortex-M3 | Sub-GHz | [`skiphansen/Tag_FW_CC13xx`](https://github.com/skiphansen/Tag_FW_CC13xx) | 新款 Chroma 74H+ / Aeon |
| **88MZ100** | Marvell Cortex-M3 | 802.15.4 (2.4GHz) | [`Tag_FW_88MZ100`](https://github.com/OpenEPaperLink/Tag_FW_88MZ100) | 部分批次 Solum 1.54" / 7.5" |
| **CC2533** | TI 8051 | 802.15.4 (2.4GHz) | [`Tag_FW_Opticon`](https://github.com/OpenEPaperLink/Tag_FW_Opticon) | Opticon EE-21x / 29x / 42x |
| **Pricer HD150（替换主控板）** | 原机为红外接收且固件驻留 RAM，不可直接刷机 | 802.15.4 (2.4GHz) | 焊接 **EFR32BG22 替换主控小板（Modchip）** 直接驱动面板 | Pricer HD150 5.83" |

## 7. 图像下发、压缩与无线 OTA 机制

```
上层调用 POST /imgupload 上传图像
  → AP makeimage.cpp：解码 → 缩放 → 抖动量化为 1bpp/2bpp → 压缩（G5 或 zlib）
  → 计算 MD5 低 8 字节作为 dataVer 存入 tagDB，并将数据块推入 C6 射频缓存
  → 标签定时唤醒（40–60s）发送 ADR（或发出 BLE 广播）
  → AP 比对发现 dataVer 变化，下发新图像分块
  → 标签校验收齐后根据 dataTypeArgument 选择 LUT（全刷/快刷）驱动 EPD 面板
```

- **无损压缩算法**：黑白双色图优先采用 Larry Bank 的 **Group 5（G5）** 游程编码压缩，多色或复杂位图采用 **zlib** 压缩，可减少 50%–80% 的空中传输分片数。
- **差分块更新（`IMG_DIFF` `0x10`）**：针对大尺寸标签，AP 支持对比新旧图像仅传输发生变化的区域。
- **无线固件升级（OTA）**：标签首次通过有线刷入 OEPL 固件后，后续固件升级全部通过无线通道完成（数据包类型 `dataType = 0x03 FW_UPDATE`）。ARM 内核标签（nRF52 / EFR32 / TLSR）采用双分区（Dual-bank）安全切换；8051 内核标签（ZBS243）受限于 64KB Flash 采用单区覆盖，建议电量充足时逐台升级。

## 8. 标签端功耗模型与电池寿命测算（基于 `powermgt.h`）

| 电源管理参数 | 设定值 | 机制说明 |
|---|---|---|
| `INTERVAL_BASE` | **40s**（BLE 为 60s） | 正常在线状态下的唤醒报到周期，纯待机平均电流约 **7.2µA** |
| `DATA_REQ_RX_WINDOW_SIZE` | **5ms** | 每次唤醒开启接收机监听的窗口宽度 |
| `INTERVAL_AT_MAX_ATTEMPTS` | **600s** | 信号微弱连续重传失败时，自动拉长唤醒间隔以防止耗尽电池 |
| 失联阶梯退避（AP 断电） | 1h × 24 次 → 2h × 12 次 → **24h 一次** | 当 AP 关机失联后，标签自动进入长周期休眠退避；AP 恢复后标签在下次唤醒时自动归队 |
| 深度睡眠底电流 | **~1.0–2.0µA** | ZBS243 / TLSR8359 睡眠态电流 |

**CR2450 纽扣电池（标称 620mAh）续航估算**：

- 纯待机保持连接（40s Check-in，不刷屏）：理论续航可达 3–5 年（计入电池自放电）。
- 日常刷屏耗电：每次全屏刷新开启升压泵与驱动约耗时 2–3 秒、电流约 5–15mA。按每天刷新 **6–40 次**（即 [多端显示仲裁](surface-arbiter.md) 设定的预算上限）计算，双颗 CR2450 电池实际续航可达 **1–2 年**；但若将刷新频率设为每 15–60 秒狂刷一次，电池将在数周内耗尽。

## 9. 已知协议与硬件限制

| 限制项 | 具体说明 |
|---|---|
| **802.15.4 与 ATC BLE 默认明文传输** | 标准 802.15.4 链路与 AP 间 UDP 组播未加密（面向家庭局域网自用设计）；若需空中加密可选用支持 AES-CCM 的 **OpenDisplay BLE 协议** |
| **响应延迟下限为 40–60 秒** | 受限于标签被动的睡眠唤醒周期，推图后需等待标签下一次唤醒才能上屏，不适用于秒级实时交互 |
| **上行通道仅限短状态包** | 标签到 AP 的上行载荷限制在 90 字节以内（用于上报电量、温度、按键事件与 NFC 卡号） |

## 参考资料

- [OpenEPaperLink 主仓库](https://github.com/OpenEPaperLink/OpenEPaperLink) · [官方 Wiki](https://github.com/OpenEPaperLink/OpenEPaperLink/wiki)
- [atc1441/ATC_TLSR_Paper（汉朔 TLSR 蓝牙开源固件）](https://github.com/atc1441/ATC_TLSR_Paper)
- [OpenEPaperLink Home Assistant 集成](https://github.com/OpenEPaperLink/Home_Assistant_Integration)
- [Dmitry Grinberg: Reverse Engineering the ZBS243 SoC](https://dmitry.gr/?r=05.Projects&proj=30)
