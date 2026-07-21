#!/usr/bin/env bash
# =============================================================================
# lab.sh — 测试机接入 / 交付（对应 RUNBOOK.md）
#
# 一条命令干一件事，子命令名和 RUNBOOK 章节一致：
#   onboard   §1  密码 → 公钥 + 写 ~/.ssh/config
#   seed      §2  donor机 → 本机缓存 → 目标机（CDN 仅 --cdn）
#   tailscale §3  安装并加入 tailnet
#   cleanup   §4  交付前清理（远程 + 本机 config）
#
# 示例：
#   ./lab.sh seed     --pull --from H100-1
#   ./lab.sh seed     --alias AMD370-Dual-Channel
#   ./lab.sh seed     --alias AMD370-Dual-Channel --all-cached
#   ./lab.sh onboard  --alias X --ip IP --password P --seed-ide
#   ./lab.sh tailscale --alias H100-3 --auth-key 'tskey-auth-xxxx'
#   ./lab.sh cleanup  --alias H100-3 --ip 221.182.146.99
#
# Agent：在 repo 根或本 skill 目录执行
#   .agents/skills/batch-ssh-onboard/scripts/lab.sh <子命令> [选项]
# =============================================================================

set -Eeuo pipefail

# ── 默认值（和 RUNBOOK 一致）────────────────────────────────────────────────
DEFAULT_KEY="${HOME}/.ssh/id_longgang"
DEFAULT_USER="root"
DEFAULT_PORT="22"
SSH_CONFIG="${HOME}/.ssh/config"
CURSOR_PRODUCT="/Applications/Cursor.app/Contents/Resources/app/product.json"
# 本机 IDE 缓存；优先从 donor 拉（内网），CDN 仅 --cdn
IDE_CACHE="${LAB_IDE_CACHE:-$HOME/.cache/lab-ide}"
DEFAULT_DONORS="${LAB_IDE_DONORS:-H100-1 H100-2}"
WARP_TARBALLS="${HOME}/Library/Application Support/dev.warp.Warp-Stable/remote-server/tarballs"

