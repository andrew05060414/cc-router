# llm-env

为 Linux AI 推理测试构建可离线分发的 Python 环境包，支持 Ollama、llama.cpp、vLLM、SGLang。

## 用途

- 在一台能联网的机器上一次性下载好所有依赖和模型。
- 用 `uv` 创建隔离的 Python 虚拟环境。
- 导出压缩包，拷贝到内网/慢网测试机后解压即用。
- 避免在每台测试机上重复下载 PyTorch、CUDA 工具链、大模型权重。

## 快速开始

```bash
# 1. 构建环境（在能联网的机器上执行）
./.claude/skills/llm-env/scripts/build-llm-env.sh

# 2. 导出压缩包
./.claude/skills/llm-env/scripts/export-llm-env.sh

# 3. 拷贝到目标机器，解压
mkdir -p /opt/lgsj-llm-env
tar xzf lgsj-llm-env.tar.gz -C /opt/lgsj-llm-env --strip-components=1

# 4. 启动服务
/opt/lgsj-llm-env/scripts/start-vllm.sh /path/to/model
/opt/lgsj-llm-env/scripts/start-sglang.sh /path/to/model
/opt/lgsj-llm-env/scripts/start-ollama.sh
```

## 生成的目录结构

```
~/lgsj-llm-env/
├── bin/
│   ├── ollama                    # Ollama 官方二进制
│   └── uv                        # uv 工具
├── envs/
│   ├── vllm/                     # vLLM + SGLang + torch
│   └── llamacpp/                 # llama.cpp 编译与运行环境
├── src/
│   └── llama.cpp/                # llama.cpp 源码（可选）
├── models/                       # 预下载模型权重
├── cache/
│   ├── pip/                      # pip/uv 缓存
│   └── huggingface/              # HuggingFace 缓存
└── scripts/
    ├── build-llm-env.sh
    ├── export-llm-env.sh
    ├── start-vllm.sh
    ├── start-sglang.sh
    ├── start-ollama.sh
    └── start-llamacpp.sh
```

## 配置项

编辑 `scripts/build-llm-env.sh` 顶部的变量：

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `LGSJ_ENV_DIR` | `$HOME/lgsj-llm-env` | 环境根目录 |
| `PYTHON_VERSION` | `3.11` | uv 创建的 Python 版本 |
| `VLLM_VERSION` | `latest` | vLLM 版本，可指定 `0.5.5` |
| `SGLANG_VERSION` | `latest` | SGLang 版本 |
| `TORCH_VERSION` | `latest` | PyTorch 版本 |
| `OLLAMA_VERSION` | `0.32.1` | Ollama 版本 |
| `LLAMACPP_VERSION` | `latest` | llama.cpp 的 git tag |
| `USE_CHINA_MIRROR` | `true` | 是否使用清华/阿里镜像 |
| `PRELOAD_MODELS` | 空 | 预下载的 HuggingFace 模型列表 |

## 支持的组件

- **Ollama**：下载官方 `ollama-linux-amd64.tar.zst` 并解压到 `bin/ollama`。
- **llama.cpp**：从 GitHub 克隆并编译 CUDA 版本，生成 `bin/llama-server`、`bin/llama-cli`。
- **vLLM**：uv 虚拟环境安装 `vllm` + 配套 torch。
- **SGLang**：与 vLLM 共享虚拟环境安装，若版本冲突可拆分为独立环境。

## 网络优化

脚本默认启用：

- pip/uv 清华镜像
- HuggingFace `hf-mirror.com`
- apt 阿里云镜像（可选，需要 sudo）

## 离线使用

导出压缩包后，目标机器不需要联网。启动脚本会：

1. 自动使用本地 uv 缓存
2. 使用本地 HuggingFace 缓存
3. 加载本地 Ollama 和 llama.cpp 二进制

## 后续升级

修改 `build-llm-env.sh` 中的版本号，重新运行构建和导出即可。已有模型权重不会重复下载。
