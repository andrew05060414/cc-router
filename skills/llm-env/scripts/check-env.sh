#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# llm-env 环境检测脚本
# 在目标机器上运行，检查 CUDA、Python、uv 是否可用。
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$(dirname "$SCRIPT_DIR")"

echo "============================================"
echo "llm-env 环境检测"
echo "============================================"

echo ""
echo "[check] 操作系统:"
uname -a

echo ""
echo "[check] CPU 信息:"
nproc
lscpu 2>/dev/null | grep "Model name" || true

echo ""
echo "[check] 内存:"
free -h 2>/dev/null || echo "free 命令不可用"

echo ""
echo "[check] GPU 信息:"
if command -v nvidia-smi >/dev/null 2>&; then
    nvidia-smi
else
    echo "WARN: nvidia-smi 不可用，可能没有 NVIDIA GPU 驱动"
fi

echo ""
echo "[check] CUDA 版本:"
if command -v nvcc >/dev/null 2>&; then
    nvcc --version
else
    echo "WARN: nvcc 不可用"
fi

echo ""
echo "[check] Python 环境:"
for env in "$ENV_DIR"/envs/*/; do
    if [[ -x "$env/bin/python" ]]; then
        echo "  $(basename "$env"): $($env/bin/python --version 2>&1)"
    fi
done

echo ""
echo "[check] 可用二进制:"
for bin in ollama llama-server llama-cli uv; do
    if [[ -x "$ENV_DIR/bin/$bin" ]]; then
        echo "  $bin: OK"
    else
        echo "  $bin: MISSING"
    fi
done

echo ""
echo "[check] 启动脚本:"
ls -1 "$ENV_DIR/scripts/"

echo ""
echo "============================================"
echo "检测完成"
echo "============================================"
