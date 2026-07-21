# cc-router setup intro and health checks (sourced by scripts/ccr).

# Global npm packages required for the default ccr 9router stack (9Router itself is separate).
CC_SETUP_PKG_CLAUDE='@anthropic-ai/claude-code'
CC_SETUP_PKG_CACHE_FIX='claude-code-cache-fix'

ccr_setup_pkg_cache_fix_present() {
  npm root -g >/dev/null 2>&1 && [[ -d "$(npm root -g)/claude-code-cache-fix" ]]
}

ccr_setup_missing_9router_stack_packages() {
  # Prints one package name per line (empty if all present).
  if ! command -v claude >/dev/null 2>&1; then
    printf '%s\n' "${CC_SETUP_PKG_CLAUDE}"
  fi
  if ccr_cache_fix_9router_enabled && ! ccr_setup_pkg_cache_fix_present; then
    printf '%s\n' "${CC_SETUP_PKG_CACHE_FIX}"
  fi
}

ccr_setup_read_yes_no() {
  local prompt="$1"
  local default_no="${2:-1}"
  local ans
  if [[ ! -t 0 ]] || [[ "${CC_ROUTER_NO_INSTALL_PROMPT:-}" == "1" ]]; then
    return 1
  fi
  if [[ "${default_no}" -eq 1 ]]; then
    read -r -p "${prompt} [y/N]: " ans </dev/tty 2>/dev/null || return 1
  else
    read -r -p "${prompt} [Y/n]: " ans </dev/tty 2>/dev/null || return 1
  fi
  ans="$(ccr_trim "${ans}")"
  ccr_truthy "${ans}"
}

ccr_setup_npm_install_global() {
  local pkg="$1"
  if ! command -v npm >/dev/null 2>&1; then
    echo "cc-router: npm not found; install Node.js first." >&2
    return 1
  fi
  echo "→ npm install -g ${pkg}"
  if ! npm install -g "${pkg}"; then
    echo "cc-router: npm install -g ${pkg} failed" >&2
    return 1
  fi
  return 0
}

# Install all missing ccr 9router stack npm packages (no prompts).
ccr_setup_install_deps() {
  local pkg failed=0
  while IFS= read -r pkg; do
    [[ -z "${pkg}" ]] && continue
    ccr_setup_npm_install_global "${pkg}" || failed=1
  done < <(ccr_setup_missing_9router_stack_packages)
  return "${failed}"
}

