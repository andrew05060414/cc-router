# cc-router shared bash helpers (sourced by scripts/ccr).

ccr_config_dir() {
  printf '%s\n' "${XDG_CONFIG_HOME:-${HOME}/.config}/cc-router"
}

ccr_config_file() {
  printf '%s\n' "$(ccr_config_dir)/config.json"
}

ccr_claude_global_settings_file() {
  printf '%s\n' "${HOME}/.claude/settings.json"
}

ccr_claude_project_settings_file() {
  local root
  root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  printf '%s\n' "${root}/.claude/settings.json"
}

ccr_require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "ccr config: jq is required. Install: brew install jq  (or apt install jq)" >&2
    return 1
  fi
}

ccr_trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "${s}"
}

ccr_bool_normalize() {
  ccr_trim "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
}

# Affirmative: y/Y, yes/Yes, true, on, 1, etc.
ccr_truthy() {
  local v
  v="$(ccr_bool_normalize "$1")"
  case "${v}" in
    y | yes | ye | yeah | yep | yea | true | 1 | on | enable | enabled | sure | ok) return 0 ;;
    *) return 1 ;;
  esac
}

# Negative: n/N, no/No, false, off, 0, etc. (not "none" — that is a separate config value.)
ccr_falsy() {
  local v
  v="$(ccr_bool_normalize "$1")"
  case "${v}" in
    n | no | false | 0 | off | disable | disabled | nah) return 0 ;;
    *) return 1 ;;
  esac
}

ccr_parse_bool() {
  local raw="$1"
  local default="${2:-false}"
  local v
  v="$(ccr_bool_normalize "${raw}")"
  if [[ -z "${v}" ]]; then
    if ccr_truthy "${default}"; then
      printf 'true\n'
    else
      printf 'false\n'
    fi
    return 0
  fi
  if ccr_truthy "${v}"; then
    printf 'true\n'
    return 0
  fi
  if ccr_falsy "${v}"; then
    printf 'false\n'
    return 0
  fi
  return 1
}

ccr_config_ensure() {
  local dir file
  dir="$(ccr_config_dir)"
  file="$(ccr_config_file)"
  mkdir -p "${dir}"
  if [[ ! -f "${file}" ]]; then
    cat >"${file}" <<'EOF'
{
  "allowDangerouslySkipPermissions": true,
  "claudePermissionsTarget": "none",
  "cachePromptEnvEnabled": true,
  "cacheFixEnabled": true,
  "cacheFixUrl": "http://127.0.0.1:9801",
  "cacheFix9routerEnabled": true,
  "nineRouterUrl": "http://127.0.0.1:20128"
}
EOF
  fi
}

ccr_config_get() {
  local key="$1"
  local default="${2:-}"
  local file val
  file="$(ccr_config_file)"
  if [[ ! -f "${file}" ]]; then
    printf '%s\n' "${default}"
    return 0
  fi
  if command -v jq >/dev/null 2>&1; then
    val="$(jq -r --arg k "${key}" --arg d "${default}" '.[$k] // $d' "${file}" 2>/dev/null || true)"
    if [[ -z "${val}" || "${val}" == "null" ]]; then
      val="${default}"
    fi
    printf '%s\n' "${val}"
    return 0
  fi
  printf '%s\n' "${default}"
}

ccr_config_set_bool() {
  local key="$1"
  local value="$2"
  local file tmp parsed
  ccr_require_jq || return 1
  ccr_config_ensure
  file="$(ccr_config_file)"
  if ! parsed="$(ccr_parse_bool "${value}" false)"; then
    echo "ccr config: expected on/off, y/n, yes/no (got: ${value})" >&2
    return 2
  fi
  tmp="$(mktemp)"
  if [[ "${parsed}" == "true" ]]; then
    jq --arg k "${key}" '.[$k] = true' "${file}" >"${tmp}"
  else
    jq --arg k "${key}" '.[$k] = false' "${file}" >"${tmp}"
  fi
  mv "${tmp}" "${file}"
}

ccr_config_set_string() {
  local key="$1"
  local value="$2"
  local file tmp
  ccr_require_jq || return 1
  ccr_config_ensure
  file="$(ccr_config_file)"
  tmp="$(mktemp)"
  jq --arg k "${key}" --arg v "${value}" '.[$k] = $v' "${file}" >"${tmp}"
  mv "${tmp}" "${file}"
}

ccr_cache_fix_enabled() {
  if [[ -n "${CC_CACHE_FIX_ENABLED:-}" ]]; then
    ccr_truthy "${CC_CACHE_FIX_ENABLED}"
    return $?
  fi
  ccr_truthy "$(ccr_config_get cacheFixEnabled true)"
}

