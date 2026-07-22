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

  # NixOS / 只读 global prefix fallback: install into ~/.local so binaries land
  # in ~/.local/bin instead of a read-only system path.
  user_prefix="${HOME}/.local"
  if [[ ! -w "$(npm prefix -g 2>/dev/null || echo /usr/local)" ]]; then
    echo "[remote] 检测到 npm global prefix 不可写，切换到用户目录: ${user_prefix}"
    export NPM_CONFIG_PREFIX="${user_prefix}"
    mkdir -p "${user_prefix}/bin"
  fi

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
  local alias="" ip="" user="$CC_REMOTE_ONBOARD_DEFAULT_USER" port="$CC_REMOTE_ONBOARD_DEFAULT_PORT"
  local password="" key="$CC_REMOTE_ONBOARD_DEFAULT_KEY"
  local do_seed=0 install_tailscale=0 tailscale_auth_key="" tailscale_hostname=""
  local install_node=-1 no_confirm=0 dry_run=0

  local first="${1:-}"
  case "$first" in
    help|-h|--help)
      ccr_remote_setup_show_help
      return 0
      ;;
    ""|-*) : ;;
    *)
      alias="$first"
      shift
      ;;
  esac

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ip) ip="$2"; shift 2 ;;
      --user) user="$2"; shift 2 ;;
      --password) password="$2"; shift 2 ;;
      --port) port="$2"; shift 2 ;;
      --key) key="$2"; shift 2 ;;
      --seed-ide) do_seed=1; shift ;;
      --tailscale-auth-key) tailscale_auth_key="$2"; install_tailscale=1; shift 2 ;;
      --tailscale-hostname) tailscale_hostname="$2"; shift 2 ;;
      --install-node) install_node=1; shift ;;
      --no-install-node) install_node=0; shift ;;
      --no-confirm) no_confirm=1; shift ;;
      --dry-run) dry_run=1; shift ;;
      -h|--help) ccr_remote_setup_show_help; return 0 ;;
      *)
        if [[ -z "$alias" && "$1" != -* ]]; then
          alias="$1"; shift
        else
          echo "ERROR: 未知选项: $1" >&2
          ccr_remote_setup_show_help >&2
          return 2
        fi
        ;;
    esac
  done

  # 1. alias
  if [[ -z "$alias" ]]; then
    if [[ "$no_confirm" -eq 1 ]]; then
      echo "ERROR: 非交互模式需要提供 alias" >&2
      return 1
    fi
    alias="$(ccr_remote_onboard_prompt "SSH alias (例如 nas-2b)")"
    [[ -n "$alias" ]] || ccr_remote_onboard_die "alias 不能为空"
  fi

  local target
  target="$(ccr_remote_ssh_target "$alias")"

  if [[ "$dry_run" -eq 1 ]]; then
    echo "[dry-run] 目标: $target"
  else
    echo "[cc-remote] 目标主机: $target"
  fi

  # 2. passwordless SSH probe
  if [[ "$dry_run" -eq 1 ]]; then
    echo "[dry-run] 将测试免密 SSH；失败时会提示上传公钥"
  elif ! ccr_remote_setup_test_ssh "$target"; then
    if [[ "$no_confirm" -eq 1 && -z "$password" ]]; then
      echo "ERROR: 免密 SSH 失败且非交互模式未提供 --password" >&2
      return 1
    fi
    if [[ -z "$ip" ]]; then
      ip="$(ccr_remote_onboard_prompt "IP address for ${alias}")"
      [[ -n "$ip" ]] || ccr_remote_onboard_die "IP 不能为空"
    fi
    if [[ -z "$password" ]]; then
      password="$(ccr_remote_onboard_prompt_secret "Password for ${user}@${ip}")"
      [[ -n "$password" ]] || ccr_remote_onboard_die "密码不能为空"
    fi
    if [[ "$no_confirm" -eq 0 ]]; then
      echo
      echo "即将为 ${alias} 配置免密 SSH:"
      echo "  host:     ${user}@${ip}:${port}"
      echo "  ssh key:  ${key}"
      local confirm
      read -r -p "确认? [Y/n]: " confirm
      [[ -z "$confirm" || "$confirm" == [yY] ]] || { echo "已取消"; return 1; }
    fi
    ccr_remote_onboard_do_onboard "$alias" "$ip" "$user" "$port" "$password" "$key" 0
    target="$(ccr_remote_ssh_target "$alias")"
  else
    ccr_remote_onboard_ok "免密 SSH 已可用: ${target}"
  fi

  # 3. OS detection
  local os arch libc is_nixos=0
  if [[ "$dry_run" -eq 0 ]]; then
    local os_info
    os_info="$(ccr_remote_ssh_exec "$target" "uname -s; uname -m; ldd --version 2>&1 | grep -qi musl && echo musl || echo gnu; test -f /etc/NIXOS && echo nixos || echo notnixos" 2>/dev/null)"
    os="$(sed -n '1p' <<<"$os_info")"
    arch="$(sed -n '2p' <<<"$os_info")"
    libc="$(sed -n '3p' <<<"$os_info")"
    [[ "$(sed -n '4p' <<<"$os_info")" == "nixos" ]] && is_nixos=1
    echo "[cc-remote] 远端 OS: ${os} ${arch} (${libc})"
    [[ "$is_nixos" -eq 1 ]] && ccr_remote_onboard_warn "检测到 NixOS"
  else
    os="Linux"; arch="x86_64"; libc="gnu"; is_nixos=0
  fi

  if [[ "$is_nixos" -eq 1 ]]; then
    echo
    echo "NixOS 无法自动安装某些组件。请选择:"
    echo "  1) 跳过 NixOS 不支持的步骤，继续其他配置"
    echo "  2) 中止并显示手动说明"
    local nix_choice="1"
    if [[ "$no_confirm" -eq 0 ]]; then
      nix_choice="$(ccr_remote_onboard_prompt "选择 [1/2]" "1")"
    fi
    if [[ "$nix_choice" == "2" ]]; then
      ccr_remote_setup_show_nixos_help
      return 1
    fi
  fi

  # 4. Node.js / npm
  local has_npm=0
  if [[ "$dry_run" -eq 0 ]] && ccr_remote_ssh_exec "$target" "command -v npm" >/dev/null 2>&1; then
    has_npm=1
  fi
  if [[ "$dry_run" -eq 1 ]]; then
    echo "[dry-run] 将检查远程 npm"
  elif [[ "$has_npm" -eq 0 ]]; then
    ccr_remote_onboard_warn "远程没有 npm"
    if [[ "$install_node" -eq -1 && "$is_nixos" -eq 0 ]]; then
      if ccr_remote_setup_read_yes_no "安装 Node.js/npm?"; then
        install_node=1
      else
        install_node=0
      fi
    fi
    if [[ "$install_node" -eq 1 ]]; then
      if [[ "$is_nixos" -eq 1 ]]; then
        ccr_remote_onboard_warn "NixOS 请手动安装: nix-shell -p nodejs"
      else
        local mirror
        mirror="$(ccr_remote_setup_probe_npm_mirror "$target")"
        ccr_remote_setup_install_nodejs "$target" "$mirror"
        has_npm=1
      fi
    fi
  fi

  # 5. Claude Code install
  if [[ "$dry_run" -eq 1 ]]; then
    echo "[dry-run] 将探测架构并安装 Claude Code"
  elif [[ "$has_npm" -eq 1 ]]; then
    local plat
    case "$arch" in
      aarch64|arm64) plat="linux-arm64" ;;
      *) plat="linux-x64" ;;
    esac
    [[ "$libc" == "musl" ]] && plat="${plat}-musl"

    local pack_dir
    pack_dir="$(ccr_remote_pack_dir)"
    if [[ ! -f "$pack_dir/anthropic-ai-claude-code-${plat}-"*.tgz ]]; then
      ccr_remote_onboard_info "本地没有 ${plat} 安装包，先执行 pack..."
      ccr_remote_pack --platforms "$plat"
    fi

    local remote_pack="/tmp/cc-router-remote-pack"
    ccr_remote_ssh_exec "$target" "rm -rf ${remote_pack} && mkdir -p ${remote_pack}"
    ccr_remote_scp_to "${pack_dir}/." "$target" "${remote_pack}/"
    ccr_remote_ssh_exec "$target" "bash ${remote_pack}/install-claude-remote.sh"
    ccr_remote_onboard_ok "Claude Code 安装完成"
  else
    ccr_remote_onboard_warn "跳过 Claude Code 安装（远程没有 npm 且未选择安装 Node.js）"
  fi

  # 6. Config sync
  if [[ "$dry_run" -eq 1 ]]; then
    echo "[dry-run] 将同步 settings.json / CLAUDE.md / skills"
  else
    ccr_remote_sync "$alias"
  fi

  # 7. Tailscale
  if [[ "$install_tailscale" -eq 0 && -z "$tailscale_auth_key" && "$no_confirm" -eq 0 && "$is_nixos" -eq 0 ]]; then
    if ccr_remote_setup_read_yes_no "安装 Tailscale?"; then
      install_tailscale=1
    fi
  fi
  if [[ "$install_tailscale" -eq 1 ]]; then
    if [[ -z "$tailscale_auth_key" && "$no_confirm" -eq 0 ]]; then
      tailscale_auth_key="$(ccr_remote_onboard_prompt_secret "Tailscale auth key")"
    fi
    [[ -n "$tailscale_auth_key" ]] || ccr_remote_onboard_die "缺少 --tailscale-auth-key"
    [[ -n "$tailscale_hostname" ]] || tailscale_hostname="$alias"
    if [[ "$dry_run" -eq 1 ]]; then
      echo "[dry-run] 将安装 Tailscale (hostname=${tailscale_hostname})"
    else
      ccr_remote_onboard_tailscale "$alias" "$tailscale_auth_key" "$tailscale_hostname" "$key" "$port"
    fi
  fi

  # 8. IDE seed
  if [[ "$do_seed" -eq 0 && "$no_confirm" -eq 0 ]]; then
    if ccr_remote_setup_read_yes_no "推送 Cursor/Warp IDE server 缓存?"; then
      do_seed=1
    fi
  fi
  if [[ "$do_seed" -eq 1 ]]; then
    if [[ "$dry_run" -eq 1 ]]; then
      echo "[dry-run] 将推送 Cursor/Warp IDE server 缓存"
    else
      ccr_remote_onboard_seed "$alias" "$key" 0
    fi
  fi

  # 9. Doctor
  if [[ "$dry_run" -eq 0 ]]; then
    echo
    ccr_remote_doctor "$alias"
  fi

  echo
  echo "[cc-remote] setup 完成: $alias"
  echo "  连接: ccr remote ssh $alias"
  echo "  同步: ccr remote sync $alias"
}

