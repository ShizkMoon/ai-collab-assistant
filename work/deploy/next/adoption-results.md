# AX6000 后续机制采用结果

本轮已从当前内核 ABI 对应的官方签名索引安装 IFB、CAKE 和 BBRv1 三个模块包，新建本机 TCP 的默认拥塞控制已读回为 `bbr`，一个实际新建本机 ESTABLISHED socket 也报告 `bbr`。这不证明所有 Ninja／UA3F socket 均使用 BBR，也不证明下载提速。AccECN 的 `tcp_ecn=3` 被设备内核以 EINVAL 拒绝，当前保留 `2`，无效持久文件已移除。Edge 两项 HKCU policy 写入被 Windows 拒绝，本轮没有修改；新测试连接仍为 TLS 1.3、ECH 有效、HTTP/2／h2。

CAKE 已完成开／关及 GSO 参数的三个有界样本，最终采用双向 `split-gso`，下载 650 Mbit、上传 unlimited，运行与持久服务均已读回启用。所有样本汇总仍为 `inconclusive`，开／关 CPU 峰值都到 94.4%，不能把此前 581.55 Mbps 与当前样本差额归因于 CAKE，也没有稳定吞吐或 QoS 收益结论。no-split-gso 样本未完成全部请求，本轮没有采用。

Ninja 裸核心 `ab32ad2d` 与官方最新发布一致，固定 ARM64 UPX digest 也与已部署文件对应，没有新核心需要替换。继续保留香港 02、当前 source／协议、三路认证、UA3F、九后缀国内 DoH、校园条件解析、家庭 PAC 和现有 Wi-Fi。本轮不重启整机、不重载 network、不清空 conntrack，不更新 Windows／Android／Desktop 客户端。

本轮最终验收 `next_functional_changes_accepted=true`、`accepted_changed_scope=true`、本地 `HEALTHY`；五项能力没有全部启用，`all_five_requested_capabilities_enabled=false`。既有校园 DNS 样本仍为 SERVFAIL，原策略可复现，因此完整验收保持 `passed=false`。实际可用改动、局部健康和完整验收分别报告，不相互覆盖。[最终验收](final-acceptance.json)。

## 五项注释的当前对应结果

编号严格对应本轮用户的五项注释，文档不嵌入应用 annotation directive。

| 编号 | 用户选择 | 当前结果与验收边界 |
| --- | --- | --- |
| 1 | L4S／DualPI2 可以考虑加入 | 当前 ABI 的 DualPI2 与 `tc` 具备部署入口，但本轮只安装 IFB／CAKE／BBR，未安装或启用 DualPI2。没有真实 ECT(1)、可扩展拥塞控制、CE／反馈与混合经典流量证据，不将普通 ECN 或 CAKE 当作 L4S 已使用。 |
| 2 | 全局 Edge HTTP/3／ECH 风险不大，可以启用 | 对当前 Windows 用户拟写 `QuicAllowed=1` 与 `EncryptedClientHelloEnabled=1`，两值原本不存在，Windows 拒绝写入，本轮未改 policy。Edge 155 的指定新连接已经有 TLS 1.3／`sni=encrypted`，实际 `h2`；ECH 该连接有效，HTTP/3 没有使用，未强制 H3 或改公共 Secure DNS。 |
| 3 | BBR／BBRv3 如何启用，并同意 BBRv1 | 匹配当前 `6.18.55` ABI 的 BBR 包已通过官方索引信任链安装，注册与允许列表为 `reno cubic bbr`，默认已为 `bbr`。一个新建本机 ESTABLISHED socket 的实际算法已验为 `bbr`。这是 BBRv1；不证明所有代理 socket、纯转发 PC TCP、BBRv3 或提速。 |
| 4 | AccECN 可以启用 | 实际写 `tcp_ecn=3` 返回 `Invalid argument`，读回仍为 `2`。未启用、未协商，无效持久文件已移除；保持 option 2／beacon 3／fallback 1。不凭上游参数文档或可见符号声称当前设备已接受 AccECN。 |
| 5 | CAKE／SQM 可以启用 | IFB／CAKE 已安装，最终采用下载 650 Mbit／上传 unlimited、双向 split-gso，自定义服务运行和持久启用已读回。三路各自小请求接收路径均在 IFB 观察到。开样本 263.80 Mbps、关样本 232.81 Mbps，两个 CPU 峰值均 94.4%；no-split 样本未全部完成。大下载 strict 外层覆盖不足、整体 inconclusive，没有稳定吞吐或 QoS 收益；不称标准 SQM 全套页面已具备。 |

