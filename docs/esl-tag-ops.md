# ESL 价签实操档案

技术档案：拆机 ESL 价签"到手之后"的全部操作面——按芯片族的刷机路径与救砖、OTA 真实边界、
不开壳辨芯片、闲鱼验货话术与收货检查流程、成交价锚点、常见坑。
配套：`oepl-internals.md`(协议/固件机制)、`eink-modules-ux.md`(采购清单)、
`eink-tech-glossary.md`(术语)。本文只管"怎么到手、怎么刷、怎么验"，不重复选型论证。

**信息源**:OEPL wiki(2026-10-24 克隆全量）、OEPL 主仓 Tag_Flasher/binaries/源码、
atc1441 系列仓与 web 工具、OEPL Hardware 仓治具、FCC 数据库条目、中文社区
(oshwhub/数码之家/什么值得买/whycan/B站up主教程）。出处在文末汇总，文中行内标注。

---

## 1. 按芯片族的刷机路径

判断次序：**先看 SoC 再看型号名**——同一外壳型号可装不同 SoC(见 §3),SoC 决定一切。

### 1.1 总览表

| SoC | 代表标签 | 首刷必须 | 接口 | 原厂固件可 dump? | 刷死恢复 | 难度 |
|---|---|---|---|---|---|---|
| **ZBS243/SEM9110** (8051) | Solum M2 全系 ST-GR/GM | 有线 | 类 SPI 4 线 (CLK/CS/MOSI/MISO)+RST+电源控制 | **可**——flash + 1KB infopage 全部可读 | 无锁，重写即可；近乎不可砖 | ★ |
| **nRF52811** | Solum M3 EL0xxH3WRA | 有线 | SWD(复用 CLK/MISO 焊盘） | 读保护→unlock 即全擦，dump 不可得 | mass-erase 后重刷 full+bootloader | ★★ |
| **EFR32xG22** | Solum M3 SiLabs EL0xxF5/F6 | 有线 | SWD(DIO/CLK/RST/VCC/GND 5 线） | debug-lock→unlock 即全擦；**先 dump User Data(0x0FE00000,1KB)** | unauth unlock 解锁即刷；丢 UD=丢屏参 | ★★ |
| **TLSR8359/825x** | 汉朔 Stellar/Nebular、Gicisky、保资/阿里云系 | 有线 UART/SWS(Gicisky 例外，见 §2) | 单线 SWS(UART TX 位bang)+NRST+3V3+GND | 原厂固件有 flash 保护，首次连接先 Unlock(=擦除） | SWS 永远在 boot ROM 层，极难砖 | ★ |
| **CC1110** | Chroma 29/42/60/74 | 有线(多数要开壳） | TI debug(DC/DD/RESETn,+VBAT,GND) | 可(Chroma 系默认无读保护） | 无锁重刷；EEPROM 坏→MAC 全零，patch_sn.py 修 | ★★ |
| **CC1310/1311** | Chroma 74H+/Aeon-74 | 有线 | cJTAG(XDS110) | — | 移植中(skiphansen/Tag_FW_CC13xx) | ★★★ |
| **CC2533** | Opticon EE 系 | 有线 | TI debug,6pin 1.27mm 排针 | **不可**——出厂 lock 只许擦除不许读 | 擦后刷 hex 即活 | ★★ |
| **88MZ100** | 部分 Solum(1.54" GR1600N、7.5" GR750BN) | 有线 | UART bootloader | — | Tag-Flasher 串口直通模式刷 | ★★ |
| **CC2630** | TG-GM29MT1C/ST-GM29MTF、EL133C2WRN | 有线 | UART bootloader(BL→GND 上电）或 cJTAG | — | Tag_FW_CC26xx 第三方固件，覆盖率差 | ★★★ |
| **MSP430+A7106/CC1101** | 老汉朔 Stellar-M(板号 HS_EL5102)、Pricer SmartTAG 系 | **不可 OEPL** | — | — | OEPL 无 MSP430 固件族；MSP430 BSL/JTAG 自研或仅拆屏 | ✗ |
| **Pricer HD150** (IR 协议） | 6" eBay 常见 | **不可刷固件** | 红外，无 RF 调试口 | 固件在 **RAM** 里，拔电池即蒸发 | 唯一路线=Modchip 换脑(§1.5) | ✗→改硬件 |

> 结论先行：**闲鱼主力货只有两条舒服路线**——ZBS243(Solum M2,pogo 治具按上就刷）
> 和 TLSR8359（汉朔系，USB-TTL 四根线）。别的要么工具链贵（CC131x cJTAG),
> 要么根本没固件（MSP430/CC2640/DA14585/LG 杂牌）。

### 1.2 ZBS243 系（Solum M2):pogo 治具 5 分钟一件

**接口本质**：自定义 SPI 状调试口，非 UART 非 SWD——CLK/CS/MOSI/MISO 四线 + RESET;
进调试模式靠**复位沿上给 CLK 打特定节拍**（来源：Dmitry Grinberg 逆向 + ZBS_Flasher README)。
还有一个窍门：刷完 SoC 会卡在调试态，**必须断电重启才跑固件**——所以正经治具都带
VCC 电源开关（MOSFET 或 LDO，ZBS_POWER 引脚切电，不许直连 GPIO)。

**要不要拆壳**:M2 标签的测试点在电池盖内侧 PCB 上——**开电池盖（免螺丝卡扣）即得,
不需要开整机壳**。M2/M3 共用同一套焊盘排布，一套治具通吃（`OpenEPaperLink/Hardware`
仓有 M3-universal 等 3D 打印治具）。

焊盘排布（贴标签那侧看，丝印自带标注）:

| 焊盘 | ZBS243 功能 | 复用为 |
|---|---|---|
| GND | 地 | — |
| Reset | RST | nRF/EFR32 RST |
| Rxd | UART RX(调试串口，可选） | — |
| Test | P1.0(button1/唤醒测试） | EFR32 MP |
| Clk | SPI_CLK | nRF/EFR32 SWDCLK |
| MISO | SPI_MISO | nRF/EFR32 SWDIO |
| VCC | 供电（经治具开关） | — |
| MOSI | SPI_MOSI | — |
| CS | SPI_SS | — |
| Txd | UART TX(调试输出，115200) | — |

**工具链**（三选一）:
- **OEPL Tag-Flasher**:Wemos S2-Mini(ESP32-S2)+ 治具，固件用
  `install.openepaperlink.de` 网页直接烧，连平台都不用装；然后
  `OEPL-Flasher.py -e -z -p COMx read/write file.bin`。同板还能刷
  nRF(-n)/88MZ100/CC1110(-c),**不支持 EFR32**。
- **atc1441 ZBS_Flasher**:ESP32 或 Arduino Nano + PlatformIO 工程 +
  `zbs_flasher.py`(命令:`read / write / read-infopage / write-infopage / reset`)。
- **AP-Flasher 一体板**:OEPL 官方"AP + 刷机位"成品/散件，烧录口在板边。

**dump 可行性**:ZBS243 **无读保护**——`read` 拿整片 64KB flash,`read-infopage`
拿 1KB infopage（出厂 MAC、校准、原 AP 配置都在里面）。**刷前必 dump**：一是留底，
二是 infopage 里的 MAC 要和外壳 SN 对应；OEPL 侧另有 `patch_mac.py`/刷机脚本里
`CMD_SAVE_MAC_FROM_FW` 帮你把原厂 MAC 种回新固件。

**刷失败恢复**：这芯片基本砖不了——调试口在 ROM 层，断电重来即可。真写坏了
（罕见，`Troubleshooting-Tags` 记过"SoC 拒收一切 flasher 命令"的坏件）,
走 OTA 有时还能救；EPD 驱动芯片坏会连累共 SPI 总线的外部刷写，表现同为刷不进。

### 1.3 TLSR8359/825x 系（汉朔/Gicisky):USB-TTL 四根线

**接口本质**:Telink 的 **SWS 单线协议**——物理上只要 UART 的 TX 一根数据线
bit-bang SWS（网页烧录器标题即"TX-SWS only"),RX 都不接；RTS/DTR 用来拉 NRST
复位进烧录态。

**要不要拆壳**:
- **Stellar-M/L(2.13"/2.9")**：背后电池盖（卡扣）掀开见主板焊盘，
  丝印直标 `SWS_RXD / VCC / TXD / NRST / GND`。理想情况不破坏外壳。
  老款 Stellar-M 透明前盖是**胶粘的**，开错方向=撬屏碎屏（§6)。
- **Stellar Pro / Nebular**：电池仓盖下同样有焊盘，但**不同板版焊盘位置会变**——
  Nebular 3.5" 改版后原有 6 焊盘消失，社区有人切壳才找到（issue #305)。
  下单前让卖家拍电池仓内部。
- OEPL Hardware 仓有现成治具：`Stellar_M_Jig.stl`、`Nebular350.stl`、
  `Stellar_Pro_266_Jig.stl`、`Stellar_Battery_tool.stl`（开电池盖辅助件）。

**接线**(USB-TTL 3.3V 端子，CH340G 可，注意 **PL2303HX 没 RTS**):

| TTL 端 | 标签焊盘 | 说明 |
|---|---|---|
| TXD | SWS | 唯一数据线（烧录口叫 RXD/SWS_RXD 就是它） |
| RTS 或 DTR | NRST | 复位脚；无 RTS 的板子可烧录前手动把 NRST 碰一下 GND |
| 3V3 | VCC | 电平必须 3.3V |
| GND | GND | |
| RXD | 不接 | "Not needed for flashing"（原厂图原话） |

**流程**(ATC WebSerial 烧录器 `atc1441.github.io/ATC_TLSR_Paper_UART_Flasher.html`):
波特率默认 460800 → Open COM → 先点 **Unlock Flash**（原厂固件带 flash 保护,
首连必须解锁，等效擦除）→ Write to Flash → 完成屏自动刷新。
**刷完先拔掉 TTL 的 TX 线再试 BLE**——挂着 TX 蓝牙连不上（社区 README 反复提醒）。

**固件选择**:
- `ATC_TLSR_Paper`:atc1441 原版 BLE 固件，WebBluetooth 传图/OTA
  (`ATC_TLSR_Paper_OTA_writing.html`)。
- `OpenEPaperLink_TLSR`(OEPL 主仓 `ARM_Tag_FW/`):接 OEPL AP 的 BLE 广播协议，
  覆盖屏型以 `epd_*.c` 文件名为准（bw_213 / bw_213_ice / bwr_154 / bwr_213 /
  bwr_350 / bwy_350 等），对应 AP 端 hwType 0x54-0x71 区间一堆 `HS *`/`TLSR *` 定义。
- **首刷后所有后续更新走 BLE OTA**，再也不用碰线。

**刷失败恢复**:SWS 是芯片 boot ROM 层协议，应用固件全烂也能重新进烧录态。
真正会翻车的点：线虚接、电平错（必须 3.3V)、焊盘版不对、固件屏型不匹配
（刷完屏不刷/花屏≠砖，重刷对型号即可）。

### 1.4 MSP430+CC1101 / A7106 系：确认不可 OEPL

任务里点名的"MSP430+CC1101"实物对应两类货，**都不在 OEPL 九族表里**:

| 实物 | 内部 SoC | 射频 | 结论 |
|---|---|---|---|
| 老汉朔 **Stellar-M 2.13"**（板号 `HS_EL5102-0_Vx`,BW 屏 250x122) | MSP430G2553(TSSOP-28) | **A7106** 2.4GHz（不是 CC1101;AMIICOM 私有协议） | 无 OEPL 固件；只能拆屏用（FPC 26pin，当普通 SPI 屏喂 ESP32),或走 MSP430 BSL 自研 |
| **Pricer** 全系（含 HD150 5.83") | 各家不一，HD150 固件在 **RAM** 里 | **红外**(1.25MHz 载波，16-bit key 无加密） | 物理上没法刷——断电固件就没了；唯一出路 Modchip 换脑 |
| SES Imagotag(Vusion) | CC2510(8051+2.4G) | 2.4GHz 私有 + AES-128 | 有 AES key 锁定机制，readout protected,不可救 |
| 盒马定制 4.2"(类汉朔壳） | DA14585(Dialog BLE) | BLE | 无现成固件，拆屏件 |
| 小米智控价签 | "智控 6626" | 私有 | 有社区内测固件（晨晨实验室）,**非 OEPL 生态** |
| CC2640R2F 版汉朔（黑边框 6.24V 批） | CC2640 ARM-M3 | BLE | 有独立社区固件（cc2640BleEpd/ihopebleepd,XDS110 JTAG 刷）,**也属非 OEPL** |

MSP430 判断标志：拆开后主控是 **TSSOP-28 小脚芯片**(MSP430G2553)+ 旁边
QFN-20 射频（A7106)；而 TLSR 版是单颗 QFN-32 SoC。不拆壳的判别法见 §3。

### 1.5 各路线 AP/工具门槛汇总

| 路线 | 刷机硬件成本 | 备注 |
|---|---|---|
| ZBS243 | Wemos S2-Mini ¥15-25 + pogo 治具（3D 打印/淘宝成品 ¥20-60) | 最省事，治具可复用 N 次 |
| TLSR | 任意 3.3V USB-TTL(CH340G ¥5)+4 根杜邦线/焊线 | 成本最低，但要焊接或治具 |
| nRF/EFR32(M3) | 任意 CMSIS-DAP:RPi Pico(¥25)/Sipeed SLogic(¥60)/ST-Link/J-Link | pyOCD + `reflash.py`;**先 dump User Data** |
| CC1110(Chroma) | CC-Debugger 克隆件 ~¥60 或 ESP_CC_Flasher | 多数要开整壳（C 版可在电池仓够到焊盘） |
| CC131x | TI XDS110 ~¥200+ | cJTAG 调试器市面少 |
| Pricer HD150 | 换脑=打板+EFR32BG22 模块（E104-BT53A1)+焊接 | 当 DIY 项目而不是"买个屏" |

---

## 2. OEPL OTA 的真实边界

### 2.1 AP 到底能不能"隔空"推固件给未刷标签?

**不能——除了一个例外**。分清三种状态:

| 标签当前固件 | AP 能看到它? | 能 OTA 成 OEPL? |
|---|---|---|
| 原厂固件（Solum/汉朔/Pricer/Chroma stock) | **看不到**。802.15.4 侧只答 OEPL 自定义协议；BLE 侧只认 Gicisky-SP/ATC-0x1337/OpenDisplay-0x2446 三种广播格式 | 不行，必须先有线首刷 |
| 已是 OEPL/ATC_TLSR_Paper 固件 | 正常 check-in | 可以：AP 端 `Firmware update` 内容卡（contentid 5）按 hwType 查 `tagotaversions.json` 选对 bin，或手动指定文件，走块传输下发 `FW_UPDATE(0x03)`,tag 端验 magic+MD5，失败屏上显示"update failed"并回传 AP |
| **Gicisky/Picksmart 原厂固件** | **能**——原厂广播格式就在 AP 识别列表里 | **能，且不拆壳**:Gicisky 原厂固件开着 Telink 标准 BLE OTA 服务（UUID `00010203-...-1912`)，用 `atc1441.github.io/BLE_EPaper_OTA.html` 直连推送 OpenDisplay/OEPL bin |

汉朔原厂固件**没有**被验证的纯无线刷入路径——标准路径就是 §1.3 的 UART 首刷。
（汉朔原厂 BLE 只用于自家配网；Telink OTA 服务在汉朔 stock 上未对外开放或已被阉，
社区一致走线刷。若某批次实测可用 BLE OTA，属捡漏不是承诺。)

