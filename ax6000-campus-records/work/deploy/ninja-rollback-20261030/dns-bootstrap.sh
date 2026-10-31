#!/bin/sh
# 开机 DNS 引导（S94，先于 esurfingclient S95 与 openclash S99）。
# 问题：dnsmasq(S19) 启动时读到的持久配置是 server=127.0.0.1#7874，
# 但 clash 要到 S99 才起；认证在 S95 用系统解析器查域名会全部失败，导致拨号失败。
# 处理：clash 未运行时，把 dnsmasq 上游恢复为 OpenClash 保存的真实上游。
# OpenClash 启动后会自行把重定向加回去。

LOG=/tmp/openclash-bootguard.log
log() { echo "$(date '+%F %T') $*" >> "$LOG"; }

# clash 已经在跑就不动（例如热重启本脚本）
if [ -n "$(pidof clash)" ]; then
	log "dns-bootstrap: clash running, skip"
	exit 0
fi

cur=$(uci -q get dhcp.@dnsmasq[0].server)
case "$cur" in
	*127.0.0.1#7874*|*127.0.0.1#*) ;;
	*) log "dns-bootstrap: no openclash redirect in dnsmasq, skip"; exit 0 ;;
esac

saved=$(uci -q get openclash.config.dnsmasq_server)
[ -z "$saved" ] && saved="223.5.5.5 119.29.29.29"

uci -q delete dhcp.@dnsmasq[0].server
for s in $saved; do
	uci -q add_list dhcp.@dnsmasq[0].server="$s"
done
uci -q commit dhcp
/etc/init.d/dnsmasq restart >/dev/null 2>&1
log "dns-bootstrap: dnsmasq upstream -> $saved (clash not running yet)"

# 等待解析可用，最多 30 秒，避免认证抢跑
t=0
while [ "$t" -lt 30 ]; do
	nslookup connect.rom.miui.com 127.0.0.1 >/dev/null 2>&1 && break
	sleep 2
	t=$((t + 2))
done
log "dns-bootstrap: resolve check after ${t}s"
exit 0
