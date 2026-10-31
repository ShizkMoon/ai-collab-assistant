# 无线 PC 固定目标经过 Ninja 的源码判断

这轮 numeric SOCKS 请求经过 Ninja 后仍可能向 UA3F 发出域名请求。`redir-host` 预处理回填 `Host`；SOCKS5 出站只要 `Host` 非空，就发送域名类型地址。API 同时显示原始 `destinationIP` 与回填域名，不能证明 UA3F 的实际外层连接保持固定目标。

本文只核对候选配置及其源码依据。当前子代理没有操作生产设备、认证、共享配置或测速进程。主代理负责部署、恢复和运行验收。

## 版本与阅读范围

Ninja 发布标签 `ab32ad2d` 的发布说明声明同步 Mihomo 提交 `5019cc090ed7cafb76643f964a76b1e97aee2985`。本次通过 GitHub API 读取该提交的 `tunnel/tunnel.go`、`constant/metadata.go`、`adapter/outbound/socks5.go`、`adapter/outbound/util.go`、`adapter/outbound/base.go`、`config/config.go` 和相关 resolver 文件。下载副本保存在同目录 `source/`。

Ninja 标签的公开 Git 树只有 `README.md`，没有可逐行核对的核心源码。因此以下机制是声明同步的上游源码结论，不能当作私有改动完全一致的证明。Ninja 运行结果仍需验证。

来源：[Ninja 发布记录](https://github.com/kachetong1314/mihomo-ninja/releases/tag/ab32ad2d)、[固定版本上游源码](https://github.com/MetaCubeX/mihomo/tree/5019cc090ed7cafb76643f964a76b1e97aee2985)。

## 地址变化的完整路径

| 步骤 | 固定版本位置 | 行为与影响 |
| --- | --- | --- |
| numeric IP 输入整理 | `tunnel/tunnel.go:275` | `fixMetadata()` 把字符串 IP 转入 `DstIP` 并清空 `Host`。 |
| redir-host 回查 | `tunnel/tunnel.go:285` | 只要映射开启、`Host` 为空且 `DstIP` 有效，就调用 `FindHostByIP()`；找到域名后设置 `Host` 与 `DNSMapping`。真实 IP 不会被清空。 |
| 调用顺序 | `tunnel/tunnel.go:520` | `preHandleMetadata()` 先于 `527` 行的 sniffer 开关。仅停用嗅探不能阻止这一回填。 |
| SOCKS 地址类型 | `constant/metadata.go:255` | `AddrType()` 在 `Host` 非空时返回域名类型，即使 `DstIP` 仍有效。 |
| SOCKS 地址序列化 | `adapter/outbound/util.go:15` | 域名类型直接发送 `metadata.Host`；IP 类型才发送 `DstIP`。 |
| 发往 UA3F | `adapter/outbound/socks5.go:64` | TCP `StreamConnContext()` 把上述序列化地址放进 SOCKS5 CONNECT 请求。该路径没有先调用 `metadata.Pure()`。 |

`config/config.go:588` 的默认 `Sniffer.Enable` 是 `false`。即使运行 YAML 没有 sniffer 段，地址回填也有独立路径。`BasicOption` 的 `ip-version`、`interface-name` 与 `dialer-proxy` 不会让上述域名序列化自动变成固定目的 IP；在这些字段上试改不能替代实际地址验证。

源码链接：[回填及拨号路径](https://github.com/MetaCubeX/mihomo/blob/5019cc090ed7cafb76643f964a76b1e97aee2985/tunnel/tunnel.go#L275-L315)、[拨号时 hosts 处理](https://github.com/MetaCubeX/mihomo/blob/5019cc090ed7cafb76643f964a76b1e97aee2985/tunnel/tunnel.go#L560-L577)、[Metadata 的地址类型与 Pure](https://github.com/MetaCubeX/mihomo/blob/5019cc090ed7cafb76643f964a76b1e97aee2985/constant/metadata.go#L255-L288)、[SOCKS 序列化](https://github.com/MetaCubeX/mihomo/blob/5019cc090ed7cafb76643f964a76b1e97aee2985/adapter/outbound/util.go#L15-L33)。

## 最小诊断候选

把下面的一项合并进现有 top-level `hosts`。保持已有条目，不创建第二个同名 YAML 段。

```yaml
hosts:
  dl.delivery.mp.microsoft.com: 171.108.211.12
```

此片段只固定本轮用于比较的微软 CDN 域名，不能泛化为其他下载、游戏或长期最优 CDN 选择。候选的目的，是先让无线 PC 经 Ninja → UA3F 的测量与路由器成功测量使用相同目标，再判断路径成本。

其源码依据是 `tunnel/tunnel.go:560`：规则匹配结束后，若 `DefaultHosts.Search(metadata.Host, false)` 找到有效 IP，就设置 `DstIP` 与 `DNSHosts`，然后调用 `Pure()`。`constant/metadata.go:280` 在 `DNSMapping` 或 `DNSHosts` 且 IP 有效时复制元数据并清空拨号副本的 `Host`。此前规则匹配使用的域名仍可保留，真正发给 UA3F 的 SOCKS 地址按 IP 类型序列化。

`config/config.go:1135` 独立解析 top-level `hosts`；`tunnel` 查的是 `resolver.DefaultHosts`。`dns.use-hosts` 是 DNS 响应端的字段，不能据此推断 top-level hosts 的拨号处理被停用或已生效。

此候选保留原来的规则、UA3F TCP 包装、UA 改写和 TTL 路径。它不会减少 TCP 代理层，也不构成无线 PC 达到 900 Mbps 的保证。

## 主代理部署后的验收

1. 先保留候选前的精确原值和恢复入口。确认运行配置里只有目标域名这一项新增或改值，并且现有 hosts 条目、认证、DNS、规则和代理链没有意外变化。通过生产二进制配置检查后加载。
2. 用原来的 numeric SOCKS 请求、固定源端口和同一 HTTP Host，先执行低速小范围读回。确认完整响应字节、目标范围与所有请求成功。
3. 同时读取 UA3F 进程持有的 socket inode 与 `/proc/net/tcp`，再结合 conntrack reply 目标验证。实际 ESTABLISHED outer socket 必须全部到 `171.108.211.12:80`；API 的 `destinationIP`、HTTP Host 或本地代理地址不能代替这一条件。
4. 只有固定目标和完整字节验收通过后，才在相同目标、范围、并发和限速状态下比较吞吐。记录无线关联、CAKE 状态、代理链、CPU 与 softirq，避免把目标变化当作加速。
5. 若目标仍改拨、任一请求缺字节、原有代理健康失败或新 DNS 错误出现，恢复这一个 hosts 原值。服务加载成功和 YAML 解析成功均不能代替运行验收。

本轮路由器 UA3F numeric SOCKS 接近 900 Mbps 的旧结果，只说明那个短测窗口里的路由器代理路径具有该吞吐能力。候选部署成功也只补足相同目标前提；无线 PC 的瓶颈及可持续速度仍由实际测试决定。