# ── 小工具 ───────────────────────────────────────────────────────────────────
info()  { printf '\033[1;34m→\033[0m %s\n' "$*" >&2; }
ok()    { printf '\033[1;32m✓\033[0m %s\n' "$*" >&2; }
die()   { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

need() {
  for c in "$@"; do
    command -v "$c" >/dev/null || die "缺少命令: $c （见 RUNBOOK §0）"
  done
}

expand_key() {
  local k="$1"
  [[ "$k" == "~/"* ]] && k="${HOME}/${k#~/}"
  printf '%s' "$k"
}

cursor_commit() {
  [[ -f "$CURSOR_PRODUCT" ]] || die "找不到 Cursor: $CURSOR_PRODUCT"
  python3 -c "import json; print(json.load(open('$CURSOR_PRODUCT'))['commit'])"
}

# IDE helpers: local cache + donor pull (CDN optional)
cursor_extracted_ok() {
  local extracted="$1"
  [[ -x "${extracted}/node" ]] || [[ -x "${extracted}/bin/remote-cli/cursor" ]]
}

ssh_e_for() {
  local key="$1"
  printf 'ssh -i %s -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=accept-new' "$key"
}

pull_cursor_commit_from_host() {
  local host="$1" commit="$2" key="$3"
  local extracted="${IDE_CACHE}/cursor/${commit}/extracted"
  local ssh_e
  ssh_e="$(ssh_e_for "$key")"

  if ! ssh -i "$key" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=8 "$host" \
      "test -x ~/.cursor-server/bin/linux-x64/${commit}/node" 2>/dev/null; then
    return 1
  fi

  info "从 ${host} 拉取 Cursor ${commit}"
  mkdir -p "$extracted"
  rsync -av --progress -e "$ssh_e" \
    "${host}:~/.cursor-server/bin/linux-x64/${commit}/" \
    "${extracted}/"
  if ! cursor_extracted_ok "$extracted"; then
    rm -rf "$extracted"
    return 1
  fi
  ok "已缓存 ${commit} <- ${host}"
  return 0
}

pull_all_from_host() {
  local host="$1" key="$2"
  local ssh_e commits c
  ssh_e="$(ssh_e_for "$key")"

  info "枚举 ${host} 上的 Cursor commits..."
  commits="$(ssh -i "$key" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=15 "$host" \
    'ls -1 ~/.cursor-server/bin/linux-x64/ 2>/dev/null' || true)"
  if [[ -z "$commits" ]]; then
    info "${host} 上没有 ~/.cursor-server/bin/linux-x64/"
  else
    while IFS= read -r c; do
      [[ -z "$c" ]] && continue
      if cursor_extracted_ok "${IDE_CACHE}/cursor/${c}/extracted"; then
        ok "本机已有 ${c}，跳过"
        continue
      fi
      pull_cursor_commit_from_host "$host" "$c" "$key" || info "跳过 ${c}"
    done <<< "$commits"
  fi

  info "从 ${host} 拉取 Warp remote-server（若有）"
  if ssh -i "$key" -o IdentitiesOnly=yes -o BatchMode=yes "$host" \
      'test -d ~/.warp/remote-server' 2>/dev/null; then
    mkdir -p "${IDE_CACHE}/warp/from-${host}"
    rsync -av --progress -e "$ssh_e" \
      "${host}:~/.warp/remote-server/" \
      "${IDE_CACHE}/warp/from-${host}/"
    touch "${IDE_CACHE}/warp/from-${host}/.ready"
    ok "Warp <- ${host}"
  else
    info "${host} 无 Warp remote-server"
  fi
}

download_cursor_cdn() {
  local commit="$1"
  local tarball="${IDE_CACHE}/cursor/${commit}/vscode-reh-linux-x64.tar.gz"
  local extracted="${IDE_CACHE}/cursor/${commit}/extracted"
  local url="https://cursor.blob.core.windows.net/remote-releases/${commit}/vscode-reh-linux-x64.tar.gz"
  local only

  need curl tar
  mkdir -p "${IDE_CACHE}/cursor/${commit}"
  info "CDN 下载（可能很慢）-> $tarball"
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
  ok "CDN 解压完成"
}

ensure_cursor_local() {
  local force="${1:-0}" allow_cdn="${2:-0}" key="${3:-$DEFAULT_KEY}" donors="${4:-$DEFAULT_DONORS}"
  local commit extracted host

  key="$(expand_key "$key")"
  commit="$(cursor_commit)"
  extracted="${IDE_CACHE}/cursor/${commit}/extracted"

  if [[ "$force" -eq 1 ]]; then
    info "强制刷新本机缓存: $commit"
    rm -rf "${IDE_CACHE}/cursor/${commit}"
  fi

  if cursor_extracted_ok "$extracted"; then
    ok "本机已有 Cursor $commit"
    printf '%s\n' "$commit"
    return 0
  fi

  info "本机缺少 $commit，尝试从 donor 拉取: $donors"
  for host in $donors; do
    if pull_cursor_commit_from_host "$host" "$commit" "$key"; then
      printf '%s\n' "$commit"
      return 0
    fi
    info "donor ${host} 无此 commit"
  done

  if [[ "$allow_cdn" -eq 1 ]]; then
    download_cursor_cdn "$commit"
    printf '%s\n' "$commit"
    return 0
  fi

  die "本机与 donors（$donors）都没有 Cursor commit $commit。
  1) Cursor 连一次 H100-1 让它下到 donor，再: ./lab.sh seed --pull --from H100-1
  2) 慢速 CDN: ./lab.sh seed --alias TARGET --cdn
  3) 先灌 donor 已有版本: ./lab.sh seed --pull --from H100-1 && ./lab.sh seed --alias TARGET --all-cached"
}

