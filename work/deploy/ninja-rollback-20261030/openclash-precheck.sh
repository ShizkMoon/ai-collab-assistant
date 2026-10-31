#!/bin/sh
# 开机预检（S98，先于 openclash 的 S99）：记录用户是否要求开机启动，并等 WAN 就绪。
# 目的：避免核心先于认证/WAN 启动而失败后，start_fail 把 enable 置 0，
# 导致后置守卫分不清“启动失败”和“用户手动停用”。
# 日志只写 /tmp（内存）。

LOG=/tmp/openclash-bootguard.log
MARK=/tmp/openclash-bootguard.wanted

log() { echo "$(date '+%F %T') $*" >> "$LOG"; }

if [ "$(uci -q get openclash.config.enable 2>/dev/null)" = "1" ]; then
	echo 1 > "$MARK"
else
	rm -f "$MARK"
	log "precheck: openclash disabled by config, skip"
	exit 0
fi

t=0
while [ "$t" -lt 240 ]; do
	if ip route show default 2>/dev/null | grep -q '^default'; then
		log "precheck: wan ready after ${t}s"
		exit 0
	fi
	sleep 3
	t=$((t + 3))
done
log "precheck: no default route after 240s, continue anyway"
exit 0
