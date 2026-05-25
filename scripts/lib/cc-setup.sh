# cc-router setup intro and health checks (sourced by scripts/cc).

# Global npm packages required for the default cc -9 stack (9Router itself is separate).
CC_SETUP_PKG_CLAUDE='@anthropic-ai/claude-code'
CC_SETUP_PKG_CACHE_FIX='claude-code-cache-fix'

cc_setup_pkg_cache_fix_present() {
  npm root -g >/dev/null 2>&1 && [[ -d "$(npm root -g)/claude-code-cache-fix" ]]
}

cc_setup_missing_9router_stack_packages() {
  # Prints one package name per line (empty if all present).
  if ! command -v claude >/dev/null 2>&1; then
    printf '%s\n' "${CC_SETUP_PKG_CLAUDE}"
  fi
  if cc_router_cache_fix_9router_enabled && ! cc_setup_pkg_cache_fix_present; then
    printf '%s\n' "${CC_SETUP_PKG_CACHE_FIX}"
  fi
}

cc_setup_read_yes_no() {
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
  ans="$(cc_router_trim "${ans}")"
  cc_router_truthy "${ans}"
}

cc_setup_npm_install_global() {
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

# Install all missing cc -9 stack npm packages (no prompts).
cc_setup_install_deps() {
  local pkg failed=0
  while IFS= read -r pkg; do
    [[ -z "${pkg}" ]] && continue
    cc_setup_npm_install_global "${pkg}" || failed=1
  done < <(cc_setup_missing_9router_stack_packages)
  return "${failed}"
}

# Interactive: offer to npm install missing packages.
cc_setup_offer_install_deps() {
  local -a missing=()
  local pkg
  while IFS= read -r pkg; do
    [[ -z "${pkg}" ]] && continue
    missing+=("${pkg}")
  done < <(cc_setup_missing_9router_stack_packages)

  if ((${#missing[@]} == 0)); then
    return 0
  fi

  echo
  echo "cc -9 needs these npm packages (global install):"
  for pkg in "${missing[@]}"; do
    echo "  • ${pkg}"
  done
  echo "9Router is not an npm package — start it separately (default http://127.0.0.1:20128)."
  echo

  if ! cc_setup_read_yes_no "Install now with npm?"; then
    echo "Skipped. Later: cc setup install-deps"
    echo "  or: npm install -g ${missing[*]}"
    return 1
  fi

  for pkg in "${missing[@]}"; do
    cc_setup_npm_install_global "${pkg}" || return 1
  done
  echo "OK: npm packages installed."
  return 0
}

# Called before launching cc -9; prompts on TTY when packages missing.
cc_router_ensure_9router_stack_deps() {
  local -a missing=()
  local pkg
  while IFS= read -r pkg; do
    [[ -z "${pkg}" ]] && continue
    missing+=("${pkg}")
  done < <(cc_setup_missing_9router_stack_packages)

  if ((${#missing[@]} == 0)); then
    return 0
  fi

  echo "cc -9 requires: ${missing[*]}" >&2
  if cc_setup_offer_install_deps; then
    return 0
  fi
  echo "Install manually, then retry:" >&2
  echo "  cc setup install-deps" >&2
  return 1
}

cc_setup_print_architecture() {
  cat <<'EOF'
Stack (default cc -9):

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

cc_setup_wait_cache_fix_health() {
  local base="${1:-http://127.0.0.1:9801}"
  local i
  base="${base%/}"
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    if cc_router_probe_cache_fix_health "${base}"; then
      return 0
    fi
    sleep 0.5
  done
  return 1
}

cc_setup_print_cache_fix_start() {
  local upstream cf
  upstream="$(cc_router_ninerouter_real_url)"
  cf="$(cc_router_cache_fix_url)"
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

cc_setup_run_check() {
  local issues=0
  local nr cf

  echo "== cc setup check =="
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

  nr="$(cc_router_ninerouter_real_url)"
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

  cf="$(cc_router_cache_fix_url)"
  echo
  echo "-- cache-fix (${cf}) --"
  if cc_setup_pkg_cache_fix_present; then
    echo "OK: ${CC_SETUP_PKG_CACHE_FIX} package present"
  elif cc_router_cache_fix_9router_enabled || cc_router_cache_fix_enabled; then
    issues=1
    echo "FAIL: ${CC_SETUP_PKG_CACHE_FIX} not installed globally"
    echo "      npm install -g ${CC_SETUP_PKG_CACHE_FIX}"
  else
    echo "INFO: ${CC_SETUP_PKG_CACHE_FIX} not installed (cache-fix disabled in config)"
  fi

  if cc_router_cache_fix_9router_enabled || cc_router_cache_fix_enabled; then
    if cc_router_probe_cache_fix_health "${cf}"; then
      echo "OK: ${cf}/health"
    else
      issues=1
      echo "FAIL: cache-fix not listening on ${cf}"
      echo
      cc_setup_print_cache_fix_start
    fi
  else
    echo "INFO: cache-fix disabled in config (cacheFixEnabled / cacheFix9routerEnabled off)"
  fi

  echo
  echo "-- cc-router config (effective) --"
  if cc_router_cache_prompt_env_enabled; then
    echo "OK: cachePromptEnvEnabled (attribution + git instructions)"
  else
    echo "INFO: cachePromptEnvEnabled off"
  fi
  if cc_router_cache_fix_9router_enabled; then
    echo "OK: cacheFix9routerEnabled → cc -9 uses ${cf}/v1 → ${nr}"
  else
    echo "INFO: cacheFix9routerEnabled off → cc -9 direct to ${nr}/v1"
  fi
  if cc_router_cache_fix_enabled; then
    echo "OK: cacheFixEnabled → official cc uses ${cf}"
  else
    echo "INFO: cacheFixEnabled off"
  fi

  echo
  if [[ "${issues}" -eq 0 ]]; then
    echo "Result: ready — run: cc -9"
  else
    echo "Result: fix items above, then: cc setup check"
    local guide="${HOME}/.local/share/cc-router/docs/SETUP-GUIDE.md"
    if [[ ! -f "${guide}" ]]; then
      guide="docs/SETUP-GUIDE.md"
    fi
    echo "Guide: ${guide}"
    if [[ -t 0 ]] && [[ "${CC_ROUTER_NO_INSTALL_PROMPT:-}" != "1" ]]; then
      if cc_setup_missing_9router_stack_packages | grep -q .; then
        cc_setup_offer_install_deps || true
        echo "Then: cc setup check  (and cc setup start-cache-fix if proxy not running)"
      fi
    else
      echo "Non-interactive: run  cc setup install-deps"
    fi
  fi
  return "${issues}"
}

cc_setup_dispatch() {
  local sub="${1:-}"
  shift || true

  case "${sub}" in
    '' | intro)
      echo "== cc setup =="
      echo
      cc_setup_print_architecture
      echo
      echo "Next: cc setup check"
      echo "      cc config show"
      echo "      cc -9 doctor"
      return 0
      ;;
    check)
      cc_setup_run_check
      return $?
      ;;
    install-deps)
      if cc_setup_missing_9router_stack_packages | grep -q .; then
        cc_setup_install_deps
        return $?
      fi
      echo "OK: npm dependencies for cc -9 already installed."
      return 0
      ;;
    start-cache-fix)
      if ! cc_setup_pkg_cache_fix_present; then
        echo "Install first: npm install -g ${CC_SETUP_PKG_CACHE_FIX}  (or: cc setup install-deps)" >&2
        if [[ -t 0 ]] && cc_setup_read_yes_no "Install ${CC_SETUP_PKG_CACHE_FIX} now?"; then
          cc_setup_npm_install_global "${CC_SETUP_PKG_CACHE_FIX}" || return 1
        else
          return 1
        fi
      fi
      export CACHE_FIX_PROXY_UPSTREAM="$(cc_router_ninerouter_real_url)"
      echo "Starting cache-fix with CACHE_FIX_PROXY_UPSTREAM=${CACHE_FIX_PROXY_UPSTREAM}"
      if cc_setup_wait_cache_fix_health "$(cc_router_cache_fix_url)" 2>/dev/null; then
        echo "Already healthy at $(cc_router_cache_fix_url)/health"
        return 0
      fi
      nohup node "$(npm root -g)/claude-code-cache-fix/proxy/server.mjs" >/tmp/cache-fix-proxy.log 2>&1 &
      if cc_setup_wait_cache_fix_health "$(cc_router_cache_fix_url)"; then
        echo "OK: $(cc_router_cache_fix_url)/health"
        echo "Log: /tmp/cache-fix-proxy.log"
        return 0
      fi
      echo "FAIL: proxy did not become healthy within ~10s" >&2
      echo "See: /tmp/cache-fix-proxy.log" >&2
      return 1
      ;;
    help | -h | --help)
      cat <<'EOF'
cc setup - stack intro and health checks

Usage:
  cc setup              Architecture overview + next steps
  cc setup check        Verify stack; offer npm install if packages missing (TTY)
  cc setup install-deps npm install -g claude-code + cache-fix (no prompts)
  cc setup start-cache-fix   Start cache-fix with upstream = nineRouterUrl

Env: CC_ROUTER_NO_INSTALL_PROMPT=1  skip install prompts on cc -9 / setup check

Docs: docs/SETUP-GUIDE.md
EOF
      return 0
      ;;
    *)
      echo "Unknown: cc setup ${sub} (try: cc setup help)" >&2
      return 2
      ;;
  esac
}
