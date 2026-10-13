# 固定 Ninja 核心的 DoH3／DoQ 临时验证方案

本方案供主代理执行；本支线只查公开官方资料和上游源码，没有 SSH、浏览器操作、私有配置读取、设备探测或生产修改。生产国内 DoH 的提交与验收、校园域名对照及第三通道由主代理负责。这里不修改双通道、Ninja 节点协议、生产 DNS 或浏览器全局设置，不安装应用。

目标是回答固定 `ab32ad2d` 二进制是否能沿指定路径完成强制 DoH3 或 DoQ 查询，以及当前浏览器能否实际使用 HTTP/3、ECH。协议可用不等于更快；临时成功不自动授权替换生产 fallback。

## 精确端点与参数

| 测试 | 临时 nameserver 单一值 | 说明 |
| --- | --- | --- |
| DoH3，直连 | `https://cloudflare-dns.com/dns-query#h3=true` | Cloudflare 正式支持 HTTP/3；不指定代理片段，保持 `respect-rules: false`。 |
| DoH3，固定香港组 | `https://cloudflare-dns.com/dns-query#🚀 节点选择&h3=true` | 临时实例中必须实际定义同名组，并只包含原固定香港节点。整串用 YAML 引号。 |
| DoQ，直连 | `quic://unfiltered.adguard-dns.com:853` | AdGuard 官方的无过滤服务；UDP 853，不能照抄旧示例的 784。仅用于实验，不更换生产供应商。 |
| DoQ，固定香港组 | `quic://unfiltered.adguard-dns.com:853#🚀 节点选择` | 同样要求临时实例实际定义固定组和独立节点 bootstrap。 |

**必须写 `#h3=true`，不要裸写 `#h3`，也不要把它写成 URL 的 `?h3=true`。** 固定上游源码将 fragment 以 `&` 分开；有等号的项进入参数表，没有等号的项作为代理／接口名称。DoH 客户端只有在 `params["h3"] == "true"` 时将可用 HTTP 协议列表限定为 HTTP/3。`prefer-h3: true` 仍允许回到 HTTP/2 或 HTTP/1.1，不能用它证明强制协议。