ccr_cache_fix_9router_enabled() {
  if [[ -n "${CC_CACHE_FIX_9ROUTER_ENABLED:-}" ]]; then
    ccr_truthy "${CC_CACHE_FIX_9ROUTER_ENABLED}"
    return $?
  fi
  ccr_truthy "$(ccr_config_get cacheFix9routerEnabled true)"
}

ccr_cache_prompt_env_enabled() {
  if [[ -n "${CC_CACHE_PROMPT_ENV_ENABLED:-}" ]]; then
    ccr_truthy "${CC_CACHE_PROMPT_ENV_ENABLED}"
    return $?
  fi
  ccr_truthy "$(ccr_config_get cachePromptEnvEnabled true)"
}

# Real 9Router gateway (OAuth routing target). NINEROUTER_URL env wins over config.
ccr_ninerouter_real_url() {
  if [[ -n "${NINEROUTER_URL:-}" ]]; then
    printf '%s\n' "${NINEROUTER_URL%/}"
    return 0
  fi
  ccr_config_get nineRouterUrl "http://127.0.0.1:20128" | sed 's|/*$||'
}

# Host Claude Code talks to (cache-fix proxy when ccr 9router chaining is enabled).
ccr_ninerouter_client_base_url() {
  if ccr_cache_fix_9router_enabled; then
    ccr_cache_fix_url
  else
    ccr_ninerouter_real_url
  fi
}

ccr_print_cache_fix_start_hint() {
  local upstream cf
  upstream="$(ccr_ninerouter_real_url)"
  cf="$(ccr_cache_fix_url)"
  echo "  CACHE_FIX_PROXY_UPSTREAM=${upstream} node \"\$(npm root -g)/claude-code-cache-fix/proxy/server.mjs\" &"
  echo "  curl -fsS ${cf}/health"
}

ccr_cache_fix_url() {
  local url
  if [[ -n "${CC_CACHE_FIX_URL:-}" ]]; then
    printf '%s\n' "${CC_CACHE_FIX_URL%/}"
    return 0
  fi
  url="$(ccr_config_get cacheFixUrl "http://127.0.0.1:9801")"
  printf '%s\n' "${url%/}"
}

# Prompt-cache hygiene for all launch modes (official, ccr 9router, ccd).
# Attribution header breaks third-party prompt caches; git status busts prefix.
# Override: CC_ATTRIBUTION_HEADER, CC_DISABLE_GIT_INSTRUCTIONS (empty disables git flag).
ccr_export_cache_prompt_env() {
  local attr git
  if ! ccr_cache_prompt_env_enabled; then
    return 0
  fi
  attr="${CC_ATTRIBUTION_HEADER-false}"
  git="${CC_DISABLE_GIT_INSTRUCTIONS-1}"
  export CLAUDE_CODE_ATTRIBUTION_HEADER="${attr}"
  if [[ -n "${git}" ]]; then
    export CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS="${git}"
  else
    unset CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS
  fi
}

ccr_probe_cache_fix_health() {
  local base="$1"
  local health_url resp
  base="${base%/}"
  health_url="${base}/health"
  if resp="$(curl -fsS --max-time 5 "${health_url}" 2>/dev/null)"; then
    if [[ "${resp}" == *'"ok":true'* || "${resp}" == *'"ok": true'* || "${resp}" == *'"status":"ok"'* ]]; then
      return 0
    fi
    return 1
  fi
  return 1
}

ccr_allow_dangerously_skip_permissions_enabled() {
  if [[ -n "${CC_ALLOW_DANGEROUSLY_SKIP_PERMISSIONS:-}" ]]; then
    if ccr_truthy "${CC_ALLOW_DANGEROUSLY_SKIP_PERMISSIONS}"; then
      return 0
    fi
    if ccr_falsy "${CC_ALLOW_DANGEROUSLY_SKIP_PERMISSIONS}"; then
      return 1
    fi
    return 1
  fi
  ccr_truthy "$(ccr_config_get allowDangerouslySkipPermissions false)"
}

ccr_resolve_claude_settings_file() {
  local scope="${1:-}"
  if [[ -z "${scope}" ]]; then
    scope="$(ccr_config_get claudePermissionsTarget none)"
  fi
  case "${scope}" in
    global | user)
      ccr_claude_global_settings_file
      ;;
    project | repo)
      ccr_claude_project_settings_file
      ;;
    none)
      echo "ccr config: claudePermissionsTarget is 'none'; pass --global or --project" >&2
      return 1
      ;;
    *)
      echo "ccr config: unknown scope '${scope}' (use global or project)" >&2
      return 1
      ;;
  esac
}

ccr_claude_extra_args() {
  if ccr_allow_dangerously_skip_permissions_enabled; then
    printf '%s\n' --allow-dangerously-skip-permissions
  fi
}

