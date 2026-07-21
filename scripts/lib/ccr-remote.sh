# ccr remote shared helpers

# ------------------------------- 路径 -----------------------------------------

ccr_remote_pack_dir() {
  printf '%s\n' "${CC_REMOTE_PACK_DIR:-${HOME}/.local/share/cc-router/remote-pack}"
}

ccr_remote_settings_local_file() {
  printf '%s\n' "${HOME}/.claude/settings.json"
}

ccr_remote_claude_md_local_file() {
  printf '%s\n' "${HOME}/.claude/CLAUDE.md"
}

ccr_remote_ssh_config_file() {
  printf '%s\n' "${HOME}/.ssh/config"
}

ccr_remote_resolve_host() {
  local input="$1"
  # 如果 input 已经是 host 格式（含 @ 或 .），直接返回
  if [[ "$input" == *@* || "$input" == *.* ]]; then
    printf '%s\n' "$input"
    return 0
  fi

  # 否则尝试从 ssh config 解析 HostName
  local ssh_config
  ssh_config="$(ccr_remote_ssh_config_file)"
  if [[ -f "$ssh_config" ]]; then
    local hostname
    hostname="$(awk -v alias="$input" '
      $1 == "Host" { current = $2 }
      current == alias && $1 == "HostName" { print $2; exit }
    ' "$ssh_config")"
    if [[ -n "$hostname" ]]; then
      printf '%s\n' "$hostname"
      return 0
    fi
  fi

  printf '%s\n' "$input"
}

ccr_remote_resolve_user() {
  local input="$1"
  if [[ "$input" == *@* ]]; then
    printf '%s\n' "${input%%@*}"
    return 0
  fi

  local ssh_config
  ssh_config="$(ccr_remote_ssh_config_file)"
  if [[ -f "$ssh_config" ]]; then
    local user
    user="$(awk -v alias="$input" '
      $1 == "Host" { current = $2 }
      current == alias && $1 == "User" { print $2; exit }
    ' "$ssh_config")"
    if [[ -n "$user" ]]; then
      printf '%s\n' "$user"
      return 0
    fi
  fi

  printf '%s\n' "${USER:-root}"
}

ccr_remote_ssh_target() {
  local input="$1"
  local host user
  host="$(ccr_remote_resolve_host "$input")"
  user="$(ccr_remote_resolve_user "$input")"
  printf '%s@%s\n' "$user" "$host"
}

# ------------------------------- SSH 执行 -------------------------------------

ccr_remote_ssh_exec() {
  local target="$1"
  shift
  ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new "$target" "$@"
}

ccr_remote_scp_to() {
  local src="$1"
  local target="$2"
  local remote_dest="$3"
  scp -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -r "$src" "$target:$remote_dest"
}

# ------------------------------- 打包 Claude Code 安装包 ----------------------

ccr_remote_pack() {
  local pack_dir
  pack_dir="$(ccr_remote_pack_dir)"
  mkdir -p "$pack_dir"

  # 解析参数
  local platforms="linux-x64,linux-arm64,linux-x64-musl,linux-arm64-musl"
  local skip_download=false
  while (($# > 0)); do
    case "$1" in
      --platforms)
        platforms="$2"
        shift 2
        ;;
      --skip-download)
        skip_download=true
        shift
        ;;
      *)
        echo "WARN: 未知参数: $1" >&2
        shift
        ;;
    esac
  done

  echo "[cc-remote] 打包目录: $pack_dir"
  echo "[cc-remote] 目标平台: $platforms"

  # 1. 下载 Claude Code npm 包（主包 + 平台 native 包）
  if [[ "$skip_download" == "true" ]]; then
    echo "[cc-remote] 跳过下载，使用已有安装包"
  else
    echo "[cc-remote] 预下载 Claude Code npm 包..."
    cd "$pack_dir"
    rm -f anthropic-ai-claude-code-*.tgz

    # 主包装器
    npm pack @anthropic-ai/claude-code

    # 平台 native 包
    local platform
    for platform in ${platforms//,/ }; do
      case "$platform" in
        linux-x64|linux-arm64|linux-x64-musl|linux-arm64-musl|win32-x64|win32-arm64|darwin-arm64|darwin-x64)
          npm pack "@anthropic-ai/claude-code-${platform}"
          ;;
        *)
          echo "WARN: 未知平台: $platform" >&2
          ;;
      esac
    done
  fi

  local main_tgz
  main_tgz="$(ls -t "$pack_dir"/anthropic-ai-claude-code-*.tgz 2>/dev/null | grep -E 'anthropic-ai-claude-code-[0-9]+\.[0-9]+\.[0-9]+\.tgz$' | head -1)"
  if [[ -z "$main_tgz" ]]; then
    echo "ERROR: Claude Code npm 主包不存在" >&2
    exit 1
  fi
  echo "[cc-remote] 主包: $(basename "$main_tgz")"

  # 2. 生成远程版 settings.json
  ccr_remote_config_generate_silent "$pack_dir/settings.json"

  # 3. 复制 CLAUDE.md
  local claude_md
  claude_md="$(ccr_remote_claude_md_local_file)"
  if [[ -f "$claude_md" ]]; then
    cp "$claude_md" "$pack_dir/CLAUDE.md"
    echo "[cc-remote] 已复制 CLAUDE.md"
  fi

  # 4. 复制选中的技能包
  ccr_remote_skills_pack "$pack_dir/skills"

  # 5. 生成远程安装脚本
  ccr_remote_generate_install_script "$pack_dir"

  echo "[cc-remote] 打包完成"
  echo "  位置: $pack_dir"
  ls -lh "$pack_dir"
}