## 官方包信任链与实际安装

设备仍为 OpenWrt SNAPSHOT `r37185-f29dfe25ba`、Linux `6.18.55`、`mediatek/filogic`、`aarch64_cortex-a53`，kernel 包为 `6.18.55~b218d80d146ac6c85db4989df73b5de9-r1`。使用这个精确 ABI 的官方 `packages.adb`，设备已有密钥验证返回 OK；模拟与真实安装只新增 `kmod-ifb`、`kmod-sched-cake`、`kmod-tcp-bbr` 的 `6.18.55-r1`。原永久 repositories 不变，没有升级 kernel／libc／base-files，没有新增全局信任或绕过签名。[索引验签和模拟](package-index-preflight.json)、[实际安装及前后读回](packages-installed.json)。

早期对独立本地 APK 直接 `apk verify` 返回 UNTRUSTED，不能把它擦掉或称独立包已经验签。当前发布的包通过官方已签名索引提供 identity／摘要来验证；后续加载可信原索引并由 APK 安装取得成功，属于另一条正确的仓库信任路径。文件 SHA 一致、索引签名与包 identity／DATA 完整性各有作用，不相互替代。[初始独立 APK 失败](package-preflight.json)、[信任路径与源码核查](package-signing-plan.md)。

## BBRv1：默认与新建本机 socket 已验收

安装加载后 `tcp_available_congestion_control` 与 `tcp_allowed_congestion_control` 均为 `reno cubic bbr`，`tcp_congestion_control=bbr`。包带 `/etc/sysctl.d/12-tcp-bbr.conf` 的启动默认设置，因此不能把它当纯运行时试用。安装前后的 Ninja／UA3F PID、network／MWAN／认证配置 hash 与固定核心 SHA 保持；包安装没有改变既有 qdisc。[安装读回](packages-installed.json)。

通过本轮新建的路由器本机 TCP 连接到公开 `223.5.5.5:443`，实际 socket 进入 ESTABLISHED，`TCP_CONGESTION` 返回 `bbr`，`TCP_INFO.state=1`。这完成默认值之外的一个真实 socket 验收；没有传输速度或拥塞收益测试，不能把它外推到全部 Ninja／UA3F socket。[实际 socket 结果](bbr-socket-acceptance.json)。

默认算法只影响按该默认创建的新 socket；应用可用 `TCP_CONGESTION` 指定算法，旧监听的接受连接也可能继承旧选择。已有连接不会由这一 sysctl 追溯切换。BBR 控制本机 TCP 发送端，不能替远端下载服务器或纯转发 PC 选择发送算法；UDP／QUIC 不因此成为 BBR。当前包是 BBRv1，BBRv3 需要独立实现／内核构建，Linux 版本与 `bbr` 名字都不能证明 BBRv3 已有。[机制与验收入口](congestion-install-plan.md)。

运行时恢复当前已记录基线的入口为：

```sh
sysctl -w net.ipv4.tcp_congestion_control=cubic
```

这不改变已经建立的 BBR socket，也不需要强行卸载活跃模块。若要完整取消下次启动默认，另须精确恢复或处理本轮包内 `/etc/sysctl.d/12-tcp-bbr.conf`，并核对其他 sysctl 优先级；只写一次 cubic 不会取消这个持久效果。移除包前先模拟只删本轮新增 `kmod-tcp-bbr`，保护原有文件，禁止扩大到 kernel 或其他包。当前 BBR 默认保持启用。

