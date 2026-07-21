#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# llm-env 构建脚本
# 在一台能联网的机器上运行，生成可离线分发的 AI 推理环境包。
# =============================================================================

# ------------------------------- 配置区 ---------------------------------------

# 环境根目录
LGSJ_ENV_DIR="${LGSJ_ENV_DIR:-$HOME/lgsj-llm-env}"

# Python 版本
PYTHON_VERSION="${PYTHON_VERSION:-3.11}"

# 组件版本（latest 表示最新）
VLLM_VERSION="${VLLM_VERSION:-latest}"
SGLANG_VERSION="${SGLANG_VERSION:-latest}"
TORCH_VERSION="${TORCH_VERSION:-latest}"
OLLAMA_VERSION="${OLLAMA_VERSION:-0.32.1}"
LLAMACPP_VERSION="${LLAMACPP_VERSION:-latest}"

# 是否使用国内镜像
USE_CHINA_MIRROR="${USE_CHINA_MIRROR:-true}"

# 是否编译 llama.cpp（需要 CUDA toolkit）
BUILD_LLAMACPP="${BUILD_LLAMACPP:-true}"

# 是否下载 Ollama
BUILD_OLLAMA="${BUILD_OLLAMA:-true}"

# 预下载的 HuggingFace 模型（空格分隔）
# 例如：PRELOAD_MODELS="meta-llama/Llama-2-7b-chat-hf Qwen/Qwen2-7B-Instruct"
PRELOAD_MODELS="${PRELOAD_MODELS:-}"

# 是否安装 evalscope 等测试工具
INSTALL_EVAL_TOOLS="${INSTALL_EVAL_TOOLS:-true}"

# ------------------------------- 目录定义 -------------------------------------

BIN_DIR="$LGSJ_ENV_DIR/bin"
ENVS_DIR="$LGSJ_ENV_DIR/envs"
SRC_DIR="$LGSJ_ENV_DIR/src"
MODELS_DIR="$LGSJ_ENV_DIR/models"
CACHE_DIR="$LGSJ_ENV_DIR/cache"
PIP_CACHE_DIR="$CACHE_DIR/pip"
HF_CACHE_DIR="$CACHE_DIR/huggingface"
UV_CACHE_DIR="$CACHE_DIR/uv"
OLLAMA_DIR="$LGSJ_ENV_DIR/ollama"
SCRIPTS_DIR="$LGSJ_ENV_DIR/scripts"

mkdir -p "$BIN_DIR" "$ENVS_DIR" "$SRC_DIR" "$MODELS_DIR" "$CACHE_DIR" \
         "$PIP_CACHE_DIR" "$HF_CACHE_DIR" "$UV_CACHE_DIR" "$OLLAMA_DIR" "$SCRIPTS_DIR"

# ------------------------------- 镜像配置 -------------------------------------

setup_mirrors() {
    if [[ "$USE_CHINA_MIRROR" == "true" ]]; then
        echo "[llm-env] 启用国内镜像源"
        export UV_INDEX_URL="https://pypi.tuna.tsinghua.edu.cn/simple"
        export PIP_INDEX_URL="https://pypi.tuna.tsinghua.edu.cn/simple"
        export PIP_TRUSTED_HOST="pypi.tuna.tsinghua.edu.cn"
        export HF_ENDPOINT="https://hf-mirror.com"
    else
        export UV_INDEX_URL="https://pypi.org/simple"
        export PIP_INDEX_URL="https://pypi.org/simple"
        export HF_ENDPOINT="https://huggingface.co"
    fi

    export UV_CACHE_DIR="$UV_CACHE_DIR"
    export PIP_CACHE_DIR="$PIP_CACHE_DIR"
    export HF_HOME="$HF_CACHE_DIR"
    export HUGGINGFACE_HUB_CACHE="$HF_CACHE_DIR/hub"
}

# ------------------------------- 工具安装 -------------------------------------