### 2.2 "store-locked / 锁区件"到底能不能 OTA?

拆开两层含义:

1. **商户绑定锁**（闲鱼常说的"锁"):stock 固件里存着原超市 AP 的
   信道/PAN/密钥种子，上电只找原 AP。表现：你的 AP 永远发现不了它。
   **对 OEPL 完全无感**——反正首刷是有线，重刷后一切清零。
   反过来说：**"能不能 OTA"这个问题只存在于已是 OEPL 固件的标签上**;
   stock 锁不锁都一样要插线。
2. **芯片读保护锁**（刷机时会撞见的）:
   - ZBS243：无锁，随便读写。
   - EFR32/nRF(M3):APPROTECT/debug-lock,`unauthenticated debug unlock`
     解锁**必连带全片擦除**——原固件保不住，但刷 OEPL 不受影响
     (reflash.py `-u` 一键；树莓派+OpenOCD 也行，Tag_FW_EFR32xG22 issue #27)。
   - TLSR8359：原厂 flash lock,WebSerial 烧录器 "Unlock Flash" 处理。
   - CC2533(Opticon)：出厂 lock 只许擦不许读，照刷。
   - 真正无解的是 MSP430 熔断 JTAG 的情况（罕见）和没固件的 SoC——
     那是"没软件"不是"锁住"。

### 2.3 闲鱼"可配网"的真实语义

卖家嘴里的词，按出现频率译成技术事实:

| 卖家话术 | 实际含义 | 对 OEPL 买家的意义 |
|---|---|---|
| "可配网 / 能配对基站" | stock 固件活着、射频没死，理论上能进原厂系统 | 只证明不是死件；你反正要重刷，**不构成溢价理由** |
| "已破解 / 已刷机 / 可蓝牙传图" | 已刷 ATC_TLSR_Paper 或晨晨实验室等社区固件 | **最省事的货**——验明 SoC 后对 OEPL 开箱即用（AP 直接发现 ATC 广播，可再 OTA 换 OEPL 固件） |
| "仅通电测试 / 功能自行研究" | 卖家不懂/没验，可能混 MSP430/CC2640/DA14585/LG 杂板 | 默认按"买屏幕送板子"估价，砍到屏价 |
| "不可配网 / 锁店" | stock 固件绑死原商户 | 对 OEPL 无差别，只要 SoC 对就照买 |
| "工程机 / 无后盖 / 裸板" | 拆机余料 | 看屏是否完好即可 |

一句话：**闲鱼上唯一需要现场确认的是"里面是什么 SoC"和"屏好不好",
锁不锁、配网不配网全是噪音**。

---

## 3. 标签端硬件辨识（到手前/到手后）

### 3.1 不开壳怎么猜 SoC

| 牌子/丝印 | 判据 | 结论 |
|---|---|---|
| Solum 背贴型号 | `ST-GR/GM xxxxx` = M2(ZBS243);`EL0xxH3WRA` = M3 nRF52811;`EL0xxF5/F6` 且 SN 后印 **"Silabs"** = M3 EFR32;`EL029GSWRN`/`EL133` = CC2630 | MAC ID 首位也对得上（3B1=GR29000 ZBS,B29=EL029H3WRA nRF 等，见 Binary-file-nomenclature) |
| FCC ID `2AFWN-*` | Solum 系认证号，fccid.io 可查内部照片 | 快速确认原厂件 |
| 汉朔型号码 | `Stellar-XXX E31X`:`M`=2.13"、`L`=2.9"、`S`=1.54"、`XL/XM`=4.2";`3`=BWR、`Y`=BWY、`N`=NFC、`H`=高分、`A`=无磁簧、`@`=LED | **型号只说明屏和外设，不说明 SoC** |
| 汉朔右上 LED 边框色(E31A 批次） | **白边框 = 4.9V 批 = TLSR8359;黑边框 = 6.24V 批 = CC2640R2F** | oshwhub 实测对照；两批屏上还各印着 4.9v/6.24v |
| Nebular 命名 | `Nebular-XXX` 数字=英寸×100(266/350/420/583/750),`-N` 带 NFC | Nebular 系几乎全 TLSR8258/8359 |
| Chroma(DisplayData/ZBD) | 背面 SN 首两位定型号：`JA`=Chroma29 BWR、`JF`=29 BWY、`JC`=42 BWR、`JD`=60、`JL/JM`=74;`ME`/`MS`/`LD/MJ` 起头=**CC131x 新核**（移植中） | 尾字母 `B`=老 CC1110 协议版，`C`=8151 屏驱版 |
| Gicisky/Picksmart | 外壳印 Gicisky,电商全新件非拆机 | TLSR 系，**唯一无线可刷** |
| Pricer | 前脸可见黑色红外接收窗，无 2.4G 痕迹 | HD150 等全系只能换脑 |

### 3.2 开壳特征速查

| 标签 | 开法 | 内部辨认 |
|---|---|---|
| Solum M2 | 背面电池盖卡扣滑开，免螺丝 | 焊盘排（丝印 GND/RST/RXD/Test/Clk/MISO/VCC/MOSI/CS/TXD),ZBS243 SoC(QFN),1MB SPI flash,NFC 版多一颗 NT3H 芯片 |
| Solum M3 | 电池盖在背面，开法略刁（官方有 YouTube 演示）,**焊盘就在电池盖下** | 同排焊盘;nRF=QFN 单芯片，EFR32 版 SN 后印 Silabs |
| 汉朔 Stellar-M/L | 背电池盖（卡扣）开；**注意：最老批是前面板胶粘，开错方向会撬裂屏**——先开后盖看板号（`HS_EL5102`=MSP430、`HS_ELE102` 等） | TLSR=QFN-32 单 SoC;MSP430=TSSOP-28+A7106;CC2640=QFN-48 |
| Chroma | **多数要开整壳**：白前脸沿角撬离灰后盖；**绝不要从屏和框之间撬**（屏排线胶在 PCB 上，扯断即废） | `C` 版可只在电池仓够焊盘；TP 丝印号见 §1.4 |
| Nebular Pro | IP68 胶封超薄（7.8mm),**官方就是一次性结构**；内嵌 LiMnO2 电池不可换 | 基本只能按"不可拆"计 |

