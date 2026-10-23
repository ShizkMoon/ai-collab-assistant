# Shared RE Toolkit — 固件/设备/软件逆向能力库

通用逆向分析底座,向本机所有 Agent(Devin/Orca worker/其他 MCP 客户端)暴露统一工具面。
源起 KPW5 固件逆向,沉淀为可复用能力。
覆盖面:任意固件镜像(路由器/IoT/智能家居/手表/平板/手机/阅读器)、
Android 应用与 OTA 包、ELF 软件、可通过 UART/SPI/JTAG/SSH 接入的实体设备。

## 组成

| 层 | 内容 |
|---|---|
| MCP 服务 | `re_toolkit_mcp.py` — stdio,15 个工具(见下) |
| 底层 CLI | nix profile:ghidra / binwalk / unblob / qemu / mitmproxy / frida-tools / rizin / gdb / **jadx / apktool / aapt2 / payload-dumper-go / abootimg / kaitai-struct-compiler / nmap / tshark / flashrom / openocd / sigrok-cli / picocom / sshpass / expect** |
| 独立工具 | kindletool(源码构建)、rea(MCP+CLI)、fitextract/lzodec/parse_wf_lut/dtbdump(`~/Repos/kpw5-analysis/tools`) |

## MCP 工具清单

| 工具 | 作用 | 关键参数 |
|---|---|---|
| `toolkit_status` | 自检:全部底层 CLI 的可用性与真实路径 | — |
| `firmware_extract` | 固件解包出文件系统 | firmware, output_dir, backend(unblob/binwalk/kindletool) |
| `firmware_scan` | 只扫描签名不解包 | firmware |
| `firmware_inventory` | 解包目录盘点:树形+ELF/脚本计数+启动入口 | path |
| `ghidra_analyze` | headless 导入+自动分析→函数清单;可点取单函数伪C | binary, function(可空) |
| `disasm` | 轻量反汇编(rizin/objdump/readelf 直达) | binary, tool, commands |
| `java_decompile` | jadx 无头反编译 jar/apk/dex → 源码树摘要 | target, output_dir, args |
| `apk_analyze` | APK 体检:badging+权限+文件清单 | apk |
| `kaitai_compile` | .ksy 格式描述 → 生成解析器代码 | ksy, output_dir, target |
| `frida_trace` | 本机进程动态追踪 | target, spawn, functions, duration_s |
| `mitm_capture` | 本地代理抓 HTTP(S) | port, duration_s, mode |
| `pcap_capture` | tshark 全协议抓包+会话摘要 | iface, duration_s, bpf |
| `net_scan` | nmap 服务指纹(**仅自有/授权网段**) | target, nmap_args |
| `serial_capture` | UART 只读捕获(不发数据) | device, baud, duration_s |
| `flash_read` | flashrom 只读 dump SPI/NOR(写不提供) | programmer, output, chip |
| `qemu_boot` | 无头引导内核/固件,抓串口日志 | kernel, initrd, arch, machine, duration_s |

## 使用

Devin CLI 已注册(user scope,`~/.config/devin/mcp_config.json`):
所有项目自动获得 `mcp__re-toolkit__*` 工具。

手动验证:`devin mcp list` / `devin mcp get re-toolkit`;
或直接 `echo '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | .venv/bin/python re_toolkit_mcp.py`。

## SOP(标准作业流)

```
解包(firmware_extract) → 盘点(firmware_inventory)→ 定位启动脚本/守护进程
→ 静态分析(disasm 快速扫 / ghidra_analyze 深挖)
→ [可选]动态验证(frida_trace 本机进程 / qemu_boot 固件)
```

**上下文保护**:严禁全量 dump 汇编/伪代码;一律"关键常数/字符串→XREF→单函数"下钻。
`ghidra_analyze` 默认只回函数清单,伪C 必须按 `function=` 点名。

## 安全红线

- 本库只做**只读分析**与本地仿真;写盘/烧录/对外发包一律不在工具面内
- 涉及物理介质烧写、Bootloader 修改、向真实设备发包前**必须人工确认**
- mitm_capture 仅本地代理模式,不自动劫持;设备端需自行配置代理
- **串口双向交互刻意不进 MCP**:`expect` 已装但只走 CLI——它能"等 login: 发密码/
  等 U-Boot 倒数按任意键打断",属于对实体设备发数据,触发红线;
  `serial_capture` 只读(stty+cat)是默认安全面,人工确认后才允许 expect 脚本

## 按需补装(已知缺口)

| 件 | 为什么还没装 | 装法 |
|---|---|---|
| CH341A/FT2232 烧录器 | flashrom/openocd 的软件就位了,**硬件要买**(¥10-30) | 淘宝;装后 flash_read/JTAG 直通 |
| `angr` | 符号执行,依赖重(unicorn/claripy ~150MB),非日常用 | `pip install angr` 进 .venv 或临时 venv |
| `qiling` | 二进制仿真框架(跑 IoT 用户态 ELF),同上按需 | `pip install qiling` |
| FACT_core / EMBA | 整机固件自动体检平台,Docker 级重;人工 SOP 已覆盖其产出 | 需要时 `docker pull fkiecad/fact-core` |
| MobSF / objection | 移动应用动静态平台,重型;jadx+frida 组合已够大多数场景 | `pip install objection` / docker |
| JTAGulator/探针 | 未知板卡引脚枚举,小众硬件件 | 有实物再配 |

原则:**轻量 CLI 一律预装(nix profile),重型平台/需要实物的先登记、用到再装**。

## 环境

- NixOS 26.11 x86_64;Python 3.14 venv(`.venv/`,mcp<2)
- Ghidra 12.1.4(nixpkgs,自带 OpenJDK 21)
- 补装:`nix profile add nixpkgs#<pkg>`(用户级,不动系统配置)
