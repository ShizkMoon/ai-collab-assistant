# 下一轮下载数据路径与并发检查

## 首先测等量小切片队列

保持生产服务、HE160、TTL64、两个认证和 UA3F 不变。对同一微软 HTTP/1.1 源固定同一个 IP，各传完整 1 GiB：A 为 16 × 64 MiB、16 个 worker，B 为 32 × 32 MiB、16 个 worker，再测 A。测试顺序由主代理独占安排，本分支不执行网络负载。

现有脚本已经支持这三个参数，无需修改配置。主代理使用现有 Python 环境，从 `work/deploy/root` 执行：

```powershell
python -X utf8 microsoft_throughput.py pc queue-a1 16 171.108.209.190 large 16 64
python -X utf8 microsoft_throughput.py pc queue-b 32 171.108.209.190 small 16 32
python -X utf8 microsoft_throughput.py pc queue-a2 16 171.108.209.190 large 16 64
```

每条命令分别执行并读回；不要和其他吞吐测试并行运行。`large/small` 在这里仅占据原脚本的参数位置，最后的 64／32 MiB 会明确覆盖 SIZE。B 始终最多 16 条活跃 curl；worker 完成一片后领取下一片，不把活跃并发增加到 32。三组覆盖同一 `[100 MiB, 1124 MiB)` 字节范围，均不保存负载文件。当前 A 每请求时限 45 秒、B 为 25 秒；若 B 超时，该轮不完整，不能当作速度收益。遇到 429／认证或健康异常时应停下并排查，不密集重试。

现有 16 路批次有明显尾部：75% 切片完成后仍需约 2.385 秒，占全批次 15.48%；另一份原阈值 16 路结果为 3.167 秒，占 20.19%。对应前一批最后两段 WAN 吞吐约 99／78 Mbps。小切片补位可能减少低并发尾部，但更多新连接也增加慢启动、SOCKS 建连和 TCP 资源占用，必须测量后判断。不能把每条流的平均速率相加当作应用实际并发吞吐。

若 B 比两个 A 均明显更快，且全部 206／字节完整、CPU 和交互延迟没有更大代价，可再用 B/A 确认该方向；提升小于 A1/A2 的自然差异时不能判为优化。尾部减少但批次更慢时也不采纳。这个实验不修改路由器持久配置；结束后服务无需回退，测试文件仅是记录。

## 第二项先分离 UA3F 与 PC 路径成本

历史的裸路由器 8 × 128 MiB 为 617.54 Mbps、整机 CPU 23.8%；完整 PC 路径的 8 × 128 MiB 为 479.57 Mbps、50.5%。这些历史批次时间和路径不同，不能直接归因于 OpenClash。

需要追加的最小对照是路由器本机 curl → 现有 `127.0.0.1:1080` SOCKS5 → UA3F → `ua3f_bal` → 两 WAN，8 × 128 MiB；它保留 UA 重写、出站 `0xc9` 和 TTL64，且不经 Wi-Fi、OpenClash 入站及额外 loopback TCP leg。通过 `--socks5 127.0.0.1:1080` 与 `--resolve` 固定源 IP；不要用 `--socks5-hostname` 误以为 `--resolve` 已控制 SOCKS 服务端解析。前后取得 CPU、UA3F／clash process jiffies、WAN 字节和新 conntrack mark。

将该组与同轮裸路由器绑定双 WAN 测试及完整 PC 路径比较。若本机 UA3F 已明显降低吞吐，则优先定位 UA3F／TCP；若接近裸路由器而 PC 路径仍低，则剩余范围为 OpenClash 额外连接与 Wi-Fi／客户端，下一步才细分。任何一组未完整传完 1 GiB或没有读回 UA3F 外连的双出口 mark，都不能作为这项路径对照。

此处不提出直接开放 LAN SOCKS、更改透明路由或绕过 UA3F 的生产改动。先用现有 loopback 端口取得分层证据，不重启核心，不增加包。

## 已有 CPU 证据的含义

解析原始 `/proc/stat` 与 `/proc/PID/stat`、按整机四核 jiffies 计算：

| 批次 | 整机 busy | softirq | UA3F process | clash process |
| --- | --- | --- | --- | --- |
| PC 8 × 128 MiB | 50.5% | 15.9% | 6.90% | 6.96% |
| PC 16 × 64 MiB | 58.1% | 20.7% | 7.76% | 7.47% |
| PC 32 × 32 MiB | 70.0% | 25.1% | 9.56% | 9.78% |
| 路由器裸双 WAN | 23.8% | 6.1% | 0.05% | 1.43% |

进程两列以整机 CPU 为分母：四核设备的 25% 相当于占满一核。UA3F／clash 增量主要在 system 时间，用户时间在 1%～2% 左右。32 路吞吐比 16 路只高约 2.95%，CPU 却增加 11.9 个百分点，说明继续扩大并发的成本已经明显。当前样本未显示单核长期满载，不能将瓶颈确认成 Ninja 加密、Go 用户态计算或某个锁。

WAN 字节／应用字节比在 PC 16 路为 1.1411，裸路由器为 1.0442；计数包含 TCP/IP 开销、重传和背景业务，不能单凭比值将额外字节全算作丢包。原 TCP 内存 A/B/A 已有负收益并恢复，不重复提高 `tcp_mem`。未有对应逐包验证前继续保持流卸载和 WED 关闭。

原始来源为 `../microsoft-throughput-*.json`、`../followup-download-counter-deltas.json`。本分支的可重跑离线分析为 `analyze_download_concurrency.py`，结果为 `download-concurrency-analysis.json`。没有 SSH、测速、运行配置修改或代理 API 写入。
