# SmartDNS 与轻量性能验收交接

适用时间：2026-10-12。主代理执行设备操作；本支线只准备官方包、配置、脚本和判断方法，没有 SSH，没有改设备或执行真实测速。

## 首选方案

先安装 OpenWrt 官方 feed 的轻量 SmartDNS 46.1-r1，在 `127.0.0.1:6053` 独立比较。它与 dnsmasq 53、OpenClash 7874 可以共存，但本阶段不修改系统 DNS、不劫持 DNS、不将 SmartDNS 设为全局上游。先判断国内直连域名的解析和 CDN 连接是否改进；没有明确收益时保持试验组件禁用，不为组合完整而强制加入生产路径。

### 已核对的官方包

本目录 `smartdns-46.1-r1.apk` 来自 OpenWrt 官方 snapshot `aarch64_cortex-a53/packages` feed，文件 182010 字节，APK 元数据声明安装逻辑大小 396556 字节，核心程序 360187 字节。包的运行依赖是 `libc`、`libopenssl3`、`libpthread`，提供 `smartdns-any`；源码 build dependency 写 `libopenssl`，最终实际 APK 名称为 `libopenssl3`。没有必需 LuCI 包；初验不用额外管理页。

SHA256：`68bcab0121093c21a015a8db77c6cdb44028d3c585ff5e4dc70855822b6ee8f7`。元数据保存在 `smartdns-46.1-r1.apk.metadata.json`。这是本机下载文件校验，不替代 APK 仓库签名校验；主代理优先让设备 APK 从已有可信仓库安装并模拟解析依赖，避免安装过程顺带大范围升级。

上游最新是 Release48.4（2026-08-05），上游 aarch64-openwrt-all APK 9129099 字节，明显不同于官方 feed 46.1 的 182010 字节。当前需求不需要以约 8.7 MiB 上游整合包取代现有官方小包。

设备执行前先读 `apk info -a smartdns` / `apk add --simulate smartdns`，再核对只新增所需包；具体 apk CLI 选项按设备帮助读回。不要把核心 APK 的 0.38 MiB 逻辑容量当成含全部未安装 OpenSSL 依赖的完整预算。

## 独立启动，避免默认服务改写 DNS

官方 46.1 OpenWrt init 默认 `auto_set_dnsmasq=1`；服务启用后可能添加 `127.0.0.1#port`、设置 `noresolv`、关闭 rebind protection/domainneeded，或者在 port=53 时关闭 dnsmasq DNS。UCI 的 bind 生成器主要生成 `:port` 或 `[::]:port` 及接口限定，不直接生成严格的 `127.0.0.1:6053`。所以初验使用本目录原生配置，保留官方 UCI `enabled=0`；不直接启用官方生成器。

试验配置可放 `/tmp/smartdns-trial.conf`，主代理用独立 foreground 子进程：

```sh
/usr/sbin/smartdns -v
/usr/sbin/smartdns -h
/usr/sbin/smartdns -f -p - -c /tmp/smartdns-trial.conf
```

`-p -` 避免占用官方服务 pidfile；`-x` 是 verbose 输出，不是语法检查。启动后核对只有 `127.0.0.1:6053` 的 UDP/TCP 监听、没有 53 占用、原 DHCP/dnsmasq 校园 DNS 配置没有变化。服务运行期间通过另一现有设备执行通道查询，不为试验连接任意新服务。

若 A/B 后决定长期采用，`smartdns-local.init` 可作为独立 procd 入口，读取 `/etc/smartdns/local-domestic.conf`；保留官方服务禁用。脚本只是可审阅模板，没有复制到设备，也没有启用启动项。主代理须检查配置内容、路径及服务命名是否与实际组件冲突，再部署。

## A/B 不是只看 DNS 速度

1. 先用 `smartdns-trial-no-speed.conf`，同当前 `10.50.11.15` 和 `202.96.128.86` 两个上游，关闭缓存与主动探测。执行 `dns-ab.sh 2`，比较当前 DNS、dnsmasq 和 SmartDNS 查询耗时、CNAME/A 结果及错误。BusyBox nslookup 大版本支持 `-type=A -retry=1 -timeout=2` 和 `127.0.0.1:6053`；设备实际帮助与一次查询确认后再批量跑。
2. 再比较 `smartdns-trial-cdn-no-speed.conf` 与 `smartdns-trial-cdn.conf`，两者上游池相同，后者用 `tcp:443,ping`/`first-ping` 选地址。试验监听使用 `-no-cache`，缓存容量仅设 128，绕过试验查询的缓存；46.1 在全局 cache-size=0 时会把 fastest-response 强制改成 fastest-ip，因此不能靠 cache-size=0 保持相同响应模式。各做 1～2 轮固定四域名，记录实际网络出口。不能把不同上游与主动选址两项同时变化归因于其中一项。
3. 对答案不同的域名，只检查各答案中的最多两个候选 IP。Windows 现有 curl 用原 hostname/SNI 和 `--resolve host:443:ip` 发起短时 HEAD/小 Range 请求，记录 TLS 是否成功、连接时间、首字节时间、HTTP 状态与 actual remote_ip。域名相同、URL 相同、路径直连才有比较意义；不使用 `-k` 绕过证书校验，也不下载任意大型内容。
4. 最后使用 `smartdns-domestic-candidate.conf`（缓存 2048）复验正常缓存命中和启动后查询，不把热缓存与冷查询混成“性能提高”。缓存不持久化、不预取、不返回过期记录、不过度抬高 TTL，先保留答案更新的可靠性。