### 3.3 天线与 RF 布局

- 全系 ESL 都是**单根 PCB 天线，无真分集**；天线走线一般在 PCB 板边
  (M2 在顶边，汉朔在侧边角料区）。贴金属面/塞金属盒会显著恶化 RSSI。
- M2 额外有一条 **RF-wake 天线**:PCB 上一段调谐走线接在类 GPIO 唤醒脚上,
  2.4GHz 突波感应唤醒，**有效距离几厘米**（几厘米，wiki 原话"a couple of
  centimeters, tops")，不是分集天线，是硬件彩蛋（配 ESP32+nRF24L01 做唤醒器）。
- 汉朔系有 NFC 线圈（绕屏框一圈），别当射频天线；NFC 用于店员手机配网。

### 3.4 电池型号与更换难度

| 标签 | 电池 | 更换难度 |
|---|---|---|
| M2 1.54" | **1×CR2450** | 易，电池盖直开；单电池扛全部射频尖峰，最先蔫的就是它 |
| M2 2.9"/2.7" | 2×CR2450 | 易 |
| M2 4.2" | 2×CR2450(KC0/03N 批为 **3×**) | 易 |
| M2 7.5"(ST-GR750BN/ST-GM7500N) | **4×CR2450** | 易，电池盖大 |
| M3 Newton 2.2"/2.9" | 2×CR2450 | 易 |
| EL029GSWRN 2.9" | **3×CR2032** | 易 |
| EL133C2WRN 13.3" | 4×AAA(2s2p) | 易；2s2p 必须四节同时换、用同型号（Opticon 750R 同此规矩，混换会反充） |
| Chroma 29 | 2×CR2450 | 易 |
| Chroma 42/60 | 4×CR2450 | 易 |
| Chroma 74 | **6×CR2450** | 易但费电池；**低于 ~2.2V 前换掉**，否则 EEPROM 数据可能被写坏（wiki 原话） |
| 汉朔 Stellar/Nebular 普通版 | 2×CR2450(标称 ~550-600mAh) | 易 |
| 汉朔 **Nebular Pro** | **LiMnO2 内嵌电池，IP68 胶封** | **不可换**——买了就当耗材 |
| Pricer HD150(改机后） | Modchip 方案自带 LiPo+充电口 | 看你手艺 |

提示:CR2450 脉冲放电能力弱，亏电时内阻飙升——空载万用表量 3V 不代表有电
(§6 电量虚标）。

---

## 4. 采购验证清单

### 4.1 问卖家的 5 个问题

1. **"背面型号贴纸拍一张"**——要的是 `ST-GRxxxxx`/`EL0xx…`/`Stellar-xx@ E31x`/`Nebular-xxx` 这些字。比"几寸几色"重要十倍。答不上来=按"买屏"估价。
2. **"电池仓能开吗？开后主板焊盘拍一张"**——看焊盘排布是否与 §1 对得上，顺便看板号丝印（`HS_EL*`/`edk286 Issue x`)。
3. **"什么渠道的件？超市下架还是工厂尾单？"**——超市下架=stock 固件（要首刷）;工厂尾单/白牌可能根本没烧固件（更可刷）。卖家说不清也行，目的是逼出"我也不知道什么芯片"的实话。
4. **"屏显正常吗，能不能上电拍个屏？"**——灰屏/花屏/黑边角在照片里藏不住；标签断电能留最后一帧，**不插电拍照也算数**（拿手里那张商品图就是"当前屏"）。
5. **"批量里有没有混别的型号/坏的？"**——杂牌混批是闲鱼常态；问出口才好在收货时逐个对。

### 4.2 收货 10 分钟检查流程

```
0:00  外观:屏面无裂纹(尤其边角)、FPC 排线完好、螺丝/卡扣没被撬烂
      → 裂屏件直接归入"拆屏件"一档
0:02  开电池仓:对 §3.4 核电池数;看主板丝印/SoC 型号,判芯片族
      → MSP430/CC2640/DA14585/智控6626/陌生 SoC → OEPL 不救,退货谈判起点
0:04  清 boot:拔电池 → 短接电池触点放电(或一节反装再复位)→ 顺推装入
      M2/M3 无 POR 电路,板载大电容放电慢,不这么干等于没重启(wiki 明示)
0:06  上电看行为:
      · 屏闪刷+显示找 AP/刷机 splash = 活的
      · 原商场画面不动 = stock 固件,正常(反正要刷)
      · 完全无反应 = 死电池或真坏,换 CR2450 再试
      · 灰屏/花屏/半屏 = EPD 或升压电路问题,归"拆屏件"
0:08  确认刷机路径:对 §1 表选工具,接治具/焊线
      · ZBS: 治具 pogo 压上 → `OEPL-Flasher.py -z read dump.bin` 先读 flash+infopage 留底
      · TLSR: 4 线 → WebSerial → Unlock → Write
      · M3 SiLabs: 5 线 → `reflash.py --dump-ud` **先存 User Data** → -u 解锁 → -f full.s37
0:10  写 OEPL 固件 → 断电重启(退出调试态)→ 屏出 OEPL splash = 通关,
      之后交给 AP 入网+OTA
```

未过检分支：屏碎/屏灰 → 拆屏当裸屏物料（FPC 转接板+微雪驱动）;
SoC 不在表 → 同上；标签反复吃电池（睡流 >7µA)→ EPD CoG 或 EEPROM 有暗病，
wiki 明说是"problematic tag"的征象。

---

## 5. 价格锚点（人民币，闲鱼口径）

**时效声明**：以下为公开报道+社区帖实价，非报价牌。2025 下半年超市批量退役潮后
价签价整体跳水；同一型号"贩子件"和"超市遗产散件"可差 3-5 倍。

| 尺寸/型号 | 时间 | 成交价 | 出处 |
|---|---|---|---|
| 汉朔 Stellar 2.13" | 2021-11 | ¥5/个 | oshwhub 拆解帖 |
| 同上 | 2022 | ¥60/10 个（¥6) | eet-china 专栏 |
| 同上（MSP430 老板） | 2026-03 坛友转手 | **¥2/个**(15 个 30 包邮） | whycan 论坛 |
| 2.13" 零售 | 2025-11 | ¥9.9/2 个 ~ ¥15.64/8 个 | 海报新闻实测闲鱼 |
| 2.2" | 2025-11 | ¥2.8/个 | 同上 |
| 2.9" | 2025-11 | ¥8/个 | 同上 |
| 汉朔 Stellar-XL/XL3N 4.2" | 2025-10 | **¥8.8-9/个**,10 个起批 | 新浪财经/虎嗅 |
| LG 4.2"（全新库存） | 2025-10 | ~¥9/个，卖家自述"仅通电" | 同上 |
| 4.2" 行情 | 2024-10 | 二三十/个（2.13" 几块、2.66" 十几） | 数码之家拆解帖 |
| 4.2" 接盘侠价 | 2025-10 报道 | ¥40/个（被割案例） | 什么值得买 |
| 5.83"(Pricer HD150,eBay) | 2021-03 | ~$20/个 | hackaday.io 拆解 |
| 7.5"/11.6" 汉朔大屏 | 2025-2026 估价 | **¥100-300 / ¥200-500**,货源稀少 | 本仓 `eink-modules-ux.md` 估价口径，下单前重询 |
| 盒马 nRF52811 2.13" | 2026 | 社区"按键相册"方案走俏，件价同 2.13 档 | 什么值得买汇总 |

判价心法：≤¥10 的 2.13-4.2" TLSR/已知 SoC 件=闭眼买；¥20-40 的要有照片实证；
>¥50 的小屏基本是贩子税。大屏（≥5.83"）不按尺寸线性溢价——货少、运费贵、
屏碎率高，看到合适就下手。

---

## 6. 常见坑实录

| 坑 | 实际表现 | 判定与处置 |
|---|---|---|
| **"灰屏不刷"** | 上电/推图后屏保持灰或旧图，xfer complete 但屏不动 | 多因：电池亏电带不动刷新（换电池先试）;EPD 升压泵坏（摸电感/管发热、全黑、拉 100mA);固件 tagtype 错配（AP 管理台重选/更新 tagtype 定义，2.60 粉底事件同款修法） |
| **刷新异常** | 竖条乱纹、偏移 ≤8px、局部反色 | 2.9" UC8151(NFC 版）+ Nano AP 上 v0029 有已知 glitch——**降级要治具有线刷，别在 Nano AP 上 OTA 降，会变软砖**;Yellow AP OTA 降级正常（wiki 明记） |
| **电量虚标** | 万用表量空载 3V"没问题"，一上电就死 | CR2450 亏电内阻飙升，**加载（射频）测才准**:OEPL 用 EPD 低压检测读数，≥2.6V 合格，2.15V 以下带载必崩；AP 里看的电压上限也就 2.6V 不是 3V——别慌是正常 |
| **电池越换越快** | 换好电池几小时又空 | 睡流排查：正常 ~2µA（含 check-in 均 ~7µA);EPD CoG/EEPROM 坏件会拉暗电流，标签是坏的征兆不是电池的锅 |
| **"锁区件"** | stock 固件找原商户 AP，自家 AP 永远扫不到 | §2.2——对 OEPL 无感，重刷即解；别为"已解锁"付溢价 |
| **同名不同芯** | 同样 Stellar-M3@ E31A 刷不进/屏不亮 | 黑边框批=CC2640（走 XDS110+ihopebleepd，非 OEPL);白边框批=TLSR；更老的 `HS_EL5102` 板=MSP430，只有屏可用 |
| **改版焊盘没了** | Nebular 3.5" 新板 6 焊盘移位 | issue #305；买前让卖家拍电池仓内板，对不上就按拆屏件砍价 |
| **开壳碎屏** | 撬前脸把屏排线扯断/屏角裂 | Stellar 老款前脸胶粘——**只开背电池盖**;Chroma 撬壳走白框与灰背接缝，**绝不插刀进屏缝** |
| **2.13" TFT 假墨水屏** | Gicisky 同尺寸有 TFT 版，当墨水屏买 | wiki 大写警告：TFT 版 BLE-AP 用不了，物理上是 LCD 不是 EPD；看参数"无需电池常显"字样区分 |
| **CC1101 杂牌模块** | AP 侧 sub-GHz 收不到包 | 通用绿板缺陷率高（晶振偏频/虚焊）,wiki 原话 avoid like the plague;AP 侧认准 **Ebyte E07-900M10S**，且确认是 868/915 版不是 433 版 |
| **刷完蓝牙连不上** | TLSR 刷完 WebBluetooth 搜不到 | 先拔 TTL 的 TX 线（原话："必须先断开 TTL TX 线") |
| **价签"找 AP"刷屏没完** | stock/新刷标签长扫 | stock 固件正常行为；OEPL 固件下该屏显示 "No AP found" 也是正常状态——入网点在 AP 管理台 |

