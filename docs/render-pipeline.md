# 统一渲染管线规格

> 状态：设计中 · 角色：**呈现面**的渲染实现（见 [架构总览 §9](architecture.md)）

墨水屏显示模块的服务端：一个把"数据"变成"屏上的图"的常驻管线。
模块全是哑终端——内容、版式、刷新策略全在服务端定。本文是实施规格，兼具设计与技术细节。

**在事件模型里的位置**：渲染服务是账的**只读派生视图**，不是独立事实源。它从账（与 HA 只读状态）取数，不直接轮询传感器；触发的源头是事件落定或定时重渲，不是设备自己问"现在该显示什么"。这条与 system-topology 的"前端不产生第二事实源"是同一条约束。

## 管线形态

```
数据源(HA/日历/cron/agent/API)──┐
                              ├─→ 渲染服务 → 版面缓存 → 分发器 ─→ 终端
外部触发(webhook/MQTT event)──┘    (PNG+meta)         (OEPL/HTTP/MQTT)
```

**一次渲染 = 一份版面描述 + 一份数据快照 → 一帧 PNG + 刷新元数据**。
终端不存逻辑，只存最后一帧 + 时间戳（断线显 stale，见 eink-modules-ux 体验原则）。

## 版面系统

- **模板**:HTML+CSS(或 SVG)，按终端型号绑定——每个设备注册一条 `{width, height, bpp, 色域, 刷新档}` 能力描述
- **渲染**:headless Chromium(playwright）截图 → 降到目标 bpp → 灰度/抖动算法固定一套(Floyd-Steinberg + 锐化），三色屏走调色板量化
- **版面约定**:24px 内边距、底部时间戳行、`--ink-fg/--ink-bg/--ink-accent` 三个色板变量、灰度阶梯固定 4 级(0/85/170/255)

## 输出规格（按终端档）

| 终端 | 输出 | 位深 | 通道 |
|---|---|---|---|
| OEPL ESL 价签 | PNG → `POST /imgupload` | 1bpp(BW) / 调色板（BWR/Y) | AP 中转，BLE 下发 |
| LilyGo T5 / ESP32 看板 | PNG | 4bpp/8bpp 灰度 | HTTP pull(`GET /frame/{id}`）或 MQTT 通知拉取 |
| KPW5（路线 B，未来） | raw/PNG 帧 | 8bpp | USB-ECM → einkd → fb0 |

帧缓存：`/var/lib/renderd/frames/{device}/{ts}.png` + `meta.json`（版面版本/数据快照哈希/渲染时间），终端拉取带 ETag/If-None-Match。

## 刷新策略（KPW5 逆向的三条原则移植）

1. **温度自适应**：版面元数据带 `temp_band`，服务端按终端回传温度选波形档——
   纯服务端逻辑，终端不用懂(KPW5 的 13 bank 证明这必须做，不然低温拖影)
2. **局部/全量分级**：版面标 `dirty-region` 提示，终端固件决定能否 partial;
   服务端按"距上次 full refresh ≥N 次或 ≥T 小时"插一次 GC16 全刷——防鬼影是服务端职责
3. **VCOM/时序归硬件**:成品板已调好，服务端永不碰电源参数(见 panel-power-rails 教训)

## 触发与路由

- **定时**：systemd timer 按版面声明的 `refresh_interval` 重渲。这是兜底，不是主路径——定时重渲只能保证"不空白"，不能保证"显示的是新的"。
- **事件**：账里有指定 kind 落定或转 `escalated` 时触发重渲（`eventd` 发 `POST /render/{layout}`）。**屏上的内容变化必须能追溯到一条事件**，否则它是装饰。
- **聚合版面**：日卡读的是账的派生视图（今日待处置 / 逾期 / 昨日落定数），由 `ev` 查询生成，渲染服务不自己扫设备。
- **路由表**：`devices.toml` 声明每块屏绑哪个版面、刷新间隔、唤醒窗口（价签睡眠省电）。

两条纪律：

- **不显示无法追溯来源的数字**。屏上每个区块对应一个 `event_id` 列表或一个聚合查询；查不到来源的区块是 bug。
- **不因为渲染失败而阻塞账**。渲染失败记 `system.render.failed`，屏停在旧帧并显示 stale 时间戳——这与"断网留最后帧"是同一条原则。

首屏契约（[架构总览 §9](architecture.md)）：日卡第一屏只放不能不管的事，最多一屏；其余靠翻查。

## 技术选型（草案，待实现时再定）

- 渲染:playwright + PIL(`pngquant`/`Pillow.Image.convert` 降 bpp)
- 服务：单进程 python(FastAPI)+ SQLite 版面/设备表；不要 broker 先，MQTT 直连 Mosquitto
- 部署：工作站 systemd user service；端口仅 Tailscale/局域网

## 验收（最小环）

1. `POST /render` 出一张 296×128 1bpp PNG，带时间戳角标
2. OEPL `/imgupload` 推上一张 ESL，屏显正确、dither 无脏边
3. 断 AP 电 10 分钟再通电，屏仍显示旧帧+时间戳(stale 原则）
4. 连续 partial 50 次后自动插一次全刷，屏面无残影