已经保存的 [rollback-bbr-cake.sh](../../../docs/local-only-materials.md) 的 `bbr` 分支先核 `/etc/sysctl.d/12-tcp-bbr.conf` 为本轮预期 SHA256 `ff6849f9d6e774560aee52828d3f4dbf4940f367fb87476d4d252e91d6a60c11`，确认目标保存位置尚不存在后，移至权限受限的 `/etc/codex-next-rollback/12-tcp-bbr.conf`，再恢复 cubic。发现未知修改就停止并保留原文件；模块继续加载，让已有 socket 自然结束。这个入口撤销本轮默认与持久文件，不声称现有连接算法被切回，也不证明恢复副本已完成真实回滚演练。

## AccECN：设备拒绝值 3，保持原值

设备写 `net.ipv4.tcp_ecn=3` 返回 EINVAL，随后四项读回仍为 `2`／`2`／`3`／`1`。记录中 `enabled=false`、`negotiation_verified=false`、`invalid_persistence_removed=true`。当前不能写“主动 AccECN 已启用”；`tcp_accecn_process` 等符号存在也不能替代 sysctl 的实际接受、握手与反馈。[实际写入拒绝和恢复](accecn-applied.json)、[符号及运行状态](current-runtime-socket.json)。

精确运行时恢复入口仍是保存的原值：

```sh
sysctl -w net.ipv4.tcp_ecn=2
```

本轮已经没有有效的 AccECN 持久新增文件。官方 `v6.18.55` 的 `tcp_ecn_mode_max` 仍为 2，正常 sysctl 路径只接受 0～2；后续上游 enable 提交才将上限改为 5。本机拒绝 3 与这个版本边界一致，但未反汇编安装内核或取得完整最终构建配置。不依据可见符号或参数文档声称完整功能已开放。以后若要采用，需包含完整支持和相关修复的新内核／固件与匹配 ABI 模块，再验握手和回退；当前不绕过 sysctl 上限。主动 ECN、AccECN、L4S 与 Prague 是不同条件，不能以连通性代替协商。[版本边界与源码](accecn-runtime-boundary.md)。

## Edge：现有 ECH 成功，HTTP/3 未使用

拟写的 HKCU 路径为 `SOFTWARE\Policies\Microsoft\Edge`，原分支和两值均不存在；本轮 Windows 拒绝写入，主代理未提权或绕过限制。`QuicAllowed` 和 `EncryptedClientHelloEnabled` 未设置时官方默认就允许相应协商路径，因此当前没有“先前全部关闭”的证据，也不能把未发生的 policy 写入当启用完成。[原值快照](edge-policy-before.json)、[支持策略与限制](browser-enable-plan.md)。

新 `crypto.cloudflare.com` 连接的 HTTP 状态为 200，Edge user agent 为 155，trace 报 `http/2`、`TLSv1.3`、`sni=encrypted`，Performance 的 `nextHopProtocol=h2`。因此该连接 ECH 有实际证据，HTTP/3 未使用；不外推所有站点、所有连接或浏览器完整 DNS 来源。[本轮浏览器实际结果](browser-transport-current.txt)。

本轮保留家庭 PAC、Windows DNS 和路由器九后缀国内 DoH／校园／广告策略。公共 DoH 模板可能绕过路由器的局域网名字、分流和广告路径，未为 ECH 自动追加。允许 QUIC 不强制 H3；普通 HTTPS 回退继续按浏览器条件运行。当前没有注册表变更需要撤回。若以后明确写策略，已保存的 [Enable-EdgeTransport.ps1](Enable-EdgeTransport.ps1) 会另存当次 `edge-policy-manual-before.json`，保护本轮原始快照，并在中途失败时尝试只撤回当次已写值；成功写入和读回才生成 `edge-policy-manual-applied.json`。该脚本需用户在当前账户提升权限的 PowerShell 中执行，Agent 没有提权。恢复候选 [Restore-EdgeTransport.ps1](Restore-EdgeTransport.ps1) 只读取当次手动快照，发现两项策略被其他动作改过就停止，不删除整分支或其他策略。两个脚本只通过本机 PowerShell 语法检查，没有执行这条后续手动流程或声称策略已被 Edge 接受。