---

## 7. 速查：我要买什么工具

| 你的货 | 最小工具 | 一次到位 |
|---|---|---|
| Solum M2(ZBS) | Wemos S2-Mini + 杜邦线临时压触点 | Tag-Flasher + 3D 打印 pogo 治具（批量刷） |
| 汉朔 TLSR | CH340G + 4 线（会焊线才行） | USB-TTL 带 RTS/DTR + Hanshow jig STL |
| M3 SiLabs | RPi Pico + pyOCD | 任意 CMSIS-DAP + `reflash.py` |
| Chroma | CC-Debugger 克隆 | ESP_CC_Flasher / Tag-Flasher 50+ 固件 |
| 全都要 | — | Tag-Flasher(ZBS/nRF/88MZ/CC1110 四合一口径）+ CH340 + Pico,DAP 全家桶 |

---

## 出处汇总

- OEPL wiki(2026-10-24 git clone):Troubleshooting-Tags、Binary-file-nomenclature、
  Firmware-Updates、BLE-only-AP、Flashing-SiLabs-based-M3-Newton-Displays、
  Flashing-SiLabs-Tags-using-reflash.py、Chroma-Series-SubGhz-Tags、
  2.9″-Chroma-29、Restoring-Lost-Serial-Numbers-in-Chroma-Tags、rf-wake、
  Lithium-Ion-replacement-for-CR2450、各型号页（ST-GR16000/29000/27000/GR42/GR750BN/
  GM7500N/GM29MT1C/EL022H3WRA/EL029H3WRA/EL029GSWRN/EL133C2WRN/Opticon-CC2533)、
  Installing-SubGhz-Beta、Generic-CC1101-modules-for-SubGhz、M2 changelog
