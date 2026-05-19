# cc-router shared bash helpers (sourced by scripts/cc and scripts/ccd).

cc_router_config_dir() {
  printf '%s\n' "${XDG_CONFIG_HOME:-${HOME}/.config}/cc-router"
}

cc_router_config_file() {
  printf '%s\n' "$(cc_router_config_dir)/config.json"
}

cc_router_claude_global_settings_file() {
  printf '%s\n' "${HOME}/.claude/settings.json"
}

cc_router_claude_project_settings_file() {
  local root
  root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  printf '%s\n' "${root}/.claude/settings.json"
}

cc_router_require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "cc config: jq is required. Install: brew install jq  (or apt install jq)" >&2
    return 1
  fi
}

cc_router_truthy() {
  local v
  v="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "${v}" in
    1 | true | yes | on | enable | enabled) return 0 ;;
    *) return 1 ;;
  esac
}

cc_router_config_ensure() {
  local dir file
  dir="$(cc_router_config_dir)"
  file="$(cc_router_config_file)"
  mkdir -p "${dir}"
  if [[ ! -f "${file}" ]]; then
    cat >"${file}" <<'EOF'
{
  "allowDangerouslySkipPermissions": false,
  "claudePermissionsTarget": "none"
}
EOF
  fi
}

cc_router_config_get() {
  local key="$1"
  local default="${2:-}"
  local file val
  file="$(cc_router_config_file)"
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

cc_router_config_set_bool() {
  local key="$1"
  local value="$2"
  local file tmp bool_json
  cc_router_require_jq || return 1
  cc_router_config_ensure
  file="$(cc_router_config_file)"
  if cc_router_truthy "${value}"; then
    bool_json=true
  else
    bool_json=false
  fi
  tmp="$(mktemp)"
  jq --arg k "${key}" --argjson v "${bool_json}" '.[$k] = $v' "${file}" >"${tmp}"
  mv "${tmp}" "${file}"
}

cc_router_config_set_string() {
  local key="$1"
  local value="$2"
  local file tmp
  cc_router_require_jq || return 1
  cc_router_config_ensure
  file="$(cc_router_config_file)"
  tmp="$(mktemp)"
  jq --arg k "${key}" --arg v "${value}" '.[$k] = $v' "${file}" >"${tmp}"
  mv "${tmp}" "${file}"
}

cc_router_allow_dangerously_skip_permissions_enabled() {
  if [[ -n "${CC_ALLOW_DANGEROUSLY_SKIP_PERMISSIONS:-}" ]]; then
    cc_router_truthy "${CC_ALLOW_DANGEROUSLY_SKIP_PERMISSIONS}"
    return $?
  fi
  cc_router_truthy "$(cc_router_config_get allowDangerouslySkipPermissions false)"
}

cc_router_resolve_claude_settings_file() {
  local scope="${1:-}"
  if [[ -z "${scope}" ]]; then
    scope="$(cc_router_config_get claudePermissionsTarget none)"
  fi
  case "${scope}" in
    global | user)
      cc_router_claude_global_settings_file
      ;;
    project | repo)
      cc_router_claude_project_settings_file
      ;;
    none)
      echo "cc config: claudePermissionsTarget is 'none'; pass --global or --project" >&2
      return 1
      ;;
    *)
      echo "cc config: unknown scope '${scope}' (use global or project)" >&2
      return 1
      ;;
  esac
}

cc_router_claude_extra_args() {
  if cc_router_allow_dangerously_skip_permissions_enabled; then
    printf '%s\n' --allow-dangerously-skip-permissions
  fi
}

cc_router_args_has_skip_permissions_flag() {
  local arg
  for arg in "$@"; do
    if [[ "${arg}" == "--allow-dangerously-skip-permissions" || "${arg}" == "--dangerously-skip-permissions" ]]; then
      return 0
    fi
  done
  return 1
}

