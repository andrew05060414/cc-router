#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# llm-env 导出脚本
# 把构建好的环境打包成可离线分发的压缩包。
# =============================================================================

LGSJ_ENV_DIR="${LGSJ_ENV_DIR:-$HOME/lgsj-llm-env}"
OUTPUT_DIR="${OUTPUT_DIR:-$HOME}"
OUTPUT_NAME="${OUTPUT_NAME:-lgsj-llm-env}"
DATE_TAG="$(date +%Y%m%d-%H%M%S)"
TARBALL="$OUTPUT_DIR/${OUTPUT_NAME}-${DATE_TAG}.tar.gz"

# 是否排除模型权重（减小体积）
EXCLUDE_MODELS="${EXCLUDE_MODELS:-false}"

if [[ ! -d "$LGSJ_ENV_DIR" ]]; then
    echo "[export] ERROR: 环境目录不存在: $LGSJ_ENV_DIR"
    echo "[export] 请先运行 build-llm-env.sh"
    exit 1
fi

echo "[export] 导出环境: $LGSJ_ENV_DIR"
echo "[export] 目标文件: $TARBALL"

# 计算压缩排除项
EXCLUDE_ARGS=()
if [[ "$EXCLUDE_MODELS" == "true" ]]; then
    echo "[export] 排除 models/ 目录"
    EXCLUDE_ARGS+=(--exclude="models")
fi

# 先清理一些不必要的文件
find "$LGSJ_ENV_DIR" -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
find "$LGSJ_ENV_DIR" -type d -name .git -prune -exec rm -rf {} + 2>/dev/null || true

# 打包
cd "$(dirname "$LGSJ_ENV_DIR")"
tar -czf "$TARBALL" \
    --exclude="*.tar.zst" \
    --exclude="*.tar.gz" \
    --exclude=".DS_Store" \
    "${EXCLUDE_ARGS[@]}" \
    "$(basename "$LGSJ_ENV_DIR")"

echo "[export] 完成: $TARBALL"
ls -lh "$TARBALL"

cat >"$OUTPUT_DIR/${OUTPUT_NAME}-${DATE_TAG}-load.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail

# 解压脚本
TARGET_DIR="\${1:-/opt/lgsj-llm-env}"
TARBALL="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)/$(basename "$TARBALL")

echo "解压到: \$TARGET_DIR"
mkdir -p "\$TARGET_DIR"
tar xzf "\$TARBALL" -C "\$TARGET_DIR" --strip-components=1

echo "解压完成"
echo "启动脚本在: \$TARGET_DIR/scripts/"
EOF
chmod +x "$OUTPUT_DIR/${OUTPUT_NAME}-${DATE_TAG}-load.sh"

echo "[export] 解压脚本: $OUTPUT_DIR/${OUTPUT_NAME}-${DATE_TAG}-load.sh"
