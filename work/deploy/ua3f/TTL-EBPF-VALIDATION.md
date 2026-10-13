# TTL 路径复查与明确 WAN 出口 nft 替代

当前建议是保持 UA3F 3.7.0 的 L3 TTL 和 BPF 两项关闭，停止原 TC 自动重挂候选，先用独立、限定目的地址的 nft 试验。这里没有 SSH、读取私密配置、重开 BPF 或修改目标设备。

## 结论与证据范围

主代理报告 16:11 开启 TTL eBPF，16:14 用户报告原 WiFi 无网，随后用户手动断电。恢复主 WAN、停用 UA3F／OpenClash／mwan3 后，主 WAN 认证进程运行，HTTPS 百度返回 200、HTTP 探针返回 204。这些事实支持一次网络可达性回归，不能证明内核崩溃；也不能仅凭时间先后排除同时发生的认证、路由或代理失败。

已找到 UA3F v3.7.0 的具体 L2 解析缺陷，主代理回报的实机网关 MAC、三个源 MAC 以及当时 TCX 挂载均符合触发条件。这个缺陷是与本次回归高度相关、可独立复现的解释。当前没有线上抓到被破坏的帧，不能把 host replay 写成在线损坏帧或内核执行的直接证明。

## 源码怎样写错位置

