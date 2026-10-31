# E-Ink 技术术语对照表

> 角色：电子墨水屏（EPD）面板型号、驱动波形与无线电子价签（ESL）协议术语速查表。底层机制详见 [OpenEPaperLink 内部机制](oepl-internals.md) 与 [epdiy 内部机制](epdiy-internals.md)。

## 1. 面板与电子价签型号命名规则

| 命名或前缀 | 厂商与含义 | 典型型号示例 |
|---|---|---|
| `GDEW` / `GDEY` / `GDEH` | **大连佳显（Good Display）** 模组编号：`W`=黑白、`Y`=黑白黄三色、`H`=高分或改进版，后接尺寸与代号 | `GDEW0213T5`（2.13" 黑白）、`GDEY029T94`（2.9" 三色） |
| `DEPG` | **东方科脉（DKE）** 电子纸模组编号，常与佳显同规格模组互为替代 | `DEPG0290BNS800`（2.9"） |
| `ED` + 6 位字符 | **元太科技（E Ink）** 原厂面板编号：`ED` + 尺寸（两或三位数字）+ 系列代号 + 膜系后缀（如 `C`=Carta 膜）；KPW5 使用的 `ED068KC1U1` 即 6.8" Carta 1200 面板 | `ED060SCT`、`ED097TC2`、`ED047TC1` |
| `OTP` | One-Time Programmable：波形表已在出厂时烧录进面板 FPC 排线上的 OTP ROM 中，无需外部 MCU 加载 `.wbf` 文件（常见于小尺寸 SPI 价签屏） | OTP 2.13" 面板 |
| `HINKE` / `HINK` | 合力泰（Holitech / Hink Vision）电子纸模组编号，常见于 4.2" 及以上拆机价签 | `HINK-E042A03` |
| `ST-` / `EL` / `HS` | 三大主流电子价签厂商前缀：**Solum**（`ST-GR` / `ST-GM`）、**Solum Newton**（`EL0xx`）、**汉朔 Hanshow**（`HS` / `Stellar` / `Nebular`） | `ST-GR29000`、`EL029H3WRA`、`HS BW 2.13"` |
| `BW` / `BWR` / `BWY` / `BWRY` | 面板显色能力：黑白双色 / 黑白红三色 / 黑白黄三色 / 黑白红黄四色 | `HS BWRY 7.5"` |
| `M2` / `M3` | Solum 价签硬件代号：`M2` 采用三星 ZBS243（8051 核）平台，`M3` 采用 Nordic nRF52811 或 SiLabs EFR32xG22（ARM 核）平台 | Solum M2 2.9"、M3 11.6" |

## 2. 驱动电路与波形（Waveform）术语

