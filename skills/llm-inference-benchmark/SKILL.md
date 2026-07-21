---
name: llm-inference-benchmark
description: >-
  Run standardized LLM inference performance benchmarks with evalscope across
  hardware profiles (AMD Strix Halo, H100x16, Huawei 910B). Use when the user
  asks for LLM/vLLM throughput tests, SLO capacity, peak tok/s, L0/L1/L2 suites,
  or cross-hardware benchmark templates.
---

# LLM Inference Benchmark

Agent workflow for reproducible serving benchmarks. Tooling lives beside this skill.

## Layout

```
.agents/skills/llm-inference-benchmark/
├── SKILL.md
├── benchmark.yaml          # profiles + suites (edit paths here)
├── run_benchmark.py        # entrypoint
├── README.md               # human docs
├── scripts/run_benchmark.py
└── templates/benchmark_meta.json.example
```

On a server, copy this whole directory (or the parent `lgsj` repo). Working dir = this skill folder.

## Prerequisites (server)

1. Python 3.10+ with `pyyaml` + `evalscope` (user installs; do not auto-install unless asked)
2. OpenAI-compatible serve URL up (vLLM/etc.)
3. Edit `benchmark.yaml` → `profiles.<name>.defaults` (`model_path`, `tokenizer_path`, `api_base`)

## Agent steps

1. Confirm hardware → pick `--profile`:
   - `amd_strix_halo` | `h100_8x2` | `huawei_910b` | `generic_8x`
2. Confirm model id + ctx; override `api_base`/`tokenizer` if needed
3. **Always dry-run first** when paths are uncertain:
   ```bash
   python run_benchmark.py --profile <profile> --suite L0 --model <id> --dry-run
   ```
4. Run suites **in order** unless user asks otherwise:
   - **L0** smoke (≤10m): p=1, out=256 — verify connectivity/success
   - **L1** SLO (≤30m): parallel 1,2,4,8… — report **max p with per-user ≥ target**
   - **L2** peak (≤45m): parallel 1,8,16,32,64,128 — report **peak total gen tok/s @ p**
5. After run, open `reports/<profile>_<suite>_<ts>/` and summarize:
   - dual metrics: **per-user decode** + **total gen**
   - success%
   - L1: SLO concurrency cap; L2: peak + p
   - cite `benchmark_meta.json`

## Suite rules (do not mix)

| Suite | Goal | Parallel | max_tokens | Pass bar |
|-------|------|----------|------------|----------|
| L0 | Smoke | `[1]` | 256 | 100% success |
| L1 | Per-user SLO | sweep 1→N | `ctx*0.25`, min=max | each p ≥ target |
| L2 | Peak total | 1,8,16…128 | `ctx*0.5`, min=max | report peak |

- Closed-loop: `--rate -1`
- Prompt budget: `prompt ≤ ctx - max_tokens - 256`
- L1 targets auto by size: 7B→30, 14B→25, 32B→20, 70B→15, 400B/GLM-5.2→10 (`--target` overrides)
- Never treat Avg Output Rate / thinking-on / overnight Phase A as peak

## Commands

```bash
cd .agents/skills/llm-inference-benchmark   # or where copied on server

python run_benchmark.py --profile amd_strix_halo --suite L0 --model Qwen2.5-7B-AWQ
python run_benchmark.py --profile amd_strix_halo --suite L1 --model Qwen2.5-7B-AWQ --target 15
python run_benchmark.py --profile h100_8x2 --suite L2 --model GLM-5.2-FP8 --ctx 32768
python run_benchmark.py --profile huawei_910b --suite L1 --model Qwen2.5-32B-AWQ --dry-run
```

Flags: `--ctx` `--api-base` `--tokenizer` `--target` `--dry-run`

## New hardware

Only add a block under `profiles` in `benchmark.yaml`. Do not fork the runner unless evalscope flags change.

## More detail

See [README.md](README.md) and [benchmark.yaml](benchmark.yaml).
