# ccr remote SSH config 管理

ccr_remote_ssh_config_ensure() {
  local ssh_config
  ssh_config="$(ccr_remote_ssh_config_file)"
  mkdir -p "$(dirname "$ssh_config")"
  if [[ ! -f "$ssh_config" ]]; then
    touch "$ssh_config"
    chmod 600 "$ssh_config"
  fi
}

ccr_remote_ssh_config_add() {
  local alias="${1:-}"
  local host="${2:-}"
  local user="${3:-${USER:-root}}"
  local port="${4:-22}"
  local key="${5:-}"

  if [[ -z "$alias" || -z "$host" ]]; then
    echo "ERROR: 用法: ccr remote ssh-config add <alias> <host> [user] [port] [key]" >&2
    exit 1
  fi

  ccr_remote_ssh_config_ensure
  local ssh_config
  ssh_config="$(ccr_remote_ssh_config_file)"

  # 如果已存在该 alias，先删除旧配置块
  ccr_remote_ssh_config_remove "$alias" >/dev/null 2>&1 || true

  {
    echo ""
    echo "Host $alias"
    echo "    HostName $host"
    echo "    User $user"
    echo "    Port $port"
    if [[ -n "$key" ]]; then
      echo "    IdentityFile $key"
    fi
    echo "    ServerAliveInterval 60"
    echo "    ServerAliveCountMax 3"
  } >> "$ssh_config"

  echo "[cc-remote] 已添加 SSH 配置: $alias → $user@$host:$port"
}

ccr_remote_ssh_config_remove() {
  local alias="$1"
  local ssh_config
  ssh_config="$(ccr_remote_ssh_config_file)"

  if [[ ! -f "$ssh_config" ]]; then
    return 0
  fi

  awk -v alias="$alias" '
    /^Host / { in_block = ($2 == alias) }
    !in_block { print }
  ' "$ssh_config" > "$ssh_config.tmp"
  mv "$ssh_config.tmp" "$ssh_config"
}

ccr_remote_ssh_config_list() {
  local ssh_config
  ssh_config="$(ccr_remote_ssh_config_file)"

  if [[ ! -f "$ssh_config" ]]; then
    echo "没有 SSH 配置文件"
    return 0
  fi

  echo "已配置的 SSH 主机:"
  awk '
    /^Host / {
      if (current != "") print current
      current = $2
      next
    }
    /^    HostName / { current = current " -> " $2 }
    /^    User / { current = current " (user: " $2 ")" }
    /^    Port / { current = current " port: " $2 }
    END { if (current != "") print current }
  ' "$ssh_config"
}