查询脚本用 `/proc/uptime`，约 10 ms 分辨率，包含 nslookup 进程开销；足以看超时或几百毫秒差异，不足以证明 1～5 ms 微小改善。上游是否已缓存不可控制；2 轮短样本只作选择线索。需要更精确数据时可用已有 `dig`，没有则不为此安装整套 BIND（bind-dig 另依赖约 1.2 MiB bind-libs）。

当前没有 IPv6 默认路由，A 查询为主要性能样本；仍用少量 AAAA、CNAME、NXDOMAIN 检查解析语义，不能把没 IPv6 路由变成默认屏蔽所有 AAAA/HTTPS type65 的理由。模板没有强制这些记录为空。校园认证域名、连通性检查与校内地址单独保留校园 DNS；不要送给公共 DNS 池，也不要开启速度探测。

解析快而 HTTP/TLS/首字节没改善，并不构成采用 SmartDNS 的充分证据。主动 TCP/ping 是地址响应探测，不是下载带宽测量；多出口或代理后端不同也会改变探测与应用路径的意义。SmartDNS 官方说明代理域名应关闭速度探测，防止探测出口与实际应用出口不一致。

## 与 OpenClash、dnsmasq、adblock-fast 的单向路径

生产候选路径：客户端 53 → dnsmasq（DHCP/本地域名/广告阻断）→ OpenClash 7874 → 仅已验证国内直连域名到 SmartDNS 6053 → 明确的公网 DNS IP。校园认证域名通过独立的校园 nameserver-policy/认证豁免走 `10.50.11.15`；代理域名按 OpenClash 原代理 DNS 策略处理。

SmartDNS 不配置 `127.0.0.1:53`、`127.0.0.1:7874`、`system` 或系统 resolv-file 上游。OpenClash `default-nameserver` 与代理节点解析也不回送 dnsmasq。避免形成 53→7874→6053→53 或 7874→53→7874 回环。上游公网 DNS 和主动探测必须按选定直连出口，不能被路由器 OUTPUT 的透明 DNS/代理规则再抓回 OC；按实际 nft 规则与日志确认。

若使用 `nameserver-policy` 指定已验证域名到 `127.0.0.1:6053`，只合并具体白名单；不要立即用“所有国内 geosite”扩大范围。Fake-IP 模式还需这些 CDN/认证域名按需要真实解析，且 DIRECT 出口解析是否跟随 nameserver-policy 必须核验：Mihomo `direct-nameserver-follow-policy` 默认 false。不同 Ninja 私有内核选项支持须实际 config 测试及查询确认，不能仅凭上游 Mihomo 文档认定等同。

OpenClash 的 dnsmasq forwarding 模式会备份/重写 server、noresolv、resolvfile、cache；直接写到 dhcp 的临时域名 server 可能在 OC 重启后被覆盖。域名策略放入 OC 支持的持久覆写路径，重启与订阅更新后读回。用 firewall DNS redirect 模式直达 7874 会绕过 dnsmasq 的广告列表；此时不能宣称 dnsmasq backend 的 adblock-fast 仍完整有效。

adblock-fast 优先选 `dnsmasq.servers`，只保留一个广告规则后端，并明确 `force_dns=0`，不叠加它默认的 53/853 拦截与 OC DNS 规则；不强制拉取大列表。认证、校园登录、Ninja/API/订阅、必要连通性检测加入 allowlist，列表更新后再次验证。DNS 屏蔽不能可靠过滤同域视频广告，DoH 客户端也不因这个方案自动受控。

## 适度性能验收

使用本目录 `router-snapshot.sh`，每个短窗之前与之后各取一次；计算 CPU/softirq、WAN 字节、Wi-Fi station 和 survey 的增量。累计 tx retries/failed 不直接除累计 packets 宣称短窗丢包率，survey busy/time 必须同窗求差。