# Interactive: offer to npm install missing packages.
ccr_setup_offer_install_deps() {
  local -a missing=()
  local pkg
  while IFS= read -r pkg; do
    [[ -z "${pkg}" ]] && continue
    missing+=("${pkg}")
  done < <(ccr_setup_missing_9router_stack_packages)

  if ((${#missing[@]} == 0)); then
    return 0
  fi

  echo
  echo "ccr 9router needs these npm packages (global install):"
  for pkg in "${missing[@]}"; do
    echo "  • ${pkg}"
  done
  echo "9Router is not an npm package — start it separately (default http://127.0.0.1:20128)."
  echo

  if ! ccr_setup_read_yes_no "Install now with npm?"; then
    echo "Skipped. Later: ccr setup install-deps"
    echo "  or: npm install -g ${missing[*]}"
    return 1
  fi

  for pkg in "${missing[@]}"; do
    ccr_setup_npm_install_global "${pkg}" || return 1
  done
  echo "OK: npm packages installed."
  return 0
}

# Called before launching ccr 9router; prompts on TTY when packages missing.
ccr_ensure_9router_stack_deps() {
  local -a missing=()
  local pkg
  while IFS= read -r pkg; do
    [[ -z "${pkg}" ]] && continue
    missing+=("${pkg}")
  done < <(ccr_setup_missing_9router_stack_packages)

  if ((${#missing[@]} == 0)); then
    return 0
  fi

  echo "ccr 9router requires: ${missing[*]}" >&2
  if ccr_setup_offer_install_deps; then
    return 0
  fi
  echo "Install manually, then retry:" >&2
  echo "  ccr setup install-deps" >&2
  return 1
}

ccr_setup_print_architecture() {
  cat <<'EOF'
Stack (default ccr 9router):

  Claude Code
       |  ANTHROPIC_BASE_URL = cacheFixUrl/v1  (default http://127.0.0.1:9801/v1)
       |  + ENABLE_TOOL_SEARCH, ATTRIBUTION_HEADER=false, …
       v
  claude-code-cache-fix  (:9801)
       |  CACHE_FIX_PROXY_UPSTREAM = 9Router URL
       v
  9Router  (:20128)
       |  OAuth / model routing (cc-pro, cc-normal, cc-lite)
       v
  Provider APIs

Official `cc`: Claude Code → cache-fix → api.anthropic.com (no 9Router).
`ccd`: DeepSeek only (no cache-fix chain).

Full guide: docs/SETUP-GUIDE.md (repo) or ~/.local/share/cc-router/docs/SETUP-GUIDE.md (after ./install.sh).
EOF
}

ccr_setup_wait_cache_fix_health() {
  local base="${1:-http://127.0.0.1:9801}"
  local i
  base="${base%/}"
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    if ccr_probe_cache_fix_health "${base}"; then
      return 0
    fi
    sleep 0.5
  done
  return 1
}

ccr_setup_print_cache_fix_start() {
  local upstream cf
  upstream="$(ccr_ninerouter_real_url)"
  cf="$(ccr_cache_fix_url)"
  echo "Start cache-fix (run in a dedicated terminal or use: cache-fix-proxy install-service):"
  echo ""
  echo "  export CACHE_FIX_PROXY_UPSTREAM=${upstream}"
  echo "  node \"\$(npm root -g)/claude-code-cache-fix/proxy/server.mjs\""
  echo ""
  echo "Or background:"
  echo "  export CACHE_FIX_PROXY_UPSTREAM=${upstream}"
  echo "  node \"\$(npm root -g)/claude-code-cache-fix/proxy/server.mjs\" &"
  echo "  # wait ~1s, then: curl -fsS ${cf}/health"
}

ccr_setup_run_check() {
  local issues=0
  local nr cf

  echo "== ccr setup check =="
  echo

  if command -v claude >/dev/null 2>&1; then
    echo "OK: claude CLI found ($(command -v claude))"
  else
    issues=1
    echo "FAIL: claude CLI not found"
    echo "      npm install -g ${CC_SETUP_PKG_CLAUDE}"
  fi

  if command -v node >/dev/null 2>&1; then
    echo "OK: node $(node --version 2>/dev/null || true)"
  else
    issues=1
    echo "FAIL: node not found (required for cache-fix proxy)"
  fi

  if command -v npm >/dev/null 2>&1; then
    echo "OK: npm $(npm --version 2>/dev/null || true)"
  else
    echo "WARN: npm not found"
  fi

  nr="$(ccr_ninerouter_real_url)"
  echo
  echo "-- 9Router (${nr}) --"
  if curl -fsS --max-time 5 "${nr}/api/health" >/dev/null 2>&1; then
    echo "OK: ${nr}/api/health"
  else
    issues=1
    echo "FAIL: cannot reach ${nr}/api/health (start 9Router first)"
  fi

  if [[ -z "${NINEROUTER_KEY:-}" ]]; then
    echo "WARN: NINEROUTER_KEY not set (required if 9Router auth is enabled)"
  else
    echo "OK: NINEROUTER_KEY is set"
  fi

  cf="$(ccr_cache_fix_url)"
  echo
  echo "-- cache-fix (${cf}) --"
  if ccr_setup_pkg_cache_fix_present; then
    echo "OK: ${CC_SETUP_PKG_CACHE_FIX} package present"
  elif ccr_cache_fix_9router_enabled || ccr_cache_fix_enabled; then
    issues=1
    echo "FAIL: ${CC_SETUP_PKG_CACHE_FIX} not installed globally"
    echo "      npm install -g ${CC_SETUP_PKG_CACHE_FIX}"
  else
    echo "INFO: ${CC_SETUP_PKG_CACHE_FIX} not installed (cache-fix disabled in config)"
  fi

  if ccr_cache_fix_9router_enabled || ccr_cache_fix_enabled; then
    if ccr_probe_cache_fix_health "${cf}"; then
      echo "OK: ${cf}/health"
    else
      issues=1
      echo "FAIL: cache-fix not listening on ${cf}"
      echo
      ccr_setup_print_cache_fix_start
    fi
  else
    echo "INFO: cache-fix disabled in config (cacheFixEnabled / cacheFix9routerEnabled off)"
  fi

  echo
  echo "-- cc-router config (effective) --"
  if ccr_cache_prompt_env_enabled; then
    echo "OK: cachePromptEnvEnabled (attribution + git instructions)"
  else
    echo "INFO: cachePromptEnvEnabled off"
  fi
  if ccr_cache_fix_9router_enabled; then
    echo "OK: cacheFix9routerEnabled → ccr 9router uses ${cf}/v1 → ${nr}"
  else
    echo "INFO: cacheFix9routerEnabled off → ccr 9router direct to ${nr}/v1"
  fi
  if ccr_cache_fix_enabled; then
    echo "OK: cacheFixEnabled → official cc uses ${cf}"
  else
    echo "INFO: cacheFixEnabled off"
  fi

  echo
  if [[ "${issues}" -eq 0 ]]; then
    echo "Result: ready — run: ccr 9router"
  else
    echo "Result: fix items above, then: ccr setup check"
    local guide="${HOME}/.local/share/cc-router/docs/SETUP-GUIDE.md"
    if [[ ! -f "${guide}" ]]; then
      guide="docs/SETUP-GUIDE.md"
    fi
    echo "Guide: ${guide}"
    if [[ -t 0 ]] && [[ "${CC_ROUTER_NO_INSTALL_PROMPT:-}" != "1" ]]; then
      if ccr_setup_missing_9router_stack_packages | grep -q .; then
        ccr_setup_offer_install_deps || true
        echo "Then: ccr setup check  (and ccr setup start-cache-fix if proxy not running)"
      fi
    else
      echo "Non-interactive: run  ccr setup install-deps"
    fi
  fi
  return "${issues}"
}

ccr_setup_dispatch() {
  local sub="${1:-}"
  shift || true

  case "${sub}" in
    '' | intro)
      echo "== ccr setup =="
      echo
      ccr_setup_print_architecture
      echo
      echo "Next: ccr setup check"
      echo "      ccr config show"
      echo "      ccr 9router doctor"
      return 0
      ;;
    check)
      ccr_setup_run_check
      return $?
      ;;
    install-deps)
      if ccr_setup_missing_9router_stack_packages | grep -q .; then
        ccr_setup_install_deps
        return $?
      fi
      echo "OK: npm dependencies for ccr 9router already installed."
      return 0
      ;;
    start-cache-fix)
      if ! ccr_setup_pkg_cache_fix_present; then
        echo "Install first: npm install -g ${CC_SETUP_PKG_CACHE_FIX}  (or: ccr setup install-deps)" >&2
        if [[ -t 0 ]] && ccr_setup_read_yes_no "Install ${CC_SETUP_PKG_CACHE_FIX} now?"; then
          ccr_setup_npm_install_global "${CC_SETUP_PKG_CACHE_FIX}" || return 1
        else
          return 1
        fi
      fi
      export CACHE_FIX_PROXY_UPSTREAM="$(ccr_ninerouter_real_url)"
      echo "Starting cache-fix with CACHE_FIX_PROXY_UPSTREAM=${CACHE_FIX_PROXY_UPSTREAM}"
      if ccr_setup_wait_cache_fix_health "$(ccr_cache_fix_url)" 2>/dev/null; then
        echo "Already healthy at $(ccr_cache_fix_url)/health"
        return 0
      fi
      nohup node "$(npm root -g)/claude-code-cache-fix/proxy/server.mjs" >/tmp/cache-fix-proxy.log 2>&1 &
      if ccr_setup_wait_cache_fix_health "$(ccr_cache_fix_url)"; then
        echo "OK: $(ccr_cache_fix_url)/health"
        echo "Log: /tmp/cache-fix-proxy.log"
        return 0
      fi
      echo "FAIL: proxy did not become healthy within ~10s" >&2
      echo "See: /tmp/cache-fix-proxy.log" >&2
      return 1
      ;;
    help | -h | --help)
      cat <<'EOF'
ccr setup - stack intro and health checks

Usage:
  ccr setup              Architecture overview + next steps
  ccr setup check        Verify stack; offer npm install if packages missing (TTY)
  ccr setup install-deps npm install -g claude-code + cache-fix (no prompts)
  ccr setup start-cache-fix   Start cache-fix with upstream = nineRouterUrl

Env: CC_ROUTER_NO_INSTALL_PROMPT=1  skip install prompts on ccr 9router / setup check

Docs: docs/SETUP-GUIDE.md
EOF
      return 0
      ;;
    *)
      echo "Unknown: ccr setup ${sub} (try: ccr setup help)" >&2
      return 2
      ;;
  esac
}
