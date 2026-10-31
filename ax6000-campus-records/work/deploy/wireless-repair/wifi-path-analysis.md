# AX6000 无线路径：固定版本证据与可回退修复

目标是无线 PC 的真实下载接近并最终稳定达到 900 Mbps，同时保留认证、UA3F 与出口 TTL。本文只读当前保存状态和固定上游源码，没有 SSH、设备操作、安装或生产修改。最先验证 HTTP 参照服务的发送成本及 RX 分配；不先重载驱动、开启 WED 或套用大缓冲。

## 已知状态与关键机制

`state-before.json` 记录 Linux 6.18.55、OpenWrt r37185-f29dfe25ba、mt76 2026.10.08~467ae2e3、uhttpd 2026.08.24~373145f7，WED=N。ethernet IRQ 121 / 122 和 mt7915e IRQ 132 的累计中断均在 CPU0；AP `phy1-ap0` RX RPS 为 `2`，即 CPU1；wan / br-lan RX RPS 为 0。单次累计分布不能替代负载增量；还缺 eth0 的实际 RX RPS、NAPI threaded 状态 / task affinity、mt76 TX worker affinity 与负载 CPU。wan 是 DSA 层，不能只由它的 RPS=0 推导底层 ethernet 不分散。

### uhttpd 不是无线线速基准

固定 uhttpd 的静态文件发送在 `file.c` 第 602～623 行：当 ustream 排队字节小于 256 时，`read(fd, uh_buf, sizeof(uh_buf))`，再 `uh_chunk_write()`；`uhttpd.h` 定义 `uh_buf[4096]`。此分支未使用 sendfile。`client.c` 对 socket 设置 TCP_NODELAY，再初始化 ustream。4 KiB 用户态分块、事件循环与无 Nagle 聚合可能增加本地成本，但 4 KiB write 不等于每个网络包必定为 4 KiB，也不能仅凭源码确定它就是当前限速根因。

现有纯 LAN 完整 512 MiB 为 567.06 / 600.71 / 605.33 Mbps，1 / 2 / 2 并发；平均 CPU 为 19.3 / 23.1 / 26.5%，最忙核平均 42.6 / 52.6 / 50.4%。这些均值不支持直接宣布 CPU 饱和，却缺少 uhttpd PID 及 1 秒峰值。历史默认 AQL 的 886.32 / 868.70 Mbps 也说明本机无线曾有更高实际正文能力。当前结果包含测试服务、socket 发送与无线，不能称为 Wi-Fi 硬上限。

### RPS、NAPI、TX worker、IRQ 是不同控制点

固定 OpenWrt `packet-steering.uc` 支持 `-n` dry run、`-d` debug、参数 `2` 全 CPU 模式。它发现设备和 `napi/...` 线程，使用 taskset 调整这些线程，并写 RX 队列的 `rps_cpus` / `rps_flow_cnt`；没有写 `/proc/irq/*/smp_affinity`。默认配置还会为 Ethernet NAPI 加权，再分配 WLAN。它不匹配名为 `mt76-tx phyX` 的 worker，因此重载 packet steering 不等于重新分配无线 TX worker。

固定 mt76 的 `mac80211.c` 为设备建立 `mt76_tx_worker`，`mt76_worker_setup(...,"tx")` 后使用 FIFO-low 调度；`util.h` 使用 `kthread_run(...,"mt76-%s %s",...)` 命名。`tx.c` 在 enqueue / wake 阶段调度该 worker，worker 运行软件 TXQ 调度。mt7915 `dma.c` 另外通过 TX NAPI 调用 `mt7915_poll_tx()` 做 cleanup / 完成处理。因此，无线下行涉及发起发送的应用 CPU、软件 TXQ worker、完成处理 / NAPI 及中断，不能把 AP RX RPS 掩码当作全部 TX 并行控制。

Linux 6.18 文档说明 RPS 分散接收协议栈处理，可通过 IPI 产生额外成本；单流仍按 hash 固定 CPU。XPS 选择多 TX 队列，单队列无收益。mac80211 的 AC 队列还有优先级语义，不应未经驱动核对把 BE 流强制散到全部 AC。当前 sysfs 的 tx-0 文件存在也不能证明只有一个 TX 队列；应枚举全部 tx-*。

### WED 不适合作为本轮在线开关