ccr_remote_setup_show_help() {
  cat <<'EOF'
ccr remote setup - Interactive all-in-one remote onboarding

Usage:
  ccr remote setup [alias] [options]

Interactive (default):
  ccr remote setup                    # prompts for alias, ip, user, password
  ccr remote setup nas-2b             # prompts for missing fields

Non-interactive:
  ccr remote setup nas-2b --ip 10.18.23.131 --user lgsj --password 'Lgsj@123.' --no-confirm

Options:
  --ip IP                  Server IP or hostname
  --user USER              SSH user (default: root)
  --password PASS          SSH password (used to upload pubkey if needed)
  --port PORT              SSH port (default: 22)
  --key PATH               SSH private key path (default: ~/.ssh/id_longgang)
  --seed-ide               Push Cursor/Warp IDE server cache
  --tailscale-auth-key KEY Install Tailscale with this auth key
  --tailscale-hostname NAME Tailscale hostname (default: alias)
  --install-node           Install Node.js/npm if missing
  --no-install-node        Skip Node.js/npm installation
  --no-confirm             Run without prompting (requires all required flags)
  --dry-run                Print steps without executing
  -h, --help               Show this help

Environment:
  CC_REMOTE_ONBOARD_DEFAULT_KEY    default SSH key
  CC_REMOTE_ONBOARD_DEFAULT_USER   default user
  CC_REMOTE_ONBOARD_DEFAULT_PORT   default port
EOF
}

