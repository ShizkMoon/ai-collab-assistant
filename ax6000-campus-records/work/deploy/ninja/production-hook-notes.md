# 生产 OpenClash 持久覆写：最小方案

当前约束：源订阅 49 个 Ninja 节点、14 个策略组；目标组为 `🎯 全球直连`。只增加 UA3FLocal SOCKS 节点和 TCP 条件规则，不重建源组、不改 Ninja 节点内容。独立 mixed 流量成功是主代理已验；本文件说明仍需在实际透明路径验证的生成方案。

## 文件及执行边界

- production-custom-overwrite.sh → /etc/openclash/custom/openclash_custom_overwrite.sh，0755。若现有 hook 有用户内容，由主代理保留并合并。
- production-overwrite-options.yaml → /etc/openclash/custom/ninja-production-options.yaml，0600。主代理补校园域名、公网 IP 段、SmartDNS 端口与 bootstrap。不得放订阅 URL 或许可注释。
- restore-ninja-license.rb → /etc/openclash/custom/restore-ninja-license.rb，0644。只处理两个私密本地文件，日志只返回错误类。
- production-custom-firewall.sh → 合并到 /etc/openclash/custom/openclash_custom_firewall_rules.sh，0755。仅增加一个受控 ip rule，不改 mwan3/NFT；必须确认候选 priority 100 空闲并早于 mwan3。

本机仅完成 shell -n 和静态源码判断；没有 Ruby 可执行文件，没有 SSH，没有读取 private。主代理需用目标端 Ruby 完成 ruby -c、synthetic/候选配置执行，以及 Ninja -t。

## 转换行为

例如原规则：

```yaml
- DOMAIN-SUFFIX,example.cn,🎯 全球直连
- IP-CIDR,1.0.1.0/24,🎯 全球直连,no-resolve
- MATCH,原代理组
```

生成：

```yaml
- AND,((NETWORK,TCP),(DOMAIN-SUFFIX,example.cn)),UA3FLocal
- DOMAIN-SUFFIX,example.cn,🎯 全球直连
- AND,((NETWORK,TCP),(IP-CIDR,1.0.1.0/24,no-resolve)),UA3FLocal
- IP-CIDR,1.0.1.0/24,🎯 全球直连,no-resolve
- MATCH,原代理组
```

匹配到这些国内规则的 TCP 走 127.0.0.1:1080；UDP 跳过 NETWORK,TCP，继续原策略组。UA3FLocal 的 udp=false 又限制该节点的能力。不能用 udp=false 代替 NETWORK 条件，因为节点无 UDP 时可能继续更晚规则，改变原顺序。其它策略组、阻断规则、MATCH 均保留。

转换只针对 options 指定组的 DOMAIN、DOMAIN-SUFFIX、DOMAIN-KEYWORD、GEOIP,CN 和公网 IP-CIDR/IP-CIDR6；不把组内 DIRECT 选择自动替换，也不转换其它组中的 DIRECT 成员。CIDR 与私网、CGNAT、回环、link-local、多播、保留段或手工校园网段重叠时不转换。前置明确 LAN/校园 DOMAIN 和 CIDR 的 DIRECT，覆盖 broad 国内匹配。IPv6 仍由首次 UCI 关闭，脚本保留原 IPv6 规则但不证明 IPv6 运行验收。

options 的 enable_ua3f_tcp 为显式布尔开关，未填写默认 true。首次 OC 单独验收设 false：hook 删除先前生成的 NETWORK,TCP→UA3FLocal 包装并恢复原策略组匹配，允许保留不被规则使用的 UA3FLocal 节点。无论开关值，每次都先移除本 hook 的包装再按当前开关重建，重复执行不叠加。false 仅取消本地 SOCKS 的 TCP 转换，LAN/校园保护与 DNS 覆写仍生效；不修改源组内选项状态。

原始组的选择状态仍可影响 UDP。例如全球直连组若用户改选了某代理，UDP 按该组当前选择；脚本不强制将其固定为 DIRECT。要承诺 UDP DIRECT，主代理必须实际读回该组选择为 DIRECT；现阶段保留源组行为。

规则逻辑依据上游文档 https://wiki.metacubex.one/config/rules/ 和 https://wiki.metacubex.one/config/proxies/socks/ 。固定到提供方声称同步的上游 5019cc09 时，rules/common/base.go 把内层 no-resolve 作为参数解析，rules/logic/logic.go 支持 AND 与 NETWORK 子匹配；拷贝在本目录。Ninja 私有实现还需真实 -t 及 TCP/UDP 流量确认。

## stock hook 时序与订阅更新

本次源码固定 e553e82e01c697aefbe1555261a503f425e00ccd / OpenClash 0.48.002。start_service 的完整生成顺序：

```text
RAW subscription → config_check → yml_change → yml_rules_change
                  → custom_overwrite(TMP_CONFIG_FILE)
                  → provider path 的 YAML dump
                  → start_run_core: TMP mv CONFIG → procd launch
```

custom_overwrite 在 stock 改写后运行，适合追加本地节点和规则。它修改临时生成文件，不修改原订阅。源订阅更新后再生成，会再次应用持久 hook。

