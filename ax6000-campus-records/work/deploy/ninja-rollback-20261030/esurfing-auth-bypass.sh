#!/bin/sh
# 校园网认证旁路（esauth1..esauth4 组）。
#
# 认证进程 /usr/bin/esurfingclient 以 esauthN 组运行（procd_set_param group）。
# 认证报文必须原样到达网关，不能被重定向、改 TTL 或改写 UA，因此按源组在三个
# 链的最前面放 return：
#   dstnat          — 关掉 DNS 劫持（TCP/UDP 53 → :53）与 TCP 透明代理
#   openclash_mangle— 关掉 UDP TPROXY
#   ua3f_wan_ttl    — 关掉出网 TTL 改写（保留真实 TTL）
# 只读判断后插入，可重复执行。
#
# 时序：OpenClash 的 set_firewall 在末尾调用本脚本，但 mangle 链可能稍后才建，
# 所以对缺失的链做有限等待（默认 20 次 × 1s）。
#
# 调用点：
#   /etc/openclash/custom/openclash_custom_firewall_rules.sh（启动/重启/firewall reload）
#   /usr/share/openclash/openclash-bootguard.sh（开机代理就绪后）

MARK="esurfing-auth-direct-20261030"
GROUPS="{ 65201, 65202, 65203, 65204 }"
WAIT=${1:-20}

have_chain() { nft list chain inet fw4 "$1" >/dev/null 2>&1; }
has_rule() { nft list chain inet fw4 "$1" 2>/dev/null | grep -Fq "$MARK"; }

add_rule() {
	chain="$1"
	i=0
	while [ "$i" -lt "$WAIT" ]; do
		have_chain "$chain" || { i=$((i + 1)); sleep 1; continue; }
		has_rule "$chain" && return 0
		if nft insert rule inet fw4 "$chain" meta skgid "$GROUPS" counter return comment "\"$MARK\"" 2>/dev/null; then
			logger -t ninja-auth-bypass "installed in $chain" 2>/dev/null || true
			return 0
		fi
		i=$((i + 1)); sleep 1
	done
	logger -t ninja-auth-bypass "chain $chain unavailable, skipped" 2>/dev/null || true
	return 1
}

add_rule dstnat
add_rule openclash_mangle
add_rule ua3f_wan_ttl
exit 0
