# Universal LLM Inference Benchmark

标准化、可复现的跨硬件/模型/量化推理性能基准工具。

## 目录结构

```
perf_test/
├── benchmark.yaml      # 配置文件：profiles + suites + 模型映射
├── run_benchmark.py    # 统一入口脚本
├── reports/            # 自动产出报告
└── README.md           # 本文件
```

## 快速开始

### 1. 环境准备

```bash
# 安装 evalscope (推荐 0.8+)
pip install evalscope

# 启动你的 vLLM 服务 (示例)
# AMD Strix Halo:
~/start_vllm_kyuz0_v36.sh

# H100:
vllm serve /mnt/models/GLM-5.2-FP8 --tensor-parallel-size 16 --dtype fp8 ...

# 健康检查
curl http://localhost:8000/v1/models
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"your-model","messages":[{"role":"user","content":"hi"}],"max_tokens":16,"stream":true}'
```

### 2. 跑基准

```bash
cd /Users/andrewwang/Code/lgsj/perf_test

# L0 冒烟测试 (≤10 min)
python run_benchmark.py --profile amd_strix_halo --suite L0 --model Qwen2.5-7B-AWQ

# L1 SLO 并发边界 (≤30 min)
python run_benchmark.py --profile amd_strix_halo --suite L1 --model Qwen2.5-7B-AWQ --target 20

# L2 峰值吞吐 (≤45 min)
python run_benchmark.py --profile h100_8x2 --suite L2 --model GLM-5.2-FP8 --ctx 32768

# 先 dry-run 看命令
python run_benchmark.py --profile huawei_910b --suite L1 --model Qwen2.5-32B-AWQ --dry-run
```

### 3. 看报告

```
reports/
├── amd_strix_halo_L0_20260714_143000/
│   ├── benchmark_meta.json    # 完整元数据
│   ├── performance_summary.txt # evalscope 原始输出
│   ├── report_L0.md           # Markdown 报告
│   └── error.log              # 失败时的错误
└── ...
```

## 三套套件详解

| Suite | 目的 | 时长 | 并发扫描 | 关键指标 |
|-------|------|------|----------|----------|
| **L0** | 冒烟/联调 | ≤10 min | p=1 | success=100%, per-user ≥ 80% 基线 |
| **L1** | 用户体验边界 | ≤30 min | 1,2,4,8,16... 直到不达标 | **per-user decode ≥ 目标值** |
| **L2** | 硬件极限吞吐 | ≤45 min | 1,8,16,32,64,128 | **Peak total gen tok/s + 对应 p** |

## Profile 选择指南

| 你的硬件 | 用这个 Profile |
|----------|----------------|
| AMD Ryzen AI Max 395 (Strix Halo, gfx1151) | `amd_strix_halo` |
| H100 × 16 (双节点 8×2 NVLink/Switch) | `h100_8x2` |
| 华为 Atlas 910B × 8 | `huawei_910b` |
| 通用单节点 8×A100/H100 | `generic_8x` |

## 常用参数

| 参数 | 说明 | 示例 |
|------|------|------|
| `--profile` | 硬件/软件栈配置 | `amd_strix_halo` |
| `--suite` | 测试套件 | `L0` / `L1` / `L2` |
| `--model` | 模型标识 (用于 tokenizer & 报告) | `Qwen2.5-7B-AWQ` |
| `--ctx` | 上下文长度 (覆盖 profile 默认) | `8192` |
| `--target` | L1 目标 per-user tok/s (覆盖自动分档) | `20` |
| `--api-base` | 覆盖 API 地址 | `http://10.0.0.5:8000/v1` |
| `--tokenizer` | 覆盖 tokenizer 路径 | `/mnt/models/Qwen2.5-7B-AWQ` |
| `--dry-run` | 只打印命令不执行 | - |

## 模型规模 → L1 目标值自动映射

| 模型规模 | 目标 tok/s | 关键词匹配 |
|----------|------------|------------|
| 7B | 30 | `7b`, `7` |
| 14B | 25 | `14b`, `14` |
| 32B | 20 | `32b`, `32` |
| 70B | 15 | `70b`, `70` |
| 400B+ | 10 | `400b`, `5.2` (GLM-5.2) |

用 `--target` 可强制覆盖。

## 输出长度策略 (自动计算)

| Suite | max_tokens | min_tokens | 说明 |
|-------|------------|------------|------|
| L0 | 256 | 256 | 短输出快速验通 |
| L1 | ctx × 0.25 | =max | 4K→1K, 8K→2K, 32K→8K |
| L2 | ctx × 0.5 | =max | 4K→2K, 8K→4K, 32K→16K (长输出榨干 decode) |

Prompt 预算：`prompt ≤ ctx - max_tokens - 256` (留 256 给模板)

## 自定义 Profile

编辑 `benchmark.yaml` 的 `profiles` 部分：

```yaml
profiles:
  my_custom_setup:
    hardware:
      gpu: "A100-40GB"
      count: 4
      ...
    software:
      serving: "vLLM 0.6.3"
      dtype: "fp16"
      ...
    defaults:
      ctx: 8192
      model_path: "/my/model"
      api_base: "http://localhost:8000/v1"
      tokenizer_path: "/my/model"
```

然后用 `--profile my_custom_setup`。

## 依赖

- Python 3.10+
- evalscope ≥ 0.8 (`pip install evalscope`)
- PyYAML (`pip install pyyaml`)
- 运行中的 vLLM / Ollama / OpenAI 兼容 API 服务

## 故障排查

| 现象 | 检查 |
|------|------|
| `evalscope: command not found` | `pip install evalscope` 并确保在 PATH |
| 连接超时 | 确认 vLLM 启动完成、端口正确、防火墙 |
| OOM | 降低 `max_num_seqs`、减小 `ctx`、开启 `chunked_prefill` |
| 成功率低 | 检查 `max_num_seqs` 是否 ≥ `parallel × n`、显存是否够 |

## 设计原则

1. **声明式配置** - YAML 描述硬件/软件/测试参数，核心逻辑零修改
2. **双指标强制双报** - 每档并发同时给出 per-user decode + total gen
3. **元数据完整记录** - `benchmark_meta.json` 含硬件/软件/模型/测试参数，便于复现对比
4. **三套套件互不混用** - L0/L1/L2 各有各的并发范围、输出长度、通过标准
5. **跨平台复用** - 换硬件只改 profile，换模型只改 `--model`，逻辑完全复用