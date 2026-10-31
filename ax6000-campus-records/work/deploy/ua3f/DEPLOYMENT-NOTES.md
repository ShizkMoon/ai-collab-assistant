# UA3F 离线部署交接

本目录只准备本机包检查和模板。设备安装、配置、启动及回退由主代理统一负责；本支线没有 SSH、执行 ARM64 程序、执行包脚本或读取私密配置。

## 已核验包

| 字段 | 实际值 |
| --- | --- |
| 上游 | `SunBK201/UA3F`，正式 `v3.7.0` |
| 发布标签 commit | `e464514ab313e3afe308881d7e5732a5baf41ce2` |
| 文件 | `ua3f-3.7.0-r1-aarch64_cortex-a53.apk` |
| 包内 name / version / arch | `ua3f / 3.7.0-r1 / aarch64_cortex-a53` |
| 文件字节 | 6,117,590，约 5.83 MiB |
| SHA-256 | `6ba0e152895212cad25085c8834513c2962df4c415f5599e1eab9900478b2089` |
| 解包文件总大小 / manifest installed_size | 16,507,405 字节，约 15.74 MiB，未计入依赖和文件系统开销 |
| 包内文件 | 25 个数据文件；包含二进制、UCI、init、LuCI controller/CBI/views/翻译与 Web 静态资源 |
| 签名块 | ADB 包没有 signature block；本次验证的是官方 release asset digest，不是 OpenWrt 软件源签名链 |
| 包内核心 ELF | ELF64，小端，`EM_AARCH64=183`，`ET_EXEC=2`，动态解释器 `/lib/ld-musl-aarch64.so.1` |
| 包内核心 | 16,378,216 字节，SHA-256 `97f77e919215b6522e5e5fa4813cc2602ab1d33c3f625b806486a37cdc70dbb4` |