ccr_remote_generate_install_script() {
  local pack_dir="$1"
  cat >"$pack_dir/install-claude-remote.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

PACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${HOME}/.claude"

mkdir -p "$CLAUDE_DIR"

echo "[remote] 安装 Claude Code..."
if command -v npm >/dev/null 2>&1; then
  # cd 到 PACK_DIR，确保相对 glob 能匹配到本目录的 .tgz
  cd "$PACK_DIR"

  # 主包（版本号文件名，如 anthropic-ai-claude-code-2.1.216.tgz）
  main_tgz="$(ls -t anthropic-ai-claude-code-[0-9]*.tgz 2>/dev/null | head -1)"
  if [[ -z "$main_tgz" ]]; then
    echo "ERROR: 找不到 Claude Code 主包 (anthropic-ai-claude-code-<version>.tgz)" >&2
    exit 1
  fi

  # 只装当前平台的 native 包，避免把 4 个平台 (~300MB) 全装上
  arch="$(uname -m)"
  libc="gnu"
  if ldd --version 2>&1 | grep -qi musl; then libc="musl"; fi
  case "$arch" in
    x86_64|amd64) plat="linux-x64" ;;
    aarch64|arm64) plat="linux-arm64" ;;
    *) plat="" ;;
  esac
  native_tgz=""
  if [[ -n "$plat" ]]; then
    if [[ "$libc" == "musl" ]]; then
      native_tgz="$(ls -t anthropic-ai-claude-code-${plat}-musl-[0-9]*.tgz 2>/dev/null | head -1)"
    else
      native_tgz="$(ls -t anthropic-ai-claude-code-${plat}-[0-9]*.tgz 2>/dev/null | head -1)"
    fi
  fi

  pkgs=("$main_tgz")
  [[ -n "$native_tgz" ]] && pkgs+=("$native_tgz")
  echo "[remote] 安装包: ${pkgs[*]}"
  npm install -g "${pkgs[@]}"
else
  echo "ERROR: 远程系统没有 npm，请先安装 Node.js" >&2
  exit 1
fi

echo "[remote] 安装路径:"
which claude || true
claude --version || true

echo "[remote] 写入 settings.json..."
if [[ -f "${PACK_DIR}/settings.json" ]]; then
  cp "${PACK_DIR}/settings.json" "${CLAUDE_DIR}/settings.json"
fi

echo "[remote] 写入 CLAUDE.md..."
if [[ -f "${PACK_DIR}/CLAUDE.md" ]]; then
  cp "${PACK_DIR}/CLAUDE.md" "${CLAUDE_DIR}/CLAUDE.md"
fi

echo "[remote] 写入技能包..."
if [[ -d "${PACK_DIR}/skills" ]]; then
  mkdir -p "${CLAUDE_DIR}/skills"
  cp -r "${PACK_DIR}/skills/"* "${CLAUDE_DIR}/skills/" 2>/dev/null || true
fi

echo "[remote] 写入环境变量到 ~/.profile..."
if ! grep -q "CLAUDE_CODE_DISABLE_TELEMETRY" "${HOME}/.profile" 2>/dev/null; then
  cat >>"${HOME}/.profile" <<'ENV_EOF'

# cc-remote: Claude Code telemetry opt-out
export CLAUDE_CODE_DISABLE_TELEMETRY=1
export ANTHROPIC_DISABLE_TELEMETRY=1
export DISABLE_AUTOUPDATER=1
ENV_EOF
fi

