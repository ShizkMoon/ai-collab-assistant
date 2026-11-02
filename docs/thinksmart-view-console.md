# ThinkSmart View 桌面主控台改造与接入

> 状态：设计定稿，待采购实施 · 角色：桌面常驻触控面板与语音交互终端（见 [架构总览 §6](architecture.md#6-显示端分配)）

在系统的显示端体系中，各类电子墨水屏均作为无按键、无背光的被动显示终端运行（见 [墨水屏交互设计](eink-modules-ux.md)）；**Lenovo ThinkSmart View（CD-18781Y）** 则作为书桌上的**固定触控与语音主控台**，补齐桌面触控确认、实时全彩看板与近场语音输入能力。

## 1. 功能定位与操作边界

| 角色模块 | 实现方式 | 优先级 |
|---|---|---|
| **近场语音入口** | 刷入 LineageOS 后运行 [View Assist](https://dinki.github.io/View-Assist/docs/supported-devices/android-devices/lenovo-thinksmart-view)，利用机身自带的远场麦克风阵列接入 Home Assistant Assist 语音管线 | 主力角色 |
| **实时全彩状态面板** | 通过 Fully Kiosk Browser 加载渲染服务的 HTML 实时模板，展示任务进度、多候选比选预览与传感器状态 | 主力角色 |
| **智能家居控制面板** | 展示 Home Assistant Lovelace 仪表盘，提供灯光、插座与空调的手动触控开关 | 基础角色 |
| **桌面音频输出端** | 利用内置 TI 功放与全频扬声器播放提醒音效或连接 Snapcast / Music Assistant | 辅助角色 |

**交互职责边界**：

- 为保持主控台界面专注，设备上仅安装 Fully Kiosk Browser 与语音助手组件，不安装无关娱乐应用。
- **写入操作边界**：触控屏界面仅针对**已存在于任务库中的任务**提供三项快捷操作：`[确认执行]`、`[延后处理]`、`[忽略关闭]`。发起全新的复杂任务统一通过语音指令或工作站键盘输入。

## 2. 硬件规格（Lenovo CD-18781Y）

| 硬件项 | 参数说明 |
|---|---|
| 主控 SoC | Qualcomm Snapdragon 624（实为 **APQ8053**，隶属 `msm8953` 家族，主线 Linux 内核与第三方 ROM 支持成熟） |
| 内存与存储 | 2GB LPDDR3 + 8GB eMMC |
| 显示屏与触控 | 8 英寸 1280×800 IPS 屏幕（原生竖屏排布），Focaltech FT8201 电容触控 |
| 音频硬件 | TI TAS5782M 数字功放 + 1.75" 全频扬声器；顶部双麦克风远场拾音阵列 |
| 物理隐私开关 | **配备机身物理摄像头遮挡拨片与硬件麦克风静音推钮**，符合宿舍环境的隐私保护要求 |
| 供电与数据接口 | 背部 12V DC 圆口供电（机身无内置电池，适合 24 小时插电常驻）；底部橡胶塞下隐藏 1 个 USB-C 刷机数据口 |
| 出厂固件说明 | 出厂预装 Android Things 8.1（分 Microsoft Teams 与 Zoom 两个外观版本，内部硬件完全一致，均需重刷开源系统） |

## 3. 刷机与系统改造方案

开源社区已提供完整的免拆机 EDL（9008）刷机包与系统固件，无需自行逆向底层引导：

```
原厂 Android Things → 按住音量键插电进入 Qualcomm 9008 (EDL) 模式 → 使用 edl 工具刷入解锁分区表与 TWRP → 刷入第三方 OS
```

三种主流社区固件对比：

| 固件方案 | 系统基础与特性 | 选型结论 |
|---|---|---|
| **LineageOS 15.1**（Deadman96385 构建） | 基于 Android 8.1，内置定制 Recovery，已修复 WebView 音频无声、触控休眠断流与第三方桌面崩溃问题；参考 [pgale 安装指南](https://github.com/pgale/lineage_15.1_Installation_TSV) | **主选方案**：驱动最完整，完美兼容 Fully Kiosk 与 View Assist |
| Android 11 GSI + Go GApps | 支持一步 QFIL 刷入并超频 GPU 至 850MHz，但存在自动亮度失效、多任务视图异常及部分批次息屏无法唤醒的问题 | 不采用：主控台不需要 Google Play 商店，稳定性优先 |
| postmarketOS（主线 Linux 6.x） | `msm8953-mainline` 已合入设备树（[PR #221](https://github.com/msm8953-mainline/linux/pull/221)），但目前蓝牙音频 PCM 与环境光传感器驱动尚不完善 | 暂不采用：当前阶段直接复用 Android 侧成熟的 Fully Kiosk 管理接口更省事 |

Linux 工作站下使用开源 [`bkerler/edl`](https://github.com/bkerler/edl) 工具刷机命令：

```powershell
# 设备断电状态下按住音量+与音量-键，插入电源与 USB-C 数据线进入 9008 模式
edl qfil rawprogram_unsparse.xml patch0.xml .
```

## 4. 与系统各模块的集成方式

| 对接模块 | 集成方案 |
|---|---|
| **多端显示仲裁器** | 在 `surfaces.toml` 中注册 `tsv` 终端（`resolution = [1280, 800]`，`color = "full"`，`output = "html"`），Kiosk 浏览器直接挂载渲染服务的实时 HTML 视图 |
| **屏幕背光联动** | 通过 Fully Kiosk 的 REST / MQTT 接口接入 Home Assistant：夜间触发"入睡"场景或连续 30 分钟检测到宿舍无人时自动关闭 LCD 背光，避免夜间亮屏刺眼；晨间唤醒或检测到人坐到书桌前时自动亮屏 |
| **语音输入管线** | View Assist 将唤醒后的语音流发送至本地 FunASR / SenseVoice 转写，再交由入口意图分类器处理 |
| **任务卡片交互** | 实时展示当前 `escalated`（`+me`）待确认卡片与多候选比选预览图，点击按钮直接回调 `ev` 接口更新任务状态 |

## 5. 硬件采购与验机要点

- **型号核对**：认准联想 **CD-18781Y**（Teams 版与 Zoom 版均可，刷机流程相同）。
- **收货检查项**：
  1. 在纯白与浅灰背景下检查 LCD 屏幕是否有明显老化发黄或烧屏残影；
  2. 测试全屏电容触控是否灵敏、底部隐藏的 USB-C 接口通信是否正常；
  3. 测试顶部音量加减按键与麦克风静音物理开关是否完好（进 9008 刷机模式必须使用音量键）。

## 参考资料

- [taoofmac: The Lenovo ThinkSmart View, Rebooted](https://taoofmac.com/space/blog/2023/04/22/1330)
- [XDA: Guide — Root, Unlocking and Improving Your Lenovo ThinkSmart View (CD-18781Y)](https://xdaforums.com/t/guide-root-unlocking-and-improving-your-lenovo-thinksmart-view-cd-18781y.4584033/)
- [pgale/lineage_15.1_Installation_TSV 安装步骤仓库](https://github.com/pgale/lineage_15.1_Installation_TSV) · [mattmon/kingston-ha-rom](https://github.com/mattmon/kingston-ha-rom)
- [Home Assistant 社区：Lenovo ThinkSmart View ROM/OS Development 讨论串](https://community.home-assistant.io/t/lenovo-thinksmart-view-rom-os-development/676324)
- [postmarketOS / msm8953-mainline Linux PR #221](https://github.com/msm8953-mainline/linux/pull/221) · [预构建主线镜像](https://felix.kaechele.ca/projects/thinksmart/)
