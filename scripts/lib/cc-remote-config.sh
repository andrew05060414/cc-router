# cc-remote settings.json 生成/同步

# ------------------------------- 认证 token 读取 --------------------------------

cc_remote_config_get_auth_token() {
  # 优先从本地 settings.json 读取 ANTHROPIC_AUTH_TOKEN
  local local_settings
  local_settings="$(cc_remote_settings_local_file)"
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

# ------------------------------- 生成远程版 settings ----------------------------

cc_remote_config_generate() {
  local pack_dir
  pack_dir="$(cc_remote_pack_dir)"
  mkdir -p "$pack_dir"

  local output="$pack_dir/settings.json"
  cc_remote_config_generate_silent "$output"

  echo "[cc-remote] 远程版 settings.json 已生成: $output"
  echo "---"
  cat "$output"
  echo "---"
}

cc_remote_config_generate_silent() {
  local output="$1"
  local mode
  mode="${CC_REMOTE_SETTINGS_MODE:-remote}"

  case "$mode" in
    local)
      cc_remote_config_from_local "$output"
      ;;
    remote)
      local token
      token="$(cc_remote_config_get_auth_token || true)"
      cc_remote_config_remote_template "$output" "$token"
      ;;
    default|template)
      cc_remote_config_default_template "$output"
      ;;
    *)
      echo "ERROR: 未知 settings 模式: $mode" >&2
      exit 1
      ;;
  esac
}

# 从本地 settings.json 提取关键字段生成远程版
cc_remote_config_from_local() {
  local output="$1"
  local local_settings
  local_settings="$(cc_remote_settings_local_file)"

  if [[ ! -f "$local_settings" ]]; then
    echo "WARN: 本地 settings.json 不存在，使用远程模板" >&2
    cc_remote_config_remote_template "$output"
    return
  fi

  if ! command -v jq >/dev/null 2>&1; then
    echo "WARN: 没有 jq，使用远程模板（安装 jq 后可用本地同步）" >&2
    cc_remote_config_remote_template "$output"
    return
  fi

  # 提取关键字段
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
    model: (.model // "opus"),
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

# 远程专用版 settings（kimi coding plan + 关闭遥测）
cc_remote_config_remote_template() {
  local output="$1"
  local token="${2:-}"

  if [[ -z "$token" ]]; then
    cat > "$output" <<'EOF'
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://api.kimi.com/coding/",
    "ANTHROPIC_DEFAULT_FABLE_MODEL": "k3[1M]",
    "ANTHROPIC_DEFAULT_FABLE_MODEL_NAME": "k3",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "kimi-for-coding",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "k3[1M]",
    "ANTHROPIC_DEFAULT_OPUS_MODEL_NAME": "k3",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "kimi-for-coding-highspeed",
    "ANTHROPIC_DEFAULT_SONNET_MODEL_NAME": "kimi-for-coding-highspeed",
    "ANTHROPIC_MODEL": "kimi-for-coding",
    "CLAUDE_CODE_AUTO_COMPACT_WINDOW": "262144",
    "CLAUDE_CODE_DISABLE_TELEMETRY": "1",
    "ANTHROPIC_DISABLE_TELEMETRY": "1",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
    "CLAUDE_CODE_MAX_CONTEXT_TOKENS": "262144",
    "API_TIMEOUT_MS": "600000",
    "DISABLE_AUTOUPDATER": "1",
    "ENABLE_TOOL_SEARCH": "true"
  },
  "git": {
    "includeCoAuthor": false
  },
  "model": "opus",
  "skipDangerousModePermissionPrompt": true
}
EOF
  else
    cat > "$output" <<EOF
{
  "env": {
    "ANTHROPIC_AUTH_TOKEN": "$token",
    "ANTHROPIC_BASE_URL": "https://api.kimi.com/coding/",
    "ANTHROPIC_DEFAULT_FABLE_MODEL": "k3[1M]",
    "ANTHROPIC_DEFAULT_FABLE_MODEL_NAME": "k3",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "kimi-for-coding",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "k3[1M]",
    "ANTHROPIC_DEFAULT_OPUS_MODEL_NAME": "k3",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "kimi-for-coding-highspeed",
    "ANTHROPIC_DEFAULT_SONNET_MODEL_NAME": "kimi-for-coding-highspeed",
    "ANTHROPIC_MODEL": "kimi-for-coding",
    "CLAUDE_CODE_AUTO_COMPACT_WINDOW": "262144",
    "CLAUDE_CODE_DISABLE_TELEMETRY": "1",
    "ANTHROPIC_DISABLE_TELEMETRY": "1",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
    "CLAUDE_CODE_MAX_CONTEXT_TOKENS": "262144",
    "API_TIMEOUT_MS": "600000",
    "DISABLE_AUTOUPDATER": "1",
    "ENABLE_TOOL_SEARCH": "true"
  },
  "git": {
    "includeCoAuthor": false
  },
  "model": "opus",
  "skipDangerousModePermissionPrompt": true
}
EOF
  fi
}

# 默认精简版 settings
cc_remote_config_default_template() {
  local output="$1"
  cat > "$output" <<'EOF'
{
  "env": {
    "CLAUDE_CODE_DISABLE_TELEMETRY": "1",
    "ANTHROPIC_DISABLE_TELEMETRY": "1",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
    "DISABLE_AUTOUPDATER": "1"
  },
  "git": {
    "includeCoAuthor": false
  },
  "model": "opus",
  "skipDangerousModePermissionPrompt": false
}
EOF
}