来源：[正式发布](https://github.com/SunBK201/UA3F/releases/tag/v3.7.0)、[包下载](https://github.com/SunBK201/UA3F/releases/download/v3.7.0/ua3f-3.7.0-r1-aarch64_cortex-a53.apk)、[发布 API](https://api.github.com/repos/SunBK201/UA3F/releases/tags/v3.7.0)。本机 `release-v3.7.0.json` 保留摘要、大小与下载来源，`package-manifest.json` 保留实际包元数据、文件和脚本。

这是 APK v3 `ADBd` 格式，不是 ZIP 或传统 tar APK。`inspect-apk.mjs` 只解压和解析，格式依据上游 apk-tools 的 `adb.h` / `apk_adb.h`；不执行包或内核。包内 UCI、init 与 uci-defaults 已逐字节比对正式标签，同源一致。已提取为 `package-etc__config__ua3f`、`package-etc__init.d__ua3f` 和 `package-etc__uci-defaults__luci-ua3f`。

核心已静态检查，未执行。主代理应先核对解释器存在，再验证实际运行。核心按独立 4 KiB 块分别 zlib 压缩的本机估算为 7,182,667 字节；该值只用于判断 UBIFS 透明压缩可能显著减少实际占用，不能替代设备安装预算、依赖预算、文件系统开销或安装后的 `df` 读回。当前主代理报告持久安装 OpenClash 和 Ninja 后 overlay 可用约 19 MiB；不能据此直接承诺全部依赖一定可安装。

LuCI 在此主包内，不需要另找 `luci-app-ua3f`。依赖求解和安装可信策略由主代理在已授权范围内按现有 APK 工具确认，不绕过依赖或内核 ABI。包摘要正确不等于已验证本机运行和校园效果。

## 实际依赖

实际 APK 的 depends 为：

```text
ipset
iptables
iptables-mod-conntrack-extra
iptables-mod-extra
iptables-mod-ipopt
iptables-mod-nfqueue
iptables-mod-tproxy
kmod-nf-conntrack-netlink
libc
luci-compat
```

这些依赖与标签 Makefile 一致，且没有指定版本。即使运行方案只用 SOCKS5 + TTL TC，安装器仍会要求声明的 iptables 依赖。新增 kmod 必须与当前 `6.18.55` 和精确固件 ABI 匹配。不能强装后来 SNAPSHOT 内核包，更不能因为模式暂时不使用就强制忽略依赖。[固定包配方](https://github.com/SunBK201/UA3F/blob/v3.7.0/openwrt/Makefile)

功能附加依赖需分别看：本方案不启用 HTTP NFQUEUE 或 TPROXY，因而不要把发布页通用的 `kmod-nft-queue`、`kmod-nft-tproxy` 当成新增必选项。TTL eBPF 的 LuCI 检查 `kmod-sched-bpf`，底层仍需实际内核 BPF/TC 支持、可用挂载接口与 verifier 成功。LuCI 新版本页面报错时，上游 release 建议核对 `libubox-lua`；先读错误和现有依赖再处理。[LuCI L3 检查](https://github.com/SunBK201/UA3F/blob/v3.7.0/openwrt/luasrc/model/cbi/ua3f/l3rewrite.lua)、[LuCI 包检查函数](https://github.com/SunBK201/UA3F/blob/v3.7.0/openwrt/luasrc/model/cbi/ua3f/utils.lua)

## 配置和守护

`ua3f.baseline.conf` 是拟写入 `/etc/config/ua3f` 的 UCI 基线。先保持 `enabled=0`，让主代理核对安装、端口、路由和 OpenClash 配置，之后再启用。

核心字段是 `main.server_mode=SOCKS5`、`bind=127.0.0.1`、`port=1080`、`rewrite_mode=GLOBAL`、`ua=FFF`。三类 JSON rewrite 列表为空；MitM、Desync、IPID、Timestamp、SYN Window、UDP/443 全局阻断、L3 BPF 和 socket BPF 初始都关闭。`FFF` 沿用上游默认，仅代表固定 UA 值，不保证任何检测效果。

上游默认虽然 disabled，但模式为 TPROXY、绑定 0.0.0.0；不能安装后未经配置就启动。stock init 读取 UCI，转换为命令行参数和环境变量，**不读取 YAML，也不传 `-c`**。`ua3f.reference.yaml` 仅供人工运行 `ua3f -c <path>` 时核对，不要误当 stock service 使用的配置。[UCI 默认](https://github.com/SunBK201/UA3F/blob/v3.7.0/openwrt/files/ua3f.conf)、[procd init](https://github.com/SunBK201/UA3F/blob/v3.7.0/openwrt/files/ua3f.init)

守护为 `USE_PROCD=1`、`START=99`，支持 respawn 和 UCI reload trigger；reload 会 stop/start。服务实际进程参数和环境、监听、日志、退出码要读回。stock init 指定 nofile 65535、memlock unlimited；不代表 BPF 初始化已成功。进程会把 OOM score 调为 -900，并按环境把 GID 设为 `nogroup` 等；只改 GID，不主动降 UID。`log_lines` 是界面使用字段，不应据此承诺后台日志严格限制到 300 行。[daemon 设置](https://github.com/SunBK201/UA3F/blob/v3.7.0/internal/daemon/daemon_unix.go)

stock init 没有导入 API 监听配置；CLI 默认 API 地址为空，故 API 关闭。SOCKS5 的监听仅本机，不能开放到 LAN/WAN；本包 SOCKS5 不提供用户名密码鉴权。本方案把 OpenClash 的此出口设为 `udp:false`，未启用该流量分支的 SOCKS UDP；UA3F 本身仍具有 UDP ASSOCIATE 实现，不能宣称程序完全没有 UDP。

## TTL 路径当前选择

UA3F v3.7.0 原始 TC TTL 实现已退役，保持 `main.l3_rewrite_ttl=0` 和 `main.l3_rewrite_bpf_offload=0`。`ttl64-ebpf.candidate.uci` 现不包含启用命令，`ua3f-ttl-reconcile.sh` 和 `99-ua3f-ttl.hotplug` 现为 no-op；原内容保留在相邻 `.pre-incident.txt` 文件用于复查。此处只修改本地候选，目标设备的旧副本由主代理负责停用。

主代理报告开 TTL eBPF 后 WiFi 无网，用户随后手动断电；恢复主 WAN、停用代理／多 WAN组件后实际请求返回 200／204。这不是内核崩溃的证据。源码查明 `parse_l2` 在解析 Ethernet 之前，把目的 MAC 首字节 `0x48` 错当 IPv4 version 4／IHL 8，导致 L3 offset 0。`set_ip_ttl` 随后把帧 offset 8 和 10 当 TTL／checksum，实际改写源 MAC，而真实 IP TTL 不变。[parse_l2](https://github.com/SunBK201/UA3F/blob/v3.7.0/internal/bpf/tc/tc.c#L34)、[set_ip_ttl](https://github.com/SunBK201/UA3F/blob/v3.7.0/internal/bpf/tc/tc.c#L328)

实机网关目的 MAC `48:46:fb:f7:c4:c9`、三个当时源 MAC 的第 3 字节及 TCX 挂载均满足条件。本机抽取未改 C 函数体，并用 host helper shim 对这些 MAC 复现，三个源 MAC 均被改写，真实 TTL 37 留在 37；普通目的 MAC 控制组则保持源 MAC并将 TTL 改为64。记录在 `ttl-l2-reproduction.json` 和 `reproduce-ttl-l2.py`。这是高度相关的源码缺陷及 host replay，未线上抓到损坏帧，不能声称在线损坏已直接取证。

替代优先使用独立 nft `table ip`、postrouting TTL64，仅按当前 1～3 个明确 WAN Linux 设备的 oifname 匹配。这里用 64，因 IPv4 转发减 1 已发生；不采用 LAN ingress65。不要盲目只关 BPF、保留 TTL并启动 stock helper：stock nft TTL 是全局 postrouting，flow offload 开启时还会改 LAN ingress65，范围不同。[stock nft helper](https://github.com/SunBK201/UA3F/blob/v3.7.0/internal/server/netlink/nftables.go)

`nft-ttl-scope.sh` 提供限目的 IPv4 ICMP、最多60秒自动删除的试验；`render-all` 只生成按明确出口的长期规则候选，不加载。当前主代理只报告 wan／eswan2 稳定上线，eswan3 已停，不为测试恢复第三个。`ttl-ebpf-verify.sh` 保留为只读快照与 TTL37 探针工具，现用 tcpdump `-e` 同时读源 MAC；它不会启用 BPF。试验步骤、回退、flow offload 与持久化限制见 `TTL-EBPF-VALIDATION.md`，均需主代理设备执行与读回。

## mark 与本机流量

TCP `SO_MARK=0xc9`，Desync inject 另用 `0xc91`，本方案 inject 关闭。SOCKS 直连 TCP 是由 UA3F 新建的本机 OUTPUT 连接，不能假定继承原客户端 mwan3 出口选择。OpenClash 回环绕过需核对 `nogroup`/mark 契约，并给本机出站一个明确策略。不要只比较 mark 数字相同与否；应核对 mask、全值 set/restore 和 rule 优先级。

本模式没有 UA3F 全局透明 TCP 接管链，不应该产生 UA3F TPROXY `0x1c9` 等路由；此处只给 TCP 出站 mark。L3 TC 处理不会自动继承 ESurfing 的认证出口选择。认证、控制访问和校园 DNS 仍由主代理的路由／分流规则明确直连。[TCP mark](https://github.com/SunBK201/UA3F/blob/v3.7.0/internal/server/base/tcp_linux.go#L17)、[SOCKS 连接](https://github.com/SunBK201/UA3F/blob/v3.7.0/internal/server/socks5/socks5.go#L210)

`openclash.fragment.yaml` 只提供本地 SOCKS 节点和选择组。应合并进主代理已验证的配置，不替换完整配置、不添加盲目的 MATCH、不让认证／LAN／Ninja 节点连接回到这个组。具体 direct TCP 规则由主代理按最终策略加入。

主代理已报告 UA3F 3.7.0 原包安装、匹配 ABI 的基础依赖安装，以及 SOCKS HTTP UA `FFF`、HTTPS 百度 200；后续原 TC TTL 路径已停止。当前仍需逐项验收独立 nft TTL 的真实包值、原源 MAC、主 WAN／eswan2 认证与实际 WiFi 可达性。此前 SOCKS 基线成功不等于新 TTL 路径、持久化或校园检测效果通过。
