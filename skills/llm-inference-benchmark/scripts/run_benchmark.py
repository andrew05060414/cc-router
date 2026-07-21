#!/usr/bin/env python3
"""
Universal LLM Inference Benchmark Runner

Usage:
  python run_benchmark.py --profile amd_strix_halo --suite L0 --model Qwen2.5-7B-AWQ
  python run_benchmark.py --profile h100_8x2 --suite L1 --model GLM-5.2-FP8 --target 20
  python run_benchmark.py --profile huawei_910b --suite L2 --model Qwen2.5-32B-AWQ --ctx 16384 --dry-run
"""

import argparse
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

import yaml

ROOT = Path(__file__).parent
CONFIG = ROOT / "benchmark.yaml"
REPORTS_DIR = ROOT / "reports"
REPORTS_DIR.mkdir(exist_ok=True)


def load_config():
    with open(CONFIG) as f:
        return yaml.safe_load(f)


def infer_model_size(model_id: str, config: dict) -> str:
    """从 model_id 推断模型规模档位"""
    keywords = config.get("model_size_keywords", {})
    model_lower = model_id.lower()
    for kw, size in keywords.items():
        if str(kw).replace("_", ".") in model_lower:
            return size
    # 兜底：找数字
    m = re.search(r"(\d+(?:\.\d+)?)b?", model_lower)
    if m:
        val = float(m.group(1))
        if val <= 10:
            return "7B"
        elif val <= 20:
            return "14B"
        elif val <= 50:
            return "32B"
        elif val <= 100:
            return "70B"
        else:
            return "400B"
    return "32B"  # 默认


def get_l1_target(model_id: str, config: dict, cli_target: int = None) -> int:
    """获取 L1 目标 per-user decode tok/s"""
    if cli_target:
        return cli_target
    size = infer_model_size(model_id, config)
    return config.get("model_slo_targets", {}).get(size, 15)


def calc_prompt_budget(ctx: int, max_tokens: int) -> tuple[int, int]:
    """计算 prompt 长度范围"""
    max_prompt = ctx - max_tokens - 256  # 安全边际
    min_prompt = int(max_prompt * 0.85)
    return min_prompt, max_prompt


def build_evalscope_cmd(
    profile: dict,
    suite: dict,
    model_id: str,
    ctx: int,
    max_tokens: int,
    parallel: list[int],
    n: int,
    api_base: str,
    tokenizer_path: str,
    out_dir: Path,
) -> list[str]:
    """组装 evalscope perf 命令"""
    min_prompt, max_prompt = calc_prompt_budget(ctx, max_tokens)

    cmd = [
        "evalscope", "perf",
        "--model", model_id,
        "--api", "openai",
        "--url", f"{api_base.rstrip('/')}/chat/completions",
        "--tokenizer-path", tokenizer_path,
        "--dataset", "random",
        "--max-prompt-length", str(max_prompt),
        "--min-prompt-length", str(min_prompt),
        "--max-tokens", str(max_tokens),
        "--min-tokens", str(max_tokens),  # L1/L2 防早停
        "--temperature", "0.0",
        "--stream", "true",
        "--parallel", " ".join(map(str, parallel)),
        "--number", str(n),
        "--rate", "-1",  # 闭环
        "--warmup-num", "0",
        "--sleep-interval", "5",
        "--apply-chat-template", "auto",
        "--tokenize-prompt", "false",
        "--output-dir", str(out_dir),
    ]
    return cmd


def write_meta(out_dir: Path, profile_name: str, suite_name: str, model_id: str, ctx: int,
               max_tokens: int, parallel: list[int], n: int, profile: dict, l1_target: int = None):
    """写入 benchmark_meta.json"""
    meta = {
        "benchmark_meta": {
            "date": datetime.now().isoformat(),
            "suite": suite_name,
            "profile": profile_name,
            "hardware": profile.get("hardware", {}),
            "software": profile.get("software", {}),
            "model": {
                "name": model_id,
                "ctx_len": ctx,
                "size_category": infer_model_size(model_id, {"model_size_keywords": {}}),
            },
            "test": {
                "ctx": ctx,
                "max_tokens": max_tokens,
                "min_tokens": max_tokens,
                "parallel_sweep": parallel,
                "n_per_point": n,
                "l1_target_per_user": l1_target,
            },
        }
    }
    (out_dir / "benchmark_meta.json").write_text(json.dumps(meta, indent=2))


def generate_report(out_dir: Path, profile_name: str, suite_name: str, model_id: str, l1_target: int = None):
    """生成 Markdown 报告"""
    perf_file = out_dir / "performance_summary.txt"
    if not perf_file.exists():
        # 尝试找 sqlite 或其他输出
        for f in out_dir.glob("*.txt"):
            if "summary" in f.name.lower() or "performance" in f.name.lower():
                perf_file = f
                break

    content = perf_file.read_text() if perf_file.exists() else "(no performance_summary.txt found)"

    md = f"""# Benchmark Report — {model_id} — {profile_name} — {suite_name}
**Date**: {datetime.now().strftime('%Y-%m-%d %H:%M')}
**Profile**: {profile_name} | **Suite**: {suite_name}
**Model**: {model_id}
{f"**L1 Target**: ≥ {l1_target} tok/s per-user" if l1_target else ""}

## Raw Output
```
{content}
```

## Quick Parse (manual)
| p | success% | per-user decode (tok/s) | total gen (tok/s) | TTFT (ms) | Notes |
|---|----------|------------------------:|------------------:|----------:|-------|
|   |          |                         |                   |           |       |
"""
    report_file = out_dir / f"report_{suite_name.lower()}.md"
    report_file.write_text(md)
    print(f"  📄 Report: {report_file}")