stock 没有 quick_start UCI 键。quickstart 按 /tmp/openclash.change 中原/生成 YAML、/etc/config/openclash 和 custom/* 的 mtime 判断。首次安装 hook/options 后删除该单一生成状态缓存，再重启可强制完整生成；后续 options/hook 或订阅改变会失效。不要删未知配置目录。quickstart 跳过修改流程，但使用先前已完成覆写的 CONFIG_FILE。

stock 不检查 custom_overwrite 的 exit status。本脚本遇到非法字段不写 YAML 并返回失败，但返回值不能独立阻止 stock 启动。因此主代理必须先对私密候选副本执行 hook、Ninja -t，并在启动后读回 UA3FLocal/规则数量/组数/许可证注释布尔值。脚本不写源文件，报错不打印异常 message。

## 许可注释恢复位置

stock YAML.load/dump 丢弃 #!PASS、#!PASS2、#!PASS3-INFO 注释；hook 后的 provider dump 仍会再次丢弃。custom_firewall 在 core 已启动成功后调用，不能用来恢复 core 启动前需要的许可注释。

可恢复的最小 init 变更是在 start_run_core() 中 `mv "$TMP_CONFIG_FILE" "$CONFIG_FILE"` 所在 if 块结束后、`chown root:root "$CLASH"` 前，插入一行：

```sh
ruby /etc/openclash/custom/restore-ninja-license.rb "$RAW_CONFIG_FILE" "$CONFIG_FILE" || { start_fail; return 1; }
```

它同时覆盖完整生成和 quickstart。helper 从 RAW 文件读取许可注释、移除 CONFIG 中旧许可注释、幂等前置最新注释，用同目录 0600 临时文件原子切换，不打印注释内容。主代理先备份原 init，确认匹配点恰为 1，修改后 sh -n。插件更新会覆盖这一行，更新后必须重新核验。

parent 已确认 trial 用普通 YAML dump 后仍可 HTTPS 204，证明当前 trial 流程没有立即依赖该注释；保留许可元数据可保护今后的更新流程，不把此 trial 推广为所有授权格式均可丢注释。

## UCI 选择

以下设置作用于当前已装 OpenClash，保持 enable=0 到候选配置与 UA3F SOCKS 均验证完成：

```text
en_mode=redir-host
operation_mode=redir-host
proxy_mode=rule
router_self_proxy=0
enable_redirect_dns=1
enable_udp_proxy=1
disable_udp_quic=0
china_ip_route=0
china_ip6_route=0
common_ports=0
enable_rule_proxy=0
enable_custom_clash_rules=0
ipv6_enable=0
ipv6_dns=0
small_flash_memory=0
smart_enable=0
core_type=Meta
enable_custom_dns=0
append_wan_dns=0
append_default_dns=0
custom_name_policy=0
enable_respect_rules=0
```

要点：china_ip_route=0 让国内 TCP 到达核心，否则 fw4 先绕过核心，就到不了 UA3FLocal；disable_udp_quic=0 保留源 UDP 路径；common_ports=0 不把透明捕获限制到常见端口。enable_redirect_dns=1 保留 dnsmasq :53：adblock NXDOMAIN 先匹配，然后转发未命中查询到核心 :7874。enable_redirect_dns=2 会直接劫持到核心，绕过此过滤入口。

端口使用当前已核配置，常见候选是 redir 7892、tproxy 7895、mixed 7893、DNS 7874、controller 9090，不能与 trial mixed 进程或 SmartDNS 占用冲突。源节点 bootstrap 必须明确可达，并且不能指向 dnsmasq :53 形成 dnsmasq→OC→dnsmasq 回环。options 空 DNS 字段保留 source；填写后只 merge nameserver-policy，不整段覆盖 source DNS。

关闭路由器自身代理意味着校园认证、UA3F 新建 socket、Ninja 到节点外层连接和本机 DNS 是本机输出流量，需由主代理的 mwan3/output 规则正确分配；它们不会作为 LAN 再次透明进入 OpenClash。UA3F 应仅启用 SOCKS 1080，并关闭其另一个 LAN 透明入口，避免重复处理。

## masked UDP ip rule 与生命周期

stock UDP rule 为 `ip rule add fwmark 0x162 table 0x162`，无 mask、无 pref。mwan3 高 mark 0x3f000000 合并后，0x01000162 等值不能匹配全 32 位 0x162，且 mwan 规则可能更早选择 WAN 表。

production-custom-firewall.sh 在 stock set_firewall() 末尾持久调用，增加候选 `pref 100 fwmark 0x162/0xffff lookup 354`。它不重复添加相同规则，priority 已占用则失败，不删除其它规则。354 是 0x162 十进制。原 full-mark stock rule可留在后面，它不会匹配合并 mark，但不妨碍早期 masked 规则。

stock stop 只删 full-mark rule，不会删 masked 新规则；其 local route 删除后表内无匹配则该规则向下一表继续，不会自行把流量指向 lo。受控回滚时由主代理删除精确规则：`ip -4 rule del pref 100 fwmark 0x162/0xffff lookup 354`。全局 firewall/network 重载也须验证该规则与 local route 的重建时序。

低位 mask 本身不证明组合行为正确：如果后续 mwan 恢复 mark 清掉低 16 位，mask 仍无效；stock input/postrouting 某些规则也用 full mark 0x162，可能受高位影响。主代理需核实际 NFT chain 优先级、mwan restore是否保留低位、TPROXY本地交付和本机外层连接mark。优先避免 LAN TPROXY 流再被 WAN 分类，而不是只修改数字。

## 最小验收

先对私密候选副本执行覆写与许可恢复，Ninja -t 成功；检查仍有原 49 个 Ninja 节点 + 1 个 UA3FLocal、14 个原组、原 MATCH、许可注释存在布尔值，规则映射目标只来自全球直连。重复执行一次应无重复 UA3F 节点/包装规则。然后真实 LAN 透明 TCP 国内经 UA3F、国外经 Ninja、校园/LAN直连、UDP仍按源规则；dnsmasq 广告 NXDOMAIN不触发上游，未命中经OC，校园DNS不泄漏/回环。最后重启与受控订阅更新，再读回并重复最关键流量。不能用本地 mixed 204替代 LAN 透明和UDP验收。
