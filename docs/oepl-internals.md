# OpenEPaperLink 内部机制

技术档案：OEPL（OpenEPaperLink）体系的底层构造——AP 固件架构、三条射频路线的协议差异、
标签芯片族、推图/OTA 流程、功耗模型、刷机解锁机制与已知限制。
配套选型文档：`eink-display-modules.md` / `eink-modules-ux.md`；术语表：`eink-tech-glossary.md`。

**信息源**：OpenEPaperLink GitHub 主仓源码（2026-10 拉取，`oepl-proto.h`/`oepl-radio-v2.h`/
`tag_types.h`/`ble_writer.cpp`/`od_session.cpp`/`powermgt.h` 等）、官方 wiki、
Tag_FW_* 各固件仓。出处在文末汇总，文中以行内链接标注。

## 1. 系统拓扑：三个平面

```
内容源(HTTP API / HA / 内容卡)
    │
    ▼  ESP32-S3 主控(AP firmware, WiFi+存储+渲染+WebUI)
    │    │ UART 115200→2Mbaud (协议 v1 ASCII / v2 COBS 帧)
    │    ├──► 射频协处理器(任选/可并存):
    │    │     ESP32-C6/H2  → 802.15.4 @2.4GHz(自定义 MAC,非 Zigbee)
    │    │     TLSR825x     → 802.15.4 或 GFSK(hwType 0xF8/0xF9)
    │    │     CC1101 模块  → GFSK @868/915MHz sub-GHz
    │    └──► ESP32-S3 自身 BLE 射频 → BLE 标签(与 WiFi 分时复用)
    ▼
tag(休眠唤醒,checkin 拉取)──── 电池供电,全年续航设计
```