cc_router_run_claude() {
  local -a extra existing=()
  local arg
  if (($# > 0)); then
    existing=("$@")
  fi
  if ((${#existing[@]} > 0)) && cc_router_args_has_skip_permissions_flag "${existing[@]}"; then
    claude "${existing[@]}"
    return
  fi
  extra=()
  while IFS= read -r arg; do
    [[ -n "${arg}" ]] && extra+=("${arg}")
  done < <(cc_router_claude_extra_args)
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

cc_router_exec_claude() {
  local -a extra existing=()
  local arg
  if (($# > 0)); then
    existing=("$@")
  fi
  if ((${#existing[@]} > 0)) && cc_router_args_has_skip_permissions_flag "${existing[@]}"; then
    exec claude "${existing[@]}"
  fi
  extra=()
  while IFS= read -r arg; do
    [[ -n "${arg}" ]] && extra+=("${arg}")
  done < <(cc_router_claude_extra_args)
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

cc_router_unset_routing_env() {
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

# env(1) cannot invoke shell functions; use a subshell with unset/export instead.
cc_router_run_official_claude() {
  (
    cc_router_unset_routing_env
    export CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST=1
    cc_router_run_claude "$@"
  )
}

cc_router_run_9router_claude() {
  local nr_base="$1"
  local nr_opus_model="$2"
  local nr_sonnet_model="$3"
  local nr_haiku_model="$4"
  local nr_tool_search="$5"
  local nr_key="${6:-}"
  shift 6
  (
    cc_router_unset_routing_env
    export ANTHROPIC_BASE_URL="${nr_base}/v1"
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
    cc_router_run_claude "$@"
  )
}

cc_router_dotpath_to_jq_array() {
  jq -Rn --arg p "$1" '$p | split(".") | map(select(length > 0))'
}

cc_router_claude_settings_ensure() {
  local file dir
  file="$1"
  dir="$(dirname "${file}")"
  mkdir -p "${dir}"
  if [[ ! -f "${file}" ]]; then
    printf '%s\n' '{}' >"${file}"
  fi
}

cc_router_config_parse_json_value() {
  local raw="$1"
  case "${raw}" in
    true | false | null) printf '%s\n' "${raw}" ;;
    \[* | \{*) printf '%s\n' "${raw}" ;;
    [0-9]* | -[0-9]*) printf '%s\n' "${raw}" ;;
    *) jq -Rn --arg v "${raw}" '$v' ;;
  esac
}

cc_router_config_claude_get() {
  local dotpath="$1"
  local scope="${2:-}"
  local file arr
  cc_router_require_jq || return 1
  file="$(cc_router_resolve_claude_settings_file "${scope}")" || return 1
  cc_router_claude_settings_ensure "${file}"
  arr="$(cc_router_dotpath_to_jq_array "${dotpath}")"
  jq --argjson path "${arr}" 'getpath($path)' "${file}"
}

cc_router_config_claude_set() {
  local dotpath="$1"
  local raw_value="$2"
  local scope="${3:-}"
  local file tmp arr parsed
  cc_router_require_jq || return 1
  file="$(cc_router_resolve_claude_settings_file "${scope}")" || return 1
  cc_router_claude_settings_ensure "${file}"
  arr="$(cc_router_dotpath_to_jq_array "${dotpath}")"
  parsed="$(cc_router_config_parse_json_value "${raw_value}")"
  tmp="$(mktemp)"
  jq --argjson path "${arr}" --argjson val "${parsed}" 'setpath($path; $val)' "${file}" >"${tmp}"
  mv "${tmp}" "${file}"
  echo "Updated ${file}"
  cc_router_config_claude_get "${dotpath}" "${scope}"
}

cc_router_config_claude_unset() {
  local dotpath="$1"
  local scope="${2:-}"
  local file tmp arr
  cc_router_require_jq || return 1
  file="$(cc_router_resolve_claude_settings_file "${scope}")" || return 1
  if [[ ! -f "${file}" ]]; then
    echo "No settings file at ${file}"
    return 0
  fi
  arr="$(cc_router_dotpath_to_jq_array "${dotpath}")"
  tmp="$(mktemp)"
  jq --argjson path "${arr}" 'delpaths([$path])' "${file}" >"${tmp}"
  mv "${tmp}" "${file}"
  echo "Removed ${dotpath} from ${file}"
}

cc_router_config_show() {
  local file bypass target
  file="$(cc_router_config_file)"
  echo "cc-router config: ${file}"
  if [[ -f "${file}" ]]; then
    if command -v jq >/dev/null 2>&1; then
      jq '.' "${file}"
    else
      cat "${file}"
    fi
  else
    echo "(not created yet — run: cc config setup)"
  fi
  echo
  if cc_router_allow_dangerously_skip_permissions_enabled; then
    bypass="enabled → prepends --allow-dangerously-skip-permissions on cc / cc -9 / ccd"
  else
    bypass="disabled"
  fi
  echo "allowDangerouslySkipPermissions (effective): ${bypass}"
  if [[ -n "${CC_ALLOW_DANGEROUSLY_SKIP_PERMISSIONS:-}" ]]; then
    echo "  (overridden by CC_ALLOW_DANGEROUSLY_SKIP_PERMISSIONS)"
  fi
  target="$(cc_router_config_get claudePermissionsTarget none)"
  echo "claudePermissionsTarget: ${target}"
  echo "  global file : $(cc_router_claude_global_settings_file)"
  echo "  project file: $(cc_router_claude_project_settings_file) (from git root or cwd)"
}

cc_router_config_help() {
  cat <<'EOF'
cc config - cc-router settings and Claude Code settings.json

cc-router uses ~/.config/cc-router/config.json for launcher toggles.
Claude permission JSON is written to global or project settings when you choose a target.

Usage:
  cc config show
  cc config setup
  cc config set allowDangerouslySkipPermissions on|off
  cc config set claudePermissionsTarget none|global|project

  cc config claude show [--global|--project]
  cc config claude get <dot.path> [--global|--project]
  cc config claude set <dot.path> <value> [--global|--project]
  cc config claude unset <dot.path> [--global|--project]
  cc config claude enable-bypass-permissions [--global|--project]
  cc config claude disable-bypass-permissions [--global|--project]

Examples:
  cc config setup
  cc config set allowDangerouslySkipPermissions on
  cc config set claudePermissionsTarget global
  cc config claude set permissions.defaultMode acceptEdits --global
  cc config claude enable-bypass-permissions --project

One-shot env override (no config file):
  CC_ALLOW_DANGEROUSLY_SKIP_PERMISSIONS=1 cc
EOF
}

cc_router_config_setup() {
  local ans target
  cc_router_config_ensure
  echo "== cc-router config setup =="
  echo "Config file: $(cc_router_config_file)"
  echo
  read -r -p "Pass --allow-dangerously-skip-permissions on every cc / cc -9 / ccd launch? [y/N]: " ans
  if cc_router_truthy "${ans:-n}"; then
    cc_router_config_set_bool allowDangerouslySkipPermissions true
    echo "  → enabled"
  else
    cc_router_config_set_bool allowDangerouslySkipPermissions false
    echo "  → disabled"
  fi
  echo
  echo "Where should 'cc config claude' write permission settings by default?"
  echo "  1) none    — only edit cc-router config.json (launcher flag above)"
  echo "  2) global  — ~/.claude/settings.json"
  echo "  3) project — <repo>/.claude/settings.json"
  read -r -p "Select [1/2/3] (default 1): " ans
  case "${ans:-1}" in
    2 | global) target=global ;;
    3 | project) target=project ;;
    *) target=none ;;
  esac
  cc_router_config_set_string claudePermissionsTarget "${target}"
  echo "  → claudePermissionsTarget=${target}"
  echo
  if [[ "${target}" != "none" ]]; then
    read -r -p "Also set permissions.defaultMode to bypassPermissions in that file? [y/N]: " ans
    if cc_router_truthy "${ans:-n}"; then
      cc_router_config_claude_set permissions.defaultMode bypassPermissions "${target}"
    fi
  fi
  echo
  cc_router_config_show
}

cc_router_config_parse_scope_flag() {
  # Sets CC_ROUTER_SCOPE_OUTPUT and returns remaining args count via array name.
  # Usage: cc_router_config_parse_scope_flag "$@" 
  CC_ROUTER_SCOPE_OUTPUT=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --global | --user) CC_ROUTER_SCOPE_OUTPUT=global; shift; continue ;;
      --project | --repo) CC_ROUTER_SCOPE_OUTPUT=project; shift; continue ;;
    esac
    break
  done
}

cc_router_config_dispatch() {
  local sub="${1:-}"
  shift || true

  case "${sub}" in
    '' | help | -h | --help)
      cc_router_config_help
      return 0
      ;;
    show)
      cc_router_config_show
      return 0
      ;;
    setup)
      cc_router_config_setup
      return 0
      ;;
    set)
      local key val
      if [[ $# -lt 2 ]]; then
        echo "Usage: cc config set <key> <value>" >&2
        return 2
      fi
      key="$1"
      val="$2"
      case "${key}" in
        allowDangerouslySkipPermissions)
          if cc_router_truthy "${val}"; then
            cc_router_config_set_bool "${key}" true
          else
            cc_router_config_set_bool "${key}" false
          fi
          echo "Set ${key}=$(cc_router_config_get "${key}" false)"
          ;;
        claudePermissionsTarget)
          case "${val}" in
            none | global | project) cc_router_config_set_string "${key}" "${val}" ;;
            *)
              echo "claudePermissionsTarget must be: none, global, or project" >&2
              return 2
              ;;
          esac
          echo "Set ${key}=${val}"
          ;;
        *)
          echo "Unknown key: ${key}" >&2
          echo "Supported: allowDangerouslySkipPermissions, claudePermissionsTarget" >&2
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
cc config claude - edit Claude Code settings.json

  cc config claude show [--global|--project]
  cc config claude get <dot.path> [--global|--project]
  cc config claude set <dot.path> <value> [--global|--project]
  cc config claude unset <dot.path> [--global|--project]
  cc config claude enable-bypass-permissions [--global|--project]
  cc config claude disable-bypass-permissions [--global|--project]