echo "[remote] Claude Code 安装完成"
EOF
  chmod +x "$pack_dir/install-claude-remote.sh"
}

# ------------------------------- 远程 ccr 自身安装 -------------------------------

ccr_remote_install_repo_dir() {
  printf '%s\n' "${CC_REMOTE_INSTALL_REPO_DIR:-${HOME}/.local/share/cc-router/install-repo}"
}

ccr_remote_probe_speed() {
  local target="$1"
  local url="$2"
  local start end elapsed
  start="$(date +%s.%N)"
  if ccr_remote_ssh_exec "$target" "curl -fsS --max-time 8 -o /dev/null '$url'" \>\>/dev/null 2\>\&1; then
    end="$(date +%s.%N)"
    elapsed="$(awk "BEGIN {print $end - $start}")"
    printf '%s\n' "$elapsed"
    return 0
  fi
  return 1
}

ccr_remote_install() {
  local input="" verbose=0 dry_run=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -v|--verbose)
        verbose=1
        shift
        ;;
      -n|--dry-run)
        dry_run=1
        shift
        ;;
      -h|--help)
        cat <<'EOF'
ccr remote install - Install ccr itself on a remote host via SSH

Usage:
  ccr remote install [-v|--verbose] [-n|--dry-run] <host|alias>

Examples:
  ccr remote install Nas-2b
  ccr remote install --verbose Nas-2b
  ccr remote install --dry-run Nas-2b
EOF
        return 0
        ;;
      -*)
        echo "ERROR: 未知选项: $1" >&2
        echo "用法: ccr remote install [-v|--verbose] [-n|--dry-run] <host|alias>" >&2
        return 2
        ;;
      *)
        if [[ -z "$input" ]]; then
          input="$1"
          shift
        else
          echo "ERROR: 只能指定一个主机参数" >&2
          return 2
        fi
        ;;
    esac
  done

  if [[ -z "$input" ]]; then
    echo "ERROR: 请指定远程主机或 SSH 别名" >&2
    echo "用法: ccr remote install [-v|--verbose] [-n|--dry-run] <host|alias>" >&2
    return 1
  fi

  if [[ "$verbose" -eq 1 ]]; then
    export CCR_VERBOSE=1
  fi

  local target
  target="$(ccr_remote_ssh_target "$input")"
  local install_dir="/tmp/cc-router-install"
  local repo_url="${CC_REMOTE_INSTALL_URL:-}"

  if [[ "$dry_run" -eq 1 ]]; then
    echo "[ccr remote install --dry-run] 目标主机: $target"
    local local_repo="${CC_ROUTER_REPO_DIR:-}"
    if [[ -z "$local_repo" ]]; then
      local_repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    fi
    echo "[ccr remote install --dry-run] 本地仓库路径: $local_repo"
    echo "[ccr remote install --dry-run] 远端安装目录: $install_dir"
    if [[ -n "$repo_url" ]]; then
      echo "[ccr remote install --dry-run] 探测远端网络速度: $repo_url"
      echo "[ccr remote install --dry-run] 若速度 < 4s 则使用 curl 直接下载，否则 SSH 推送"
    else
      echo "[ccr remote install --dry-run] 无 CC_REMOTE_INSTALL_URL，将通过 SSH 推送本地仓库"
    fi
    echo "[ccr remote install --dry-run] 将要执行的 SSH 命令:"
    echo "  ssh $target 'rm -rf $install_dir && mkdir -p $install_dir'"
    echo "  tar -czf - --exclude='.git' --exclude='.codegraph' --exclude='remote-pack' -C \"$local_repo\" . | ssh $target 'tar -xzf - -C $install_dir'"
    echo "  ssh $target 'bash $install_dir/install.sh'"
    echo "[ccr remote install --dry-run] 结束（未执行任何操作）"
    return 0
  fi

  echo "[ccr remote install] 目标主机: $target"

  # If a public URL is configured, probe whether the remote can fetch it quickly.
  local use_curl=false
  if [[ -n "$repo_url" ]]; then
    local elapsed
    echo "[ccr remote install] 探测远端网络速度 ($repo_url)..."
    if elapsed="$(ccr_remote_probe_speed "$target" "$repo_url")"; then
      # If download finishes in under 4 seconds, let remote fetch directly.
      if awk "BEGIN {exit !($elapsed < 4.0)}"; then
        use_curl=true
      fi
    fi
  fi

  if [[ "$use_curl" == "true" ]]; then
    echo "[ccr remote install] 远端网络良好，使用 curl 直接下载..."
    ccr_remote_ssh_exec "$target" "
      set -e
      rm -rf ${install_dir}
      mkdir -p ${install_dir}
      curl -fsSL '$repo_url' -o ${install_dir}/cc-router.tar.gz
      tar -xzf ${install_dir}/cc-router.tar.gz -C ${install_dir} --strip-components=1
      bash ${install_dir}/install.sh
    "
  else
    echo "[ccr remote install] 使用 SSH 推送本地仓库..."
    local local_repo="${CC_ROUTER_REPO_DIR:-}"
    if [[ -z "$local_repo" ]]; then
      local_repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    fi

    if [[ -n "${CCR_VERBOSE:-}" ]]; then
      echo "[ccr remote install] 本地仓库路径: $local_repo"
      echo "[ccr remote install] 远端安装目录: $install_dir"
      echo "[ccr remote install] tar 命令: tar -czf - --exclude='.git' --exclude='.codegraph' --exclude='remote-pack' -C \"$local_repo\" ."
    fi

    ccr_remote_ssh_exec "$target" "rm -rf ${install_dir} && mkdir -p ${install_dir}"
    # Exclude git history and pack files to keep the transfer small.
    tar -czf - \
      --exclude='.git' \
      --exclude='.codegraph' \
      --exclude='remote-pack' \
      -C "$local_repo" . \
      | ccr_remote_ssh_exec "$target" "tar -xzf - -C ${install_dir}"

    echo "[ccr remote install] 在远端运行 install.sh..."
    ccr_remote_ssh_exec "$target" "bash ${install_dir}/install.sh"
  fi

  echo "[ccr remote install] 完成: $target"
  echo "[ccr remote install] 远端现在可用: ccr remote setup $input"
}