install_uv() {
    echo "[llm-env] 检查 uv..."
    if [[ -f "$BIN_DIR/uv" ]]; then
        echo "[llm-env] uv 已存在，跳过安装"
        return
    fi

    echo "[llm-env] 下载 uv..."
    curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR="$BIN_DIR" sh

    if [[ ! -f "$BIN_DIR/uv" ]]; then
        echo "[llm-env] ERROR: uv 安装失败"
        exit 1
    fi
}

# ------------------------------- Python 环境 ----------------------------------

create_vllm_env() {
    echo "[llm-env] 创建 vLLM/SGLang 环境..."
    local env_dir="$ENVS_DIR/vllm"

    if [[ -d "$env_dir" ]]; then
        echo "[llm-env] 环境已存在: $env_dir"
        return
    fi

    "$BIN_DIR/uv" venv "$env_dir" --python "$PYTHON_VERSION"

    local torch_spec="torch"
    local vllm_spec="vllm"
    local sglang_spec="sglang[all]"

    if [[ "$TORCH_VERSION" != "latest" ]]; then
        torch_spec="torch==$TORCH_VERSION"
    fi
    if [[ "$VLLM_VERSION" != "latest" ]]; then
        vllm_spec="vllm==$VLLM_VERSION"
    fi
    if [[ "$SGLANG_VERSION" != "latest" ]]; then
        sglang_spec="sglang[all]==$SGLANG_VERSION"
    fi

    echo "[llm-env] 安装 PyTorch..."
    "$BIN_DIR/uv" pip install --python "$env_dir/bin/python" "$torch_spec" torchvision torchaudio

    echo "[llm-env] 安装 vLLM..."
    "$BIN_DIR/uv" pip install --python "$env_dir/bin/python" "$vllm_spec"

    echo "[llm-env] 安装 SGLang..."
    "$BIN_DIR/uv" pip install --python "$env_dir/bin/python" "$sglang_spec" || {
        echo "[llm-env] WARN: SGLang 安装失败，可能和 vLLM 的 torch 版本冲突，请检查版本。"
    }

    echo "[llm-env] 安装常用工具包..."
    "$BIN_DIR/uv" pip install --python "$env_dir/bin/python" \
        transformers accelerate fastapi uvicorn openai requests

    if [[ "$INSTALL_EVAL_TOOLS" == "true" ]]; then
        echo "[llm-env] 安装测试工具..."
        "$BIN_DIR/uv" pip install --python "$env_dir/bin/python" \
            evalscope datasets numpy pandas scipy
    fi
}

create_llamacpp_env() {
    echo "[llm-env] 创建 llama.cpp 编译环境..."
    local env_dir="$ENVS_DIR/llamacpp"

    if [[ -d "$env_dir" ]]; then
        echo "[llm-env] 环境已存在: $env_dir"
        return
    fi

    "$BIN_DIR/uv" venv "$env_dir" --python "$PYTHON_VERSION"
    "$BIN_DIR/uv" pip install --python "$env_dir/bin/python" numpy sentencepiece
}

# ------------------------------- Ollama ---------------------------------------

install_ollama() {
    if [[ "$BUILD_OLLAMA" != "true" ]]; then
        echo "[llm-env] 跳过 Ollama"
        return
    fi

    echo "[llm-env] 下载 Ollama $OLLAMA_VERSION..."
    local tar_file="$OLLAMA_DIR/ollama-linux-amd64.tar.zst"

    if [[ -f "$tar_file" ]]; then
        echo "[llm-env] Ollama 压缩包已存在，跳过下载"
    else
        local url="https://github.com/ollama/ollama/releases/download/v${OLLAMA_VERSION}/ollama-linux-amd64.tar.zst"
        curl -L -k -o "$tar_file" "$url" || wget --no-check-certificate -O "$tar_file" "$url"
    fi

    echo "[llm-env] 解压 Ollama..."
    rm -rf "$OLLAMA_DIR/extracted"
    mkdir -p "$OLLAMA_DIR/extracted"
    tar --zstd -xf "$tar_file" -C "$OLLAMA_DIR/extracted"

    # 创建统一入口
    ln -sf "$OLLAMA_DIR/extracted/bin/ollama" "$BIN_DIR/ollama"

    echo "[llm-env] Ollama 版本:"
    "$BIN_DIR/ollama" --version || true
}