Without --global/--project, uses claudePermissionsTarget from config.json.
EOF
          return 0
          ;;
        show)
          cc_router_require_jq || return 1
          file="$(cc_router_resolve_claude_settings_file "${scope}")" || return 1
          echo "${file}"
          cc_router_claude_settings_ensure "${file}"
          jq '.' "${file}"
          return 0
          ;;
        path)
          cc_router_resolve_claude_settings_file "${scope}"
          return 0
          ;;
        get)
          if [[ ${#filtered[@]} -lt 1 ]]; then
            echo "Usage: cc config claude get <dot.path> [--global|--project]" >&2
            return 2
          fi
          cc_router_config_claude_get "${filtered[0]}" "${scope}"
          return 0
          ;;
        set)
          if [[ ${#filtered[@]} -lt 2 ]]; then
            echo "Usage: cc config claude set <dot.path> <value> [--global|--project]" >&2
            return 2
          fi
          cc_router_config_claude_set "${filtered[0]}" "${filtered[1]}" "${scope}"
          return 0
          ;;
        unset)
          if [[ ${#filtered[@]} -lt 1 ]]; then
            echo "Usage: cc config claude unset <dot.path> [--global|--project]" >&2
            return 2
          fi
          cc_router_config_claude_unset "${filtered[0]}" "${scope}"
          return 0
          ;;
        enable-bypass-permissions)
          cc_router_config_claude_set permissions.defaultMode bypassPermissions "${scope}"
          return 0
          ;;
        disable-bypass-permissions)
          cc_router_config_claude_unset permissions.defaultMode "${scope}"
          return 0
          ;;
        *)
          echo "Unknown: cc config claude ${action}" >&2
          return 2
          ;;
      esac
      ;;
    *)
      echo "Unknown: cc config ${sub}" >&2
      cc_router_config_help >&2
      return 2
      ;;
  esac
}

cc_router_source_lib() {
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
    "${script_dir}/lib/cc-common.sh"
    "${HOME}/.local/share/cc-router/lib/cc-common.sh"
  )
  for c in "${candidates[@]}"; do
    if [[ -f "${c}" ]]; then
      # shellcheck source=/dev/null
      source "${c}"
      return 0
    fi
  done
  echo "cc-router: lib/cc-common.sh not found (re-run ./install.sh)" >&2
  return 1
}
