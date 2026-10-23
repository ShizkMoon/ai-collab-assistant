# epdiy 内部机制

技术档案：epdiy（ESP32 直驱商用 EPD 裸屏的软硬件栈）的波形系统、渲染管线、
ESP32-S3 驱动架构、支持面板与 ESPHome/HA 集成现状。
配套选型文档：`eink-display-modules.md` / `eink-modules-ux.md`；术语表：`eink-tech-glossary.md`。

**信息源**：vroland/epdiy 主仓源码与 wiki（2026-10 拉取）、ESPHome 文档/PR、
fread-ink/inkwave。文中以行内链接标注；本机 `/tmp/research/epdiy` 为浅克隆快照。

## 0. 定位：epdiy 解决什么问题

SPI 驱动板（SPI→TCON→EPD）把波形表和时序封装在屏端，只给上层留"发整帧"接口；
epdiy 走另一条路：**ESP32 用并行 TTL 直接驱动面板玻璃上的 source/gate driver**，
波形、灰度、刷新时序全部自己实现——所以它能刷出 SPI 屏做不到的
**16 级灰、可控部分刷新、~10fps 刷新率**，代价是硬件复杂（约 20 根信号线 + 高压电源）
和每块面板的手工调参。

它对应选型文档里"LilyGo T5 / M5Paper / ereader 主板"这一类——即 epdiy **v7 硬件**
（[epdiy-hardware](https://vroland.github.io/epdiy-hardware/)、[Getting-Started](https://github.com/vroland/epdiy/wiki/Getting-Started)）。

## 1. 版本划分：I2S → LCD_CAM 两代驱动

| 代 | MCU | 数据通路 | 状态 |
|---|---|---|---|
| v1–v6 | ESP32 (PICO-D4) | **I2S LCD 传输模式**：借 I2S 的并行外设 + DMA 推像素总线，RMT 生成 CKV | `epdiy-v7` 之前分支（v5/v6 成品板：M5Paper 类） |
| **v7** | **ESP32-S3** | **LCD_CAM 外设 RGB 模式** + GDMA + RMT；16bit 总线支持 6bpp/refresh | 主线，`src/output_lcd/` |

v7 换 S3 的动机（[Waveform-timings wiki](https://github.com/vroland/epdiy/wiki/Waveform-timings-for-epdiy)）：
S3 有独立的 LCD_CAM + 大 PSRAM，能提供更高总线带宽和新的矢量指令做帧间差分加速；
v7 板级加的是 **TPS65185 EPD PMIC**（+PCA9555 IO 扩展）替代早期分立高压方案。
**v6 与 v7 代码差异集中在 output 层**（`output_i2s/` vs `output_lcd/`），上层
`epd_highlevel` API 一致——应用代码不换。

## 2. 波形系统：`.epw` 的实际结构

### 2.1 术语澄清：没有"运行时 `.epw` 解析器"

E Ink 供应链里波形是**厂商二进制 blob**：`.wbf`（面板 FPC 上 flash 里烧录的）/
`.wrf`（Kindle 等设备的波形固件文件）。epdiy 的做法是把这些 blob **离线转成
C 数组头文件编译进固件**，而不是运行时解析文件：

```
厂商 .wbf/.wrf ──extract──► inkwave ──► JSON(模式×温度×phase 的 LUT 矩阵)
                                   │
                    scripts/waveform_hdrgen.py ──► epdiy_<panel>.h
                                   │     (--list-modes / --export-modes 1,2,5,16,17
                                   │      --temperature-range 15,35)
                                   ▼
                        EpdWaveform 结构体，链接进固件
```

（`doc/source/filegen.rst`：缺厂商波形时，可基于相近面板 `epdiy_ED097TC2` 基础波形改；
注释源说"If no waveform is provided, a default will be used"，内置波形为程序生成。）

### 2.2 `EpdWaveform` 数据结构（`epd_internals.h`）

```
EpdWaveform            { num_modes, num_temp_ranges, temp_intervals[], mode_data[] }
 └─EpdWaveformTempInterval[]   { min, max }            ← 温度档：℃上下界
 └─EpdWaveformMode[]          { type, num_phases, range_data[num_temp_ranges] }
      └─EpdWaveformPhases[]   { phases, luts, phase_times? }
           └─luts: uint8_t[n_phases × 16 × 4]         ← 每 phase 16×16 矩阵的紧凑编码
```

每字节 = **4 个 2bit 操作码**，对应 16×16 LUT 里"源灰度→目标灰度"的一次操作。
2bit 操作语义（wiki + `unpacked_lut.h`）：`00`=no-op 保持、`01`=驱黑(darken)、
`10`=驱白(lighten)、`11`=no-op/reserved。一帧相位表铺满 16 个 4B 时隙，
每 4B 组覆盖 16 个像素列——与 KPW5 解码笔记
（`/home/shizuku/Repos/kpw5-analysis/notes/waveform-lut-decoded.md`，以原生文件为准）
里 32×32 矩阵/2-bit 操作/256B 每帧的 `wf_lut` 结构是同族格式，可互为印证。

**phase ↔ frame**：一次灰度过渡跑 `num_phases` 帧；每帧对每个像素按
`luts[src_gray][dst_gray]` 查得操作码后输出驱动脉冲。帧数即"波形步数"。

### 2.3 波形模式（`epd_internals.h` `EpdDrawMode`）

| 模式 | 用途 |
|---|---|
| `MODE_INIT` | 上电清残影（多帧黑白翻转） |
| `MODE_DU` | 黑白直驱，1 帧，最快（~90ms 级） |
| `MODE_GC16` | 16 级灰保画质全刷（含清残影步序），最慢但干净 |
| `MODE_GC16_FAST`/`MODE_GL16`/`MODE_GL16_FAST` | 灰度级局部刷/快速变体（GL=grayscale local，跳全屏清除步） |
| `MODE_A2` | 黑白大字号文本极快刷（A2 = 印刷术语的 A2 尺寸黑白图） |
| `MODE_DU4`/`MODE_GL4`/`MODE_GL16_INV` | 4 灰变体、反色版 |
| 自定义 | `waveform_hdrgen.py --export-modes` 只导出需要的，省 flash |

模式语义命名沿用 E Ink 惯例：DU=direct update、GC=gray clear、GL=gray local、
A2=mono text，**Regal** 则指波形里 GLR16/GLDW16 这类"白底保护+温和过渡"配方
（Kindle `wf_lut` 同款族），epdiy 对应 `epdiy_regal` 屏型变体（见 §5）。

### 2.4 温度补偿

`waveform_temp_range_index(waveform, t)`：取第一个 `min >= t` 的档位
（`render.c`）——**厂商波形按温度分区存 phase 表**，ESP32 读出环境温度后索引到
当前温度档的 LUT，低温档用更长/更强脉冲补偿颗粒迁移率下降。

```c
epd_ambient_temperature() → render_context.waveform_range
epd_draw_base(img, area, temperature)      // 温度参数直接进渲染上下文
```

- **内置波形只带一个温度区间（默认 15–35℃ 导出窗）**，注释明示"v1–v6 内置波
  形在非室温环境补偿能力有限，建议换厂商波形"（`epd_driver.h` 注释 + filegen.rst）。
- v7 的 `epd_board_ambient_temperature()` 读 TPS65185 的 `TMST_VALUE` 寄存器——
  **PMIC 上的面板热敏电阻**，与 KPW5 的 fiti9930 NTC 方案同构
  （`/home/shizuku/Repos/kpw5-analysis/notes/epdc-temperature-policy.md`）。
- v7 已知行为：**`phase_times` 被忽略，帧率由 LCD 时钟固定**（wiki 原话：内置
  "variable-timing" 波形在 v7 上按恒定时序执行；波形表里带变化时序的 phase
  只保留重复循环效果）。需要真·变速时序要改 LCD 端脉冲计数。

### 2.5 灰度渲染管线（`render.c`）

1. `epd_draw_base()`：解析参数 → `render_context`（帧缓冲指针、波形索引、模式、
   phase 数、可选 phase_times）。
2. **差分**：`epd_difference_image_cropped()` 对前后帧缓冲逐像素做差 →
   得 dirty rect + 每像素 {src,dst}；4bpp 输入、内部统一 8bpp 工作面。
3. **LUT 展开**：`unpacked_lut()` / `lookup_pair_4b()` / S3 **矢量查表**把
   64bit 组合查表降到单指令；查表结果 = 每像素每相位的 2bit 驱动码。
4. 逐 phase：`lcd_do_update()` → 准备 context → 喂 FreeRTOS feeder task →
   等帧完成 → 推进下一相位。全部 phase 跑完一次模式更新结束。

## 3. ESP32-S3 驱动架构（`src/output_lcd/`）

### 3.1 硬件信号清单（`lcd_driver.h`）

| 组 | 信号 | 电平/时序角色 |
|---|---|---|
| 数据总线 | 8 或 16 GPIO，`bus_width` | 每时钟 8/16 像素（4bpp/6bpp） |
| 像素时钟 | LCD 内部 pclk，`bus_speed`（MHz） | source driver 移位时钟 |
| 行时序 | CKV（竖直时钟）、STV（起始脉冲）、LEH（latch）、OE（output enable） | gate driver 行选通序列 |
| RMT | 生成 CKV | 独立于 LCD 外设的周期性脉冲 |
| 电源 | TPS65185：VGH≈+22V / VGL≈−20V / VPOS≈+15V / VNEG≈−15V / VCOM≈−1.5…−2.5V | PMIC I²C 可编程 |

时序实体参数（`LcdEpdConfig_t`）：`pixel_clock`、`ckv_high_time`(≈70×0.1µs)、
`line_front_porch`(4)、`le_high_time`(4)、`bus_width`、`bus_pins[]`。
**改面板时这些就是手调项**（[parallel-pixel wiki](https://github.com/vroland/epdiy/wiki/How-pixels-are-driven-in-a-parallel-epaper-with-epdiy)）。

### 3.2 数据通路

```
framebuffer(PSRAM, 4bpp/8bpp)
  → 差分 LUT 查表（CPU/vector 加速，2bit 码流）
  → DMA bounce buffers(GDMA 链式描述符)
  → LCD_CAM FIFO → RGB 并行口(D0..D15 + pclk)
     + RMT 通道驱动 CKV/STV 行时序
  → 面板 source driver 移位锁存 → gate driver 选行 → 高压驱动像素
```

`render_lcd.c`：双线程 feeder 循环 `line_queues`，ISR 里 `frame_done` 信号量
推进 phase；`rmt.c` 管 CKV 发生器的启停。**并行是“每个 phase 都发一整帧行数据”**
——波形 LUT 决定每个像素该驱什么，LCD 总线只负责按源驱动时序把码流摆上总线。

### 3.3 与 v6(I2S) 的实质差异

| | v6(I2S LCD 模式) | v7(LCD_CAM RGB) |
|---|---|---|
| 外设 | 借 I2S 并行数据外设 | 独立 LCD_CAM/GDMA，带宽更高 |
| 总线宽 | 8bit 为主 | 8/16bit，`bus_width` 可配 |
| 灰度帧 | 4bpp/refresh | 16bit 总线 → 6bpp/refresh 余量 |
| 时序 | 相位时长随波形表可变 | **恒定 LCD 时钟**，`phase_times` 忽略 |
| 加速 | 无 | S3 vector 指令做 LUT 查表/差分 |

## 4. 支持面板对照表（`src/displays.c` + `epd_display.h`）

| 型号 | 分辨率 | 总线 | 速度(MHz) | 默认波形 | 备注 |
|---|---|---|---|---|---|
| `ED060SCT` | 800×600 | 8 | 20 | — | 6" 经典，Kindle PW 系面板 |
| `ED060XC3` | 1024×768 | 8 | 20 | — | 6" HD，KPW3/Kobo 常见 |
| `ED097OC4` | 1200×825 | 8 | 15 | — | 9.7" |
| `ED097TC2` | 1200×825 | 8 | 22 | `epdiy_ED097TC2` | **DISPLAY_TYPE_ED097TC2**：快板需要低 hold 时序 |
| `ED133UT2` | 1600×1200 | 8 | 20 | — | 13.3" |
| `ED047TC1` | 960×540 | 8 | 20 | `epdiy_ED047TC1` | 4.7"，M5Paper 同款 |
| `ED047TC2` | 960×540 | 8 | 20 | — | 4.7" v2 |
| `ED078KC1` | 1872×1404 | **16** | 11 | — | 7.8" 需 16bit 总线 |
| `ED052TC4` | 1280×720 | 8 | 20 | — | 5.2" |
| `ED103MC2` | 1872×1404 | 16 | 11 | `epdiy_ED097TC2` | 10.3"，**UP SEQ 上电序列 + 镜像**（`DISPLAY_UPSEQ_MC2 \| HORIZONTAL_MIRRORED`） |

`display_type` 兼容位：`GENERIC`、`HORIZONTAL_MIRRORED`（行数据反序送）、
`ED097TC2`（快板低 hold）、`UPSEQ_MC2`（MC2 需要的上电时序变体）。
**插一块不在表里的面板 = 填这块表 + 调时序 + 配/做波形**——三块已验证的工作量项。

Board 层（`epd_board_v7.c`）：PCA9555 IO 扩展（PWRGOOD/INT/VCOM_CTRL/PWRUP），
TPS65185 I²C 寄存器组（ENABLE/VADJ/VCOM1-2/UPSEQ/PG/TMST），上电走
`enable→wait PG→tps_set_vcom` 流程；`vcom` 默认 1600（−1.60V），
`epd_board_measure_vcom` 支持上电实测。

## 5. Regal 与波形谱系

Kindle 生态的波形命名（KPW5 解码笔记同款术语）：
`wf_lut` 里的 `epd_regal`、`epd_regal4`（ED068KC1U1 ED_REGAL 4）等型态 = 
**Regal 波形配方**：迁移层加了白色保护膜，灰阶更稳、粉彩更淡，E Ink 产线代号。
epdiy 的 `epdiy_regal` 波形文件对应此族——**给 Regal 膜系面板配的改良波形**，
与 `epdiy_ED097TC2` 这类"按某面板调的波形"同层。选屏时看面板 datasheet 是否
Regal 膜系，即可对上选哪个波形头文件。

## 6. ESPHome / Home Assistant 现状

| 组件 | 支持范围 | 状态（2025-10 时点） |
|---|---|---|
| [`waveshare_epaper`](https://esphome.io/components/display/waveshare_epaper/) | SPI 屏全谱系（1.54"–7.5" 黑白/三色，SSD1608/1681/1680 等） | **进入维护态**：新贡献转向 `epaper_spi`，存量模型逐步迁移 |
| `epaper_spi`（新） | 统一 SPI 架构：状态队列刷新、更好的部分刷新、split-buffer 省 RAM | ESPHome 2025.10 新增；首批 SSD1683（WeAct 2.9"/4.2"/2.13" 三色，PR #13894 已合入）+ 基础单模型（PR #10462） |
| epdiy | **不在 ESPHome 里**——epdiy 面板是并行 TTL，不是 SPI；要自己用 ESP-IDF 写固件 | — |

**HA 集成路径**：
- **SPI 屏（ESPHome 原生）**：YAML 里 `display:` + `lambda:` 画 UI，
  ESPHome 原生 API 自动暴露给 HA；HA 传感器/日历直接喂进 display lambda。
- **epdiy 屏**：自己写 ESP-IDF 固件（epd_highlevel + 网络拉图），HA 侧用
  REST/MQTT 推渲染好的位图；或走 **OEPL AP**——HA 有官方
  [OpenEPaperLink 集成](https://github.com/OpenEPaperLink/Home_Assistant_Integration)，
  可以把 HA 画面/图片经 `/imgupload` 打到 ESL 标签——**标签和自研看板统一在 HA 后面**，
  与选型文档的"渲染上收"决策一致。
- 渲染上收的具体实现（选型文档已定）：HA 端用 `pillow`/`Puppeteer` 渲染 PNG →
  OEPL AP/ESPHome 设备端仅解码显示。

## 7. 选型要点（与本仓已有结论的关系）

- **SPI 屏 vs 直驱**：SPI 屏（ESPHome 直接管）延迟高、只有黑/红，胜在集成省事；
  直驱（epdiy）拿到灰度+快刷，但要养一块自研板。选型文档"SPI 标签为主、
  直驱面板做展示屏"的分工在架构层正好对上这两个栈的分工。
- **波形是消耗品**：epdiy 换面板要重新拿 `.wbf`、跑 inkwave、导头文件——
  **每款面板一份波形 + 一份 `displays.c` 行**，没有通用驱动。
- **v7 的硬件门槛**：TPS65185/PCA9555/16bit 总线使板子不可手焊 DIY，
  推荐直接用现成板（LilyGo T-Echo 类板子或由 epdiy-hardware Gerber 打板）。
- **温度补偿差异**：epdiy 的温度读数来自 PMIC 的屏端 NTC，只喂波形索引；
  OEPL tag 的温度走 `AvailDataReq` 上报给 AP 做遥测——两条温度链路各自独立，
  别指望互通。

## 出处汇总

- epdiy 主仓：https://github.com/vroland/epdiy（`src/epd_internals.h`、`src/render.c`、
  `src/output_lcd/{lcd_driver.c,lcd_driver.h,render_lcd.c,rmt.c}`、`src/epd_display.h`、
  `src/displays.c`、`src/board/epd_board_v7.c`、`src/board/tps65185.h`、`doc/source/filegen.rst`、
  `scripts/waveform_hdrgen.py`）
- epdiy wiki：https://github.com/vroland/epdiy/wiki（Waveform-timings-for-epdiy、
  How-pixels-are-driven-in-a-parallel-epaper-with-epdiy、Getting-Started、Hardware-PCB）
- inkwave（厂商波形→JSON 转换器）：https://github.com/fread-ink/inkwave
- epdiy 硬件：https://vroland.github.io/epdiy-hardware/、
  https://github.com/vroland/epdiy-hardware
- ESPHome：`waveshare_epaper` 组件文档、`epaper_spi` 组件（PR #10462 基础版 / #13894 WeAct 三色）
- 本机参考（以原生文件为准）：`/home/shizuku/Repos/kpw5-analysis/notes/waveform-lut-decoded.md`、
  `epdc-temperature-policy.md`、`wrf-format.md`、`eink-module-conversion.md`