官方依据：[Mihomo DNS 附加参数](https://wiki.metacubex.one/config/dns/)、[Cloudflare DoH 支持](https://developers.cloudflare.com/1.1.1.1/encryption/dns-over-https/)、[AdGuard 正式端点](https://adguard-dns.io/en/public-dns.html)。精确解析与客户端行为依据固定上游提交 `88dcbf7f1614a67c3b36b848ee3592dfa92ada36` 的 [config/config.go](https://github.com/MetaCubeX/mihomo/blob/88dcbf7f1614a67c3b36b848ee3592dfa92ada36/config/config.go)、[dns/doh.go](https://github.com/MetaCubeX/mihomo/blob/88dcbf7f1614a67c3b36b848ee3592dfa92ada36/dns/doh.go)、[dns/doq.go](https://github.com/MetaCubeX/mihomo/blob/88dcbf7f1614a67c3b36b848ee3592dfa92ada36/dns/doq.go)。这些不是当前 fork 的源码证明；必须使用当前固定二进制验收。

## 最小直连配置

每个协议使用新的私有临时工作目录、配置和进程，两个实例顺序执行。`17875` 只是候选端口，主代理先确认没有占用；不要改生产 53／7874，也不让临时实例监听 LAN 或 WAN。以下为公开配置骨架；Ninja 若需要现有授权注释，主代理在设备私有临时文件中保留，不能把注释或私有节点导出到本文件。

```yaml
port: 0
socks-port: 0
mixed-port: 0
redir-port: 0
tproxy-port: 0
allow-lan: false
bind-address: 127.0.0.1
mode: rule
log-level: debug
ipv6: false
external-controller: ''
tun:
  enable: false
profile:
  store-selected: false
  store-fake-ip: false
proxies: []
proxy-groups: []
rules:
  - MATCH,DIRECT
dns:
  enable: true
  listen: 127.0.0.1:17875
  ipv6: false
  enhanced-mode: redir-host
  use-hosts: false
  use-system-hosts: false
  respect-rules: false
  prefer-h3: false
  default-nameserver:
    - 223.5.5.5
    - 119.29.29.29
  nameserver:
    - 'https://cloudflare-dns.com/dns-query#h3=true'
  nameserver-policy: {}
  fallback: []
  fallback-filter:
    geoip: false
  direct-nameserver: []
  proxy-server-nameserver:
    - 223.5.5.5
    - 119.29.29.29
```

DoQ 轮次只把 `nameserver` 中的单一字符串换成 `quic://unfiltered.adguard-dns.com:853`。不把两种协议或其他解析器同时列在 `nameserver`；否则回答可能来自另一条路径。

配置中的 `default-nameserver` 只用于 DoH／DoQ 端点主机名 bootstrap，`proxy-server-nameserver` 只用于节点 bootstrap。允许这些名字的明文查询，**不声称测试期间全部 DNS 都加密**。判断被测 `example.com`／`example.org` 的回答不能来自普通 DNS，需要区分 bootstrap 名字和被测业务名字；不要把独立 bootstrap 改成不可达端点，以免把启动解析失败误判为 QUIC 失败。

不要复制生产 controller、TUN、redirect、rule-provider、订阅更新入口或完整路由规则。无 GeoIP／GeoSite 引用，无自动下载 geodata、provider 或健康测试。临时目录不能沿用生产缓存／选择状态；每轮新进程可确保被测名字没有从旧缓存命中。保留证书校验，不设置 `skip-cert-verify`。

## 固定香港的最小变体

主代理在私有临时配置中只保留原固定节点所需的定义及授权，并定义原同名 select 组且只有该节点；其他代理、测速组、provider 和生产监听移除。保留上面的 `MATCH,DIRECT`，由 DNS URL 的显式组片段选择香港路径；不是依赖业务规则猜测 DNS 出站。

记录当前固定节点名称、临时组唯一成员及被测连接链，但不导出节点地址、账户或密钥。WAN 上可能只能看到代理隧道的外层 TCP／UDP，不能因外层是 TCP 就否定内层 DoH3／DoQ，也不能因看到外层 UDP 就认定内层成功。DIRECT 与香港路径是不同结论，不能相互替代。

## 有界执行与证明条件

1. 主代理先读回生产认证／UA3F PID、核心摘要、53／7874 最低业务探针及可用内存。使用现有固定核心，不解包、升级或替换。临时配置通过 `-t` 后再启动；`-t` 成功仅是解析检查。
2. 临时实例使用独立目录和唯一 PID，最多同时一个；确认只有回环 DNS 端口。只向临时端口发送 `example.com` 和 `example.org` 两个 A 查询，单次等待上限 5 秒；独立外部计时器最多 20 秒结束本轮临时进程，避免核心内部重试无限占用。若超时即记录失败，不等待到生产恢复周期，也不重启服务。
3. 验证 DNS transaction ID、QR、question、rcode 和有效 A／CNAME；若现有探针支持，再查一个已选 ECH 网站的 HTTPS 类型 65。类型 65 采用 EDNS 1232 字节或遇 TC 时 TCP 重试，防止 512 字节截断导致误判；此步骤不需要新增工具。
4. DoH3 需要单一 `#h3=true`、新进程无被测缓存、有效 DNS 响应，以及对应上游的实际 HTTP/3 日志／QUIC 握手证据。核对上游 `using HTTP/3` 成功记录，不把源码日志文字“QUIC was faster”写成性能结论。固定上游在强制 H3 失败时可能先输出 `using HTTP/2` 失败日志，再返回“不支持 H1/H2”错误；看到这一行本身不是 H2 成功，必须看实际请求结果与传输。
5. DoQ 需要单一 `quic://`、新进程、有效 DNS 响应，以及 QUIC／`doq` 协商或明确的该实例连接证据。上游 DoQ 客户端只做 QUIC 重试，没有普通 DNS、DoT 或 H2 回退。若现有日志不暴露协商，应如实区分“强制配置且有效应答”和“另有 ALPN 实测”，不编造后者。
6. 若现有抓包工具可用，只采临时实例相关的少量回环 DNS、bootstrap 53 与目标 UDP 443／853 连接；核对普通 53 中没有被测名字。香港路径以实例日志／连接链为主，普通 WAN 抓包只能看到外层。不要为本次安装 Wireshark、tcpdump 或编译新客户端。
7. 每个协议结束只停止其精确 PID 并读回生产探针与认证／UA3F PID，不使用 `killall`、OpenClash stop/restart、网络重载或整机重启。容量不足、监听异常或任何生产探针退化时停止本轮。

最小为每协议 2 次 A 查询、每次 5 秒上限。第一次 DIRECT 成功不要求再测所有路径；生产外国 DNS 仍固定香港，所以如考虑采用，必须额外核对该香港路径。DIRECT 失败也不能推导核心无实现；可能是校园 UDP 路径、bootstrap、证书、时间或上游问题。任何路径失败均不自动变更生产 fallback。

排除 H2／普通 DNS 回退的证据是组合：单一强制端点、无 fallback／policy／hosts、独立缓存、被测名字没有普通 DNS 外发、正常证书与有效应答、协议证据。单独的 HTTP 200、UDP 回包、配置成功或查询耗时不足。无需为证明这一点修改生产防火墙来阻断 TCP 443。

## 当前浏览器的 HTTP/3／ECH 检查

主代理在已有浏览器中控制新测试标签页，本支线不操作浏览器。保留 PAC、系统代理、Secure DNS、扩展和浏览器全局 flags／策略原值，不导出整个 profile 或全会话 NetLog／HAR。

**HTTP/3：** 先读回该测试 URL 的 PAC 求值与当前访问路径，选择不登录的现有公开小页面。打开 Network 面板后请求页面，显示 Protocol 列；只记录测试主请求的 URL、状态、`h3`、来源与少量计时。若首轮为 H2 且响应发布 Alt-Svc，可在同一标签页仅再请求一次，避免把尚未发现 H3 的首次结果判为不支持。确认响应实际来自网络，不是 memory/disk cache 或 service worker。刷新／面板清空不代表 DNS 或 TLS 冷启动，不据此做性能排名。

PAC 的 DIRECT 是“不使用电脑显式 HTTP 代理”，不代表路由器业务必然 DIRECT；仍应核对透明路由规则。HTTP CONNECT／普通 mixed HTTP 代理不能替代终端 UDP 443 路径。若现有 curl 已编译 HTTP3，可将 `--http3-only` 用作补充而不是 `--http3`，但它不能证明浏览器当前使用 H3，不为此安装另一版 curl。[Edge Network 使用与列显示](https://learn.microsoft.com/en-us/microsoft-edge/devtools/network/reference#add-or-remove-columns)、[curl 的 HTTP3-only 与回退区别](https://curl.se/docs/http3.html)

**ECH：** 先用现有 DNS 探针确认被测域名在实际 LAN DNS 路径取得 HTTPS 记录和 `ech` 参数，再在当前浏览器的新标签页运行 Mozilla 官方列出的检查入口，如 [Cloudflare Browser Check](https://www.cloudflare.com/ssl/encrypted-sni/) 或 [DEfO ECH 检查](https://defo.ie/ech-check.php)。只有页面明确报告当前连接的 ECH 实际使用／服务端接受，才记为成功；页面能打开、TLS 1.3、H3 或捕获到 ECH 扩展都不足，扩展可能只是 GREASE。

若当前浏览器没有实际使用 ECH，记录现有状态，排查 HTTPS 记录、浏览器实现／策略、显式代理与站点支持，不在本轮自动改变全局 DoH、PAC 或注册表。已有浏览器自带 DoH 的结果可能绕过路由器国内 DoH 与过滤；应单独注明实际 resolver，不把浏览器成功等同于路由器 DNS 全链路成功。[Mozilla 的实际 ECH 验证与 GREASE 说明](https://wiki.mozilla.org/Security/Encrypted_Client_Hello)、[Edge 的 ECH 使用条件](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/EncryptedClientHelloEnabled)

ECH 成功只是指定终端、站点和当前路径的隐私特性，不是带宽或校园认证收益，也不隐去目标 IP。若没有无需改变当前设置即可通过的检查，结论为“当前路径未验证／未使用”，不据此新增服务。

## 回传记录

每轮仅保存：核心 SHA／版本、临时配置摘要（私有材料剔除）、端点与强制参数、bootstrap 名称、回环监听、PID、单次查询时间和 DNS 语义、实际协议证据、DIRECT／固定香港路径、生产前后探针与 PID。长调试日志只保留设备私有临时目录中相关片段，公开记录不含节点密钥、订阅 URL、浏览器 Cookie 或用户公网 IP。

本文件只给配方和验收标准，所有运行结果仍待主代理执行。不能用上游源码或官方服务能力替代 `ab32ad2d` 的实际结果。
