# 代理迁移与路由器清理记录

日期：2026-10-27（UTC+8）。设备：Redmi AX6000 / OpenWrt SNAPSHOT `r37185-f29dfe25ba` / Linux `6.18.55`。本机：NixOS 26.11，x86_64。

## 结论

- 路由器不再运行 OpenClash、Ninja Connector、UA3F 或 smartdns。相关包、核心、配置、LuCI 入口、防火墙 include 与 `local-health-recovery` 已删除。
- 本机运行 Ninja `ab32ad2d`（linux-amd64），混合端口 `127.0.0.1:7890`，控制 API `127.0.0.1:9090`，固定 `香港 02（专线；智能）`。
- `ninja-proxy` 是 systemd 用户服务，已 enable；`Linger=yes`，`Restart=always`，开机即启动，不依赖手动登录后再开。
- Firefox 默认 profile 已写入 `user.js` 手动代理；无头实例访问 `ipinfo.io` 的请求在 Ninja 日志中匹配 `香港 02`。
- 路由器 overlay 从 48.3 MB / 61.6 MB（83%）降到 8.9 MB / 61.6 MB（15%），可用 49.5 MB。
- 四路认证、四条 WAN、四出口 HTTP 204、TTL64、dnsmasq 与 adblock-fast 保持运行。`auth#4` 在 21:08:29 出现一次心跳响应超时，21:12:40 起恢复，21:33:33 仍在正常心跳；单次超时不写成长期稳定结论。

## 路由器清理

卸载的显式包：

```text
luci-app-ninjaconnector2 luci-app-openclash ua3f smartdns
ruby ruby-yaml unzip kmod-nft-tproxy kmod-inet-diag
```

`apk del` 同时清理了 openclash/UA3F 的依赖，包括 `kmod-tun`、`ipset`、`iptables-nft`、`iptables-mod-*`、`kmod-ipt-*`、`xtables-nft` 等，共 45 个包。`librt` 与 `libpthread` 在卸载前加入 world，避免被自动移除；`libxtables12` 因 `tc-full` 依赖保留。

手工清理的残留：

- `/etc/openclash`（21.5 MB）、`/usr/share/openclash`（14.6 MB）、`/usr/share/ninjaconnector2`
- `/usr/bin/ua3f`（15.6 MB，随包删除）
- `/etc/config/openclash`、`/etc/config/ninjaconnector2`、`/etc/config/ua3f`、`/etc/config/smartdns`
- `/etc/init.d/openclash`、`/etc/init.d/ninja-trial`、`/etc/init.d/smartdns-cdn`、`/etc/init.d/smartdns-daily`
- `/etc/init.d/local-health-recovery`、`/usr/libexec/local-health-recovery`
- `/lib/upgrade/keep.d/luci-app-openclash`
- `/etc/smartdns`（5.1 MB，包含手工放置的 smartdns 48.4 与两个仍监听的测试实例；进程 5303/5304 已停止）
- `/etc/config/firewall` 的 `openclash` include；`fw4 reload` 后无引用错误
- LuCI 的 OpenClash／Connector controller、view、ACL、ucitrack 与索引缓存

保留：

- `/etc/nftables.d/90-ua3f-wan-ttl.nft`，四出口 TTL64 规则继续由 fw4 加载，链名仍为 `ua3f_wan_ttl`。
- `/etc/esurfing-deploy`、`/etc/esurfing-recovery` 与四路认证配置；后者是历史备份，不属于运行软件。
- `/etc/config/mwan3` 中的 `ua3f_bal` 策略作为配置残留保留，当前没有 UA3F 使用。
- `tc-full`、`kmod-sched-core`、CAKE/BBR 相关包；`codex-cake` 仍为 disabled，未加载 cake qdisc。

清理后 `apk list --installed` 为 194 个包；没有 OpenClash/Ninja/UA3F/smartdns/Ruby/iptables 包。`libxtables12` 是 `tc-full` 依赖，保留。

## 本机代理