固定 mt7915 `mmio.c` 默认 `static bool wed_enable`，module_param 允许读写；但 `mt7915_mmio_wed_init()` 在设备初始化阶段判断它，关闭就直接返回，启用后才 attach WED 并变更 IRQ / dma_dev。在线写 Y 不会证明已有设备重新 attach。重载驱动会中断无线，需要另一个工作窗口和实际字段 / 路由验收，本轮不把它作为即刻修复。PPE / flowtable、WED、UA3F socket sockmap 与 L3 TC 是不同能力；无需把 WED 与硬件 flow offload 一起打开来验证当前 RX 分配问题。

## 第一项：短测分离服务 / socket / 无线

复用已有独占 RAM 文件和 uhttpd，仅绑定 LAN 管理地址，PC 保持当前 WLAN、位置、频段和防检测设置。先做相同 512～768 MiB、固定总字节的 1 / 2 / 12 并发，各≤30 秒；采每秒 CPU、uhttpd PID CPU、`mt76-tx` 与 NAPI task CPU、AP station / survey 增量、TCP sender 状态和接收正文。不要与公网测速同时跑。

如果现有两端已经有 iperf3，做单个 15 秒反向 TCP 与 12 并发的反向 TCP，对比 uhttpd。若没有，不扩大滚动仓库升级；可先使用现有 nc / 单独测试 helper 的有界 TCP 发送器，绑定 LAN 且只接收指定 PC，固定≤256 MiB / 15 秒。若后续要安装 iperf3，须由主线核对当前 apk 解析计划、签名、版本和不升级基础依赖，本支线不执行。

关键不是再找一个数字，而是观测区别：

- uhttpd 低、另一个 TCP sender 高，且 wireless retries / airtime 相近：支持服务发送分块 / 调度限制，不称无线瓶颈。
- 增加到 12 条明显改善，单条 `ss -tinm` / TCP_INFO 显示低 cwnd 或发送窗口、应用受限：继续核对 socket / 流控制；不用总 CPU 低推定空口限制。
- 所有 sender 相近、AP TX airtime 高、同窗 retries 增加 / bitrate 变化：支持当前无线条件；retry / failed 的累计总值不是本轮丢包率。
- TX worker 或 NAPI / softirq 单核连续高，其余核有余量：支持本地调度 / 完成处理分布问题，可以进入下一项。

发送 buffer 要读取实际 `ss -tinm` / TCP_INFO 的 sndbuf、cwnd、unacked、retrans、rwnd/app limited 等可用字段，以及 sender 的 SO_SNDBUF；系统 wmem_max=4 MiB 只是上限，不等于 socket 实际缓冲。没有 app-limited / sndbuf-limited 等信号时，不增大 tcp_wmem / wmem_max。可用独立 helper 的 per-socket buffer 做 A/B，不能把全局设置作为首个修复。

## 第二项：官方 steering=2 的临时可回退试验

这是当前最容易保持认证、UA3F、nft TTL 和 WLAN 连续在线的修复候选。先由唯一设备操作方执行只读 dry run：

```sh
/usr/libexec/network/packet-steering.uc -d -n 2
```

前提是没有 `/usr/libexec/platform/packet-steering.sh` 覆盖系统实现；若存在，先核对该文件，不绕过它。保存所有受影响网卡 RX 队列的 RPS / flow_cnt，所有被 dry run 点名任务的 affinity，原 UCI 存在与值，以及 NAPI threaded 状态。日志中确认 eth0 / wlan 设备识别与目标任务；不把当前 wan=0直接改成 f。

建立独立回退计时器后，临时运行同一个 uc 程序的模式 2（无 UCI commit），读回其实际 mask / task affinity，再以相同 source / outer endpoint / 并发做 LAN 与完整无线 PC 的短 A/B/A。若 PC 外层 CDN 无法固定，不能用公网差额确认收益，先以纯 LAN 和 CPU 分布决定。程序只改变本地调度 / RX RPS，不改包 UA / TTL 或认证协议。

全 CPU RPS 不是确定更快：额外 IPI / cache 移动也可能下降。只有吞吐改善超过前后 A 波动、softirq 热点缓和、重传 / 延迟 / 管理与业务正常才保留。退化或异常时按快照精确恢复任务和队列，不只运行模式 1，因为旧状态可能来自其他 hotplug 分配。确认有效之后，才由主线持久设置 `network.@globals[0].packet_steering=2` 并调用现有 init reload；无需 network reload、无线重建或重启认证。既有无线 hotplug helper 继续复用官方服务，不叠加第二套脚本抢写。

## 第三项：有证据后才移动 TX worker / IRQ

