# E-Ink 技术术语对照表

速查表：面板型号命名、波形/驱动词汇、协议缩写。详见 `oepl-internals.md` /
`epdiy-internals.md`。

## 面板型号命名

| 前缀/命名 | 含义 | 例子 |
|---|---|---|
| `GDEW` / `GDEY` / `GDEH` | **Good Display** 电子纸模组编号：W=white 黑白、Y=yellow 三色(BWY)、H=高清/变体；后接尺寸+代号 | GDEW0213T5（2.13"黑白）、GDEY029T94（2.9"三色） |
| `DEPG` | **DKE/东方科脉** 模组编号，常与 GDE 系列同面板竞争供货 | DEPG0290BNS800（2.9"） |
| `ED` + 6 位 | **E Ink** 原厂面板编号：`ED` + 尺寸（两位/三位）+ 代号 + 尾缀（C=Carta膜、T=温度档等）；KPW5 `ED068KC1U1` 即 6.8" KC1 膜 U1 版 | ED060SCT、ED097TC2、ED133UT2 |
| `OTP` 前缀 | One-Time-Programmable——波形直接烧在面板 FPC 的 OTP ROM 里，无 `.wbf` 文件；多见于小尺寸 ESL 屏 | OTP 2.13" 屏 |
| `HINKE` / `HINK` | Hinak Vision 模组编号，常在 4.2"+ ESL 屏见到 | HINK-E042A03 |
| `ST-` / `EL` / `HS` | **Solum**(`ST-GR/S-GM`)、**Newton/Silicon Labs**(`EL0xx`)、**汉朔 Hanshow**(`HS`) 三大 ESL 厂牌前缀 | ST-GR29000、EL029H3WRA、HS BW 2.13" |
| `BW`/`BWR`/`BWY`/`BWRY` | 屏色：黑白 / 黑白红 / 黑白黄 / 黑白红黄 | HS BWRY 7.5" |
| `M2`/`M3` | Solum 标签系列代号：M2=ZBS243 平台、M3=nRF52/SiLabs 平台 | M2 2.9"、M3 11.6" |
| 尾缀 `@…@` | 标签标签贴纸上的附加信息（固件版本/加密型等），兼容表常省略 | `EL029H3WRA@CC` |

## 波形/驱动词汇

| 词 | 含义 |
|---|---|
| **LUT**（Look-Up Table） | 波形查找表：源灰度×目标灰度 → 每相位的 2bit 驱动码；epdiy `luts[phase][16][4]`、Kindle `wf_lut` 同款结构 |
| **phase / frame** | 波形相位/帧：一次灰度过渡跑 N 帧，每帧对全屏每个像素发一次 2bit 驱动脉冲 |
| **波形模式** | DU（直驱黑白）/ GC16（16 灰全刷）/ GL16（16 灰局刷）/ A2（大字黑白快刷）/ DU4/GL4（4 灰变体） |
| **温度档** | 波形按温度分档存（`min`/`max` 上下界）；选档取"第一个 min≥t 的区间" |
| **Regal** | E Ink 改良波形/膜系代号（白色保护膜 + 温和灰阶过渡）；`epd_regal`、`wf_regal`、epdiy `epdiy_regal` |
| **VCOM** | 面板公共电极参考电压（−1.5…−2.5V），出厂每块屏单独标定（丝印 VCOM 值），PMIC 按此调输出 |
| **FPL** | Front-Plane Laminate——前平板（膜+电极+颗粒）层压件，E Ink 产线工艺术语 |
| **高压驱动轨** | VPOS(+15V)/VNEG(−15V)/VGH(+22V)/VGL(−20V)：source/gate driver 供电，TPS65185 这类 EPD PMIC 生成 |
| **源/栅驱动** | source driver=列数据移位锁存（XCL/XLE 等）；gate driver=行选（CKV/STV/SPV） |
| **并行 TTL** | epdiy 式直接驱动：8/16bit 总线 + CKV/STV/LE/OE，无 TCON 芯片 |
| **OTP 屏** | 波形内置面板 OTP ROM 的屏：ESP32 只需发命令，不用外挂 `.wbf` |
| **`.wbf` / `.wrf` / `.epw`** | 波形二进制文件：`wbf`=面板 FPC 烧录；`wrf`=Kindle 设备波形固件；`epw`=epdiy 导出的 C 数组（非运行时文件） |
| **鬼影/残影清除** | `MODE_INIT`/`epd_fullclear`：多帧黑白翻转把滞留粒子复位；部分刷新攒残影后要定期全刷 |

## 协议/硬件缩写

| 缩写 | 全称/含义 |
|---|---|
| EPD | Electrophoretic Display，电泳式电子纸 |
| ESL | Electronic Shelf Label，电子货架标签 |
| TCON | Timing Controller，屏端时序控制芯片 |
| FPC | Flexible Printed Circuit，面板排线 |
| PMIC | Power Management IC（TPS65185/FITI9930 类，EPD 专用高压电源） |
| NTC | 屏端热敏电阻，经 PMIC `TMST` 寄存器读温度 |
| SPI/并行 | 两种屏接口：SPI（商用模组常用）vs 并行 TTL（epdiy 裸屏） |
| MAC / PAN ID | 802.15.4 链路层地址/PAN 标识；OEPL PAN 固定 `0x4447` |
| GFSK | Gaussian FSK，sub-GHz 调制方式（CC1101 用） |
| SWS | Single-Wire Slave，Telink 单线调试/烧录口 |
| cJTAG | 压缩 JTAG，CC131x 调试口 |
| SWD | Serial Wire Debug，ARM 两线调试（nRF52/EFR32 刷机口） |
| infopage/UICR | 芯片出厂信息区/用户配置区：固件按此识别屏型 |
| AP | Access Point：OEPL 语境里指 ESP32 主控板（AP 固件），不是 WiFi AP |
| tag | OEPL 语境里的 ESL 标签 |
| check-in / ADR | 标签主动找 AP 报到（Avail Data Request）的协议步 |
| MAC vs hwType | 标签链路层地址 vs OEPL 屏型编号（`tagtypes/*.json` 键值） |
| HW type 高位 | `0x00xx` 射频类、`0x01xx` OpenDisplay BLE、`0xF8/0xF9` TLSR AP、`0xC6` ESP32-C6 |
| `1bpp`/`2bpp`/`4bpp` | 每像素位深：黑白/三色/16 灰；选 bpp 决定内存与传输量 |
| dither | 抖动：把连续灰度/彩色量化到屏端色表时的误差扩散算法 |
| RGB vs 4:4:4 vs 4:2:0 | JPEG 色度子采样比；4:4:4 保锐利的红/白跳变（OEPL 推图建议） |
| baseline JPEG | 基线（非渐进）JPEG，ESP32 端解码兼容性需求 |
| COBS | Consistent Overhead Byte Stuffing，0x00 分帧的字节填塞编码（OEPL radio v2 用） |
| OTA | Over-The-Air，无线固件升级 |