- **AP 不负责推**——所有数据通路都是 tag 发起 check-in，AP 只应答。这是功耗模型的根基
  （[Tag protocol timing](https://github.com/OpenEPaperLink/OpenEPaperLink/wiki/Tag-protocol-timing)）。
- 802.15.4 与 BLE 两条路线可在同一 AP 并存（S3 跑 BLE 写任务 + C6 跑 802.15.4）；
  sub-GHz 需要 AP 上加 CC1101 模块，独立信道与 2.4G 互不影响。
- 多 AP：同网段 AP 经 **UDP 组播**自动互发现并同步 tagDB；每个 tag 选定一个"内容 AP"，
  但可在任意 AP 射频上取数据（[Multiple Access Points](https://github.com/OpenEPaperLink/OpenEPaperLink/wiki/Multiple-Access-Points)）。

## 2. AP 固件架构（ESP32_AP-Flasher）

Arduino/PlatformIO 工程，ESP32-S3 N16R8 为主力目标（16MB flash + 8MB PSRAM；
2.75 是最后支持 S2/<16MB 板的版本，[wiki Home](https://github.com/OpenEPaperLink/OpenEPaperLink/wiki)）。

| 部件 | 实现 | 依据 |
|---|---|---|
| RTOS | FreeRTOS；`ledTask`/`APTask`/`BLETask`/`usbFlasherTask`/`webFlasherTask` 常驻 | `main.cpp` setup() |
| Web | AsyncWebServer + WebSocket；`/imgupload`、`/jsonupload`、`/get_db`、`/tag_cmd`、`/led_flash`、`/flash_tlsr`、`/update_c6` 等约 40 个端点 | `web.cpp` |
| 存储 | LittleFS：`tagDB.json`（标签库）+ `/tagtypes/*.json`（屏型定义）+ 内容卡/字体/待发图 | `storage.cpp` |
| 内容管线 | `contentmanager.cpp` 按 contentMode 渲染（内置内容卡 ~28 种：日期/天气/RSS/日历/QR/HA/json template…），或收外部上传图 | `contentmanager.cpp`, tagtype-notes.md |
| 图像 | JPEG 解码(基线)→ 缩到屏分辨率 → 量化到 tagtype colortable → 1/2bpp 位图 → 可选 G5/zlib 压缩 | `makeimage.cpp` |
| 射频后端 | `zbs_interface.cpp`(C6/H2 串口)、`cc_interface.cpp`(CC1101)、`ble_writer.cpp`(BLE)、`legacytransport.cpp`/`v2transport.cpp`/`newproto.cpp`(串口协议 v1/v2) | src/ |
| OTA | `ota.cpp`：GitHub releases 拉包自更新；C6 固件内嵌随主固件下发 | web.cpp `/update_c6` |

**容量上限**：ESP32/ESP32-S2 ≈ 30 个 tag；S3-16MB 更多；官方建议高 tag 数用 C6 方案
（[FAQ](https://github.com/OpenEPaperLink/OpenEPaperLink/wiki/FAQ)）。PSRAM 是硬需求——
4.2" BWR 图需要整幅 2bpp 缓冲（400×300×2bit），无 PSRAM 只能出 1bpp。

### tagtypes 兼容表结构

`resources/tagtypes/NN.json`（NN=hwType 十六进制），每型字段：

| 字段 | 含义 | 例(01.json = M2 2.9") |
|---|---|---|
| `width/height` | 分辨率 | 296×128 |
| `bpp` | 屏每像素位深 | 2（4色） |
| `colortable`/`perceptual` | 逻辑色→RGB 映射（渲染输出端参考） | white/black/red(/yellow) |
| `rotatebuffer` | 帧缓冲预旋转 0-3 | 1 (90°) |
| `g5_compression`/`zlib_compression` | 该型首次支持对应压缩的固件版本号 | `"29"` / `"27"` |
| `shortlut` | 短 LUT（快速刷）支持 | 2 |
| `options` | `button`/`led` 可选硬件 | `["button"]` |
| `contentids`/`template`/`usetemplate` | 可用内容卡 + 布局参数；usetemplate 十进制借用另一型的模板 | `[22,23,1,…]` |

hwType 高字节区分：`0x00xx` 射频类标签，`0x01xx` OpenDisplay BLE 标签（AP 从 tag 配置读出后自建），
`0xF8/0xF9` TLSR 射频协处理器，`0xC6` ESP32-C6（`tag_types.h` 注释）。

## 3. 射频路一：802.15.4 @2.4GHz（M2/M3 主线）

**裸 802.15.4 MAC，非 Zigbee**——官方 FAQ 明说是"intentionally basic"的自定义协议，
因 tag CPU/电量都极简。PAN ID 固定 `0x4447`，8 字节扩展地址，包长 ≤125B
（`oepl-proto.h`）。

### 会话模型（tag 永远主动）

| 包 ID | 值 | 方向 | 作用 |
|---|---|---|---|
| `PKT_PING`/`PONG` | 0xED/0xEE | tag→AP→tag | 入网发现（tag 扫 11-26 频道选最强 AP） |
| `PKT_AVAIL_DATA_REQ` | 0xE5 | tag→AP | **check-in**：带 batteryMv/温度/RSSI/LQI/hwType/唤醒原因/固件版本/能力位 |
| `PKT_AVAIL_DATA_INFO` | 0xE6 | AP→tag | 应答：`dataVer`(待发数据 MD5 低 8B)、`dataSize`、`dataType`、`dataTypeArgument`、`nextCheckIn` |
| `PKT_BLOCK_REQUEST` | 0xE4 | tag→AP | 按 4KB block 请求数据，可带 partial-request 位图 |
| `PKT_BLOCK_PART` | 0xE8 | AP→tag | block 分片（99B/片 ×42 片=4KB） |
| `PKT_XFER_COMPLETE`/`_ACK` | 0xEA/0xEB | tag→AP | 收齐，落 EPD |
| `PKT_TAG_RETURN_DATA` | 0xE1/0xE2 | tag→AP | tag 回传数据(如按钮/NFC/调试) |

要点（[RF protocol](https://github.com/OpenEPaperLink/OpenEPaperLink/wiki/RF-protocol) +
`oepl-proto.h`）：
- check-in 后 tag 只留 **5ms 接收窗**（`DATA_REQ_RX_WINDOW_SIZE`）；无数据就回去睡。
- `nextCheckIn` 由 AP 下发：bit15=0 按分钟，=1 按秒——AP 可在应答里命令"5 秒后再来"
  以快速续传（`newproto.cpp` 里外推数据用 `5|0x8000`）。
- 数据类型 `dataType`：`IMG_RAW_1BPP/2BPP/4BPP`(0x20/0x21/0x22)、`IMG_DIFF`(0x10)、
  `IMG_ZLIB`/`IMG_G5`（压缩）、`FW_UPDATE`(0x03)、`NFC_*`、`TAG_CONFIG_DATA`、
  `COMMAND_DATA`、`CUSTOM_LUT_OTA`、`UK/EU_SEGMENTED`（段码屏）——见 `oepl-definitions.h`。
- 分块窗口机制：tag 报自己要的 blockId+part 位图，AP 逐片发；丢片 tag 重请，
  14 次(`DATA_REQ_MAX_ATTEMPTS`)拿不到就 XTO 超时放弃，保电优先。

### S3 ↔ 射频协处理器串口（协议 v1→v2）

AP 主控与射频芯片（ESP32-C6/H2 或 TLSR）之间是 UART：

| 代 | 形态 | 依据 |
|---|---|---|
| v1 | 115200 ASCII 短命令：`RDY?`/`NFO?`/`ADR>`/`RQB>`/`XFC>`/`SDA>`…定长数据+简单校验 | `legacytransport.cpp`, RF-protocol wiki |
| v2 | **2 Mbaud**，COBS(header‖payload‖CRC16)+0x00 成帧，seq+ACK/NAK，30ms 超时×3 重传；数据按 240B chunk、4 块窗口 | `oepl-radio-v2.h` |

v2 协议升级点（releases 3.00 说明 + `oepl-radio-v2.h` 注释）：
- 启动先用 ASCII，射频回 `CAP>xxxx` 声明能力后 S3 发 `FRM1`，双方 20ms 后切 2Mbaud。
- **射频侧 block cache**（≤256KB）：S3 把待发图先灌给 C6，tag 醒来的 RQB 直接命中缓存，
  省去"tag 等着 AP 现取数据"的窗口——直接缩短 tag 清醒时间=省电池。
- **tag 库存锁定**（`V2_CFG_LOCK_*`）：射频按 allow-list 只答应认识的 tag；
  learning 模式只收新 boot 的全量 check-in。解决两个 AP 同信道抢 tag 的问题。
- 消息集：HELLO/HEARTBEAT/SET_CONFIG/SET_PENDING/DATA_CHUNK/GET_STATS/ALLOW_* 
  → CHECKIN/DATA_NEEDED/BLOCK_SERVED/XFER_COMPLETE/TAG_RETURN_DATA/LOG/STATUS。

## 4. 射频路二：BLE（汉朔 TLSR / Gicisky / OpenDisplay）

AP 用 **S3 自带 BLE 射频扫描**——与 WiFi 分时复用所以是低占空比
（`ble_writer.cpp`：interval 320ms / window 30ms；BLE 连接期间扫描暂停）。
BLE 标签的 "check-in" = **广播包**，AP 不靠连接保活；要推图时才临时 GATT 连接。
标签上报间隔 ≤1/min（`BLE_CHECKIN_INTERVAL_MS 60000`）。

三种广播格式已被 AP 识别（`ble_filter.cpp`）：

| 族 | 识别特征 | 会话/加密 | 固件来源 |
|---|---|---|---|
| **Gicisky/Picksmart** | manu `0x53 0x50`("SP")，7B：型码+电压+固件 | GATT `0xFEF0/0xFEF1/0xFEF2`，明文 | Gicisky 自家/社区固件 |
| **ATC_BLE_OEPL**(atc1441 系) | manu `0x37 0x13`(0x1337 LE)，V1/V2 广播结构：hwType+固件+电量+温度 | GATT service `0x1337`，命令式 Ctrl characteristic，明文 | [ATC_TLSR_Paper](https://github.com/atc1441/ATC_TLSR_Paper) / OEPL TLSR 固件 |
| **OpenDisplay** | company id `0x2446`，v1(14B)/旧(11B)广播 | **AES-128-CMAC 握手 + AES-CCM 加密会话**（master key→session key KDF："OpenDisplay session"），AP 端 `od_session.cpp` 完整实现，key 存 NVS | OpenDisplay 固件（Gicisky 新固件方向） |

BLE 图像上传走 GATT 写：ATC 系是 `0x1337` ctrl 特征上发命令字+240B 分片；
OpenDisplay 走加密会话内的块传输（`BLE_CMD_*` 命令族，`ble_writer.cpp`）。

**限制**：广播只带状态不带图像；推图需连接，S3 同时只能和一个 BLE 标签传图
（状态机 `BLE_MAIN_STATE_*`）。官方明确 2.13" **TFT** 类标签不走 BLE-AP 路线
（BLE-only AP wiki 页警告）。

## 5. 射频路三：sub-GHz（Chroma 系，CC1101）

| 项 | 值 | 出处 |
|---|---|---|
| 物理层 | **GFSK**，802.15.4-like 帧头；868MHz(欧)/915MHz(美/澳) 各 5 信道 | SubGhz-AP-Configuration wiki |
| AP 侧 | CC1101 模块（推荐 **Ebyte E07-900M10**；通用 CC1101 模块缺陷率高，wiki 原话"avoid like the plague"），接在 ESP-C6 射频板上 | Chroma-Series-SubGhz-Tags wiki |
| tag 侧 | DisplayData Chroma 系：**CC1110**(8051, 26MHz, 32KB flash/4KB RAM) 老款；新款 **CC1310F64/CC1311R3**(Cortex-M3) | 同上 |
| 入网 | tag 首次开机扫两个 band 全部信道，记下 AP 所在 band+channel；之后只扫本 band——**换 band 要清 tag 设置** | 同上 |
| 优势 | sub-GHz 穿墙更好、避开 2.4G WiFi/BLE/Zigbee 拥塞 | 同上 |

MAC 从序列号推导：8B 扩展地址高 2B 固定 `0x44 0x67`，低 6B=SN 数字部分。

## 6. 标签固件芯片族

OEPL 把全世界拆机 ESL 收编进一张大表，**芯片族决定固件仓、刷机接口、协议路线**：

| 族 | SoC | 核 | 射频路线 | 固件仓 | 标签代表 |
|---|---|---|---|---|---|
| **ZBS243/SEM9110** | 三星电机定制 8051 | 8051 @16MHz，64KB flash，8KB XRAM，256B IRAM，~1µA 睡 | 802.15.4 2.4G | [Tag_FW_ZBS243](https://github.com/OpenEPaperLink/Tag_FW_ZBS243) (SDCC) | Solum M2：ST-GR16000/29000、ST-GM29 系 |
| **nRF52811** | Nordic BLE SoC | Cortex-M4 | 802.15.4 2.4G | [Tag_FW_nRF52811](https://github.com/OpenEPaperLink/Tag_FW_nRF52811)（含独立 bootloader） | M3 Newton：EL022/029H3WRA |
| **EFR32xG22** | SiLabs MG22/FG22/BG22 | Cortex-M33 | 802.15.4 2.4G | [Tag_FW_EFR32xG22](https://github.com/OpenEPaperLink/Tag_FW_EFR32xG22)（GSDK 4.4.1 + bootloader；CC BY-NC-SA） | M3 SiLabs 版：EL0xxF5/F6 系（SN 后印 "Silabs"） |
| **CC1110** | TI | 8051 @26MHz，32KB/4KB | sub-GHz | [Tag_FW_Chroma](https://github.com/OpenEPaperLink/Tag_FW_Chroma) (SDCC) | Chroma 29/42/60/74 |
| **CC1310/1311** | TI | Cortex-M3 | sub-GHz | [skiphansen/Tag_FW_CC13xx](https://github.com/skiphansen/Tag_FW_CC13xx)（移植中） | Chroma 74H+、Aeon-74 |
| **88MZ100** | Marvell | Cortex-M3 | 802.15.4 2.4G | [Tag_FW_88MZ100](https://github.com/OpenEPaperLink/Tag_FW_88MZ100) | 部分 Solum |
| **TLSR825x/8359** | Telink | ARM(8258)/类ARM 核 | **BLE**(也可 802.15.4/GFSK) | 主仓 `ARM_Tag_FW/OpenEPaperLink_TLSR` + atc1441 系 | 汉朔 Stellar/Nebular：HS BW/BWR/BWY 系 |
| **CC2533** | TI | 8051 | 802.15.4 | [Tag_FW_Opticon](https://github.com/OpenEPaperLink/Tag_FW_Opticon) | Opticon EE-21x/29x/42x/750R |
| **Modchip** | EFR32BG22 模块（Ebyte E104-BT53A1）| Cortex-M33 | 802.15.4 | 复用 EFR32 固件 | **Pricer HD150**：原厂红外通信不可刷，"脑移植"小板直接驱动屏（[Modchip by stevew817](https://github.com/OpenEPaperLink/Hardware/tree/main/Modchip%20by%20stevew817)） |

> 注：任务线索里的 "MSP430+CC1101" 是老 Pricer SmartTAG 架构的印象；OEPL 实际收录的
> Pricer HD150 走的是**红外**协议，不可刷固件，社区方案是 modchip 换脑——
> 兼容表里没有现成 MSP430 固件族。

**固件形态两派**：
- **8051 系**（ZBS243/CC1110/CC2533）：SDCC 工具链，单 bin；ZBS 固件把 64KB flash 抠到极致
  （v0026 记录"8KB idata 省出 210B 栈 + 7KB flash"，M2 changelog）。
- **ARM 系**（nRF52811/EFR32/CC1310/88MZ100）：**bootloader + app 分离**，`full` 与 `ota` 两种 bin；
  M3 通用固件（`SOL_M3_Uni_*`）靠出厂 UICR/userdata（EFR32 在 `0x0FE00000`，nRF 在 UICR 客户区）
  识别屏型——**刷前必须先 dump user data**，丢了就没法按屏配驱动
  （Flashing-SiLabs-based-M3-Newton-Displays wiki）。

## 7. 推图与 OTA 流程

### 推一张图的完整链路

```
POST /imgupload (jpeg+baseline) 或 内容卡渲染
  → makeimage: 解码→缩放判定→抖动→量化到 colortable→1/2bpp 位图(+压缩)
  → taginfo(md5/size/dataType) 记入 tagDB，pendingData 入队 (newproto.cpp)
  → v2: S3 直接把数据 DATA_CHUNK 灌给 C6 射频缓存
tag 醒(≤40s) → ADR → AP 回 availDataInfo(dataVer=MD5)
  → tag 比对 dataVer 发现新版本 → RQB 逐 4KB block 拉
  → block 收齐 → XFER_COMPLETE → tag 刷 EPD(按 dataTypeArgument 指定 LUT)
  → tag 按 AP 给的 nextCheckIn 回去睡
```

- **AP 推送延迟 = tag check-in 周期**，典型 40-60s；内容卡可声明 nextCheckIn
  让 tag 睡更久（如日期卡睡到天亮前），"Maximum sleep"/per-tag TTL/"no updates between"
  三个设置层叠（Tag-protocol-timing wiki）。
- 压缩：G5（Larry Bank 的 Group5，黑白图效果好，M2 v29+）与 zlib（M3 v27+）；
  tagtype JSON 的 `g5_compression`/`zlib_compression` 字段声明该型从哪个固件版起支持，
  AP 按 tag 固件版本自动选格式。
- `IMG_DIFF`(0x10)：AP 算新旧图差分只传变化区——大屏标签的关键省带宽机制。
- `preloadImage` 位（imageDataTypeArg）：可先写 EEPROM 不刷屏（缓存预热/幻灯片模式）。

### 标签 OTA

- 走同一条块传输链，`dataType=0x03(FW_UPDATE)`；tag 端校验 magic+MD5，
  失败回显"update failed"并上报 AP（M2 v0026 changelog）。
- AP 端 `binaries/Tag/tagotaversions.json` 按 `hwType` 映射该推哪个 bin；
  `full` bin 用于治具直刷，`ota` bin 用于无线（Binary-file-nomenclature wiki）。
- ARM 系双区 OTA：bootloader 收新固件验签后切换；8051 系单区，OTA 写坏有变砖风险
  （社区建议一次只升一台，M3 v0026 changelog 原话）。
- AP/射频固件 OTA：AP WebUI 一键拉 GitHub release；C6 射频固件随 AP 包内嵌，
  v2 协议下 12s 更完不重启 AP（release 3.00 notes）。

## 8. 标签端功耗模型（ZBS/M2 为基准，`powermgt.h`）

| 参数 | 值 | 语义 |
|---|---|---|
| `INTERVAL_BASE` | **40s** | 正常 check-in 周期；目标平均电流 **7.2µA** |
| `DATA_REQ_RX_WINDOW_SIZE` | 5ms | 每次 check-in 只开窗 5ms 听 AP |
| `DATA_REQ_MAX_ATTEMPTS` | 14 | 弱信号重试上限 |
| `INTERVAL_AT_MAX_ATTEMPTS` | 600s | 信号差时退避到的最长 check-in 间隔 |
| `POWER_SAVING_SMOOTHING` | 8 样本 | 用近 8 次 check-in 的尝试数平滑出下次睡眠 |
| `MINIMUM_INTERVAL` | 45s | 可配置 check-in 下限（决定寿命） |
| 失联退避 | 1h×24次 → 2h×12次 → **24h 一次** | AP 消失后逐级省电（`INTERVAL_1/2/3`） |
| `LONG_DATAREQ_INTERVAL` | 300s | 每 5min 一次带温度的长 check-in |
| `VOLTAGE_CHECK_INTERVAL` | 288×300s ≈ 24h | 每天一次射频带载测电池电压 |
| 深度睡眠 | **~1µA** | ZBS243 SoC 规格（SoC-ZBS243 wiki） |
| RF-wake 附加 | +0.9µA | 2.4G 突波唤醒（几厘米距离，见 §9） |

**电池测算（CR2450 ≈ 620mAh 标称）**：
- 纯 check-in（40s/5ms）：7.2µA 均值 → 理论 620mAh/7.2µA ≈ **9.8 年**；
  计上自放电/屏幕刷新/低温衰减，社区经验值 **3-5 年**量级。
- 刷屏耗电是大头：幻灯片实测——15s 间隔 400-850µA、60s 100-250µA、
  300s 30-50µA、1800s ~10µA（M2 changelog）。**5min 级状态刷新对标签寿命无伤，
  分钟级以下刷新就别指望用电池标签**。
- 弱信号环境 = 更多重试 = 更短 check-in 间隔仍更费电（退避拉高间隔补偿）；
  RSSI 差的标签群建议 AP 前移或多 AP。

## 9. 刷机/解锁机制

| 族 | 接口 | 工具 | 解锁机制 |
|---|---|---|---|
| ZBS243 | 自定义 4 线（CLK/CS/MOSI/MISO，类 SPI 调试口） | Tag_Flasher（Wemos S2-Mini）/`OEPL-Flasher.py`、web flasher | 无锁，直刷；infopage 可读原配置 |
| nRF52811 | **SWD**(SWDCLK/SWDIO) | Tag-Flasher / J-Link / pyOCD | 读保护位需 mass-erase，原固件保不住 |
| EFR32xG22 | SWD | pyOCD(荐)/J-Link/DAPLink/OpenOCD/Pico2 | 出厂 debug-lock；**unauthenticated debug unlock 会整片擦除**——先想好再刷 |
| CC1110 | TI debug（DC/DD/Reset） | CC-Debugger/ESP_CC_Flasher/Tag-Flasher | 无锁 |
| CC131x | **cJTAG** | XDS110 | 无锁 |
| TLSR8359 | **SWS**（单线）或 UART 烧录 | [ATC UART Flasher](https://atc1441.github.io/ATC_TLSR_Paper_UART_Flasher.html)、`telink_flasher`、AP 上 `/flash_tlsr` | 首刷需 **flash unlock**（atc1441 工具一键）；SWS 也可做 AP 射频固件烧录 |
| 88MZ100 | SWD | Tag-Flasher | — |
| Pricer HD150 | 不可刷（IR 协议） | **Modchip 换脑**：EFR32BG22 小板直驱屏 | — |

**共用物理接口**：M2/M3 各代标签的测试点布局统一（GND/RST/RXD/Test/CLK(SWDCLK)/
MISO(SWDIO)/VCC/MOSI/CS/TXD），3D 打印通用治具（`OpenEPaperLink/Hardware` 仓多个 jig）。

**入网即刷机**：BLE/TLSR 标签一次都不必拆——atc1441 的 WebSerial/UART 工具先解锁+刷
OEPL TLSR 固件，之后全部 OTA；AP 发现新 tag 后也可一键推送固件（FIRMWARE_UPDATE 内容卡）。

**闲鱼锁区风险提示**（ux 文档已记，机制在此）：拆机 tag 固件里存着原商户的 AP 配置
（信道/PAN/密钥种子），上电只会找原 AP；表现为"AP 发现不了"。清法：重刷固件或
断电进首刷流程清 settings——**能进 AP 管理台的才是好件**。

## 10. 已知限制清单

| 限制 | 细节 | 出处 |
|---|---|---|
| **无加密** | 802.15.4 链路明文；AP 间 UDP 组播明文；WebUI 无密码——官方定位 hobbyist/家用 | FAQ |
| **延迟下限** | 标签最快 ~40s 级响应（`MINIMUM_INTERVAL 45s`）；实时刷新不可能 | powermgt.h |
| **容量** | S2 ~30 tag；4.2"+ 需 PSRAM；大屏标签群建议 S3+C6 分体 AP | FAQ |
| **BLE 占空比** | BLE 与 WiFi 共享射频，扫描开窗 30/320ms；固件注释自比 ESPHome BLE proxy | ble_writer.cpp |
| **单向为主** | tag→AP 回传仅限 90B `TAG_RETURN_DATA`（按钮/NFC/调试）；非通用双向信道 | oepl-proto.h |
| **sub-GHz 换 band** | tag 记死初始 band，换区需清设置 | Chroma wiki |
| **厂商波形依赖** | tag 屏驱动 LUT 来自逆向/原厂参数拼凑，个别屏有色差/鬼影残留报告（固件 2.60 粉底问题=tagtype 定义过期） | FAQ, issues |
| **WiFi 兼容性** | UniFi 系 AP 需关 BSS Transition/Multicast Enhancement 等（ESP32 老毛病） | FAQ |
| **TLSR 屏族覆盖** | 汉朔 TLSR 固件按具体屏型手工配 EPD pinout/分辨率（5.83" 屏在 v3.x 仍需自配编译，issue #488） | issue tracker |
| **维护节奏** | tag 固件各仓进度不一；CC131x/部分 Chroma/13.3" EL133 仍在 in-process | wiki tag 表 |

## 出处汇总

- 主仓源码：https://github.com/OpenEPaperLink/OpenEPaperLink（`oepl-proto.h`、`oepl-radio-v2.h`、`oepl-esp-ap-proto.h`、`oepl-definitions.h`、`tag_types.h`、`ESP32_AP-Flasher/src/*`、`resources/tagtypes/*`、`binaries/Tag/*`、`ARM_Tag_FW/*`）
- wiki：https://github.com/OpenEPaperLink/OpenEPaperLink/wiki（RF-protocol、Tag-protocol-timing、SubGhz-AP-Configuration、Chroma-Series-SubGhz-Tags、Flashing-SiLabs-based-M3-Newton-Displays、Binary-file-nomenclature、ZBS243-(SEM9110)-SoC、FAQ、BLE-only-AP、Multiple-Access-Points、M2-Tag-Firmware-changelog、tagtype-notes）
- 标签固件仓：Tag_FW_ZBS243、Tag_FW_nRF52811、Tag_FW_EFR32xG22、Tag_FW_Chroma、Tag_FW_88MZ100、Tag_FW_Opticon、skiphansen/Tag_FW_CC13xx、ARM_Tag_FW/OpenEPaperLink_TLSR
- BLE 上游：https://github.com/atc1441/ATC_TLSR_Paper、atc1441.github.io 各 web 工具
- HA 集成：https://github.com/OpenEPaperLink/Home_Assistant_Integration
- ZBS243 逆向源头：https://dmitry.gr/?r=05.Projects&proj=30（Dmitry Grinberg 的 SoC 逆向）