ensure_warp_local() {
  local force="${1:-0}"
  local latest version tgz extracted from_dir

  from_dir="$(find "${IDE_CACHE}/warp" -maxdepth 1 -type d -name 'from-*' 2>/dev/null | head -1 || true)"
  if [[ -n "$from_dir" && -e "${from_dir}/.ready" && "$force" -ne 1 ]]; then
    ok "使用已拉取的 Warp: $from_dir"
    printf '%s\n' "$from_dir"
    return 0
  fi

  [[ -d "$WARP_TARBALLS" ]] || {
    if [[ -n "$from_dir" && -e "${from_dir}/.ready" ]]; then
      printf '%s\n' "$from_dir"
      return 0
    fi
    info "本机无 Warp tarballs，跳过 Warp"
    return 1
  }

  latest="$(find "$WARP_TARBALLS" -maxdepth 1 -type d -name 'v*' | sort | tail -1)"
  [[ -n "$latest" ]] || { info "未找到 Warp 版本目录，跳过"; return 1; }
  version="$(basename "$latest")"
  tgz="${latest}/linux-x86_64/oz.tar.gz"
  [[ -f "$tgz" ]] || { info "无 $tgz，跳过 Warp"; return 1; }

  extracted="${IDE_CACHE}/warp/${version}"
  if [[ "$force" -eq 1 ]]; then
    rm -rf "$extracted"
  fi
  mkdir -p "$extracted"
  if [[ -e "${extracted}/.ready" ]]; then
    ok "本机已有 Warp 缓存 ($version)"
  else
    info "解压 Warp oz.tar.gz ($version) -> 本机缓存"
    tar -xzf "$tgz" -C "$extracted"
    if [[ -f "${extracted}/oz" && ! -e "${extracted}/oz-${version}" ]]; then
      mv "${extracted}/oz" "${extracted}/oz-${version}"
    fi
    touch "${extracted}/.ready"
    ok "Warp 缓存就绪"
  fi
  printf '%s\n' "$extracted"
}

# ── §1 onboard：密码登录一次，以后公钥 ───────────────────────────────────────
cmd_onboard() {
  local alias="" ip="" password="" user="$DEFAULT_USER" port="$DEFAULT_PORT"
  local key="$DEFAULT_KEY"
  local do_seed=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --alias)      alias="$2";      shift 2 ;;
      --ip)         ip="$2";         shift 2 ;;
      --password)   password="$2";   shift 2 ;;
      --user)       user="$2";       shift 2 ;;
      --port)       port="$2";       shift 2 ;;
      --key)        key="$2";        shift 2 ;;
      --seed-ide)   do_seed=1;       shift ;;
      --seed-from)  die "改用: ./lab.sh seed --pull --from HOST" ;;
      -h|--help)    help_onboard; return 0 ;;
      *) die "未知参数: $1 （运行 ./lab.sh onboard --help）" ;;
    esac
  done

  [[ -n "$alias" && -n "$ip" && -n "$password" ]] || { help_onboard; die "缺少 --alias / --ip / --password"; }

  key="$(expand_key "$key")"
  local pub="${key}.pub"
  [[ -f "$key" && -f "$pub" ]] || die "密钥不存在: $key"
  need ssh scp sshpass awk

  info "[$alias] 上传公钥到 ${user}@${ip}:${port}"
  SSHPASS="$password" sshpass -e ssh -p "$port" -o StrictHostKeyChecking=accept-new \
    "${user}@${ip}" 'mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys'

  SSHPASS="$password" sshpass -e scp -P "$port" "$pub" "${user}@${ip}:/tmp/lab_pubkey.tmp"
  SSHPASS="$password" sshpass -e ssh -p "$port" "${user}@${ip}" \
    'grep -qxF -f /tmp/lab_pubkey.tmp ~/.ssh/authorized_keys 2>/dev/null || cat /tmp/lab_pubkey.tmp >> ~/.ssh/authorized_keys; rm -f /tmp/lab_pubkey.tmp'
  ok "公钥已写入 authorized_keys"

  info "[$alias] 写入 ~/.ssh/config"
  mkdir -p "$(dirname "$SSH_CONFIG")"
  touch "$SSH_CONFIG"
  chmod 600 "$SSH_CONFIG"
  if grep -q "^Host ${alias}$" "$SSH_CONFIG" 2>/dev/null; then
    awk -v a="$alias" '$0 ~ "^Host " a "$" {skip=1; next} skip && /^Host / {skip=0} !skip {print}' \
      "$SSH_CONFIG" > "${SSH_CONFIG}.tmp" && mv "${SSH_CONFIG}.tmp" "$SSH_CONFIG"
  fi
  cat >> "$SSH_CONFIG" <<EOF

# lab: ${alias}
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
  ok "config 已更新"

  info "[$alias] 验证密钥登录"
  ssh -i "$key" -o IdentitiesOnly=yes -o BatchMode=yes -p "$port" "${user}@${ip}" 'echo OK && hostname && whoami'
  ok "SSH 免密可用: ssh ${alias}"

  if [[ "$do_seed" -eq 1 ]]; then
    cmd_seed --alias "$alias" --key "$key"
  fi
}