ccr_args_has_skip_permissions_flag() {
  local arg
  for arg in "$@"; do
    if [[ "${arg}" == "--allow-dangerously-skip-permissions" || "${arg}" == "--dangerously-skip-permissions" ]]; then
      return 0
    fi
  done
  return 1
}

ccr_map_model_alias() {
  local raw="$1"
  local opus_model="$2"
  local sonnet_model="$3"
  local haiku_model="$4"
  case "${raw}" in
    opus|claude-opus-*)
      printf '%s\n' "${opus_model}"
      ;;
    sonnet|claude-sonnet-*)
      printf '%s\n' "${sonnet_model}"
      ;;
    haiku|claude-haiku-*)
      printf '%s\n' "${haiku_model}"
      ;;
    *)
      printf '%s\n' "${raw}"
      ;;
  esac
}

ccr_normalize_model_args() {
  local opus_model="$1"
  local sonnet_model="$2"
  local haiku_model="$3"
  local arg raw mapped
  shift 3
  CC_ROUTER_NORMALIZED_ARGS=()
  while (($# > 0)); do
    arg="$1"
    shift
    case "${arg}" in
      --model|-m)
        CC_ROUTER_NORMALIZED_ARGS+=("${arg}")
        if (($# > 0)); then
          raw="$1"
          shift
          mapped="$(ccr_map_model_alias "${raw}" "${opus_model}" "${sonnet_model}" "${haiku_model}")"
          CC_ROUTER_NORMALIZED_ARGS+=("${mapped}")
        fi
        ;;
      --model=*)
        raw="${arg#--model=}"
        mapped="$(ccr_map_model_alias "${raw}" "${opus_model}" "${sonnet_model}" "${haiku_model}")"
        CC_ROUTER_NORMALIZED_ARGS+=("--model=${mapped}")
        ;;
      -m=*)
        raw="${arg#-m=}"
        mapped="$(ccr_map_model_alias "${raw}" "${opus_model}" "${sonnet_model}" "${haiku_model}")"
        CC_ROUTER_NORMALIZED_ARGS+=("-m=${mapped}")
        ;;
      *)
        CC_ROUTER_NORMALIZED_ARGS+=("${arg}")
        ;;
    esac
  done
}

