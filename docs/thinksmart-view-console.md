# ThinkSmart View 桌面主控台

定位:助手系统的**唯一可交互表面**。墨水屏全系哑终端坚守"无输入"
(eink-modules-ux §1),TSV 补上"可问可查、可操控"这条腿——它不是第 N 块屏,
是另一条腿:**交互面归它+手机+voice,环境面继续归 e-ink**。

## 1. 角色判定

| 候选角色 | 说明 | 判定 |
|---|---|---|
| 语音入口 | [View Assist](https://dinki.github.io/View-Assist/docs/supported-devices/android-devices/lenovo-thinksmart-view) 原生支持 CD-18781Y:HA Assist 卫星+状态屏;麦克风阵列本是 Teams 会议件,桌面拾音底子好 | ⭐ 主角色 |
| 渲染管线富终端 | kiosk 浏览器直指渲染服务的 HTML 模板,版面系统零改动,PNG 档之外多出**彩色实时档**(见 render-pipeline.md) | ⭐ 主角色 |
| HA 操控面板 | Fully Kiosk + HA 仪表盘,落 dorm-smart 拓扑里"HA 面板(备用)"那一格 | 兜底角色 |
| 音乐端点 | 扬声器+蓝牙,可当 MPD/PlexAmp/Snapcast 端 | 顺手,不专门做 |

红线:钉死"主控台"单一角色(一屏一事原则)——刷了 LOS 后它是台能用的
安卓平板,要刷网页干别的用手机,别让它退化成吃灰的桌面平板。

## 2. 硬件底细(Lenovo CD-18781Y)

| 项 | 实情 |
|---|---|
| SoC | SDA624 实为 **APQ8053**,骁龙 625 近亲(msm8953 家族),主线内核支持好 |
| 屏 | 8" 1280×800(面板原生竖向),Focaltech FT8201 触控 |
| 音频 | TI TAS5782M 功放+扬声器;远场麦克风阵列 |
| 隐私件 | 物理镜头盖+独立麦克风静音开关——天生贴合"室友隐私"约束(dorm-smart §约束) |
| 接口/供电 | 仅 12V 圆口供电 + 一个 USB-C(橡胶盖下,唯一数据口),无电池 |
| 库存状态 | 已停产,联想下架官方资源;全靠二手+社区固件 |
| 出厂系统 | Android Things 8.1,Teams/Zoom 两种 SKU(均须重刷,无差别) |

## 3. 改造链路(社区已走通,不必从零 RE)

链式路径:**泄露的 userdebug 固件 → EDL 刷机 → BL 解锁 → 三选一 OS**

| 路线 | 内容 | 判定 |
|---|---|---|
| **LineageOS 15.1**(Deadman 构建) | Android 8.1 底+定制 recovery 支持 sideload;修了浏览器无声/触摸超时/换 launcher 启动崩溃;[pgale 安装指南](https://github.com/pgale/lineage_15.1_Installation_TSV)是当前标准文档 | ⭐ **本系统选它** |
| Android 11 GSI + Go GApps | 一步 QFIL 包,Play 商店+GPU OC 850MHz+重分区;bug:无自动亮度/Recents 坏/部分机息屏唤不醒 | 不选:Play 对主控台无增益,bug 更多 |
| postmarketOS | msm8953-mainline 已收 device tree([PR#221](https://github.com/msm8953-mainline/linux/pull/221),kaechele),lk2nd+6.x 主线内核;但**相机无驱动、蓝牙音频缺 PCM、ALS 有问题** | 不选:主控台要 Android 应用生态(View Assist/Fully Kiosk) |

刷机前置:`bkerler/edl`(Linux 比 QFIL 省心),关机状态按住音量±插电进
EDL;`edl qfil rawprogram_unsparse.xml patch0.xml .`。固件镜像与各 ROM 包
链路见 XDA 楼主 [deadman96385 的 ROOT/解锁指南帖](https://xdaforums.com/t/guide-root-unlocking-and-improving-your-lenovo-thinksmart-view-cd-18781y.4584033/)
与 HA 论坛 [ROM/OS Development](https://community.home-assistant.io/t/lenovo-thinksmart-view-rom-os-development/676324) 长帖。

## 4. 接入现有系统

| 接口 | 接法 |
|---|---|
| 渲染管线 | `devices.toml` 加一条 TSV 终端:能力 `{1280×800, 全彩, 实时}`;kiosk 指 HTML 模板 URL,**不出 PNG**——管线第一个非哑终端 |
| HA | Fully Kiosk MQTT/REST 控屏:息屏挂"入睡"场景(无活动 30min→灭屏),晨起场景渐亮——解 LCD 夜光扰民 |
| 语音 | View Assist → HA Assist pipeline;wakeword 方案到机实测 |
| agent | Orca 任务摘要→渲染服务→TSV 富卡,与 T5 桌面卡同一数据源不同输出档 |
| 分层失效 | 纯增强层:断电/断网/关机时 HA 本地兜底不受影响("agent 是增强不是开关") |

## 5. 原则摩擦点(两个,都可解)

- **零打扰 vs LCD 夜光**:共享宿舍里一块亮屏比一墙墨水屏扰民→屏开关
  自动化挂入睡/晨起场景,不手动。
- **室友隐私 vs 常开麦**:物理镜头盖+静音开关兜底;语音常开与否需拍板
  ——wakeword-only 且静音开关当常态默认,或砍语音只做触控面板。

## 6. 采购注意

- 型号认准 **CD-18781Y**;Teams/Zoom SKU 无差别(都重刷)
- 渠道:闲鱼/二手(taoofmac 博文入手 ~€50/台,**下单前重新核价**)
- 收货检查:浅色背景看烧屏残影、触控、USB-C 口、音量键(进 EDL 要用)
- 预算位:一台 ≈ 一块 Tier3 看板+语音入口两件事的钱

## 7. 未决项

- 语音常开麦的宿舍边界(室友在场时的默认姿态)
- T5 桌面卡 vs TSV 主控台的内容分工——两屏不许显示同一条信息(一屏一事)
- View Assist 在 LOS 15.1 上的 wakeword 实测:延迟、误唤醒率
- €50 级价位是否值得囤一台备机(停产件,坏一台少一台)

## 来源

- [taoofmac: The Lenovo ThinkSmart View, Rebooted](https://taoofmac.com/space/blog/2023/04/22/1330)(userdebug 刷机+adb 精简路线,本文基准线)
- [XDA: [GUIDE][ROOT] Unlocking and Improving Your Lenovo ThinkSmart View](https://xdaforums.com/t/guide-root-unlocking-and-improving-your-lenovo-thinksmart-view-cd-18781y.4584033/)
- [pgale/lineage_15.1_Installation_TSV](https://github.com/pgale/lineage_15.1_Installation_TSV) / [mattmon/kingston-ha-rom](https://github.com/mattmon/kingston-ha-rom)
- [HA 论坛:Lenovo ThinkSmart View ROM/OS Development](https://community.home-assistant.io/t/lenovo-thinksmart-view-rom-os-development/676324)(硬件拆解底细出处)
- [msm8953-mainline/linux PR#221](https://github.com/msm8953-mainline/linux/pull/221) / [felix.kaechele.ca 预构建镜像](https://felix.kaechele.ca/projects/thinksmart/)