| 项目 | 路径或值 |
| --- | --- |
| 核心 | `/home/shizuku/.local/lib/ninja/ninja` |
| 版本 | `Mihomo Meta ab32ad2d linux amd64 with go1.26.2` |
| 配置 | `/home/shizuku/.config/ninja/config.yaml`（0600） |
| 订阅 URL | `/home/shizuku/.config/ninja/sub.url`（0600，不进入仓库） |
| GeoIP | `/home/shizuku/.config/ninja/Country.mmdb` |
| 服务 | `/home/shizuku/.config/systemd/user/ninja-proxy.service` |
| 端口 | `127.0.0.1:7890`；控制 API `127.0.0.1:9090` |
| 自启 | `systemctl --user enable ninja-proxy`；`loginctl enable-linger shizuku` |
| 更新 | `~/.local/bin/ninja-update sub|core|status`；`upctl update ninja` |
| 环境变量 | `/home/shizuku/.config/environment.d/90-ninja-proxy.conf` |

订阅刷新使用固定 UA `clash-ninja/v2.4.0`；候选配置先通过 `ninja -t`，再原子替换并重启。核心升级按 GitHub release 的 SHA256 校验，失败自动回滚。当前订阅 49 个 `ninja` 节点，配置含 `#!PASS-INFO` 授权段。

开机自启采用用户服务 + linger，不新增 root 服务；服务退出后由 `Restart=always` 在 3 秒后重启。路由器不再保存订阅 token，也不再运行代理核心。

## 浏览器

Firefox 默认 profile 为 `krou8ptl.default`，已新增 `user.js`：

```javascript
user_pref("network.proxy.type", 1);
user_pref("network.proxy.http", "127.0.0.1");
user_pref("network.proxy.http_port", 7890);
user_pref("network.proxy.ssl", "127.0.0.1");
user_pref("network.proxy.ssl_port", 7890);
user_pref("network.proxy.share_proxy_settings", true);
user_pref("network.proxy.no_proxies_on", "localhost, 127.0.0.1, ::1, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, .lan, .local");
user_pref("network.proxy.allow_hijacking_localhost", false);
user_pref("network.proxy.failover_direct", false);
```

Firefox 正在运行时不会立即读取 `user.js`，需要完整退出并重开。验证使用独立临时 profile 的无头实例访问 `https://ipinfo.io/json`；Ninja 日志出现：

```text
[TCP] 127.0.0.1:39790 --> ipinfo.io:443 match Match using 🐟 漏网之鱼[香港 02（专线；智能）]
```

Playwright 的 Chromium/Firefox 缓存不在此次浏览器配置范围内；它们由测试工具自行启动，未改动。

## 验证摘要

| 检查 | 结果 |
| --- | --- |
| overlay | 8.9 MB / 61.6 MB，15%，可用 49.5 MB |
| 路由器进程 | 无 OpenClash/UA3F/smartdns/Ninja/clash |
| 路由器监听 | 无 1080/6053/7890/9090 |
| 四路认证 | PID 12275~12278 运行；auth#4 21:08 一次心跳超时后已恢复 |
| MWAN | wan/wan2/wan3/wan4 全部 online |
| TTL | 4 条 `ip ttl set 64` 规则 |
| DNS | `nslookup www.baidu.com 127.0.0.1` 有答案 |
| LuCI | HTTP 200 |
| 本机服务 | `ninja-proxy` active/enabled，linger=yes，Restart=always |
| 本机代理 | Google 204、GitHub 200、香港出口 `188.253.112.163` |
| 代理吞吐 | Cloudflare 20 MiB 约 22.5 MB/s（同目标直连约 1.1 MB/s） |
| Firefox | 无头实例 `ipinfo.io` 匹配香港 02 |

原始清理前后清单见 [router-before.txt](router-before.txt) 与 [router-after.txt](router-after.txt)。

## 边界

- 未做路由器整机重启或四路冷启动；`Linger=yes` 与 enable 已读回，但没有用一次真实重启验证开机自动连接。
- 未重做四路同条件聚合；历史三路 921.67 Mbps 只能作为三路批次结果。
- 未验证 Windows、Android 或其它终端的代理切换；Firefox 之外的浏览器未配置。
- `ua3f_bal` 策略与历史 `/etc/esurfing-recovery` 备份仍在路由器上，属于配置残留或记录，不是运行软件。
- 本机配置和订阅 URL 含敏感信息，保持 0600；仓库只记录路径、版本、测试结果与清理清单。