help_onboard() {
  cat <<'EOF'
用法: ./lab.sh onboard --alias NAME --ip IP --password PASS [选项]

  --alias NAME        SSH 别名（写入 ~/.ssh/config）
  --ip IP             目标 IP
  --password PASS     初始密码（只用这一次）
  --user USER         默认 root
  --port PORT         默认 22
  --key PATH          默认 ~/.ssh/id_longgang
  --seed-ide          接入后推 IDE（donor/本机缓存；缺包见 seed --pull）
EOF
}

# ── §2 seed：donor -> 本机缓存 -> 目标机 ───────────────────────────────────────
cmd_seed() {
  local alias="" key="$DEFAULT_KEY"
  local force=0 allow_cdn=0 do_pull=0 all_cached=0
  local donors="$DEFAULT_DONORS" pull_from=""
  local host commit warp_path ssh_e c

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --alias)       alias="$2"; shift 2 ;;
      --key)         key="$2"; shift 2 ;;
      --from)        pull_from="$2"; donors="$2"; shift 2 ;;
      --pull)        do_pull=1; shift ;;
      --refresh)     force=1; shift ;;
      --force)       force=1; shift ;;
      --cdn)         allow_cdn=1; shift ;;
      --all-cached)  all_cached=1; shift ;;
      --port)        shift 2 ;;
      -h|--help)     help_seed; return 0 ;;
      *) die "未知参数: $1" ;;
    esac
  done

  key="$(expand_key "$key")"
  need ssh rsync

  if [[ "$do_pull" -eq 1 ]]; then
    if [[ -n "$pull_from" ]]; then
      pull_all_from_host "$pull_from" "$key"
    else
      for host in $donors; do
        pull_all_from_host "$host" "$key" || true
      done
    fi
    ok "本机缓存目录: ${IDE_CACHE}"
    ls -1 "${IDE_CACHE}/cursor" 2>/dev/null | sed 's/^/  cursor /' || true
    if [[ -z "$alias" ]]; then
      return 0
    fi
  fi

  if [[ -z "$alias" ]]; then
    ensure_cursor_local "$force" "$allow_cdn" "$key" "$donors" >/dev/null
    ensure_warp_local "$force" >/dev/null || true
    ok "本机缓存已更新 -> ${IDE_CACHE}"
    return 0
  fi

  ssh_e="$(ssh_e_for "$key")"

  if [[ "$all_cached" -eq 1 ]]; then
    info "[$alias] 推送本机全部已缓存 Cursor commits"
    ssh -i "$key" -o IdentitiesOnly=yes "$alias" 'mkdir -p ~/.cursor-server/bin/linux-x64'
    for c in "${IDE_CACHE}/cursor"/*; do
      [[ -d "$c/extracted" ]] || continue
      cursor_extracted_ok "$c/extracted" || continue
      c="$(basename "$c")"
      info "  -> $c"
      ssh -i "$key" -o IdentitiesOnly=yes "$alias" "mkdir -p ~/.cursor-server/bin/linux-x64/${c}"
      rsync -av --progress -e "$ssh_e" \
        "${IDE_CACHE}/cursor/${c}/extracted/" \
        "${alias}:~/.cursor-server/bin/linux-x64/${c}/"
    done
  else
    commit="$(ensure_cursor_local "$force" "$allow_cdn" "$key" "$donors")"
    info "[$alias] 推送 Cursor server (commit=$commit)"
    ssh -i "$key" -o IdentitiesOnly=yes "$alias" \
      "mkdir -p ~/.cursor-server/bin/linux-x64/${commit}"
    rsync -av --progress -e "$ssh_e" \
      "${IDE_CACHE}/cursor/${commit}/extracted/" \
      "${alias}:~/.cursor-server/bin/linux-x64/${commit}/"
    ok "Cursor -> ${alias}:~/.cursor-server/bin/linux-x64/${commit}/"
  fi

  if warp_path="$(ensure_warp_local "$force")"; then
    info "[$alias] 推送 Warp remote-server"
    ssh -i "$key" -o IdentitiesOnly=yes "$alias" 'mkdir -p ~/.warp/remote-server'
    rsync -av --progress -e "$ssh_e" \
      --exclude '.ready' \
      "${warp_path}/" \
      "${alias}:~/.warp/remote-server/"
    ok "Warp 已推送"
  fi

  ok "IDE 同步完成（本机: ${IDE_CACHE}）"
}

help_seed() {
  cat <<'EOF'
用法:
  ./lab.sh seed --pull [--from H100-1]     # 从已有机器拉 Cursor/Warp -> 本机缓存（先跑这个）
  ./lab.sh seed --alias NAME               # 本机缓存 -> 目标机
  ./lab.sh seed --alias NAME --all-cached  # 推送本机所有已缓存 commit
  ./lab.sh seed --alias NAME --cdn         # 允许公网下载当前 commit（慢）
  ./lab.sh seed --refresh --cdn            # 强制 CDN 刷新当前 commit 到本机

默认 donors: H100-1 H100-2（LAB_IDE_DONORS 或 --from）
缓存目录: ~/.cache/lab-ide/

若当前 Cursor commit 不在 donor：先 Remote-SSH 连一次 donor 让它下好，再 --pull。
EOF
}

# ── §3 tailscale ─────────────────────────────────────────────────────────────
cmd_tailscale() {
  local alias="" auth_key="" hostname="" key="$DEFAULT_KEY" port="$DEFAULT_PORT"
  local deb=""   # 非空 = 离线装：本机 deb 路径

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --alias)    alias="$2";     shift 2 ;;
      --auth-key) auth_key="$2"; shift 2 ;;
      --hostname) hostname="$2"; shift 2 ;;
      --deb)      deb="$2";      shift 2 ;;
      --key)      key="$2";      shift 2 ;;
      --port)     port="$2";     shift 2 ;;
      -h|--help)  help_tailscale; return 0 ;;
      *) die "未知参数: $1" ;;
    esac
  done

  [[ -n "$alias" && -n "$auth_key" ]] || { help_tailscale; die "缺少 --alias / --auth-key"; }
  [[ -n "$hostname" ]] || hostname="$alias"
  key="$(expand_key "$key")"
  need ssh scp

  if [[ -n "$deb" ]]; then
    info "[$alias] 离线安装 Tailscale: $deb"
    [[ -f "$deb" ]] || die "deb 不存在: $deb"
    scp -i "$key" -o IdentitiesOnly=yes -P "$port" "$deb" "${alias}:/tmp/tailscale.deb"
    ssh -i "$key" -o IdentitiesOnly=yes -p "$port" "$alias" \
      'dpkg -i /tmp/tailscale.deb || apt-get -f install -y'
  else
    info "[$alias] 在线安装 Tailscale"
    ssh -i "$key" -o IdentitiesOnly=yes -p "$port" "$alias" \
      'curl -fsSL https://tailscale.com/install.sh | sh'
  fi

  info "[$alias] 加入 tailnet: hostname=${hostname}"
  ssh -i "$key" -o IdentitiesOnly=yes -p "$port" "$alias" \
    "tailscale up --auth-key=${auth_key} --hostname=${hostname} --accept-routes --ssh"
  ssh -i "$key" -o IdentitiesOnly=yes -p "$port" "$alias" 'tailscale status'
  ok "Tailscale 就绪（Admin 面板确认节点: https://login.tailscale.com/admin/machines）"
}

help_tailscale() {
  cat <<'EOF'
用法: ./lab.sh tailscale --alias NAME --auth-key tskey-auth-xxx [选项]

  --auth-key KEY   Tailscale auth key（Admin → Settings → Keys）
  --hostname NAME  tailnet 主机名，默认等于 --alias
  --deb PATH       离线：本机 .deb 路径（机器不能上网时用，见 RUNBOOK §3b）
EOF
}

# ── §4 cleanup：交付清理 ─────────────────────────────────────────────────────
cmd_cleanup() {
  local alias="" ip="" key="$DEFAULT_KEY" port="$DEFAULT_PORT"
  local remote=1 local_clean=1
  local key_tag="longgang"   # authorized_keys 里匹配这串的行会删掉

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --alias)       alias="$2"; shift 2 ;;
      --ip)          ip="$2";    shift 2 ;;
      --key)         key="$2";   shift 2 ;;
      --key-tag)     key_tag="$2"; shift 2 ;;
      --remote-only) local_clean=0; shift ;;
      --local-only)  remote=0; shift ;;
      -h|--help)     help_cleanup; return 0 ;;
      *) die "未知参数: $1" ;;
    esac
  done

  [[ -n "$alias" ]] || { help_cleanup; die "缺少 --alias"; }
  key="$(expand_key "$key")"
  need ssh awk

  if [[ "$remote" -eq 1 ]]; then
    info "[$alias] 远程清理（Tailscale / SSH key / IDE 缓存）"
    ssh -i "$key" -o IdentitiesOnly=yes -p "$port" "$alias" bash -s -- "$key_tag" <<'REMOTE'
set -e
TAG="$1"
tailscale logout 2>/dev/null || true
systemctl stop tailscaled 2>/dev/null || true
systemctl disable tailscaled 2>/dev/null || true
apt-get purge -y tailscale tailscale-archive-keyring 2>/dev/null || true
rm -rf /var/lib/tailscale /var/log/tailscale*
if [[ -f ~/.ssh/authorized_keys ]]; then
  grep -v "$TAG" ~/.ssh/authorized_keys > /tmp/lab_ak || true
  mv /tmp/lab_ak ~/.ssh/authorized_keys
  chmod 600 ~/.ssh/authorized_keys
fi
rm -rf ~/.cursor-server ~/.warp ~/.config/warp-terminal
echo "REMOTE CLEANUP DONE"
REMOTE
    ok "远程清理完成"
    info "请到 Tailscale Admin 确认节点已删除: https://login.tailscale.com/admin/machines"
  fi

  if [[ "$local_clean" -eq 1 ]]; then
    info "[$alias] 本机清理 ~/.ssh/config"
    if [[ -f "$SSH_CONFIG" ]]; then
      awk -v a="$alias" '
        $0 ~ "^# lab: " a "$" {skip=1; next}
        $0 ~ "^Host " a "$" {skip=1; next}
        skip && /^$/ {skip=0; next}
        skip && /^Host / {skip=0}
        !skip {print}
      ' "$SSH_CONFIG" > "${SSH_CONFIG}.tmp" && mv "${SSH_CONFIG}.tmp" "$SSH_CONFIG"
    fi
    if [[ -n "$ip" ]]; then
      ssh-keygen -R "$ip" 2>/dev/null || true
    fi
    ssh-keygen -R "$alias" 2>/dev/null || true
    ok "本机 config / known_hosts 已清理"
  fi
}

help_cleanup() {
  cat <<'EOF'
用法: ./lab.sh cleanup --alias NAME [--ip IP]

  --ip IP           本机 known_hosts 清理用（建议带上）
  --key-tag TEXT    删 authorized_keys 含此文本的行，默认 longgang
  --remote-only     只清远程
  --local-only      只清本机 config（须已能 ssh）
EOF
}

# ── 总帮助 ───────────────────────────────────────────────────────────────────
usage() {
  cat <<'EOF'
lab.sh — 测试机接入 / 交付

子命令:
  onboard    密码 → 公钥，写 ~/.ssh/config
  seed       donor → 本机缓存 → 目标机（--pull / --cdn）
  tailscale  安装 Tailscale 并加入 tailnet
  cleanup    交付前清理（远程 + 本机）

快速开始:
  ./lab.sh seed --pull --from H100-1
  ./lab.sh seed --alias AMD370-Dual-Channel --all-cached
  ./lab.sh onboard --alias H100-3 --ip 1.2.3.4 --password 'xxx' --seed-ide
  ./lab.sh tailscale --alias H100-3 --auth-key 'tskey-auth-xxx'
  ./lab.sh cleanup --alias H100-3 --ip 1.2.3.4

详细命令见 RUNBOOK.md；每个子命令加 --help。
EOF
}

# ── 入口 ─────────────────────────────────────────────────────────────────────
main() {
  local cmd="${1:-}"
  shift || true
  case "$cmd" in
    onboard)   cmd_onboard "$@" ;;
    seed)      cmd_seed "$@" ;;
    tailscale) cmd_tailscale "$@" ;;
    cleanup)   cmd_cleanup "$@" ;;
    help|-h|--help|"") usage ;;
    *) die "未知子命令: $cmd （运行 ./lab.sh help）" ;;
  esac
}

main "$@"
