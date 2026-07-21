# ccr remote settings.json 生成/同步

# ------------------------------- 认证 token 读取 --------------------------------

ccr_remote_config_get_auth_token() {
  # 优先从本地 settings.json 读取 ANTHROPIC_AUTH_TOKEN
  local local_settings
  local_settings="$(ccr_remote_settings_local_file)"
  if [[ -f "$local_settings" ]] && command -v jq >/dev/null 2>&1; then
    local token
    token="$(jq -r '.env.ANTHROPIC_AUTH_TOKEN // empty' "$local_settings" 2>/dev/null)"
    if [[ -n "$token" ]]; then
      printf '%s\n' "$token"
      return 0
    fi
  fi

  # 其次从环境变量读取
  if [[ -n "${CC_REMOTE_AUTH_TOKEN:-}" ]]; then
    printf '%s\n' "$CC_REMOTE_AUTH_TOKEN"
    return 0
  fi

  return 1
}

# ------------------------------- 模板加载 ---------------------------------------

ccr_remote_template_dir() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  local candidates=(
    "${script_dir}/templates/remote"
    "${HOME}/.local/share/cc-router/templates/remote"
  )
  for d in "${candidates[@]}"; do
    if [[ -d "$d" ]]; then
      printf '%s\n' "$d"
      return 0
    fi
  done
  printf '%s\n' "${candidates[0]}"
}

ccr_remote_vendor_template() {
  local vendor="${1:-kimi}"
  local template_dir
  template_dir="$(ccr_remote_template_dir)"
  local path="${template_dir}/${vendor}.json"
  if [[ ! -f "$path" ]]; then
    echo "WARN: 未知 vendor '${vendor}'，回退到 default 模板" >&2
    path="${template_dir}/default.json"
  fi
  printf '%s\n' "$path"
}

# ------------------------------- 生成远程版 settings ----------------------------

ccr_remote_config_generate() {
  local pack_dir
  pack_dir="$(ccr_remote_pack_dir)"
  mkdir -p "$pack_dir"

  local output="$pack_dir/settings.json"
  ccr_remote_config_generate_silent "$output"

  echo "[ccr remote] 远程版 settings.json 已生成: $output"
  echo "---"
  cat "$output"
  echo "---"
}

ccr_remote_config_generate_silent() {
  local output="$1"
  local mode
  mode="${CC_REMOTE_SETTINGS_MODE:-remote}"

  case "$mode" in
    local)
      ccr_remote_config_from_local "$output"
      ;;
    remote)
      local token vendor
      token="$(ccr_remote_config_get_auth_token || true)"
      vendor="${CCR_REMOTE_VENDOR:-kimi}"
      ccr_remote_config_vendor_template "$output" "$vendor" "$token"
      ;;
    default|template)
      local vendor
      vendor="${CCR_REMOTE_VENDOR:-default}"
      ccr_remote_config_vendor_template "$output" "$vendor" ""
      ;;
    *)
      echo "ERROR: 未知 settings 模式: $mode" >&2
      exit 1
      ;;
  esac
}

# 从本地 settings.json 提取关键字段生成远程版
ccr_remote_config_from_local() {
  local output="$1"
  local local_settings
  local_settings="$(ccr_remote_settings_local_file)"

  if [[ ! -f "$local_settings" ]]; then
    echo "WARN: 本地 settings.json 不存在，使用远程模板" >&2
    ccr_remote_config_vendor_template "$output" "${CCR_REMOTE_VENDOR:-kimi}" ""
    return
  fi

  if ! command -v jq >/dev/null 2>&1; then
    echo "WARN: 没有 jq，使用远程模板（安装 jq 后可用本地同步）" >&2
    ccr_remote_config_vendor_template "$output" "${CCR_REMOTE_VENDOR:-kimi}" ""
    return
  fi

  # 提取关键字段。保留 ANTHROPIC_MODEL 与 ANTHROPIC_DEFAULT_*（官方 kimi coding
  # 接入需要档位映射，确保子 agent 的 Haiku 档也可用）；遥测/tool-use 开关同样保留。
  jq '
  {
    env: (
      .env // {} |
      with_entries(select(.key | test("ANTHROPIC_|CLAUDE_|DISABLE_AUTOUPDATER|ENABLE_TOOL_SEARCH"))) |
      if has("DISABLE_AUTOUPDATER") then . else . + {"DISABLE_AUTOUPDATER": "1"} end
    ),
    git: {
      includeCoAuthor: (.git.includeCoAuthor // false)
    },
    skipDangerousModePermissionPrompt: (.skipDangerousModePermissionPrompt // true)
  }' "$local_settings" > "$output"

  # 追加 telemetry 关闭和官方推荐参数
  jq '.env += {
    "CLAUDE_CODE_DISABLE_TELEMETRY": "1",
    "ANTHROPIC_DISABLE_TELEMETRY": "1",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
    "API_TIMEOUT_MS": "600000"
  }' "$output" > "$output.tmp"
  mv "$output.tmp" "$output"
}

# 加载 vendor 模板并可选注入 token
ccr_remote_config_vendor_template() {
  local output="$1"
  local vendor="${2:-kimi}"
  local token="${3:-}"
  local template
  template="$(ccr_remote_vendor_template "$vendor")"

  if [[ -z "$token" ]]; then
    cp "$template" "$output"
  else
    jq --arg token "$token" '.env.ANTHROPIC_AUTH_TOKEN = $token' "$template" > "$output"
  fi
}

# 默认精简版 settings（兼容旧函数名）
ccr_remote_config_default_template() {
  local output="$1"
  ccr_remote_config_vendor_template "$output" "default" ""
}

# 旧 remote 模板别名（兼容旧调用）
ccr_remote_config_remote_template() {
  local output="$1"
  local token="${2:-}"
  ccr_remote_config_vendor_template "$output" "kimi" "$token"
}