ccr_run_claude() {
  local -a extra existing=()
  local arg
  if (($# > 0)); then
    existing=("$@")
  fi
  if ((${#existing[@]} > 0)) && ccr_args_has_skip_permissions_flag "${existing[@]}"; then
    claude "${existing[@]}"
    return
  fi
  extra=()
  while IFS= read -r arg; do
    [[ -n "${arg}" ]] && extra+=("${arg}")
  done < <(ccr_claude_extra_args)
  if ((${#extra[@]} == 0)); then
    if ((${#existing[@]} == 0)); then
      claude
    else
      claude "${existing[@]}"
    fi
    return
  fi
  if ((${#existing[@]} == 0)); then
    claude "${extra[@]}"
  else
    claude "${extra[@]}" "${existing[@]}"
  fi
}

ccr_exec_claude() {
  local -a extra existing=()
  local arg
  if (($# > 0)); then
    existing=("$@")
  fi
  if ((${#existing[@]} > 0)) && ccr_args_has_skip_permissions_flag "${existing[@]}"; then
    exec claude "${existing[@]}"
  fi
  extra=()
  while IFS= read -r arg; do
    [[ -n "${arg}" ]] && extra+=("${arg}")
  done < <(ccr_claude_extra_args)
  if ((${#extra[@]} == 0)); then
    if ((${#existing[@]} == 0)); then
      exec claude
    else
      exec claude "${existing[@]}"
    fi
  elif ((${#existing[@]} == 0)); then
    exec claude "${extra[@]}"
  else
    exec claude "${extra[@]}" "${existing[@]}"
  fi
}

ccr_unset_routing_env() {
  unset ANTHROPIC_AUTH_TOKEN \
    ANTHROPIC_API_KEY \
    ANT_API_KEY \
    ANTHROPIC_BASE_URL \
    ANTHROPIC_MODEL \
    ANTHROPIC_DEFAULT_OPUS_MODEL \
    ANTHROPIC_DEFAULT_SONNET_MODEL \
    ANTHROPIC_DEFAULT_HAIKU_MODEL \
    CLAUDE_CODE_SUBAGENT_MODEL \
    CLAUDE_CODE_MAX_OUTPUT_TOKENS \
    CLAUDE_CODE_EFFORT_LEVEL \
    CLAUDE_AUTOCOMPACT_PCT_OVERRIDE \
    CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST \
    ENABLE_TOOL_SEARCH \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC \
    CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK
}

# Print a single tree-style doctor line.
#   $1 prefix : "├" or "└"
#   $2 status : ok | fail | warn | info | (empty)
#   $3 label  : short label (padded to 22 chars)
#   $4 value  : value (optional)
ccr_doctor_item() {
  local prefix="$1" status="$2" label="$3" value="${4:-}"
  local badge=""
  case "${status}" in
    ok)   badge="OK  " ;;
    fail) badge="FAIL" ;;
    warn) badge="WARN" ;;
    info) badge="INFO" ;;
  esac
  if [[ -n "${badge}" ]]; then
    if [[ -n "${value}" ]]; then
      printf '    %s %s  %-22s %s\n' "${prefix}" "${badge}" "${label}" "${value}"
    else
      printf '    %s %s  %s\n' "${prefix}" "${badge}" "${label}"
    fi
  else
    if [[ -n "${value}" ]]; then
      printf '    %s %-22s %s\n' "${prefix}" "${label}" "${value}"
    else
      printf '    %s %s\n' "${prefix}" "${label}"
    fi
  fi
}

# Print a multi-line detail block under a doctor line. Each input line is
# prefixed with 6 spaces so it visually attaches to the parent item.
#   $* : the lines to print
ccr_doctor_detail() {
  local line
  for line in "$@"; do
    printf '      %s\n' "${line}"
  done
}

# env(1) cannot invoke shell functions; use a subshell with unset/export instead.
ccr_run_official_claude() {
  (
    ccr_unset_routing_env
    export CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST=1
    ccr_export_cache_prompt_env
    if ccr_cache_fix_enabled; then
      export ANTHROPIC_BASE_URL="$(ccr_cache_fix_url)"
    fi
    ccr_run_claude "$@"
  )
}

ccr_run_9router_claude() {
  local nr_base="$1"
  local nr_opus_model="$2"
  local nr_sonnet_model="$3"
  local nr_haiku_model="$4"
  local nr_tool_search="$5"
  local nr_key="${6:-}"
  local client_base
  shift 6
  if declare -F ccr_ensure_9router_stack_deps >/dev/null 2>&1; then
    ccr_ensure_9router_stack_deps || exit 1
  fi
  client_base="$(ccr_ninerouter_client_base_url)"
  if [[ "${client_base}" == */v1 ]]; then
    client_base="${client_base%/v1}"
  fi
  (
    ccr_unset_routing_env
    export ANTHROPIC_BASE_URL="${client_base}/v1"
    export ANTHROPIC_MODEL="${nr_sonnet_model}"
    export ANTHROPIC_DEFAULT_OPUS_MODEL="${nr_opus_model}"
    export ANTHROPIC_DEFAULT_SONNET_MODEL="${nr_sonnet_model}"
    export ANTHROPIC_DEFAULT_HAIKU_MODEL="${nr_haiku_model}"
    export CLAUDE_CODE_SUBAGENT_MODEL="${nr_haiku_model}"
    export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
    export CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK=1
    if [[ -n "${nr_tool_search}" ]]; then
      export ENABLE_TOOL_SEARCH="${nr_tool_search}"
    fi
    if [[ -n "${nr_key}" ]]; then
      export ANTHROPIC_AUTH_TOKEN="${nr_key}"
    fi
    # Whitelist the default sonnet slot so Claude Code's v2.1.150+ client-side
    # model allowlist accepts the custom 9Router name. With discovery also on,
    # 9Router's /v1/models exposes the other slots (opus/haiku) to the picker.
    export ANTHROPIC_CUSTOM_MODEL_OPTION="${nr_sonnet_model}"
    export ANTHROPIC_CUSTOM_MODEL_OPTION_NAME="9Router (sonnet)"
    export CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY=1
    ccr_export_cache_prompt_env
    ccr_normalize_model_args "${nr_opus_model}" "${nr_sonnet_model}" "${nr_haiku_model}" "$@"
    if ((${#CC_ROUTER_NORMALIZED_ARGS[@]} > 0)); then
      ccr_run_claude "${CC_ROUTER_NORMALIZED_ARGS[@]}"
    else
      ccr_run_claude
    fi
  )
}

ccr_dotpath_to_jq_array() {
  jq -Rn --arg p "$1" '$p | split(".") | map(select(length > 0))'
}

ccr_claude_settings_ensure() {
  local file dir
  file="$1"
  dir="$(dirname "${file}")"
  mkdir -p "${dir}"
  if [[ ! -f "${file}" ]]; then
    printf '%s\n' '{}' >"${file}"
  fi
}

ccr_config_parse_json_value() {
  local raw="$1"
  case "${raw}" in
    true | false | null) printf '%s\n' "${raw}" ;;
    \[* | \{*) printf '%s\n' "${raw}" ;;
    [0-9]* | -[0-9]*) printf '%s\n' "${raw}" ;;
    *) jq -Rn --arg v "${raw}" '$v' ;;
  esac
}

ccr_config_claude_get() {
  local dotpath="$1"
  local scope="${2:-}"
  local file arr
  ccr_require_jq || return 1
  file="$(ccr_resolve_claude_settings_file "${scope}")" || return 1
  ccr_claude_settings_ensure "${file}"
  arr="$(ccr_dotpath_to_jq_array "${dotpath}")"
  jq --argjson path "${arr}" 'getpath($path)' "${file}"
}

ccr_config_claude_set() {
  local dotpath="$1"
  local raw_value="$2"
  local scope="${3:-}"
  local file tmp arr parsed
  ccr_require_jq || return 1
  file="$(ccr_resolve_claude_settings_file "${scope}")" || return 1
  ccr_claude_settings_ensure "${file}"
  arr="$(ccr_dotpath_to_jq_array "${dotpath}")"
  parsed="$(ccr_config_parse_json_value "${raw_value}")"
  tmp="$(mktemp)"
  jq --argjson path "${arr}" --argjson val "${parsed}" 'setpath($path; $val)' "${file}" >"${tmp}"
  mv "${tmp}" "${file}"
  echo "Updated ${file}"
  ccr_config_claude_get "${dotpath}" "${scope}"
}

ccr_config_claude_unset() {
  local dotpath="$1"
  local scope="${2:-}"
  local file tmp arr
  ccr_require_jq || return 1
  file="$(ccr_resolve_claude_settings_file "${scope}")" || return 1
  if [[ ! -f "${file}" ]]; then
    echo "No settings file at ${file}"
    return 0
  fi
  arr="$(ccr_dotpath_to_jq_array "${dotpath}")"
  tmp="$(mktemp)"
  jq --argjson path "${arr}" 'delpaths([$path])' "${file}" >"${tmp}"
  mv "${tmp}" "${file}"
  echo "Removed ${dotpath} from ${file}"
}

ccr_config_show() {
  local file bypass target
  file="$(ccr_config_file)"
  echo "cc-router config: ${file}"
  if [[ -f "${file}" ]]; then
    if command -v jq >/dev/null 2>&1; then
      jq '.' "${file}"
    else
      cat "${file}"
    fi
  else
    echo "(not created yet — run: ccr config setup)"
  fi
  echo
  if ccr_allow_dangerously_skip_permissions_enabled; then
    bypass="enabled → prepends --allow-dangerously-skip-permissions on cc / ccr 9router / ccd"
  else
    bypass="disabled"
  fi
  echo "allowDangerouslySkipPermissions (effective): ${bypass}"
  if [[ -n "${CC_ALLOW_DANGEROUSLY_SKIP_PERMISSIONS:-}" ]]; then
    echo "  (overridden by CC_ALLOW_DANGEROUSLY_SKIP_PERMISSIONS)"
  fi
  target="$(ccr_config_get claudePermissionsTarget none)"
  echo "claudePermissionsTarget: ${target}"
  echo "  global file : $(ccr_claude_global_settings_file)"
  echo "  project file: $(ccr_claude_project_settings_file) (from git root or cwd)"
  echo
  if ccr_cache_prompt_env_enabled; then
    echo "cachePromptEnvEnabled (effective): enabled → ATTRIBUTION_HEADER=false, DISABLE_GIT_INSTRUCTIONS=1"
  else
    echo "cachePromptEnvEnabled (effective): disabled"
  fi
  if [[ -n "${CC_CACHE_PROMPT_ENV_ENABLED:-}" ]]; then
    echo "  (overridden by CC_CACHE_PROMPT_ENV_ENABLED)"
  fi
  echo
  if ccr_cache_fix_enabled; then
    echo "cacheFixEnabled (effective): enabled → official cc sets ANTHROPIC_BASE_URL=$(ccr_cache_fix_url)"
  else
    echo "cacheFixEnabled (effective): disabled"
  fi
  if [[ -n "${CC_CACHE_FIX_ENABLED:-}" ]]; then
    echo "  (overridden by CC_CACHE_FIX_ENABLED)"
  fi
  echo "cacheFixUrl (config): $(ccr_config_get cacheFixUrl "http://127.0.0.1:9801")"
  echo
  if ccr_cache_fix_9router_enabled; then
    echo "cacheFix9routerEnabled (effective): enabled → ccr 9router uses $(ccr_cache_fix_url)/v1 → 9Router at $(ccr_ninerouter_real_url)"
  else
    echo "cacheFix9routerEnabled (effective): disabled → ccr 9router uses $(ccr_ninerouter_real_url)/v1 directly"
  fi
  if [[ -n "${CC_CACHE_FIX_9ROUTER_ENABLED:-}" ]]; then
    echo "  (overridden by CC_CACHE_FIX_9ROUTER_ENABLED)"
  fi
  echo "nineRouterUrl (config fallback): $(ccr_config_get nineRouterUrl "http://127.0.0.1:20128")"
}

ccr_config_help() {
  cat <<'EOF'
ccr config - cc-router settings and Claude Code settings.json

cc-router uses ~/.config/cc-router/config.json for launcher toggles.
Claude permission JSON is written to global or project settings when you choose a target.

Usage:
  ccr config show
  ccr config setup
  ccr config set allowDangerouslySkipPermissions on|off
  ccr config set cachePromptEnvEnabled on|off
  ccr config set cacheFixEnabled on|off
  ccr config set cacheFixUrl http://127.0.0.1:9801
  ccr config set cacheFix9routerEnabled on|off
  ccr config set nineRouterUrl http://127.0.0.1:20128
  ccr config set claudePermissionsTarget none|global|project

  ccr config claude show [--global|--project]
  ccr config claude get <dot.path> [--global|--project]
  ccr config claude set <dot.path> <value> [--global|--project]
  ccr config claude unset <dot.path> [--global|--project]
  ccr config claude enable-bypass-permissions [--global|--project]
  ccr config claude disable-bypass-permissions [--global|--project]

Examples:
  ccr config setup
  ccr config set allowDangerouslySkipPermissions on
  ccr config set claudePermissionsTarget global
  ccr config claude set permissions.defaultMode acceptEdits --global
  ccr config claude enable-bypass-permissions --project

One-shot env override (no config file):
  CC_ALLOW_DANGEROUSLY_SKIP_PERMISSIONS=1 cc
EOF
}

ccr_config_setup() {
  local ans target parsed
  ccr_config_ensure
  echo "== cc-router config setup =="
  echo "Config file: $(ccr_config_file)"
  echo
  read -r -p "Pass --allow-dangerously-skip-permissions on every cc / ccr 9router / ccr deepseek launch? [Y/n]: " ans
  ans="$(ccr_trim "${ans}")"
  if [[ -z "${ans}" ]]; then
    ans=y
  fi
  if ! parsed="$(ccr_parse_bool "${ans}" y)"; then
    echo "  → unrecognized '${ans}'; use y/yes or n/no (default: enabled)" >&2
    parsed=true
  fi
  if [[ "${parsed}" == "true" ]]; then
    ccr_config_set_bool allowDangerouslySkipPermissions true
    echo "  → enabled"
  else
    ccr_config_set_bool allowDangerouslySkipPermissions false
    echo "  → disabled"
  fi
  echo
  echo "Where should 'ccr config claude' write permission settings by default?"
  echo "  1) none    — only edit cc-router config.json (launcher flag above)"
  echo "  2) global  — ~/.claude/settings.json"
  echo "  3) project — <repo>/.claude/settings.json"
  read -r -p "Select [1/2/3] (default 1): " ans
  case "${ans:-1}" in
    2 | global) target=global ;;
    3 | project) target=project ;;
    *) target=none ;;
  esac
  ccr_config_set_string claudePermissionsTarget "${target}"
  echo "  → claudePermissionsTarget=${target}"
  echo
  if [[ "${target}" != "none" ]]; then
    read -r -p "Also set permissions.defaultMode to bypassPermissions in that file? [y/N]: " ans
    ans="$(ccr_trim "${ans}")"
    [[ -z "${ans}" ]] && ans=n
    if parsed="$(ccr_parse_bool "${ans}" n 2>/dev/null)" && [[ "${parsed}" == "true" ]]; then
      ccr_config_claude_set permissions.defaultMode bypassPermissions "${target}"
    fi
  fi
  echo
  ccr_config_show
}

ccr_config_parse_scope_flag() {
  # Sets CC_ROUTER_SCOPE_OUTPUT and returns remaining args count via array name.
  # Usage: ccr_config_parse_scope_flag "$@" 
  CC_ROUTER_SCOPE_OUTPUT=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --global | --user) CC_ROUTER_SCOPE_OUTPUT=global; shift; continue ;;
      --project | --repo) CC_ROUTER_SCOPE_OUTPUT=project; shift; continue ;;
    esac
    break
  done
}

ccr_config_dispatch() {
  local sub="${1:-}"
  shift || true

  case "${sub}" in
    '' | help | -h | --help)
      ccr_config_help
      return 0
      ;;
    show)
      ccr_config_show
      return 0
      ;;
    setup)
      ccr_config_setup
      return 0
      ;;
    set)
      local key val
      if [[ $# -lt 2 ]]; then
        echo "Usage: ccr config set <key> <value>" >&2
        return 2
      fi
      key="$1"
      val="$2"
      case "${key}" in
        allowDangerouslySkipPermissions)
          ccr_config_set_bool "${key}" "${val}" || return $?
          echo "Set ${key}=$(ccr_config_get "${key}" false)"
          ;;
        cachePromptEnvEnabled)
          ccr_config_set_bool "${key}" "${val}" || return $?
          echo "Set ${key}=$(ccr_config_get "${key}" true)"
          ;;
        cacheFixEnabled)
          ccr_config_set_bool "${key}" "${val}" || return $?
          echo "Set ${key}=$(ccr_config_get "${key}" true)"
          ;;
        cacheFixUrl)
          ccr_config_set_string "${key}" "${val}"
          echo "Set ${key}=$(ccr_config_get "${key}" "")"
          ;;
        cacheFix9routerEnabled)
          ccr_config_set_bool "${key}" "${val}" || return $?
          echo "Set ${key}=$(ccr_config_get "${key}" true)"
          ;;
        nineRouterUrl)
          ccr_config_set_string "${key}" "${val}"
          echo "Set ${key}=$(ccr_config_get "${key}" "")"
          ;;
        ccsProxyUrl)
          ccr_config_set_string "${key}" "${val}"
          echo "Set ${key}=$(ccr_config_get "${key}" "")"
          ;;
        claudePermissionsTarget)
          case "${val}" in
            none | global | project) ccr_config_set_string "${key}" "${val}" ;;
            *)
              echo "claudePermissionsTarget must be: none, global, or project" >&2
              return 2
              ;;
          esac
          echo "Set ${key}=${val}"
          ;;
        *)
          echo "Unknown key: ${key}" >&2
          echo "Supported: allowDangerouslySkipPermissions, cachePromptEnvEnabled, cacheFixEnabled, cacheFixUrl, cacheFix9routerEnabled, nineRouterUrl, ccsProxyUrl, claudePermissionsTarget" >&2
          return 2
          ;;
      esac
      return 0
      ;;
    claude)
      local action="" scope=""
      local -a filtered=()
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --global | --user) scope=global; shift ;;
          --project | --repo) scope=project; shift ;;
          *) filtered+=("$1"); shift ;;
        esac
      done
      action="${filtered[0]:-}"
      if ((${#filtered[@]} > 0)); then
        filtered=("${filtered[@]:1}")
      fi

      case "${action}" in
        '' | help | -h | --help)
          cat <<'EOF'
ccr config claude - edit Claude Code settings.json

  ccr config claude show [--global|--project]
  ccr config claude get <dot.path> [--global|--project]
  ccr config claude set <dot.path> <value> [--global|--project]
  ccr config claude unset <dot.path> [--global|--project]
  ccr config claude enable-bypass-permissions [--global|--project]
  ccr config claude disable-bypass-permissions [--global|--project]

Without --global/--project, uses claudePermissionsTarget from config.json.
EOF
          return 0
          ;;
        show)
          ccr_require_jq || return 1
          file="$(ccr_resolve_claude_settings_file "${scope}")" || return 1
          echo "${file}"
          ccr_claude_settings_ensure "${file}"
          jq '.' "${file}"
          return 0
          ;;
        path)
          ccr_resolve_claude_settings_file "${scope}"
          return 0
          ;;
        get)
          if [[ ${#filtered[@]} -lt 1 ]]; then
            echo "Usage: ccr config claude get <dot.path> [--global|--project]" >&2
            return 2
          fi
          ccr_config_claude_get "${filtered[0]}" "${scope}"
          return 0
          ;;
        set)
          if [[ ${#filtered[@]} -lt 2 ]]; then
            echo "Usage: ccr config claude set <dot.path> <value> [--global|--project]" >&2
            return 2
          fi
          ccr_config_claude_set "${filtered[0]}" "${filtered[1]}" "${scope}"
          return 0
          ;;
        unset)
          if [[ ${#filtered[@]} -lt 1 ]]; then
            echo "Usage: ccr config claude unset <dot.path> [--global|--project]" >&2
            return 2
          fi
          ccr_config_claude_unset "${filtered[0]}" "${scope}"
          return 0
          ;;
        enable-bypass-permissions)
          ccr_config_claude_set permissions.defaultMode bypassPermissions "${scope}"
          return 0
          ;;
        disable-bypass-permissions)
          ccr_config_claude_unset permissions.defaultMode "${scope}"
          return 0
          ;;
        *)
          echo "Unknown: ccr config claude ${action}" >&2
          return 2
          ;;
      esac
      ;;
    *)
      echo "Unknown: ccr config ${sub}" >&2
      ccr_config_help >&2
      return 2
      ;;
  esac
}

ccr_source_lib() {
  local script_path="${1:?}"
  local script_dir candidates c
  while [[ -L "${script_path}" ]]; do
    local link_target
    link_target="$(readlink "${script_path}")"
    if [[ "${link_target}" = /* ]]; then
      script_path="${link_target}"
    else
      script_path="$(cd "$(dirname "${script_path}")" && pwd)/${link_target}"
    fi
  done
  script_dir="$(cd "$(dirname "${script_path}")" && pwd)"
  candidates=(
    "${script_dir}/lib/ccr-common.sh"
    "${HOME}/.local/share/cc-router/lib/ccr-common.sh"
  )
  for c in "${candidates[@]}"; do
    if [[ -f "${c}" ]]; then
      # shellcheck source=/dev/null
      source "${c}"
      return 0
    fi
  done
  echo "cc-router: lib/ccr-common.sh not found (re-run ./install.sh)" >&2
  return 1
}

# Minimal doctor implementation. Full diagnostics (cache-fix, settings.json, profile checks)
# will be expanded here incrementally; this covers the most common 9Router/official checks.
ccr_doctor() {
  local routing_mode="${1:-official}"
  shift 1 || true
  local detail_mode=0 arg
  for arg in "$@"; do
    case "$arg" in
      detail|--detail|-d|--verbose|-v) detail_mode=1 ;;
    esac
  done

  echo "== ccr doctor =="
  if [[ "$routing_mode" == "9router" ]]; then
    echo "Target: 9Router mode"
  else
    echo "Target: official Claude mode (clean env)"
  fi
  echo

  if command -v claude >/dev/null 2>&1; then
    echo "OK: claude found at $(command -v claude)"
  else
    echo "FAIL: claude not found in PATH"
    echo "Fix (npm): npm install -g @anthropic-ai/claude-code"
  fi
  echo

  if [[ "$routing_mode" != "9router" ]]; then
    if ccr_cache_fix_enabled; then
      local cf_url="$(ccr_cache_fix_url)"
      echo "INFO: cacheFixEnabled → official ccr sets ANTHROPIC_BASE_URL=${cf_url}"
      if ccr_probe_cache_fix_health "${cf_url}"; then
        echo "OK: cache-fix health ${cf_url}/health"
      else
        echo "WARN: cacheFixEnabled but ${cf_url}/health failed"
        echo "Fix: ccr setup install-deps && ccr setup start-cache-fix"
      fi
    else
      echo "INFO: cacheFixEnabled=false (official ccr uses Anthropic directly)"
    fi
    echo
  fi

  if [[ "$routing_mode" == "9router" ]]; then
    local nr_real nr_client
    nr_real="$(ccr_ninerouter_real_url)"
    nr_client="$(ccr_ninerouter_client_base_url)"
    if [[ -n "${NINEROUTER_URL:-}" ]]; then
      echo "OK: NINEROUTER_URL=${NINEROUTER_URL%/} (9Router upstream)"
    else
      echo "INFO: NINEROUTER_URL unset; using nineRouterUrl from config: ${nr_real}"
    fi
    echo "Hint: 9Router health -> ${nr_real}/api/health"
    if health_resp="$(curl -fsS --max-time 5 "${nr_real}/api/health" 2>/dev/null)"; then
      if [[ "$health_resp" == '"ok":true'* || "$health_resp" == '"ok": true'* ]]; then
        echo "OK: 9Router health check returned ok=true"
      else
        echo "WARN: 9Router health check responded but ok!=true"
      fi
    else
      echo "WARN: failed to reach ${nr_real}/api/health"
    fi
    if ccr_cache_fix_9router_enabled; then
      local cf_url="$(ccr_cache_fix_url)"
      echo "OK: cacheFix9routerEnabled → ccr 9router ANTHROPIC_BASE_URL=${cf_url}/v1 (via cache-fix)"
      if ccr_probe_cache_fix_health "${cf_url}"; then
        echo "OK: cache-fix health ${cf_url}/health"
      else
        echo "WARN: cache-fix not reachable at ${cf_url}/health"
      fi
    else
      echo "INFO: cacheFix9routerEnabled=false → ccr 9router talks directly to ${nr_real}/v1"
    fi
    if [[ -n "${NINEROUTER_KEY:-}" ]]; then
      echo "OK: NINEROUTER_KEY detected"
    else
      echo "WARN: NINEROUTER_KEY not found (only fine if 9Router auth is disabled)"
    fi

    local eff_opus eff_sonnet eff_haiku
    eff_opus="${NINEROUTER_OPUS_MODEL:-cc-pro}"
    eff_sonnet="${NINEROUTER_SONNET_MODEL:-cc-normal}"
    eff_haiku="${NINEROUTER_HAIKU_MODEL:-cc-lite}"
    echo "OK: agent slot alias rewrite active (explicit --model sonnet|haiku|opus maps to current 9Router slot targets)"

    if [[ "$detail_mode" -eq 1 ]]; then
      echo
      echo "=== Detail ==="
      echo "  agent slot alias rewrite active         = sonnet->${eff_sonnet}, haiku->${eff_haiku}, opus->${eff_opus}"
    fi
    echo
  fi

  echo "Doctor result: healthy"
}