ccr_remote_setup_show_nixos_help() {
  cat <<'EOF'
NixOS 手动配置提示:

1. Node.js:
   nix-shell -p nodejs

2. Tailscale (在 /etc/nixos/configuration.nix 的 services 块里添加):
   services.tailscale.enable = true;
   services.tailscale.authKeyFile = /etc/nixos/tailscale-auth-key;
   services.tailscale.extraUpFlags = [ "--hostname=<NAME>" "--accept-routes" "--ssh" ];

3. Claude Code:
   运行 `ccr remote setup <alias> --install-node` 不可行，因为 NixOS 没有传统包管理器。
   建议先用 nix-shell 提供 nodejs/npm，再运行 `ccr remote setup <alias>`。
EOF
}

ccr_remote_setup_test_ssh() {
  local target="$1"
  ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$target" 'echo OK' >/dev/null 2>&1
}

ccr_remote_setup_read_yes_no() {
  local prompt="$1" default_no="${2:-1}" ans
  if [[ ! -t 0 ]] || [[ "${CC_ROUTER_NO_INSTALL_PROMPT:-}" == "1" ]]; then
    return 1
  fi
  if [[ "$default_no" -eq 1 ]]; then
    read -r -p "$prompt [y/N]: " ans </dev/tty 2>/dev/null || return 1
  else
    read -r -p "$prompt [Y/n]: " ans </dev/tty 2>/dev/null || return 1
  fi
  ans="$(ccr_trim "$ans")"
  ccr_truthy "$ans"
}

