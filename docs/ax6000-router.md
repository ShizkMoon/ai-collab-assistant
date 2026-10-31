# AX6000 校园网路由

> 结论：AX6000 继续当路由 + AP + 校园认证宿主，不拆。N100 只做局域网服务器，接在它后面拿 `192.168.31.x`。
>
> 核对基线：2026-10-31，AX6000 记录提交 `77dae62`（`ax6000-campus-records/`）。设备细节、实验原始 JSON 与恢复步骤以子树内文档为准，本文只记设计结论与拓扑契约。

## 它现在是什么

Redmi AX6000（RB06，stock 分区）跑 OpenWrt SNAPSHOT `r37185-f29dfe25ba` / Linux `6.18.55`，MT7986A（4×A53 @2.0G）+ 512MB RAM。

| 能力 | 当前状态 |
| --- | --- |
| 校园网自动认证 | ESurfingClient `2.1.5-r6`，四个实例（`account 1~4`），四个逻辑 WAN 共用一根物理线路 |
| 分流 | mwan3-nft 3.6.12-1，新连接随机分配，连接内固定出口 |
| 防共享 | 四出口 IPv4 TTL64（nftables），四路规则已读回 |
| 代理 | OpenClash `0.48.002` + 固定核心，LAN 透明代理；2026-10-30 从本机回滚回来 |
| 无线 | 5GHz HE160，WED 已挂接，AQL 已做默认对照 |
| 性能 | 同端点裸三路 902.30 / 908.67 Mbps，CPU 平均 33.7%、单核最高 52.5%；受控三路聚合 921.67 Mbps |

四路冷启动、四路聚合重测、电脑稳定 900 Mbps 三项仍未验收，不能把三路数字外推。

## 为什么路由不搬到 N100

| 视角 | AX6000 留在路由位 | N100 接管路由 |
| --- | --- | --- |
| 认证宿主 | 四实例已在跑，GID pin / SO_MARK / macvlan / netifd 全套验证过 | `esurfingclient` 非 OpenWrt 环境只加载第一个配置；多账号要重做整套，仓库里没有 x86 证据 |
| 无线 | HE160 + WED + AQL 调优直接可用 | N100 没有无线，AX6000 降级成纯 AP，调优作废，还要重做 AP 配置 |
| 换 MAC 风险 | 不动 | 换设备等于换 MAC，校园网端口绑定可能直接拒 |
| 实际收益 | — | 换来 RAM/overlay 余量与单核 spike 消失，**不是速度** |
| 故障域 | 路由是唯一网关 | 路由与入口同机时，路由挂了连救援入口一起没 |

现有瓶颈（CAKE 650 整形上限、Wi-Fi 完整路径的单核 softirq、CDN 端点差异）中，没有一个能被 N100 解决。N100 换来的只有余量，代价是整套认证链路重做 + 无线降级。

## 目标拓扑

```
校园网物理口
  └─ AX6000（路由 + AP + ESurfing 认证 + mwan3 + TTL64 + OpenClash）
       ├─ Wi-Fi：手机 / 墨水屏 / ThinkSmart View / 传感器
       └─ LAN 口 → N100（DS-Bot 入口宿主，192.168.31.x）
                     └─ Tailscale → 工作站 SSH → orca CLI
```

职责边界：

- **AX6000**：唯一网关。校园认证、多出口、TTL、DNS、代理全在它身上。
- **N100**：只做入口宿主，不是网关，不参与路由与 NAT。断电或重启只影响入口可达性，不影响任何设备的联网。
- **工作站**：编排与执行。任务账仍在 Orca，N100 只持 Run/Dispatch ID 与摘要。

## N100 规格

只做入口宿主，不需要四口网卡。

| 项 | 建议 | 说明 |
| --- | --- | --- |
| 主机 | 单口/双口 N100 准系统 | 不买四口 i226；那是路由才需要的 |
| 内存 | 16GB 单条 | 8GB 是下限，Chromium 一开就紧 |
| 存储 | 512GB NVMe | 256GB 起步；AgentReach profile 与附件会涨 |
| 系统 | Ubuntu 24.04 LTS / Debian 12 | DS-Bot 预构建镜像只发 `linux/amd64` |
| 软件 | Docker 24+ / Compose 2.24+ | 单容器，非 root 运行 |

进程预算沿用 [`ds-bot-entry.md`](ds-bot-entry.md)：DSH + DS-Bot 2–3GB，AgentReach/Chromium 2–4GB，IM 插件 1–2GB，OS 余量 1–2GB。16GB 对应「单容器舒适档」。

## 三条硬约束

1. **N100 的 IP 必须在 OpenClash 直连列表里。** 代理已回滚到 AX6000，LAN 默认会被透明代理。Tailscale 的 `41641/udp` 与 `3478/udp` 一旦被吃进 HK 出口，就是本机 DERP 300ms–1s 那个坑的重演。
2. **N100 不挂宿主根目录、不挂 Docker socket、不挂工作站凭据。** 容器默认 `DSH_PERMISSION_MODE=danger-full-access` + approval `never`，容器就是边界。
3. **跨机只有薄入口一条路。** 容器 → 工作站 SSH 的 key 只允许调用 `~/.local/bin/` 下的薄包装，动作固定四类：建任务、查状态、读输出、发跟进。不给裸 shell。

## 与现有文档的关系

- 入口层选型、DSH 插件边界、IM 接入：见 [`ds-bot-entry.md`](ds-bot-entry.md)。
- 三层职责、下发即监督、通道收敛：见 [`system-topology.md`](system-topology.md)。
- 设备与实验原始记录：见 [`ax6000-campus-records/`](../ax6000-campus-records/README.md)，以子树内文档为准。

## 待验收

- 四路认证冷启动（整机重启后四实例恢复、四出口 online）
- 四路同条件聚合重测（现有 921.67 Mbps 是三路、代理在路由器时测的）
- N100 加入 LAN 后 OpenClash 直连规则的实际生效验证