如果模式 2 无收益，而 `mt76-tx phyX` 与 busy core / Ethernet RX / 代理线程的冲突可以重复观察，下一候选是只移动现有 mt76 TX worker：确认 /proc/PID/comm 和 starttime，保存 taskset 旧 affinity；选择同窗空闲核心，用 `taskset -pc <CPU> <PID>` 做≤30 秒测试，随后恢复原 affinity。不可硬编码 PID 或把全部 UA3F / Clash 固定一个核；若 worker 本来可在全部核运行且未饱和，这项不应执行。单一 worker 仍不自动变成多 worker，收益取决于竞争 / cache。

IRQ 121 / 122 / 132 的 CPU0 累计集中只是候选信号。先每秒记录该 IRQ、NET_RX / NET_TX、对应 task 和 effective_affinity；只有它们在本次热点重合且允许可写 affinity 时，才单独短试无线 IRQ 的一个适当 CPU，保持 Ethernet 及其他 IRQ 不变。保存原 smp_affinity_list，精确恢复。不要运行任意下载的“MTK 全核优化”脚本、安装 irqbalance 或同时修改 RPS / IRQ / worker 三项。IRQ 硬入口与 threaded NAPI 后续处理分开，转移入口不保证转移全部负载。

## 验收与退出条件

当前公共下载 CAKE 650 Mbit 必须在根代理明确管理下临时停止并恢复，才可测试 900；不用永久放宽它来掩盖低速根因。每次只变一个项；UA3F HTTP UA 小预检、真实 outer inode / conntrack / 三出口、TTL 规则计数、认证 PID、DNS / 国内及代理 HTTPS 均需读回。连续 3 秒单核≥95%、服务失联、认证重启或不完整正文时结束自有测试并恢复，不重试压测。

修复完成须以无线 PC 实际路径、固定并读回的真实 outer、完整正文且临近重复的短窗证明收益；随后才进行用户目标的30秒稳定900验收。router local 902 Mbps 或PHY2402均不能替代。没有明显收益时交付已排除层与具体剩余点，不开启更多防检测 / 加速开关。

## 固定原始来源与本地证据

- [uhttpd file.c，373145f7](https://github.com/openwrt/uhttpd/blob/373145f72c884c36a2b16f7f47e74ffae06bd754/file.c#L602)、[uhttpd.h](https://github.com/openwrt/uhttpd/blob/373145f72c884c36a2b16f7f47e74ffae06bd754/uhttpd.h)、[client.c](https://github.com/openwrt/uhttpd/blob/373145f72c884c36a2b16f7f47e74ffae06bd754/client.c)：文件发送与TCP_NODELAY。本轮 gh 读到真实固定源码。
- [OpenWrt packet-steering.uc，f29dfe25](https://github.com/openwrt/openwrt/blob/f29dfe25baaa5c03f2b52f49dfdc12ed99abe8df/package/network/config/netifd/files/usr/libexec/network/packet-steering.uc)：dry run、模式2、RPS / taskset实现。
- [mt76 TX](https://github.com/openwrt/mt76/blob/467ae2e3f190baf737e15e318906da0dc7d0ab91/tx.c)、[mac80211.c](https://github.com/openwrt/mt76/blob/467ae2e3f190baf737e15e318906da0dc7d0ab91/mac80211.c)、[util.h](https://github.com/openwrt/mt76/blob/467ae2e3f190baf737e15e318906da0dc7d0ab91/util.h)：TX worker命名、调度与注册。
- [mt7915 DMA](https://github.com/openwrt/mt76/blob/467ae2e3f190baf737e15e318906da0dc7d0ab91/mt7915/dma.c)、[mmio.c](https://github.com/openwrt/mt76/blob/467ae2e3f190baf737e15e318906da0dc7d0ab91/mt7915/mmio.c)：TX NAPI与WED初始化。
- [Linux 6.18 scaling](https://docs.kernel.org/6.18/networking/scaling.html)：RPS、RFS、XPS的作用与代价。OpenWrt WED网页本轮受站点挑战，只引用实际取得的源码，不以挑战页面证明功能。
- 当前本地：[state-before.json](state-before.json)；已有完整结果：[LAN](../aggregation/lan-current.json)、[本机UA3F与裸重复](../aggregation/ua3f-layer-cases.json)、[结果](../aggregation/results.md)、[防检测分层](../aggregation/wireless-antidetection-analysis.md)；旧热插拔实现为 `work/deploy/firmware/upstream-packet-steering.uc` 及相邻 helper。

本轮使用 Agent Reach 的 GitHub / gh 后端获取公开固定源码；check-update读回本机v1.5.0已是最新，未升级。