- OEPL 仓库：`Tag_Flasher/README.md`+`OEPL-Flasher.py`、`binaries/Tag/tagotaversions.json`、
  `ESP32_AP-Flasher/src/web.cpp`(`/flash_tlsr`)/`ble_writer.cpp`、`resources/tagtypes/*.json`
- OEPL Hardware 仓：治具清单（M3-universal、Stellar_M_Jig、Nebular350、Chroma29 jig)、
  `Modchip by stevew817/README.md`
- atc1441:`ZBS_Flasher` README（引脚表/ZBS_POWER)、`ATC_TLSR_Paper` README+
  `Hanshow_Stellar_MN@_E31H_Pinout.txt`+`USB_UART_Flashing_connection.jpg`、
  web 工具（UART_Flasher/OTA_writing/Image_Upload/BLE_EPaper_OTA)、
  `ESP_CC_Flasher`、`ESP32_nRF52_SWD`、`ATC_GICISKY_ESL`、`E-Paper_Pricetags`
- 社区固件/教程：reece15/stellar-L3N-etag、marcgallego/stellar-pro-etag、
  ihopenot/ihopebleepd(CC2640 版）,skiphansen/Tag_FW_CC13xx
- issue/案例：OpenEPaperLink #305(Nebular 焊盘移位）、#383(Gicisky TFT)、
  Tag_FW_EFR32xG22 #27（树莓派 OpenOCD 解锁）
- 中文信源：oshwhub《汉朔三色电纸墨水价签研究》(2021)、数码之家
  mydigit.cn/thread-163976(Stellar-M MSP430,2020)/thread-454355(盒马 DA14585,2024-05)/
  thread-474964(Stellar-XM3N@,2024-10)、eet-china a517267(2024-06)、
  whycan t_8290(2022/2026 回帖）、新浪财经 t.cj.sina 2025-10(Stellar-XL ¥9)、
  大众网/海报新闻 2025-11（闲鱼实测价目）、什么值得买 a82pele0(2025-10 汇总）
- 其他：dmitry.gr《Reverse Engineering an Unknown Microcontroller》(ZBS243 源头）、
  furrtek.org ESL 页（各厂射频/加密对照）、hackaday.io Pricer HD150 拆解（$20 锚点）、
  Hanshow 官网 Nebular Pro 规格页（LiMnO2/IP68/电池不可换）