## CAKE：采用 split-gso，保留有限对照结果

临时队列由本轮专属 `/usr/libexec/codex-cake`、`/etc/init.d/codex-cake` 与 `96-codex-cake` hotplug 管理。主路与两条 macvlan 共用物理 `wan`；入口聚合至 `ifb-cake`，下载 CAKE 为 650 Mbit，上传 `wan` CAKE 为 unlimited，两个方向使用 `besteffort flows`、`split-gso`、`ethernet`、`no-ack-filter`、每方向 `memlimit 8mb`。650 Mbit 优先保留下载能力，不保证低于校园上游瓶颈；上传 unlimited 不是完整上游上传整形。没有安装标准 `sqm-scripts`／LuCI SQM，也不称全套 SQM 已完成。[最小队列方案](queue-install-plan.md)、[实际应用及业务读回](cake-applied.json)。

初次应用后国内 HTTP 200、国外 HTTP 204、本地 HEALTHY；随后 `enable1` 的同源有界样本完成 16 流、768 MiB，载荷 24.422 秒、有效 263.80 Mbps，CPU 单核峰值 94.4%，连续高 CPU 观察 14 次。汇总为 `inconclusive`，原因是严格的活动 WAN 同源外层覆盖不足。入口总计数或透明代理内层 mark 不足以证明三路均承载这组完整下载，也不能只用 TTFB 把变化归于队列。[开 CAKE 样本](queue-cake-enable1.json)。

主线随后停止本轮队列，读回 `wan noqueue` 与 HEALTHY；同源关 CAKE 的 A 样本为 232.81 Mbps，CPU 单核最高仍 94.4%，同样有外层覆盖缺口、整体 inconclusive。因而当前不能称 CAKE 使此前 581.55 Mbps 降为 263.80 Mbps，也不能称 B 大于 A 就证明稳定吞吐收益：不同有限窗的外部源、代理、CPU 与网络状态仍影响结果。开／关样本只支持这次有限比较；没有稳定 QoS、日常速率或三路带宽收益结论。[临时回退读回](cake-runtime-rollback.json)、[三个样本汇总](cake-comparison.json)。

后续 no-split-gso 样本取得约 213.50 Mbps，但只收到 803143174 字节，未完成全部预定范围，并有恢复延迟样本缺失和一行原生外部 ping 失败；其结果仍为 inconclusive，不能把这个数字当完整下载速度。本轮恢复 split-gso，最终读回上传 unlimited、下载 650 Mbit、双向每队列 8 MiB，`runtime_active=true` 与 `persistent_service_enabled=true`。这些是当前采用状态，完整三路业务覆盖、因果提速、稳定负载延迟仍未证明。[no-split 原始样本](queue-cake-gso2.json)、[最终参数和状态](cake-applied.json)。

最后逐一路由器绑定三个源地址发起小请求，三路均取得 HTTP 204；每路对应接收 TCP 头都在 `ifb-cake` 上观察到，IFB 字节计数分别增长。该有限检查支持三个自有接收路径确实进入本轮聚合入口队列，修补了只看 lowerdev 或总计数的证明缺口；它没有证明前述 PC 768 MiB 大下载的每条外层分配，更没有证明长期混合业务覆盖或 QoS 收益。[三路自有请求的 IFB 覆盖](three-queue-coverage.json)。最终验收还读回当前两棵 CAKE 的真实非零计数及服务 running／enabled，证明当前队列在运行，不只停留在安装文件。[运行与业务最终验收](final-acceptance.json)。

本轮 hotplug 已修正为先检查 `/etc/init.d/codex-cake enabled`，再响应 wan／wan2／wan3 的 ifup。因此持久回退应先 disable 阻止自动重建，再 stop watcher，由本轮 helper 只删除它拥有的 `ca10:` root、`pref 49152` ingress redirect 和带 `codex-cake-managed` alias 的 IFB：