ccr_remote_setup_probe_npm_mirror() {
  local target="$1"
  local mirrors=(
    "https://registry.npmjs.org/"
    "https://registry.npmmirror.com/"
    "https://registry.yarnpkg.com/"
  )
  local best="" best_time=999
  local url start end elapsed
  ccr_remote_onboard_info "测试 npm registry 速度..."
  for url in "${mirrors[@]}"; do
    start="$(date +%s.%N)"
    if ccr_remote_ssh_exec "$target" "curl -fsS --max-time 5 -o /dev/null '$url'" >/dev/null 2>&1; then
      end="$(date +%s.%N)"
      elapsed="$(awk "BEGIN {print $end - $start}")"
      ccr_remote_onboard_info "  $url: ${elapsed}s"
      if awk "BEGIN {exit !($elapsed < $best_time)}"; then
        best_time="$elapsed"
        best="$url"
      fi
    else
      ccr_remote_onboard_warn "  $url: 不可达"
    fi
  done
  if [[ -z "$best" ]]; then
    best="https://registry.npmjs.org/"
    ccr_remote_onboard_warn "没有可访问的 mirror，回退到 $best"
  else
    ccr_remote_onboard_ok "使用 npm registry: $best"
  fi
  printf '%s\n' "$best"
}

ccr_remote_setup_install_nodejs() {
  local target="$1" mirror="${2:-https://registry.npmjs.org/}"
  ccr_remote_onboard_info "[$target] 安装 Node.js/npm..."

  # Set npm registry for future npm commands
  if [[ -n "$mirror" ]]; then
    ccr_remote_ssh_exec "$target" "npm config set registry '$mirror'" 2>/dev/null || true
  fi

  if ccr_remote_ssh_exec "$target" "command -v apt-get" >/dev/null 2>&1; then
    ccr_remote_ssh_exec "$target" "apt-get update -qq && apt-get install -y -qq curl ca-certificates gnupg"
    ccr_remote_ssh_exec "$target" "curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && apt-get install -y -qq nodejs"
  elif ccr_remote_ssh_exec "$target" "command -v yum" >/dev/null 2>&1; then
    ccr_remote_ssh_exec "$target" "yum install -y curl && curl -fsSL https://rpm.nodesource.com/setup_22.x | bash - && yum install -y nodejs"
  elif ccr_remote_ssh_exec "$target" "command -v dnf" >/dev/null 2>&1; then
    ccr_remote_ssh_exec "$target" "dnf install -y curl && curl -fsSL https://rpm.nodesource.com/setup_22.x | bash - && dnf install -y nodejs"
  elif ccr_remote_ssh_exec "$target" "command -v apk" >/dev/null 2>&1; then
    ccr_remote_ssh_exec "$target" "apk add --no-cache nodejs npm curl"
  else
    ccr_remote_onboard_warn "未知包管理器，尝试 nvm"
    ccr_remote_ssh_exec "$target" "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash"
    ccr_remote_ssh_exec "$target" 'export NVM_DIR="$HOME/.nvm" && [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" && nvm install 22 && nvm use 22 && nvm alias default 22'
  fi
  ccr_remote_onboard_ok "Node.js 安装完成"
}