固定标签 `v3.7.0/internal/bpf/tc/tc.c` 的 `parse_l2` 第 34～44 行，在解析以太网头之前，把 `skb.data` 的第一个字节按 IPv4 version／IHL 判断：高 4 位为 4、低 4 位至少为 5 时，设置 `off=0` 并直接返回。它没有先根据链路类型或 skb protocol 区分 Ethernet 和裸 IPv4。[原始 parse_l2](https://github.com/SunBK201/UA3F/blob/v3.7.0/internal/bpf/tc/tc.c#L34)

实机目的网关 MAC `48:46:fb:f7:c4:c9` 的首字节 `0x48` 被解释为 version 4、IHL 8。普通长度 IPv4 以太网帧满足后续至少 32 字节的边界检查，于是 `set_ip_ttl` 使用错误的 L3 offset 0。第 368～371 行把帧 offset 10 当 IPv4 checksum、offset 8 当 TTL；实际它们属于 Ethernet 源 MAC：第 3 字节以及第 5／6 字节。真实 IPv4 头起始在 offset 14，真实 TTL 位于 offset 22，因而没有被改写。[错误写入位置](https://github.com/SunBK201/UA3F/blob/v3.7.0/internal/bpf/tc/tc.c#L328)

`set_ip_ttl` 在误读的“TTL”小于 10，或已经等于 64 时会提前返回；主代理报告的 WAN 源 MAC 第 3 字节分别为 `0x4c`、`0x60`、`0x60`，均满足写入条件。这不是“三默认路由本身必然有错”：默认路由只让三个设备都被枚举并挂载这个有缺陷的程序。[接口枚举与 TCX 挂载](https://github.com/SunBK201/UA3F/blob/v3.7.0/internal/bpf/tc/tc.go)

## 离线复现结果

`reproduce-ttl-l2.py` 从本地已下载的正式标签源码直接抽取未修改的 `parse_l2` 和 `set_ip_ttl` 函数体，用本机 Clang 构建 Windows x64 DLL，并提供包写字节／checksum helper shim。Linux 64 位 long 和 packet structure layout 在 host shim 中明确定义。该检查执行的是 host C 函数，不是 ARM64 UA3F，也不是内核 BPF；checksum helper 为静态语义模拟。

构造目的 MAC `48:46:fb:f7:c4:c9`、原始 IPv4 TTL 37 的普通 Ethernet 帧，结果如下：

| 输入源 MAC | host replay 的输出源 MAC | 真实 IPv4 TTL |
| --- | --- | --- |
| synthetic `02:11:aa:bb:cc:dd` | `02:11:40:bb:36:de` | 37 → 37 |
| 实机主 WAN `4c:c6:4c:2c:2e:65` | `4c:c6:40:2c:3a:65` | 37 → 37 |
| 实机 eswan2 `02:66:60:00:00:02` | `02:66:40:00:20:02` | 37 → 37 |
| 实机 eswan3 `02:66:60:00:00:03` | `02:66:40:00:20:03` | 37 → 37 |

控制组只把目的 MAC 首字节换成 `0x28`，L3 offset 正确成为 14，源 MAC 保持原值，TTL 37 → 64，真实 IPv4 checksum 有效。另一个控制组把源 MAC 第 3 字节设为 `0x08`，误判仍发生，但提前返回而没有写包。结果记录在 `ttl-l2-reproduction.json`，源码 SHA256 为 `96f58cb9c4c0160f7efbbcd6c749cb0c661a73be7abb061aeec8e87a9e7c65c3`。

这些控制可以区分“普通 TTL64 数值不合适”和“L2／L3 边界误判”：host replay 中问题发生在 MAC 字节，真实 TTL 没有改变。在线网关可能因源 MAC 不符合认证／邻居关系而不转发，或回送到错误 MAC；这项线上结果仍是机制推断。

## 其他需要区分的失效路径

启动时 helper 先于 SOCKS server；BPF verifier、接口枚举或所有 TCX／classic attach 失败会让整个 UA3F 退出，`127.0.0.1:1080` 不出现。若 OpenClash 的直连分支依赖该 SOCKS，会因此中断；这不需要内核崩溃。[启动顺序](https://github.com/SunBK201/UA3F/blob/v3.7.0/cmd/root.go#L263)、[helper 失败传播](https://github.com/SunBK201/UA3F/blob/v3.7.0/internal/server/netlink/netlink_linux.go#L48)

原 UCI candidate 只开启 TTL、BPF 和 value 64，并显式关 IPID、Timestamp、TCP Window 和 QUIC 阻断；没有修改路由或 nft。只开 TTL 时，源码也不会启动 HTTP NFQUEUE、IPID／SYN 队列或 QUIC drop。因此不能把这次事件解释成已启用这些功能。旧 hotplug helper 会重启 UA3F，从而短暂中断 SOCKS，但原离线候选是否实际被安装／执行只能由主代理核对，不据源码自行认定。

原 `ttl64-ebpf.candidate.uci` 现已改为无命令的退役说明；`ua3f-ttl-reconcile.sh` 和 `99-ua3f-ttl.hotplug` 已改为 no-op。原内容保留在相邻 `.pre-incident.txt` 文件。目标设备中若已复制旧文件，需由主代理停用对应目标；本支线没有修改设备。此版本不再建议通过换 MAC、重新挂载或切 classic 回避，因为 classic 仍使用相同的有缺陷程序。

## 选择 nft 路径

下一步优先用独立 nft `ip ttl set 64`，避开这个自定义 Ethernet parser，并且不让 TTL 的初始化错误关闭 UA3F SOCKS。仍保持 UA3F 的 `l3_rewrite_ttl=0` 和 `l3_rewrite_bpf_offload=0`。

不要只把 BPF 改为 0、TTL 保持 1后启动 stock helper：UA3F 的非 BPF TTL 路径创建全局 `inet UA3F_HELPER` postrouting TTL 规则，没有 WAN oif 范围；如果 flow offload 开启，还会在 LAN ingress 设置 65，影响范围比这里的明确出口替代更大。[stock nft TTL](https://github.com/SunBK201/UA3F/blob/v3.7.0/internal/server/netlink/nftables.go)

独立替代使用 `table ip` 和 `hook postrouting priority mangle`，只按1～3 个明确、不同且当前存在的 Linux WAN 设备的 `oifname` 匹配，逐出口一条计数规则。它不改 routing mark、conntrack mark、认证规则、策略路由、IPv6、LAN 输出或其他 UA3F 功能。长期候选保留 `ip ttl >= 10` 条件，低 TTL 诊断／inject 包不改写；其余匹配 IPv4 统一为 64。

这里必须设 **64，不是 65**。IPv4 转发减 1 发生在 postrouting 之前，postrouting 设置 64 后正常出口仍是 64。65 只适用于 LAN ingress 设置后还要经历转发减 1 的补偿，本替代不创建任何 ingress chain。[Linux ip_forward](https://github.com/torvalds/linux/blob/v6.18/net/ipv4/ip_forward.c)、[UA3F ingressTTL 注释](https://github.com/SunBK201/UA3F/blob/v3.7.0/internal/server/netlink/nftables.go)

## 最小实机 nft 试验与回退

`nft-ttl-scope.sh` 已通过本机 shell 语法检查，未在设备执行。主代理将它暂存为 `/tmp/nft-ttl-scope.sh`，将 `ttl-ebpf-verify.sh` 暂存为 `/tmp/ttl-ebpf-verify.sh`。后者只是只读快照和有界 ICMP／tcpdump 工具，不会开启 BPF；抓包现已加 `-e`，用于核对源 MAC。

`<DEV1>` 等应替换为实际 Linux 设备名。脚本接受 1～3 个不同设备，各自必须存在且有 IPv4，拒绝 lo／br-lan。主代理最新回报仅 wan／eswan2 稳定上线，eswan3 已停且设备不存在；当前只验证两个出口，不为测试重建第三个。主 WAN 实际 Linux 设备名仍需按路由读回。`<TEST_IPV4>` 使用已允许探测的 IPv4 地址。先做 TTL37 基线，再仅对该目的 ICMP echo request 加三出口 TTL64，30 秒自动删除试验表。以下命令仅列当前两个出口：

```sh
# 先确认 UA3F L3 TTL/BPF 都关闭；不要重开退役程序。
uci -q get ua3f.main.l3_rewrite_ttl
uci -q get ua3f.main.l3_rewrite_bpf_offload
sh /tmp/ttl-ebpf-verify.sh probe /tmp/ua3f-ttl/nft-off <TEST_IPV4> <DEV1> <DEV2>

# 试验进程在后台等待，30 秒后删除它自己的 UA3F_TTL_PROBE。
sh /tmp/nft-ttl-scope.sh trial 30 <TEST_IPV4> <DEV1> <DEV2> >/tmp/ua3f-nft-trial.log 2>&1 &
trial_pid=$!
sleep 1
sh /tmp/ttl-ebpf-verify.sh probe /tmp/ua3f-ttl/nft-on <TEST_IPV4> <DEV1> <DEV2>
cat /tmp/ua3f-ttl/nft-on/probe-summary.txt
wait "$trial_pid"
```

试验拒绝同时存在的 UA3F TCX／classic TTL 附件、stock `UA3F_HELPER` TTL chain，或本候选的长期表，以免混合路径失去归因。它先运行目标端 `nft -c`，通过后才加载原子 transaction。只修改表 `ip UA3F_TTL_PROBE`。超时或正常退出删除该表；被 SIGKILL 可能来不及执行 trap，此时主代理可运行下面的明确回退。断电后该非持久表消失。

验收逐 WAN 应有发出请求的包值 **37 → 64**，原 Ethernet 源 MAC 保持不变，目的 MAC 为真实网关；每出口 nft counter 与对应请求一致。还需同时验证认证心跳、HTTP／HTTPS 200／204、DNS和用户 WiFi 请求没有回归。没有样本不等于通过；零样本需要读 `*-capture.txt`、`*-ping.txt` 和路由。ICMP 对方不回复，也可检查发出的请求；但可达性仍需另测实际响应。

```sh
# 只删除本候选生成的两个确定表名，不改 fw4、mwan、路由或服务。
sh /tmp/nft-ttl-scope.sh rollback
```

## 明确出口长期规则的准备边界

最小试验通过后，主代理可生成包含当前 1～3 个明确 oifname、TTL >= 10 的完整 IPv4 规则候选：

```sh
sh /tmp/nft-ttl-scope.sh render-all <DEV1> <DEV2> > /tmp/ua3f-ttl64-reviewed.nft
cat /tmp/ua3f-ttl64-reviewed.nft
nft -c -f /tmp/ua3f-ttl64-reviewed.nft
# 内容、范围和实际运行验收确认后再由主代理加载。
```

`render-all` 只输出，永远不加载规则。长期表名为 `ip UA3F_TTL64`。按名字匹配而非固定 ifindex，设备重建后无需 TC reattach，原热插拔 helper 不再使用。

nft postrouting 可能被已进入软件／硬件 flowtable 的后续转发包绕过。不能根据本机 ICMP结果宣称所有 LAN TCP／UDP 长连接都已统一 TTL。长期明确出口方案第一轮验证应关闭 flow offload，使用新 LAN TCP／UDP 流检查出口 TTL；flow offload 的变更由主代理核对原值并执行，本脚本不会擅自改 UCI。若需要继续保留加速，必须另行验证可观察路径，不能直接套 stock LAN ingress65。[nft flowtable 路径](https://docs.kernel.org/networking/nf_flowtable.html)

本支线没有新增 boot／fw4 include。主代理应接入既有防火墙 owner 并在 fw4 reload 后读回这个表，不能把“当前手工加载”写成持久规则。nft 试验、长期规则、系统恢复和校园检测效果分别验收；任何网络回归优先删除本候选表并保持已恢复的主 WAN。