```sh
/etc/init.d/codex-cake disable
/etc/init.d/codex-cake stop
tc -s qdisc show dev wan
tc filter show dev wan ingress
```

disable 后 hotplug gate 也阻止后续 ifup 重建。需要重新采用已保存参数时，先核 helper／init／hotplug 与记录的 SHA，再 `/etc/init.d/codex-cake enable`、`/etc/init.d/codex-cake start` 并读回；start 进入 watcher 后应用自有队列。回退不删除共享模块，不碰 `eth0` 原 `mq`／`fq_codel`、认证 PID、TTL／MSS／MWAN 标记或既有其他 filter，不重载网络、不清空 conntrack。所有权基线不符合时先读回，而不是套用整棵队列删除。[带 enabled gate 的 hotplug](../../../docs/local-only-materials.md)、[自有队列管理脚本](../../../docs/local-only-materials.md)。

## L4S／DualPI2：具备入口，未采用

精确 ABI 仓库有 DualPI2 模块，当前 `tc` 支持对应参数，证明可准备部署。DualPI2 不是带宽整形器，CAKE 也不能把它作为子队列；同一瓶颈串联二者不等于标准 DualQ。实际 L4S 要求外层正确 ECT(1)、CE、反馈与可扩展拥塞控制，透明代理可能重建外层 TCP，不能从内层 PC ECN 推断外层；本轮没有这些端点证据。没有安装／启用 DualPI2，也不把普通 ECN、CUBIC／BBRv1、CAKE 的 AQM 当作 L4S 已验收。[L4S 条件和队列关系](queue-install-plan.md)。

## Ninja 核心：已是最新，不替换

官方裸核心最新为 `ab32ad2d`，ARM64 UPX 为 18,749,664 字节，SHA256 `3398a44cca5db17710491ec3bb474c3c1cd4a30a3f849eb063dcfd2abd35375b`；实际安装前后 `/etc/openclash/core/clash_meta` 都为这个 digest。截图的 NinjaV2 `1.0.6` 是客户端集合，24 项含 22 个安装包和 2 个仅 README 的自动仓库压缩包，没有更高裸 ARM64 UPX。上游 Mihomo latest 或 Verge prerelease 不能代替 Ninja 协议核心。本轮不替换同文件，不改固定香港 02、source／协议或许可，也不安装 Desktop／Lite／Windows／Android 客户端。[官方版本与 24 项附件核对](ninja-update-plan.md)、[公开发布元数据](release-safe.json)、[实际核心 SHA 前后](packages-installed.json)。

## 本轮剩余边界与恢复资料

当前配置／运行文件成对归档为 18,523,060／230,322 字节，runtime 共 111 项；44 个必需运行文件与当前设备逐字节一致。E 盘另一物理磁盘的 `isolated-expansion-next` 已核验 197 个普通文件、8 条链接元数据、44 个必需文件和固定核心，没有执行脚本、创建链接或恢复权限、属主、业务。旧阶段归档原值另有保留，精确模块 APK 与原签名索引也已保存。[当前成对清单](backup-manifest.json)、[隔离展开](backup-isolated-expansion.json)、[包与索引恢复清单](transport-packages-manifest.json)、[受控回退候选](../../../docs/local-only-materials.md)。文件一致性与真实路由器灾难恢复分开报告，E 盘仍在同一电脑内。

CAKE 已采用状态、三个有限样本、三路自有接收覆盖、BBR 新本机 socket 与最终健康／业务验收已反映于对应段落。校园 SERVFAIL 可在原 DNS 策略复现；本轮模块或浏览器动作不能自动把完整 DNS 验收变为通过。冷启动、硬断电、故障注入、每流迁移、整体备份恢复和长期 QoS 尚未证明。[当前最终验收](final-acceptance.json)、[此前有效改动与校园限制](../frontier/adoption-results.md)。