# ------------------------------- 远程安装 -------------------------------------

# Upload the current repo (scripts/) to a remote host so `ccr` there is up to date.
# Does not reinstall or touch the remote PATH.
ccr_remote_push() {
  local input="$1"
  local target
  target="$(ccr_remote_ssh_target "$input")"
  local install_dir="/tmp/cc-router-install"
  local local_repo="${CC_ROUTER_REPO_DIR:-}"
  if [[ -z "$local_repo" ]]; then
    local_repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  fi

  echo "[ccr remote push] 目标主机: $target"
  ccr_remote_ssh_exec "$target" "rm -rf ${install_dir} && mkdir -p ${install_dir}"
  tar -czf - \
    --exclude='.git' \
    --exclude='.codegraph' \
    --exclude='remote-pack' \
    -C "$local_repo" . \
    | ccr_remote_ssh_exec "$target" "tar -xzf - -C ${install_dir}"

  ccr_remote_ssh_exec "$target" "
    set -e
    cp -r ${install_dir}/scripts/lib/ ~/.local/share/cc-router/lib/
    cp ${install_dir}/scripts/ccr ~/.local/bin/ccr
    cp ${install_dir}/templates/remote/* ~/.local/share/cc-router/templates/remote/
    echo 'push done'
  "
  echo "[ccr remote push] 完成: $target"
}

ccr_remote_setup() {
  local input="$1"
  local target
  target="$(ccr_remote_ssh_target "$input")"

  echo "[cc-remote] 目标主机: $target"

  # 确保本机已打包（按远端架构只打包对应平台，避免每次下载 ~300MB 全平台）
  local pack_dir
  pack_dir="$(ccr_remote_pack_dir)"
  local remote_plat
  remote_plat="$(ccr_remote_ssh_exec "$target" 'uname -m; ldd --version 2>&1 | grep -qi musl && echo musl || echo gnu' 2>/dev/null | tr '\n' ' ')"
  local arch libc plat
  arch="$(awk '{print $1}' <<<"$remote_plat")"
  libc="$(awk '{print $2}' <<<"$remote_plat")"
  case "$arch" in
    aarch64|arm64) plat="linux-arm64" ;;
    *) plat="linux-x64" ;;
  esac
  [[ "$libc" == "musl" ]] && plat="${plat}-musl"
  if [[ ! -f "$pack_dir/anthropic-ai-claude-code-${plat}-"*.tgz ]]; then
    echo "[cc-remote] 本地没有 ${plat} 安装包，先执行 pack --platforms ${plat}..."
    ccr_remote_pack --platforms "$plat"
  fi

  # 上传到远程（用 "$pack_dir/." 拷贝目录内容，避免 scp -r 把目录本身嵌套成 remote-pack/remote-pack/）
  local remote_pack="/tmp/cc-router-remote-pack"
  echo "[cc-remote] 上传安装包到 ${target}:${remote_pack}..."
  ccr_remote_ssh_exec "$target" "rm -rf ${remote_pack} && mkdir -p ${remote_pack}"
  ccr_remote_scp_to "${pack_dir}/." "$target" "${remote_pack}/"

  # 远程执行安装
  echo "[cc-remote] 远程执行安装..."
  ccr_remote_ssh_exec "$target" "bash ${remote_pack}/install-claude-remote.sh"

  echo "[cc-remote] 安装完成: $target"
  echo "[cc-remote] 运行 'cc-remote ssh $input' 连接"
}

ccr_remote_sync() {
  local input="$1"
  local target
  target="$(ccr_remote_ssh_target "$input")"

  echo "[cc-remote] 同步配置到: $target"

  local pack_dir
  pack_dir="$(ccr_remote_pack_dir)"

  # 重新生成 settings.json
  ccr_remote_config_generate_silent "$pack_dir/settings.json"

  # 重新复制 CLAUDE.md
  local claude_md
  claude_md="$(ccr_remote_claude_md_local_file)"
  if [[ -f "$claude_md" ]]; then
    cp "$claude_md" "$pack_dir/CLAUDE.md"
  fi

  # 重新打包技能
  ccr_remote_skills_pack "$pack_dir/skills"

  # 上传到远程
  local remote_pack="/tmp/cc-router-remote-pack"
  ccr_remote_ssh_exec "$target" "mkdir -p ${remote_pack}"
  ccr_remote_scp_to "$pack_dir/settings.json" "$target" "${remote_pack}/"
  if [[ -f "$pack_dir/CLAUDE.md" ]]; then
    ccr_remote_scp_to "$pack_dir/CLAUDE.md" "$target" "${remote_pack}/"
  fi
  if [[ -d "$pack_dir/skills" ]]; then
    ccr_remote_ssh_exec "$target" "rm -rf ${remote_pack}/skills"
    ccr_remote_scp_to "$pack_dir/skills" "$target" "${remote_pack}/"
  fi

  # 远程应用
  ccr_remote_ssh_exec "$target" "
    mkdir -p ~/.claude
    cp ${remote_pack}/settings.json ~/.claude/settings.json 2>/dev/null || true
    cp ${remote_pack}/CLAUDE.md ~/.claude/CLAUDE.md 2>/dev/null || true
    if [[ -d ${remote_pack}/skills ]]; then
      mkdir -p ~/.claude/skills
      cp -r ${remote_pack}/skills/* ~/.claude/skills/ 2>/dev/null || true
    fi
    echo 'sync done'
  "

  echo "[cc-remote] 同步完成: $target"
}

ccr_remote_ssh() {
  local input="$1"
  shift
  local target
  target="$(ccr_remote_ssh_target "$input")"

  echo "[cc-remote] 连接 $target 并启动 Claude Code..."

  local claude_args=()
  local project_dir=""
  if (($# > 0)); then
    project_dir="$1"
    shift
    claude_args=("$@")
  fi

  # 如果传了项目目录，先 cd 过去再启动 claude
  if [[ -n "$project_dir" ]]; then
    exec ssh -t "$target" "cd '$project_dir' && exec claude $(printf '%q ' "${claude_args[@]}")"
  else
    exec ssh -t "$target" "exec claude $(printf '%q ' "${claude_args[@]}")"
  fi
}

ccr_remote_doctor() {
  local input="$1"
  local target
  target="$(ccr_remote_ssh_target "$input")"

  echo "[cc-remote] 检查远程环境: $target"
  ccr_remote_ssh_exec "$target" "
    echo '--- OS ---'; uname -a
    echo '--- Node ---'; command -v node && node --version || echo 'node not found'
    echo '--- npm ---'; command -v npm && npm --version || echo 'npm not found'
    echo '--- Claude ---'; command -v claude && claude --version || echo 'claude not found'
    echo '--- Settings ---'; ls -la ~/.claude/settings.json 2>/dev/null || echo 'no settings.json'
    echo '--- CLAUDE.md ---'; ls -la ~/.claude/CLAUDE.md 2>/dev/null || echo 'no CLAUDE.md'
    echo '--- Skills ---'; ls -la ~/.claude/skills/ 2>/dev/null | head -20 || echo 'no skills'
    echo '--- Telemetry env ---'; env | grep -E 'TELEMETRY|AUTOUPDATER' || echo 'no telemetry env'
  "
}