| 术语 | 技术含义 |
|---|---|
| **LUT（Look-Up Table，波形查找表）** | 定义像素从"源灰度"过渡到"目标灰度"在每个相位（Phase）应施加的 2-bit 电压操作码矩阵（`00`=保持、`01`=驱黑、`10`=驱白）；`epdiy` 的 `luts[phase][16][4]` 与 Kindle 的 `wf_lut` 均为此结构 |
| **Phase / Frame（波形相位/帧）** | 完成一次灰阶图像更新所需连续施加的脉冲步数（通常一次 `GC16` 全刷包含数十个 Phase），每个 Phase 对全屏像素输出一轮驱动脉冲 |
| **刷新模式（Waveform Modes）** | `MODE_INIT`（多帧黑白翻转清屏）/ `DU`（Direct Update，单色快刷）/ `GC16`（Grayscale Clear 16，16 级灰带闪烁全刷）/ `GL16`（Grayscale Local 16，无闪烁灰阶局刷）/ `A2`（单色极速刷字） |
| **温度分档（Temperature Bands）** | 电泳粒子迁移速率受温度影响显著，厂商波形表按温度区间（`min`–`max` °C）存储多套 LUT；驱动端读取屏端 NTC 温度后查表选择对应档位 |
| **Regal 波形** | E Ink 针对 Carta 膜系推出的无闪烁灰阶刷新算法（如 `GLR16` / `GLD16` 及 `epdiy_regal`），通过局部脉冲序列在不触发全屏黑闪的前提下抑制灰阶残影 |
| **VCOM（公共电极参考电压）** | 面板前电极参考偏置电压（通常在 −1.5V 至 −2.5V 之间），每批次面板出厂实测标定并印在 FPC 排线上，由 PMIC 精确输出 |
| **FPL（Front-Plane Laminate）** | 前基板层压膜（包含微胶囊/微杯电泳介质层与 ITO 透明导电膜），即电子纸的核心显示薄膜材料 |
| **高压驱动轨（Power Rails）** | 驱动电泳粒子所需的四路高压电源：`VPOS`（+15V）、`VNEG`（−15V）、`VGH`（+22V）、`VGL`（−20V），通常由 TPS65185 或 FITI9930 等专用 EPD PMIC 按严格时序生成 |
| **Source / Gate Driver（源极/栅极驱动器）** | 绑定在玻璃基板边缘的行列驱动芯片：Source Driver 负责锁存每行像素的列电平，Gate Driver 负责按行扫描选通（控制信号包括 `CKV`、`STV`、`LE`、`OE`） |
| **并行 TTL 直驱 vs SPI TCON** | SPI 模组由屏端内置 TCON 芯片管理波形与刷新；并行 TTL 直驱（如 `epdiy`）则由外部 ESP32-S3 通过 8/16 位数据总线加时序控制线直接驱动玻璃基板上的行列驱动器 |
| **`.wbf` / `.wrf` / `.epw`** | 波形文件扩展名：`.wbf` 为 E Ink 原厂烧录二进制格式；`.wrf` 为 Kindle 专用波形固件格式；`.epw` / `.h` 为 `epdiy` 通过 `inkwave` 工具转换出的结构化波形数据 |
| **鬼影（Ghosting）** | 多次局部刷新后部分电泳粒子滞留导致的旧画面残影，需定期插入一次 `GC16` 全屏刷新清除 |

## 3. 硬件接口与 OpenEPaperLink 协议缩写

| 缩写 | 全称与技术说明 |
|---|---|
| **EPD** | Electrophoretic Display，电泳式电子纸显示屏 |
| **ESL** | Electronic Shelf Label，商超电子货架标签（电子价签） |
| **TCON** | Timing Controller，时序控制器 |
| **FPC** | Flexible Printed Circuit，柔性印制电路排线 |
| **PMIC** | Power Management IC，电源管理芯片（如 TI TPS65185） |
| **NTC** | Negative Temperature Coefficient，负温度系数热敏电阻（贴装于面板背面测量环境温度） |
| **PAN ID** | IEEE 802.15.4 个人局域网标识符；OpenEPaperLink 协议固定使用 `0x4447` |
| **GFSK** | Gaussian Frequency-Shift Keying，高斯频移键控（Sub-GHz 频段 CC1101 射频模块采用的调制方式） |
| **SWS** | Single-Wire Slave，泰凌微（Telink TLSR825x/8359）芯片专用的单线调试与烧录协议（可通过普通 UART TX 引脚模拟） |
| **SWD / cJTAG** | ARM Cortex-M 系列芯片的两线调试烧录接口（nRF52811 与 EFR32 使用 SWD，TI CC1310 使用 cJTAG） |
| **Infopage / UICR / User Data** | 芯片内部独立于主程序 Flash 的非易失性出厂配置扇区，记录原厂 MAC 地址、校准参数与屏幕硬件型号；刷机前必须先备份该区域 |
| **OEPL AP** | OpenEPaperLink 语境下的主控网关板（运行于 ESP32-S3），负责管理标签数据库与下发待显示图像 |
| **Check-in / ADR** | 标签定时从深度睡眠唤醒并向 AP 发送 `PKT_AVAIL_DATA_REQ`（`0xE5`）询问是否有新图像数据的过程 |
| **`hwType`** | OEPL 中标识标签具体屏幕尺寸、分辨率与颜色的表索引号（对应 `resources/tagtypes/NN.json`） |
| **COBS** | Consistent Overhead Byte Stuffing，一致性开销字节填充编码（用于 OEPL AP 主控与射频协处理器之间的 2Mbaud 串口 v2 成帧协议） |