| 样本 | 执行位置与范围 | 说明 |
| --- | --- | --- |
| 空闲延迟 | 现有 Windows：到路由器 LAN IP 20 次 ping；到当前校园网关与一处已确认稳定公网 IP 各 20 次 | 公网 ICMP 被限速会误导；校园网关/公共 DNS不等同真实应用服务器。 |
| 满载延迟 | 一次现有下载或经过明确同服务的 2～4 并发下载，约 15～30 秒；同时重复上述 ping | 总流量先限在约 100～200 MiB，避免无目的长下载。没有可复用可靠服务器就报告未验，不能把随机镜像吞吐当校园上限。 |
| CPU 与内存 | /proc/stat 前后，softirq 每核增量、各服务 VmRSS、MemAvailable、OOM 日志 | 一核 softirq 饱和且其余核空闲可支持 packet steering 试验；mihomo/UA3F 自身热点需另判。空闲负载不能证明满载上限。 |
| Wi-Fi | 固定现有 PC/位置，记录 station HE宽度/MCS/NSS/RSSI、短窗重试与 busy；到路由器延迟 | 调 HE160/信道后重新读回，保留 CAC/DFS 或掉线记录；不把 PHY速率当有效吞吐。 |
| 功能完整 | 查询广告样本/allowlist、认证恢复、直连与指定代理分别请求；UA3F改写实际命中 | 速度增加同时导致改写漏包、认证异常、代理回环或内存崩溃不算通过。 |

### 无需另一台机器的 Wi-Fi 局域网轻量方法

当前 Windows PC 本身可作接收端，路由器用已有 uhttpd（先看 `uhttpd -h`）在 **LAN IP:18080** 临时提供 RAM 文件；不用安装 iperf/大型基准，不改现有 80/443 管理服务。确认空闲 MemAvailable 足够后生成 `/tmp/ax6000-local-test/ax6000-test.bin`，大小 32 MiB，从已有 Wi-Fi PC 用 curl GET 到 NUL，最多 3 次，记录 speed_download、time_total 与 size_download。实际临时 httpd 命令与清理由主代理单一负责人执行，不能自动对 WAN 全地址监听。

```sh
# 路由器，先检查目录不存在或确认归属，准备临时已知文件：
mkdir -p /tmp/ax6000-local-test
dd if=/dev/zero of=/tmp/ax6000-local-test/ax6000-test.bin bs=1M count=32
# 核对本机 uhttpd 帮助后，可使用独立前台进程；LAN_IP用实际IP。
uhttpd -f -p LAN_IP:18080 -h /tmp/ax6000-local-test
```

```powershell
# 现有 Windows，LAN_IP 用实际 IP；不写本地磁盘数据。
& curl.exe --noproxy '*' --max-time 15 --output NUL --write-out 'bytes=%{size_download} seconds=%{time_total} bytes_per_second=%{speed_download}\n' 'http://LAN_IP:18080/ax6000-test.bin'
```

这是路由器本机 socket→Wi-Fi PC 的局域网路径，能避开校园限速，为空口性能提供短样本；它没有经过 WAN NAT/代理，不证明完整校园转发吞吐。uhttpd 单核性能、短样本/TCP启动也会成为瓶颈，所以用来排查明显受限，不据一次峰值声称无线极限。既有设备若没有 uhttpd 可启动方法，不为此修改系统服务或安装工具。测试后终止自己的临时进程，核对已停监听，再删除自己的临时测试目录；不使用 killall 影响管理服务。

## 一手来源

- [官方 snapshot SmartDNS APK](https://downloads.openwrt.org/snapshots/packages/aarch64_cortex-a53/packages/smartdns-46.1-r1.apk)
- [固定 OpenWrt feed Makefile](https://github.com/openwrt/packages/blob/6fb711fed018a04030ffae4976030b7079c9a489/net/smartdns/Makefile)
- [SmartDNS Release46.1 默认 OpenWrt init](https://github.com/pymumu/smartdns/blob/Release46.1/package/openwrt/files/etc/init.d/smartdns)
- [SmartDNS Release46.1 配置样例](https://github.com/pymumu/smartdns/blob/Release46.1/etc/smartdns/smartdns.conf)
- [SmartDNS Release46.1 CLI实现](https://github.com/pymumu/smartdns/blob/Release46.1/src/smartdns.c)
- [SmartDNS 官方速度模式说明](https://pymumu.github.io/smartdns/config/check-speed-mode/)
- [SmartDNS Release48.4 官方发布](https://github.com/pymumu/smartdns/releases/tag/Release48.4)
- [Mihomo 官方 DNS 说明](https://wiki.metacubex.one/config/dns/)
- [固定 adblock-fast 默认配置](https://github.com/openwrt/packages/blob/6fb711fed018a04030ffae4976030b7079c9a489/net/adblock-fast/files/etc/config/adblock-fast)
- [BusyBox nslookup 大版本实现](https://github.com/mirror/busybox/blob/master/networking/nslookup.c)

模板依据46.1官方源码整理。三个 shell 文件已通过本机 Git Bash 的 `bash -n` 语法检查，配置及脚本保持 UTF-8/LF；这不是目标 BusyBox/SmartDNS 运行验证。真实安装、监听、查询A/B、路径和性能结果由主代理记录后再决定保留。
