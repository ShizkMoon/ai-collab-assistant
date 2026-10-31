#!/bin/sh
# OpenClash 启动守卫：开机后等待核心与 WAN 就绪，必要时有限次重启。
# 只处理“启动时序未就绪”，不覆盖人为停用；看门狗把 enable 置 0 时不介入。
# 日志只写 /tmp（内存），不落闪存。

LOG=/tmp/openclash-bootguard.log
MARK=/tmp/openclash-bootguard.wanted
MAX_RESTART=2
RESTARTED=0

log() { echo "$(date '+%F %T') $*" >> "$LOG"; }

enabled() { [ "$(uci -q get openclash.config.enable 2>/dev/null)" = "1" ]; }

# 本次开机是否由用户配置要求启动（S98 预检写入）。
# enable 被 start_fail 或看门狗改成 0 时，用它区分“启动失败”和“用户停用”。
wanted() { [ -f "$MARK" ] || enabled; }

# BusyBox nc 不支持 -z，用 netstat 判断监听
listening() { netstat -lnt 2>/dev/null | grep -q ":$1 "; }

wait_core() {
	t=0
	while [ "$t" -lt "$1" ]; do
		[ -n "$(pidof clash)" ] && listening 7890 && return 0
		sleep 2
		t=$((t + 2))
	done
	return 1
}

wait_dns() {
	t=0
	while [ "$t" -lt "$1" ]; do
		listening 7874 && return 0
		sleep 2
		t=$((t + 2))
	done
	return 1
}

wait_wan() {
	t=0
	while [ "$t" -lt "$1" ]; do
		ip route show default 2>/dev/null | grep -q '^default' && return 0
		sleep 3
		t=$((t + 3))
	done
	return 1
}

# OpenClash 在 mixed-port 上启用了认证，必须带 --proxy-user；
# 注意 curl 的 -u 是源站认证，不是代理认证。
proxy_ok() {
	u=$(uci -q get openclash.@authentication[0].username 2>/dev/null)
	p=$(uci -q get openclash.@authentication[0].password 2>/dev/null)
	if [ "$(uci -q get openclash.@authentication[0].enabled 2>/dev/null)" = "1" ] && [ -n "$u" ]; then
		code=$(curl -s --max-time 10 --proxy-user "$u:$p" -o /dev/null -w '%{http_code}' \
			--proxy http://127.0.0.1:7890 https://www.gstatic.com/generate_204 2>/dev/null)
	else
		code=$(curl -s --max-time 10 -o /dev/null -w '%{http_code}' \
			--proxy http://127.0.0.1:7890 https://www.gstatic.com/generate_204 2>/dev/null)
	fi
	[ "$code" = "204" ]
}

restart_core() {
	[ "$RESTARTED" -ge "$MAX_RESTART" ] && return 1
	wanted || return 1
	RESTARTED=$((RESTARTED + 1))
	log "restart openclash (#$RESTARTED)"
	uci -q set openclash.config.enable=1
	uci -q commit openclash
	/etc/init.d/openclash restart >/dev/null 2>&1
	return 0
}

sleep 5
wanted || { log "disabled by config, exit"; exit 0; }
enabled || log "enable=0 after boot (start_fail or watchdog), still guarding this boot"
log "guard start"

# 1) 核心与 DNS 端口
if ! wait_core 120; then
	log "core not ready after 120s (pid=$(pidof clash))"
	if ! restart_core; then
		log "restart budget exhausted, exit"
		exit 1
	fi
	wait_core 90 || { log "core still not ready, exit"; exit 1; }
fi
wait_dns 30 || log "dns port 7874 not listening"

# 认证旁路：mangle 链可能晚于 set_firewall 建立，这里再补一次（脚本自带有限等待）。
if [ -x /usr/share/ninjaconnector2/esurfing-auth-bypass.sh ]; then
	/usr/share/ninjaconnector2/esurfing-auth-bypass.sh 30
	log "auth bypass ensured"
fi

# 2) 等 WAN（认证在 S95，OpenClash 在 S99，两者可能仍在拨号）
if ! wait_wan 240; then
	log "no default route after 240s"
	exit 1
fi
log "wan ready"

# 3) 等认证进程起来再自检，避免账号尚未上线时的瞬时失败
t=0
while [ "$t" -lt 90 ]; do
	[ "$(ps w | grep -c '[e]surfingclient')" -ge 1 ] && break
	sleep 3
	t=$((t + 3))
done
sleep 10

# 4) 代理出口自检：连续 2 次失败才重启，避免单次抖动触发
fails=0
i=0
while [ "$i" -lt 8 ]; do
	if proxy_ok; then
		log "proxy path ok"
		exit 0
	fi
	fails=$((fails + 1))
	log "proxy check failed ($fails)"
	[ "$fails" -ge 2 ] && break
	sleep 15
	i=$((i + 1))
done

if restart_core; then
	wait_core 90
	sleep 15
	if proxy_ok; then
		log "proxy path ok after restart"
		exit 0
	fi
fi
log "proxy path still failing, leave running for watchdog"
exit 1
