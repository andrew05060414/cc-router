#!/usr/bin/env bash
# DeepSeek prompt-cache bench — same env injection as `ccd` (no worktree).
set -euo pipefail

_cc_script_path="${BASH_SOURCE[0]}"
while [[ -L "${_cc_script_path}" ]]; do
  _cc_link="$(readlink "${_cc_script_path}")"
  if [[ "${_cc_link}" = /* ]]; then
    _cc_script_path="${_cc_link}"
  else
    _cc_script_path="$(cd "$(dirname "${_cc_script_path}")" && pwd)/${_cc_link}"
  fi
done
_cc_script_dir="$(cd "$(dirname "${_cc_script_path}")" && pwd)"
for _cc_lib in "${_cc_script_dir}/lib/ccr-common.sh" "${HOME}/.local/share/cc-router/lib/ccr-common.sh"; do
  if [[ -f "${_cc_lib}" ]]; then
    # shellcheck source=/dev/null
    source "${_cc_lib}"
    break
  fi
done
if ! declare -F ccr_export_cache_prompt_env >/dev/null 2>&1; then
  echo "cc-router: lib/ccr-common.sh not found (re-run ./install.sh)" >&2
  exit 1
fi

model="${CCD_BENCH_MODEL:-deepseek-v4-pro[1m]}"
haiku_model="${CCD_BENCH_HAIKU_MODEL:-deepseek-v4-flash}"
runs="${CCD_BENCH_RUNS:-3}"
skip_api=0

usage() {
  cat <<EOF
ccd-cache-bench — verify DeepSeek prompt cache behavior (same env as ccr deepseek)

Usage:
  $(basename "$0") [--dry-run] [--runs N]
  $(basename "$0") --help

Requires: DEEPSEEK_API_KEY, claude CLI on PATH.

Options:
  --dry-run     Print env + manual steps only (no API calls)
  --runs N      Number of identical --print requests (default: 3)
  --help        This help

Env overrides (same as ccd):
  CCD_TOOL_SEARCH, CC_ATTRIBUTION_HEADER, CC_DISABLE_GIT_INSTRUCTIONS
  CCD_BENCH_MODEL, CCD_BENCH_HAIKU_MODEL, CCD_BENCH_RUNS

See: docs/CCD-CACHE-BENCH.md
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help) usage; exit 0 ;;
    --dry-run) skip_api=1; shift ;;
    --runs)
      runs="$2"
      shift 2
      ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "${DEEPSEEK_API_KEY:-}" ]]; then
  echo "Set DEEPSEEK_API_KEY before running (or: ccd setup)" >&2
  exit 1
fi

if [[ "${skip_api}" -eq 0 ]] && ! command -v claude >/dev/null 2>&1; then
  echo "claude CLI not found. Install: npm install -g @anthropic-ai/claude-code" >&2
  exit 1
fi

ccr_unset_routing_env
export ANTHROPIC_BASE_URL='https://api.deepseek.com/anthropic'
export ANTHROPIC_AUTH_TOKEN="${DEEPSEEK_API_KEY}"
export ANTHROPIC_MODEL="${model}"
export ANTHROPIC_DEFAULT_OPUS_MODEL="${model}"
export ANTHROPIC_DEFAULT_SONNET_MODEL="${model}"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="${haiku_model}"
export CLAUDE_CODE_SUBAGENT_MODEL="${haiku_model}"
export CLAUDE_CODE_MAX_OUTPUT_TOKENS='4096'
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC='1'
export CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK='1'
export CLAUDE_CODE_EFFORT_LEVEL='low'
ccd_tool_search="${CCD_TOOL_SEARCH-true}"
if [[ -n "${ccd_tool_search}" ]]; then
  export ENABLE_TOOL_SEARCH="${ccd_tool_search}"
fi
ccr_export_cache_prompt_env

bench_prompt='Reply with exactly: CACHE_BENCH_OK'

echo "== ccr deepseek cache bench =="
echo "Model: ${model}"
echo "Runs:  ${runs} (identical prompt for cache hit on run 2+)"
echo
echo "Injected (ccd-aligned):"
printf '  %-40s %s\n' ANTHROPIC_BASE_URL "${ANTHROPIC_BASE_URL}"
printf '  %-40s %s\n' CLAUDE_CODE_ATTRIBUTION_HEADER "${CLAUDE_CODE_ATTRIBUTION_HEADER:-<unset>}"
printf '  %-40s %s\n' CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS "${CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS:-<unset>}"
printf '  %-40s %s\n' ENABLE_TOOL_SEARCH "${ENABLE_TOOL_SEARCH:-<unset>}"
echo

if [[ "${skip_api}" -eq 1 ]]; then
  echo "--dry-run: skipping claude --print calls."
  echo "Manual: run the same command ${runs} times and compare usage.cache_read_input_tokens:"
  echo "  claude --print --model '${model}' '${bench_prompt}'"
  exit 0
fi

stable_system='You are a minimal assistant for cache benchmarking. Do not use tools.'

for i in $(seq 1 "${runs}"); do
  echo "--- run ${i}/${runs} ---"
  if ! out="$(claude --print --model "${model}" --system-prompt "${stable_system}" "${bench_prompt}" 2>&1)"; then
    echo "${out}" >&2
    echo "FAIL: claude --print exited non-zero on run ${i}" >&2
    exit 1
  fi
  echo "${out}" | tail -n 3
  echo
done

cat <<'EOF'
What to look for (DeepSeek / Anthropic-compatible usage in response metadata or logs):
  - Run 1: cache_creation_input_tokens may be > 0 (cold prefix)
  - Run 2+: cache_read_input_tokens should dominate; cache_creation near 0
  - If every run shows cache_creation with no cache_read, prefix is not stable
    (check git instructions, changing system prompt, or attribution header)

Full procedure: docs/CCD-CACHE-BENCH.md
EOF