def run_suite(profile_name: str, suite_name: str, model_id: str, ctx: int,
              api_base: str, tokenizer_path: str, target: int, dry_run: bool):
    config = load_config()

    # 获取 profile
    if profile_name not in config["profiles"]:
        print(f"❌ Unknown profile: {profile_name}")
        print(f"   Available: {list(config['profiles'].keys())}")
        sys.exit(1)
    profile = config["profiles"][profile_name]

    # 获取 suite 配置
    suite_cfg = config["suites"][suite_name]
    suite_fixed = suite_cfg.get("fixed", {})

    # 确定参数
    max_tokens = suite_fixed.get("max_tokens", 256)
    min_tokens = suite_fixed.get("min_tokens", max_tokens)
    n = suite_fixed.get("n", 8)
    parallel = suite_cfg.get("parallel", suite_cfg.get("parallel_sweep", [1]))

    # L1 特殊：输出长度 = ctx * 0.25
    if suite_name == "L1":
        max_tokens = int(ctx * 0.25)
        min_tokens = max_tokens
    elif suite_name == "L2":
        max_tokens = int(ctx * 0.5)
        min_tokens = max_tokens

    # L1 目标值
    l1_target = get_l1_target(model_id, config, target) if suite_name == "L1" else None

    # 输出目录
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    out_dir = REPORTS_DIR / f"{profile_name}_{suite_name}_{ts}"
    out_dir.mkdir(parents=True, exist_ok=True)

    # 组装命令
    cmd = build_evalscope_cmd(
        profile=profile,
        suite=suite_cfg,
        model_id=model_id,
        ctx=ctx,
        max_tokens=max_tokens,
        parallel=parallel,
        n=n,
        api_base=api_base,
        tokenizer_path=tokenizer_path,
        out_dir=out_dir,
    )

    # 写元数据
    write_meta(out_dir, profile_name, suite_name, model_id, ctx, max_tokens, parallel, n, profile, l1_target)

    print(f"\n=== {profile_name} | {suite_name} | {model_id} ===")
    print(f"Ctx: {ctx} | Max tokens: {max_tokens} | Parallel: {parallel} | N: {n}")
    print(f"Output dir: {out_dir}")
    print(f"Cmd: {' '.join(cmd)}")

    if dry_run:
        print("  (dry-run, not executing)")
        return

    # 运行
    start = time.time()
    result = subprocess.run(cmd, capture_output=True, text=True)
    elapsed = time.time() - start

    if result.returncode != 0:
        print(f"❌ FAILED ({elapsed:.1f}s): {result.stderr[:500]}")
        (out_dir / "error.log").write_text(result.stderr)
        sys.exit(result.returncode)

    print(f"✅ Done ({elapsed:.1f}s)")

    # 生成报告
    generate_report(out_dir, profile_name, suite_name, model_id, l1_target)


def main():
    parser = argparse.ArgumentParser(description="Universal LLM Inference Benchmark")
    parser.add_argument("--profile", required=True,
                        choices=["amd_strix_halo", "h100_8x2", "huawei_910b", "generic_8x"],
                        help="Hardware/software profile")
    parser.add_argument("--suite", required=True, choices=["L0", "L1", "L2"],
                        help="Test suite")
    parser.add_argument("--model", required=True, help="Model ID (for tokenizer & reporting)")
    parser.add_argument("--ctx", type=int, default=None, help="Context length (override profile default)")
    parser.add_argument("--api-base", default=None, help="API base URL (override profile default)")
    parser.add_argument("--tokenizer", default=None, help="Tokenizer path (override profile default)")
    parser.add_argument("--target", type=int, default=None, help="L1 per-user target tok/s (override auto)")
    parser.add_argument("--dry-run", action="store_true", help="Print command only")
    args = parser.parse_args()

    config = load_config()
    profile = config["profiles"][args.profile]
    defaults = profile.get("defaults", {})

    # 解析参数（CLI > profile default）
    model_id = args.model
    ctx = args.ctx or defaults.get("ctx", 4096)
    api_base = args.api_base or defaults.get("api_base", "http://localhost:8000/v1")
    tokenizer_path = args.tokenizer or defaults.get("tokenizer_path", model_id)

    run_suite(
        profile_name=args.profile,
        suite_name=args.suite,
        model_id=model_id,
        ctx=ctx,
        api_base=api_base,
        tokenizer_path=tokenizer_path,
        target=args.target,
        dry_run=args.dry_run,
    )


if __name__ == "__main__":
    main()