# ------------------------------- llama.cpp ------------------------------------

install_llamacpp() {
    if [[ "$BUILD_LLAMACPP" != "true" ]]; then
        echo "[llm-env] 跳过 llama.cpp"
        return
    fi

    echo "[llm-env] 获取 llama.cpp..."
    local repo_dir="$SRC_DIR/llama.cpp"

    if [[ -d "$repo_dir/.git" ]]; then
        echo "[llm-env] llama.cpp 已存在，拉取更新..."
        cd "$repo_dir"
        git fetch --tags
        if [[ "$LLAMACPP_VERSION" == "latest" ]]; then
            git checkout master
            git pull
        else
            git checkout "tags/$LLAMACPP_VERSION" -b "build-$LLAMACPP_VERSION" || true
        fi
    else
        echo "[llm-env] 克隆 llama.cpp..."
        rm -rf "$repo_dir"
        git clone --depth 1 --recursive https://github.com/ggerganov/llama.cpp "$repo_dir"
        cd "$repo_dir"
        if [[ "$LLAMACPP_VERSION" != "latest" ]]; then
            git fetch --tags
            git checkout "tags/$LLAMACPP_VERSION"
            git submodule update --init --recursive
        fi
    fi

    echo "[llm-env] 编译 llama.cpp (CUDA)..."
    cmake -B build -DGGML_CUDA=ON
    cmake --build build --config Release -j$(nproc)

    # 链接二进制到 bin 目录
    ln -sf "$repo_dir/build/bin/llama-server" "$BIN_DIR/llama-server"
    ln -sf "$repo_dir/build/bin/llama-cli" "$BIN_DIR/llama-cli"
    ln -sf "$repo_dir/build/bin/llama-bench" "$BIN_DIR/llama-bench"

    echo "[llm-env] llama.cpp 编译完成:"
    "$BIN_DIR/llama-server" --version || true
}

# ------------------------------- 预下载模型 -----------------------------------

preload_models() {
    if [[ -z "$PRELOAD_MODELS" ]]; then
        echo "[llm-env] 没有配置预下载模型"
        return
    fi

    echo "[llm-env] 预下载 HuggingFace 模型..."
    local env_dir="$ENVS_DIR/vllm"

    for model in $PRELOAD_MODELS; do
        echo "[llm-env] 下载模型: $model"
        "$env_dir/bin/python" - <<PY
from huggingface_hub import snapshot_download
snapshot_download("$model", cache_dir="$HUGGINGFACE_HUB_CACHE")
PY
    done
}

# ------------------------------- 启动脚本生成 ---------------------------------