ccr_remote_setup_cleanup() {
  local alias="$1"
  shift
  ccr_remote_onboard_cmd_cleanup "$alias" "$@"
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
# ccr remote setup - interactive SSH onboarding for lab/remote machines
# Standalone; does not depend on batch-ssh-onboard skill.

set -euo pipefail

# ------------------------------- defaults -------------------------------------

CC_REMOTE_ONBOARD_DEFAULT_KEY="${CC_REMOTE_ONBOARD_DEFAULT_KEY:-${HOME}/.ssh/id_longgang}"
CC_REMOTE_ONBOARD_DEFAULT_USER="${CC_REMOTE_ONBOARD_DEFAULT_USER:-root}"
CC_REMOTE_ONBOARD_DEFAULT_PORT="${CC_REMOTE_ONBOARD_DEFAULT_PORT:-22}"
CC_REMOTE_ONBOARD_SSH_CONFIG="${HOME}/.ssh/config"
CC_REMOTE_ONBOARD_IDE_CACHE="${CC_REMOTE_ONBOARD_IDE_CACHE:-${HOME}/.cache/cc-onboard-ide}"
CC_REMOTE_ONBOARD_CURSOR_PRODUCT="/Applications/Cursor.app/Contents/Resources/app/product.json"
CC_REMOTE_ONBOARD_WARP_TARBALLS="${HOME}/Library/Application Support/dev.warp.Warp-Stable/remote-server/tarballs"

# ------------------------------- ui helpers -----------------------------------

ccr_remote_onboard_info()  { printf '\033[1;34m→\033[0m %s\n' "$*" >&2; }
ccr_remote_onboard_ok()    { printf '\033[1;32m✓\033[0m %s\n' "$*" >&2; }
ccr_remote_onboard_warn()  { printf '\033[1;33m!\033[0m %s\n' "$*" >&2; }
ccr_remote_onboard_die()   { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

ccr_remote_onboard_need() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || ccr_remote_onboard_die "缺少命令: $c"
  done
}

ccr_remote_onboard_ensure_key() {
  local key="$1"
  if [[ -f "$key" && -f "${key}.pub" ]]; then
    printf '%s\n' "$key"
    return 0
  fi
  ccr_remote_onboard_info "生成 SSH key: $key"
  mkdir -p "$(dirname "$key")"
  ssh-keygen -t ed25519 -C "cc-onboard-$(whoami)" -f "$key" -N ""
  ccr_remote_onboard_ok "密钥已生成: $key"
  printf '%s\n' "$key"
}

ccr_remote_onboard_expand_key() {
  local k="$1"
  [[ "$k" == "~/"* ]] && k="${HOME}/${k#~/}"
  printf '%s\n' "$k"
}

ccr_remote_onboard_cursor_commit() {
  [[ -f "$CC_REMOTE_ONBOARD_CURSOR_PRODUCT" ]] || return 1
  python3 -c "import json; print(json.load(open('$CC_REMOTE_ONBOARD_CURSOR_PRODUCT'))['commit'])" 2>/dev/null
}

ccr_remote_onboard_ssh_target() {
  local alias="$1" user="$2" host="$3" port="$4"
  printf '%s@%s -p %s' "$user" "$host" "$port"
}

ccr_remote_onboard_ssh_cmd() {
  local key="$1"
  shift
  ssh -i "$key" -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$@"
}

# ------------------------------- interactive ----------------------------------

ccr_remote_onboard_prompt() {
  local prompt="$1" default="${2:-}"
  local value
  if [[ -n "$default" ]]; then
    read -r -p "${prompt} [${default}]: " value
    value="${value:-$default}"
  else
    read -r -p "${prompt}: " value
  fi
  printf '%s\n' "$value"
}

ccr_remote_onboard_prompt_secret() {
  local prompt="$1"
  local value
  read -r -s -p "${prompt}: " value
  echo >&2
  printf '%s\n' "$value"
}

# ------------------------------- config ---------------------------------------

ccr_remote_onboard_write_ssh_config() {
  local alias="$1" ip="$2" user="$3" port="$4" key="$5"
  mkdir -p "$(dirname "$CC_REMOTE_ONBOARD_SSH_CONFIG")"
  touch "$CC_REMOTE_ONBOARD_SSH_CONFIG"
  chmod 600 "$CC_REMOTE_ONBOARD_SSH_CONFIG"

  # Remove existing block for this alias
  if grep -q "^Host ${alias}$" "$CC_REMOTE_ONBOARD_SSH_CONFIG" 2>/dev/null; then
    local tmp
    tmp="$(mktemp)"
    awk -v a="$alias" '$0 ~ "^Host " a "$" {skip=1; next} skip && /^Host / {skip=0} !skip {print}' \
      "$CC_REMOTE_ONBOARD_SSH_CONFIG" > "$tmp" && mv "$tmp" "$CC_REMOTE_ONBOARD_SSH_CONFIG"
  fi

  cat >> "$CC_REMOTE_ONBOARD_SSH_CONFIG" <<EOF

# ccr remote setup: ${alias}
Host ${alias}
  HostName ${ip}
  User ${user}
  Port ${port}
  IdentityFile ${key}
  IdentitiesOnly yes
  AddKeysToAgent yes
  UseKeychain yes
  ServerAliveInterval 20
  ServerAliveCountMax 6
EOF
}

# ------------------------------- onboard core ---------------------------------

ccr_remote_onboard_do_onboard() {
  local alias="$1" ip="$2" user="$3" port="$4" password="$5" key="$6" do_seed="$7"

  key="$(ccr_remote_onboard_expand_key "$key")"
  key="$(ccr_remote_onboard_ensure_key "$key")"
  local pub="${key}.pub"

  ccr_remote_onboard_need ssh scp sshpass

  local target
  target="$(ccr_remote_onboard_ssh_target "$alias" "$user" "$ip" "$port")"

  ccr_remote_onboard_info "[$alias] 上传公钥到 ${user}@${ip}:${port}"
  SSHPASS="$password" sshpass -e ssh -p "$port" -o StrictHostKeyChecking=accept-new \
    "${user}@${ip}" 'mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys'

  SSHPASS="$password" sshpass -e scp -P "$port" "$pub" "${user}@${ip}:/tmp/cc_onboard_pubkey.tmp"
  SSHPASS="$password" sshpass -e ssh -p "$port" "${user}@${ip}" \
    'grep -qxF -f /tmp/cc_onboard_pubkey.tmp ~/.ssh/authorized_keys 2>/dev/null || cat /tmp/cc_onboard_pubkey.tmp >> ~/.ssh/authorized_keys; rm -f /tmp/cc_onboard_pubkey.tmp'
  ccr_remote_onboard_ok "公钥已写入 authorized_keys"

  ccr_remote_onboard_info "[$alias] 写入 ~/.ssh/config"
  ccr_remote_onboard_write_ssh_config "$alias" "$ip" "$user" "$port" "$key"
  ccr_remote_onboard_ok "SSH config 已更新"

  ccr_remote_onboard_info "[$alias] 验证免密登录"
  if ! ccr_remote_onboard_ssh_cmd "$key" -p "$port" "${user}@${ip}" 'echo OK && hostname && whoami'; then
    ccr_remote_onboard_die "免密登录验证失败"
  fi
  ccr_remote_onboard_ok "SSH 免密可用: ssh ${alias}"

  if [[ "$do_seed" == "1" ]]; then
    ccr_remote_onboard_seed "$alias" "$key"
  fi
}

# ------------------------------- seed ide -------------------------------------

ccr_remote_onboard_cursor_extracted_ok() {
  local extracted="$1"
  [[ -x "${extracted}/node" ]] || [[ -x "${extracted}/bin/remote-cli/cursor" ]]
}

ccr_remote_onboard_download_cursor_cdn() {
  local commit="$1"
  local tarball="${CC_REMOTE_ONBOARD_IDE_CACHE}/cursor/${commit}/vscode-reh-linux-x64.tar.gz"
  local extracted="${CC_REMOTE_ONBOARD_IDE_CACHE}/cursor/${commit}/extracted"
  local url="https://cursor.blob.core.windows.net/remote-releases/${commit}/vscode-reh-linux-x64.tar.gz"
  local only

  ccr_remote_onboard_need curl tar
  mkdir -p "${CC_REMOTE_ONBOARD_IDE_CACHE}/cursor/${commit}"
  ccr_remote_onboard_info "CDN 下载 Cursor server ${commit}..."
  curl -fL --retry 3 --retry-delay 2 -o "${tarball}.partial" "$url"
  mv "${tarball}.partial" "$tarball"
  rm -rf "$extracted"
  mkdir -p "$extracted"
  tar -xzf "$tarball" -C "$extracted"
  if [[ "$(find "$extracted" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" -eq 1 ]]; then
    only="$(find "$extracted" -mindepth 1 -maxdepth 1 -type d | head -1)"
    if [[ -n "$only" ]]; then
      shopt -s dotglob nullglob
      mv "$only"/* "$extracted"/
      shopt -u dotglob nullglob
      rmdir "$only" 2>/dev/null || true
    fi
  fi
  ccr_remote_onboard_ok "Cursor ${commit} 下载完成"
}

ccr_remote_onboard_ensure_cursor_local() {
  local allow_cdn="${1:-0}"
  local commit
  commit="$(ccr_remote_onboard_cursor_commit)" || ccr_remote_onboard_die "找不到 Cursor product.json"
  local extracted="${CC_REMOTE_ONBOARD_IDE_CACHE}/cursor/${commit}/extracted"

  if ccr_remote_onboard_cursor_extracted_ok "$extracted"; then
    ccr_remote_onboard_ok "本机已有 Cursor ${commit}"
    printf '%s\n' "$commit"
    return 0
  fi

  if [[ "$allow_cdn" == "1" ]]; then
    ccr_remote_onboard_download_cursor_cdn "$commit"
    printf '%s\n' "$commit"
    return 0
  fi

  ccr_remote_onboard_die "本机缺少 Cursor server ${commit}。\n  可选: 1) 先让本机 Remote-SSH 连一次目标自动下载; 2) 用 --cdn 允许公网下载"
}

ccr_remote_onboard_ensure_warp_local() {
  local latest version tgz extracted

  [[ -d "$CC_REMOTE_ONBOARD_WARP_TARBALLS" ]] || return 1
  latest="$(find "$CC_REMOTE_ONBOARD_WARP_TARBALLS" -maxdepth 1 -type d -name 'v*' | sort | tail -1)"
  [[ -n "$latest" ]] || return 1
  version="$(basename "$latest")"
  tgz="${latest}/linux-x86_64/oz.tar.gz"
  [[ -f "$tgz" ]] || return 1

  extracted="${CC_REMOTE_ONBOARD_IDE_CACHE}/warp/${version}"
  mkdir -p "$extracted"
  if [[ -e "${extracted}/.ready" ]]; then
    ccr_remote_onboard_ok "本机已有 Warp ${version}"
  else
    ccr_remote_onboard_info "解压 Warp ${version}..."
    tar -xzf "$tgz" -C "$extracted"
    if [[ -f "${extracted}/oz" && ! -e "${extracted}/oz-${version}" ]]; then
      mv "${extracted}/oz" "${extracted}/oz-${version}"
    fi
    touch "${extracted}/.ready"
    ccr_remote_onboard_ok "Warp ${version} 解压完成"
  fi
  printf '%s\n' "$extracted"
}

ccr_remote_onboard_seed() {
  local alias="$1"
  local key="${2:-$CC_REMOTE_ONBOARD_DEFAULT_KEY}"
  local allow_cdn="${3:-0}"
  key="$(ccr_remote_onboard_expand_key "$key")"

  ccr_remote_onboard_need ssh rsync

  local commit
  commit="$(ccr_remote_onboard_ensure_cursor_local "$allow_cdn")"

  ccr_remote_onboard_info "[$alias] 推送 Cursor server ${commit}"
  ssh -i "$key" -o IdentitiesOnly=yes "$alias" \
    "mkdir -p ~/.cursor-server/bin/linux-x64/${commit}"
  rsync -av --progress \
    -e "ssh -i ${key} -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new" \
    "${CC_REMOTE_ONBOARD_IDE_CACHE}/cursor/${commit}/extracted/" \
    "${alias}:~/.cursor-server/bin/linux-x64/${commit}/"
  ccr_remote_onboard_ok "Cursor -> ${alias}:~/.cursor-server/bin/linux-x64/${commit}/"

  local warp_path
  if warp_path="$(ccr_remote_onboard_ensure_warp_local 2>/dev/null)"; then
    ccr_remote_onboard_info "[$alias] 推送 Warp remote-server"
    ssh -i "$key" -o IdentitiesOnly=yes "$alias" 'mkdir -p ~/.warp/remote-server'
    rsync -av --progress \
      -e "ssh -i ${key} -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new" \
      --exclude '.ready' \
      "${warp_path}/" \
      "${alias}:~/.warp/remote-server/"
    ccr_remote_onboard_ok "Warp 已推送"
  fi
}

# ------------------------------- tailscale ------------------------------------

ccr_remote_onboard_tailscale() {
  local alias="$1" auth_key="$2" hostname="${3:-$1}"
  local key="${4:-$CC_REMOTE_ONBOARD_DEFAULT_KEY}"
  local port="${5:-$CC_REMOTE_ONBOARD_DEFAULT_PORT}"
  key="$(ccr_remote_onboard_expand_key "$key")"

  [[ -n "$auth_key" ]] || ccr_remote_onboard_die "缺少 --auth-key"
  ccr_remote_onboard_need ssh scp

  # Detect NixOS: it cannot use curl|sh and needs configuration.nix
  local is_nixos=0
  if ssh -i "$key" -o IdentitiesOnly=yes -o BatchMode=yes -p "$port" "$alias" \
       'test -f /etc/NIXOS' 2>/dev/null; then
    is_nixos=1
  fi

  if [[ "$is_nixos" -eq 1 ]]; then
    ccr_remote_onboard_warn "[$alias] 检测到 NixOS，不能直接 curl|sh 安装 Tailscale。"
    cat <<EOF

请在远程主机上执行以下操作：

1. 把 auth key 写入文件：
   sudo mkdir -p /etc/nixos
   echo '${auth_key}' | sudo tee /etc/nixos/tailscale-auth-key
   sudo chmod 600 /etc/nixos/tailscale-auth-key

2. 编辑 /etc/nixos/configuration.nix，在 services 块里添加：

  services.tailscale = {
    enable = true;
    authKeyFile = "/etc/nixos/tailscale-auth-key";
    extraUpFlags = [
      "--hostname=${hostname}"
      "--accept-routes"
      "--ssh"
    ];
  };

  # 如果希望作为 exit node，再加上：
  # "--advertise-exit-node"

3. 应用配置：
   sudo nixos-rebuild switch

4. （可选）如果用了 --advertise-exit-node，去 Tailscale Admin 控制台 approve。

EOF
    return 1
  fi

  ccr_remote_onboard_info "[$alias] 安装 Tailscale..."
  ssh -i "$key" -o IdentitiesOnly=yes -p "$port" "$alias" \
    'curl -fsSL https://tailscale.com/install.sh | sh'

  ccr_remote_onboard_info "[$alias] 加入 tailnet (hostname=${hostname})"
  ssh -i "$key" -o IdentitiesOnly=yes -p "$port" "$alias" \
    "tailscale up --auth-key=${auth_key} --hostname=${hostname} --accept-routes --ssh"
  ssh -i "$key" -o IdentitiesOnly=yes -p "$port" "$alias" 'tailscale status'
  ccr_remote_onboard_ok "Tailscale 就绪"
}

# ------------------------------- cleanup --------------------------------------

ccr_remote_onboard_cleanup() {
  local alias="$1" ip="${2:-}"
  local key="${3:-$CC_REMOTE_ONBOARD_DEFAULT_KEY}"
  local port="${4:-$CC_REMOTE_ONBOARD_DEFAULT_PORT}"
  key="$(ccr_remote_onboard_expand_key "$key")"

  ccr_remote_onboard_need ssh

  ccr_remote_onboard_info "[$alias] 远程清理"
  ssh -i "$key" -o IdentitiesOnly=yes -p "$port" "$alias" bash -s <<'REMOTE'
set -e
tailscale logout 2>/dev/null || true
systemctl stop tailscaled 2>/dev/null || true
systemctl disable tailscaled 2>/dev/null || true
apt-get purge -y tailscale tailscale-archive-keyring 2>/dev/null || true
rm -rf /var/lib/tailscale /var/log/tailscale*
if [[ -f ~/.ssh/authorized_keys ]]; then
  grep -v 'cc-onboard' ~/.ssh/authorized_keys > /tmp/cc_onboard_ak || true
  mv /tmp/cc_onboard_ak ~/.ssh/authorized_keys
  chmod 600 ~/.ssh/authorized_keys
fi
rm -rf ~/.cursor-server ~/.warp ~/.config/warp-terminal
echo "REMOTE CLEANUP DONE"
REMOTE
  ccr_remote_onboard_ok "远程清理完成"

  ccr_remote_onboard_info "[$alias] 本机清理 ~/.ssh/config"
  if [[ -f "$CC_REMOTE_ONBOARD_SSH_CONFIG" ]]; then
    local tmp
    tmp="$(mktemp)"
    awk -v a="$alias" '
      $0 ~ "^# ccr remote setup: " a "$" {skip=1; next}
      $0 ~ "^Host " a "$" {skip=1; next}
      skip && /^$/ {skip=0; next}
      skip && /^Host / {skip=0}
      !skip {print}
    ' "$CC_REMOTE_ONBOARD_SSH_CONFIG" > "$tmp" && mv "$tmp" "$CC_REMOTE_ONBOARD_SSH_CONFIG"
  fi
  [[ -n "$ip" ]] && ssh-keygen -R "$ip" 2>/dev/null || true
  ssh-keygen -R "$alias" 2>/dev/null || true
  ccr_remote_onboard_ok "本机 config / known_hosts 已清理"
}

