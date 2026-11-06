# 模型路由与本地推理

> 状态：设计中 · 上位文档：[架构总览 §2](architecture.md#2-意图分类与结构化路由)、[系统运维](platform-ops.md)、[开源复用清单](open-source-reuse.md)
>
> 本文定义模型注册表、`kind → 任务类别 → 模型` 的路由策略、多级降级链与缓存、批处理成本核算、16GB 显存分配机制，以及受限解码（Guided Decoding）与置信度温度校准方案。系统以 **LiteLLM 作为统一模型网关**，配合轻量级本地路由与独占文件锁串行化显存使用。

## 0. 状态与缓存路径约定

模型网关、校准数据库与权重缓存的路径按 [工作站配置 §3](workstation-windows.md#3-目录布局) 的 Windows 目录约定放置：

| 用途 | 路径 | 当前本机状态 |
|---|---|---|
| 运行时状态（花费记录、置信度校准、批处理队列） | `%LOCALAPPDATA%\aica\state\` | 安装脚本创建 |
| 模型权重缓存与导出数据 | `%LOCALAPPDATA%\aica\data\` | 安装脚本创建 |
| 大体积产物与备份暂存 | `D:\aica\` | `D:` 数据卷已就绪，首次使用前需执行 `New-Item -ItemType Directory D:\aica` |

## 1. 模型注册表：`models.toml`

所有本地与云端模型统一在 `models.toml` 中声明，LiteLLM 的网关配置、云端兜底模型清单以及成本统计分组均由该文件生成：

| 模型 ID | 运行位置 | 推理引擎 | 上下文窗口 | 显存占用 | 主要用途 | 结构化输出能力 | p50 延迟 | 参考价格（元 / 1M in·out） |
|---|---|---|---|---|---|---|---|---|
| `qwen3-8b-q4` | 工作站 GPU | vLLM 常驻 | 8k | 6.2 GB | 意图分类、摘要、初稿 | XGrammar | 0.9s | 0 |
| `qwen3-14b-q4` | 工作站 GPU | Ollama 按需加载 | 8k | 10.8 GB | 夜间批处理、复杂推理 | GBNF Schema | 1.8s | 0 |
| `qwen2.5-vl-7b` | 工作站 GPU | vLLM 按需加载 | 8k | 7.0 GB | 本地桌面截图理解与视觉点击 | Schema | 1.4s | 0 |
| `bge-m3` + Reranker | 工作站 GPU | Ollama | 8k | 2.3 GB | 知识库向量化与重排 | - | 60ms | 0 |
| `bge-small-zh` | 云端 CPU | `sentence-transformers` | 512 | - | 云端兜底 Embedding 与 SetFit 分类 | - | 35ms | 0 |
| `paraformer-zh` | 工作站 | FunASR | - | 0.9 GB | 语音输入转写、播客字幕 | - | 实时 | 0 |
| `deepseek-chat` | 云端 API | 官方 API | 64k | - | 长文写作、代码开发、复杂长尾任务 | `json_schema` | 3.2s | 2 / 8 |
| `qwen-max` | 云端 API | DashScope | 128k | - | 长文审校与跨厂商交叉评审 | `json_schema` | 4.0s | 按官方计费 |

LiteLLM 服务配置生成逻辑：

```python
# %ProgramData%\aica\gen\litellm_config.py —— 由 models.toml 生成 LiteLLM 配置
import os, pathlib, tomllib

models = tomllib.loads(pathlib.Path("models.toml").read_text(encoding="utf-8"))["models"]
spend = pathlib.Path(os.environ["LOCALAPPDATA"]) / "aica" / "state" / "litellm" / "spend.db"

def entry(m):
    params = {
        "model": f"{m['provider']}/{m['id']}" if m["where"] == "cloud" else f"{m['engine']}/{m['id']}",
        "api_base": (f"http://workstation.ts.net:{m['port']}" if m["where"] == "workstation"
                     else f"http://127.0.0.1:{m['port']}"),
        "num_ctx": m["ctx"],
    }
    if m["where"] == "cloud":
        params["api_key"] = "os.environ/" + m["key_env"]
    return {"model_name": m["id"], "litellm_params": params}

config = {
    "model_list": [entry(m) for m in models if m["where"] != "n100"],
    "environment": {"DATABASE_URL": f"sqlite:///{spend.as_posix()}"},
}
```

## 2. 按任务类别路由：`kind` → `task_class` → 模型

入口仅需确定任务的 `kind`，路由层通过简单的前缀映射表将 `kind` 映射到对应的 `task_class`（能力 TOML 中也可显式声明 `task_class` 覆盖默认值），从而实现更换底层模型时无需修改能力定义：

| 任务类别（`task_class`） | 典型 `kind` | 首选模型 | 选型原因 |
|---|---|---|---|
| `classify` | 入口意图分类、账单分类 | 本地 8B + `guided_choice` | 输入短、要求严格结构化输出、延迟敏感 |
| `extract` | `life.trip.plan`、邮件字段抽取 | 本地 8B（失败回退云端） | 多字段 JSON 抽取 |
| `summarize` | 每日早晚报、`info.feed.digest` | 本地 8B（超 8k 上下文转云端） | 高频调用，优先使用本地免费算力 |
| `longform` | `work.write.longform`、`work.book.polish` | 云端大模型（经 `agent:local` Worker） | 生成质量优先 |
| `code` | `work.code.task`、`work.rev.*` | 云端代码模型（Devin / Codex / Claude） | 由执行层 Worker 直接调用 |
| `vision` | 桌面截图理解、GUI 视觉操作 | 本地 `qwen2.5-vl-7b` | 屏幕截图留在本地处理，保障隐私 |
| `embed` | `info.recall`、规则聚类挖掘 | 工作站 `bge-m3` / 云端 `bge-small-zh` | 高频向量化，本地低延迟 |
| `asr` | 语音指令输入、播客音频转写 | 本地 `paraformer-zh` / SenseVoice | 中文识别率高，支持本地离线运行 |
| `batch` | 夜间批量转写、书库标签整理 | 夜间批处理窗口 + 云端折扣时段 | 时效要求低，集中调度降本 |

```python
# routing.py
OVERRIDES = {}          # 读取自各能力 TOML 的 task_class 覆盖项
MAP = {"life.": "classify", "home.": "classify", "meta.review": "summarize",
       "info.": "summarize", "work.video": "longform", "work.book": "longform",
       "work.code": "code", "work.rev": "code", "life.study": "extract"}

def task_class(kind: str, cap: dict) -> str:
    return cap.get("task_class") or next((v for k, v in MAP.items() if kind.startswith(k)), "classify")
```

## 3. 故障降级链与四层缓存

LiteLLM 网关层的重试与超时降级配置：

```yaml
router_settings: { num_retries: 2, timeout: 20, allowed_fails: 2, cooldown_time: 60,
  fallbacks: { decide-local: [decide-cloud, n100-knn], summarize-local: [summarize-cloud] },
  context_window_fallbacks: { summarize-local: [summarize-cloud] } }
```

入口意图分类的四级降级顺序：

```
1. 工作站本地 vLLM (qwen3-8b) → 2. 云端 API (deepseek-chat) → 3. 云端 CPU 分类器 (SetFit/kNN) → 4. 待分类队列 (meta.triage.pending)
```

- **工作站休眠场景**：工作站改为接交流电时保持唤醒（[网络与设备组网 §6](network-fabric.md#6-电源唤醒与夜间批处理)），云端兜底分类只在工作站确实不可达时使用；事件先入等待队列，不另设唤醒链路。
- **云端 CPU 兜底边界**：云服务器上的 SetFit 分类器仅负责预测 `kind` 并将原始文本存入 `payload`，不运行生成式大模型提取复杂参数（受限于云服务器的内存预算）。
- **兜底归档**：若前三级均无法给出达标结果，任务归入 `meta.triage.pending`，在次日早报中汇总提示，不发送即时弹窗打扰。

推理请求设置四层缓存：

| 缓存层级 | 实现方式 | 缓存键 | 有效期 |
|---|---|---|---|
| 精确匹配缓存 | LiteLLM 内置 `disk` 缓存 | `sha256(prompt + model + schema)` | 30 天 |
| 语义相似缓存 | 本地 `sqlite-vec` + `bge-small-zh`（余弦相似度 ≥ 0.93） | Prompt 向量 | 命中后记录样本供阈值校准 |
| 聚合结果缓存 | 当日早晚报生成文件落盘即复用 | `date + kind` | 当日有效 |
| 故障冷却缓存 | LiteLLM 内置 `cooldown` | 异常模型 ID | 60 秒 |

## 4. 夜间批处理与成本统计

标记为 `lane = "batch"` 的任务写入 `%LOCALAPPDATA%\aica\state\batch\queue.jsonl`，白天仅入队不执行；每日凌晨 01:00 由任务计划程序拉起处理，充分利用云端 API 夜间折扣时段与本地空闲算力。若队列中存在驻留超过 48 小时的任务，在早报中提示。

系统每晚汇总三项成本来源并按 `kind` 关联（调用网关时附带 `metadata.tags = ["kind:<kind>", "task:<uuid>"]`）：

1. LiteLLM `SpendLogs` 记录的云端 Token 消耗与金额；
2. 本地 `gpu-lease` 记录的 GPU 占用时长与显存峰值；
3. Home Assistant 计量插座统计的实际耗电量（kWh × 电价）。

```sql
-- 每晚 03:10 聚合生成日报表，供周报按 kind 统计调用次数、返工率与总成本
SELECT day, kind, model, SUM(tokens_in), SUM(tokens_out), SUM(yuan), SUM(gpu_minutes)
FROM daily_usage GROUP BY 1,2,3;
```

## 5. 本地推理显存分配（16GB VRAM）

工作站桌面合成运行在核显（iGPU）上，独显（RTX 4080 Laptop 16GB）在非图形渲染时段可全量供计算任务使用（在 NVIDIA 控制面板或 Windows 图形设置中把计算程序显式指定到独显）：

| 模型或任务 | 权重显存（Q4） | 8k 上下文 KV Cache | 显存合计（GB） | 驻留策略 |
|---|---|---|---|---|
| `qwen3-8b` | 5.0 | 1.2 | **6.2** | 常驻显存，服务高频分类与摘要 |
| `bge-m3` + Reranker | 2.3 | - | **2.3** | 常驻显存，服务知识库检索 |
| `qwen3-14b` | 9.0 | 1.8 | 10.8 | 按需独占加载，用于夜间批处理 |
| `qwen2.5-vl-7b` | 5.5 | 1.5 | 7.0 | 按需加载（与 8B 互斥或临时卸载 8B） |
| `paraformer` / `cosyvoice2` | 0.9 / 2.5 | - | 3.4 | 按需加载，用完释放 |
| ACE-Step 1.5 音乐生成 | ~4.0 | - | ~4.0 | 按需加载 |
| ComfyUI（MOSS / SDXL / Flux） | 6.0–11.0 | - | 6.0–11.0 | 出图期间独占高显存，空闲回落至 ~3GB |

常驻的 `qwen3-8b`（6.2GB）与 `bge-m3`（2.3GB）合计占用约 8.5GB，剩余约 7.5GB 供中小型按需任务使用。对于 ComfyUI 出图、14B 模型推理、Blender Cycles 渲染等高显存独占任务，统一通过 `%LOCALAPPDATA%\aica\state\gpu-lease` 文件锁（独占打开，进程退出自动释放）串行化调度：

```powershell
# 所有高显存 Provider 启动前先独占打开租约文件，进程退出自动释放
$lease = Join-Path $env:LOCALAPPDATA 'aica\state\gpu-lease'
$fs = [IO.File]::Open($lease, 'OpenOrCreate', 'ReadWrite', 'None')  # 拿不到即抛 IOException
try { <启动 Provider> } finally { $fs.Dispose() }
```

租约等待 120 秒仍拿不到的，Provider 以退出码 75 结束（`EX_TEMPFAIL`），派发方收到后自动延后重试。常驻 vLLM 由 WinSW 包装为 Windows 服务，等价于：

```xml
<!-- %ProgramData%\aica\units\vllm.xml（WinSW） -->
<service>
  <id>vllm</id>
  <executable>vllm.exe</executable>
  <arguments>serve Qwen/Qwen3-8B-AWQ --port 8000 --max-model-len 8192 --gpu-memory-utilization 0.55 --guided-decoding-backend xgrammar --enable-prefix-caching</arguments>
  <onfailure action="restart" delay="10 sec"/>
  <startmode>Automatic</startmode>
</service>
```

## 6. 受限解码分类接口：`decide(state, schema)`

意图分类通过推理引擎的受限解码（Guided Decoding）将模型输出严格限制在候选集合或 JSON Schema 内，并直接读取首 Token 的 `logprobs` 计算各候选 `kind` 的归一化概率：

| 推理后端 | 适用场景 | 受限解码参数 |
|---|---|---|
| vLLM | 工作站常驻服务 | `guided_choice` / `guided_json`（基于 XGrammar Token 掩码） |
| Ollama | 本地按需加载模型 | `format: <schema>`（基于内置 GBNF 语法） |
| `outlines` / `llguidance` | 离线脚本批处理 | 库级语法掩码控制 |

```python
def decide(state: str, labels: list[str], model="decide-local") -> dict[str, float]:
    letters = "ABCDE"[:len(labels)]
    prompt = ("从下列能力中选一个最匹配的，只输出一个字母。\n"
              + "\n".join(f"{l}. {k}" for l, k in zip(letters, labels))
              + f"\n\n任务描述：{state}\n答案：")
    r = litellm.completion(model=model, messages=[{"role": "user", "content": prompt}],
        max_tokens=1, temperature=0,
        extra_body={"guided_choice": list(letters), "logprobs": True, "top_logprobs": len(letters)})
    p = {}
    for t in r.choices[0].logprobs.content[0].top_logprobs:
        tok = t.token.strip().upper()
        if tok in letters: p[tok] = p.get(tok, 0.0) + math.exp(t.logprob)
    z = sum(p.values()) or 1.0
    return {labels[letters.index(k)]: v / z for k, v in p.items()}
```

置信度路由阈值分为三档：

- `p ≥ 0.85`：直接派发执行；
- `0.50 ≤ p < 0.85`：向用户发送卡片追问确认；
- `p < 0.50`：归入待分类队列（`meta.triage.pending`）。

各 `kind` 的具体阈值独立保存在 `%LOCALAPPDATA%\aica\state\calibration.db` 中，防止低频长尾能力因全局固定阈值过高而始终无法自动派发。

## 7. 置信度温度缩放校准（Temperature Scaling）

根据任务库中用户对分类结果的确认（正样本）与修改（负样本）记录，系统每周运行一次温度缩放拟合，校准模型输出概率：

```python
def fit_temperature(p, y):          # p: 预测概率数组, y: 实际是否正确 (0/1)
    def nll(T):
        q = p ** (1/T); q = q / (q + (1-p) ** (1/T) + 1e-9)
        return -np.mean(y*np.log(q+1e-9) + (1-y)*np.log(1-q+1e-9))
    return float(minimize_scalar(nll, bounds=(0.5, 5.0), method="bounded").x)
```

仅当某类能力的累计样本数 **≥ 30** 且校准后的期望校准误差（ECE）**< 0.05** 时，才更新该类的独立温度参数 `T`；样本量不足的能力继续使用全局默认温度参数。