generate_scripts() {
    echo "[llm-env] 生成启动脚本..."

    cat > "$SCRIPTS_DIR/start-vllm.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$(dirname "$SCRIPT_DIR")"

export PATH="$ENV_DIR/bin:$PATH"
export VIRTUAL_ENV="$ENV_DIR/envs/vllm"
export UV_CACHE_DIR="$ENV_DIR/cache/uv"
export HF_HOME="$ENV_DIR/cache/huggingface"
export HUGGINGFACE_HUB_CACHE="$HF_HOME/hub"
export HF_ENDPOINT="https://hf-mirror.com"

MODEL="${1:-}"
HOST="${2:-0.0.0.0}"
PORT="${3:-8000}"

if [[ -z "$MODEL" ]]; then
    echo "用法: $0 <model_path_or_hf_id> [host] [port]"
    echo "示例: $0 /opt/lgsj-llm-env/models/Llama-2-7b-chat-hf"
    exit 1
fi

echo "启动 vLLM: $MODEL @ $HOST:$PORT"
"$VIRTUAL_ENV/bin/python" -m vllm.entrypoints.openai.api_server \
    --model "$MODEL" \
    --host "$HOST" \
    --port "$PORT" \
    --trust-remote-code
EOF
    chmod +x "$SCRIPTS_DIR/start-vllm.sh"

    cat > "$SCRIPTS_DIR/start-sglang.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$(dirname "$SCRIPT_DIR")"

export PATH="$ENV_DIR/bin:$PATH"
export VIRTUAL_ENV="$ENV_DIR/envs/vllm"
export UV_CACHE_DIR="$ENV_DIR/cache/uv"
export HF_HOME="$ENV_DIR/cache/huggingface"
export HUGGINGFACE_HUB_CACHE="$HF_HOME/hub"
export HF_ENDPOINT="https://hf-mirror.com"

MODEL="${1:-}"
HOST="${2:-0.0.0.0}"
PORT="${3:-30000}"

if [[ -z "$MODEL" ]]; then
    echo "用法: $0 <model_path_or_hf_id> [host] [port]"
    exit 1
fi

echo "启动 SGLang: $MODEL @ $HOST:$PORT"
"$VIRTUAL_ENV/bin/python" -m sglang.launch_server \
    --model-path "$MODEL" \
    --host "$HOST" \
    --port "$PORT"
EOF
    chmod +x "$SCRIPTS_DIR/start-sglang.sh"

    cat > "$SCRIPTS_DIR/start-ollama.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$(dirname "$SCRIPT_DIR")"

export PATH="$ENV_DIR/bin:$PATH"
export OLLAMA_HOST="${OLLAMA_HOST:-0.0.0.0:11434}"
export OLLAMA_MODELS="${OLLAMA_MODELS:-$ENV_DIR/models/ollama}"

mkdir -p "$OLLAMA_MODELS"

echo "启动 Ollama @ $OLLAMA_HOST"
nohup ollama serve > "$ENV_DIR/ollama.log" 2>&1 &
sleep 2
ollama list || true
echo "Ollama 已启动"
EOF
    chmod +x "$SCRIPTS_DIR/start-ollama.sh"

    cat > "$SCRIPTS_DIR/start-llamacpp.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$(dirname "$SCRIPT_DIR")"

export PATH="$ENV_DIR/bin:$PATH"

MODEL="${1:-}"
HOST="${2:-0.0.0.0}"
PORT="${3:-8080}"
N_GPU_LAYERS="${N_GPU_LAYERS:-999}"

if [[ -z "$MODEL" ]]; then
    echo "用法: $0 <gguf_model_path> [host] [port] [n_gpu_layers]"
    echo "示例: $0 /opt/lgsj-llm-env/models/llama-2-7b.Q4_K_M.gguf"
    exit 1
fi

echo "启动 llama.cpp server: $MODEL @ $HOST:$PORT"
llama-server \
    -m "$MODEL" \
    --host "$HOST" \
    --port "$PORT" \
    -ngl "$N_GPU_LAYERS" \
    --chat-template llama-2
EOF
    chmod +x "$SCRIPTS_DIR/start-llamacpp.sh"
}

# ------------------------------- 元信息 ---------------------------------------

generate_metadata() {
    cat > "$LGSJ_ENV_DIR/metadata.json" <<EOF
{
  "created_at": "$(date -Iseconds)",
  "python_version": "$PYTHON_VERSION",
  "vllm_version": "$VLLM_VERSION",
  "sglang_version": "$SGLANG_VERSION",
  "torch_version": "$TORCH_VERSION",
  "ollama_version": "$OLLAMA_VERSION",
  "llamacpp_version": "$LLAMACPP_VERSION",
  "use_china_mirror": $USE_CHINA_MIRROR,
  "preload_models": "${PRELOAD_MODELS:-}",
  "cuda_version": "$(nvcc --version 2>/dev/null | grep release | head -1 || echo 'not detected')"
}
EOF
}

# ------------------------------- 主流程 ---------------------------------------

main() {
    echo "============================================"
    echo "llm-env 构建开始"
    echo "目标目录: $LGSJ_ENV_DIR"
    echo "============================================"

    setup_mirrors
    install_uv
    create_vllm_env
    create_llamacpp_env
    install_ollama
    install_llamacpp
    preload_models
    generate_scripts
    generate_metadata

    echo "============================================"
    echo "llm-env 构建完成"
    echo "下一步: 运行 ./export-llm-env.sh 导出压缩包"
    echo "============================================"
}

main "$@"
