# Ninja 回滚到路由器记录

日期：2026-10-30（UTC+8）。设备：Redmi AX6000 / OpenWrt SNAPSHOT `r37185-f29dfe25ba` / Linux `6.18.55`。按用户要求**未重启路由器**，因此本次没有冷启动验证。

## 结论

- OpenClash `0.48.002`、Ninja Connector 2 `1.1.0-r4`、官方 ARM64 UPX 核心 `ab32ad2d` 已装回路由器并在运行。
- 运行核心 `/etc/openclash/core/clash_meta`，SHA256 `3398a44cca5db17710491ec3bb474c3c1cd4a30a3f849eb063dcfd2abd35375b`，`-v` 输出 `Mihomo Meta ab32ad2d linux arm64`。
- LAN 透明代理已生效：本机（`192.168.31.171`）不设代理访问 `ipinfo.io` 出口为 `188.253.112.163`（HK），GitHub／百度均 200。
- 四路认证进程、四条 WAN、四出口 TTL64 规则全部保持；`mwan3 status` 四路 online。
- 开机自启已设：`/etc/init.d/openclash enabled`。**未做整机重启实测**。

## 安装内容

| 项 | 版本／摘要 |
| --- | --- |
| luci-app-openclash | `0.48.002`，APK SHA256 `f7ebbd43…c0b155b` |
| luci-app-ninjaconnector2 | `1.1.0-r4`，APK SHA256 `2783d1fa…cfc5292` |
| 核心 ninja-arm64-upx | `ab32ad2d`，SHA256 `3398a44c…d35375b`（与官方 asset digest 一致） |
| 新增内核模块 | `kmod-nft-tproxy`、`kmod-inet-diag`、`kmod-tun`（6.18.55-r1） |
| 新增依赖 | ruby 4.0.7 系列、libyaml、unzip 等 |

安装顺序：`apk update` → kmod → 本地 APK（`--allow-untrusted`，仅限已核 SHA 的三份文件）→ 核心已在包内落位 `/etc/openclash/core/clash_meta`，复核 SHA 后启动。安装前备份 `/etc/config/{network,firewall,dhcp,mwan3,uhttpd}`、`/etc/apk/world`、`/etc/init.d` 到 `/root/pre-ninja-rollback-20261030/`。

## 启动前修正

路由器已卸载 UA3F 与 smartdns，旧生产选项文件仍引用它们的端口：

- `enable_ua3f_tcp: true` → `false`（`UA3FLocal` socks5 `127.0.0.1:1080` 已不存在，overwrite 会注入到 `🎯 全球直连` 的 TCP 包装）。
- `dns_nameserver_policy` / `dns_overrides` 中 780 处 `127.0.0.1:6054`、`127.0.0.1:6055`（smartdns 已卸载）→ 国内 `223.5.5.5`、代理侧 `119.29.29.29`。

改前副本：`/etc/openclash/custom/ninja-production-options.yaml.bak.pre-rollback-20261030`。

启动输出：`Ninja overwrite: UA3F TCP=false; TCP wrappers=0; proxies=50; groups=14; rules=3505`。

## 防覆写

- `/usr/share/openclash/openclash_core.sh` 换成失败退出脚本，阻止 OpenClash 自动下载公版核心。
- `/usr/share/ninjaconnector2/ninja_kernel.sh` 换成入口守卫：`detect_arch`／`core_version`／`core_path` 转发给 `ninja_kernel.vendor.sh`，`install` 直接返回 `ERR:CORE_INSTALL_BLOCKED`。
- 原脚本备份：`/usr/share/ninjaconnector2/ninja_kernel.vendor.sh`（SHA256 `670c41df…3db`）、`/root/pre-ninja-rollback-20261030/openclash_core.sh.vendor`（SHA256 `66d7130b…189`）。
- 插件升级会覆盖这些包管理文件；升级后须重装守卫并复核核心 SHA。

## 验收摘要

| 检查 | 结果 |
| --- | --- |
| OpenClash 服务 | `OpenClash Start Successful!`；clash PID 运行，watchdog 在跑 |
| 核心 SHA | `3398a44c…d35375b`，与安装前一致 |
| DNS | `nslookup www.baidu.com 127.0.0.1` 有答案；dnsmasq `server=127.0.0.1#7874` |
| LAN 透明代理 | 本机 `gstatic 204`，`ipinfo.io` 出口 `188.253.112.163` HK |
| 直连对照 | 路由器自身 `--noproxy` 出口 `14.211.18.211` |
| 四路认证 | 4 个 `esurfingclient` 进程，心跳持续 |
| MWAN | wan／wan2／wan3／wan4 全部 online |
| TTL | 4 条 `ip ttl set 64` 规则 |
| LuCI | `200` |
| overlay | 42.7 MB / 61.6 MB，73%，可用 15.7 MB |
| 内存 | `MemAvailable` 约 167 MiB（clash 常驻约 1.3 GB VSZ） |

## 边界

- 未重启：冷启动后 OpenClash、认证、MWAN、TTL 的启动顺序未验证；`enabled` 只是配置读回。
- 未重测吞吐。历史同路径上限（PC 8／16／32 路 479.57／557.61／574.07 Mbps，CPU 50.5%／58.1%／70.0%）仍应视为本配置的量级参考，未经本次复测。
- `/etc/openclash` 下的生产配置（63 节点订阅、`#!PASS-INFO`、`ninja-subscription-update.rb` 等）在本次安装窗口内出现；安装包本身不含这些文件，恢复来源未独立查明（同期有另一会话在操作路由器）。配置内容未作改动，只改了上述两处已失效端口与开关。
- 本机 Ninja（`127.0.0.1:7890`）保持运行；本次未关闭，也未验证两者同时存在时的出口差异。
