#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/ccr-common.sh
source "${ROOT_DIR}/scripts/lib/ccr-common.sh"

ccr_ensure_9router_stack_deps() {
  return 0
}

ccr_ninerouter_client_base_url() {
  printf '%s\n' "http://127.0.0.1:20128"
}

ccr_export_cache_prompt_env() {
  :
}

ccr_claude_extra_args() {
  :
}

claude() {
  printf '%s\n' "$@"
}

assert_args() {
  local name="$1"
  local expected="$2"
  shift 2
  local output
  output="$(
    ccr_run_9router_claude \
      "http://127.0.0.1:20128" \
      "cc-pro" \
      "cc-normal" \
      "cc-lite" \
      "true" \
      "" \
      "$@"
  )"
  if [[ "${output}" != "${expected}" ]]; then
    echo "[FAIL] ${name}" >&2
    echo "Expected:" >&2
    printf '%s\n' "${expected}" >&2
    echo "Actual:" >&2
    printf '%s\n' "${output}" >&2
    exit 1
  fi
  echo "[PASS] ${name}"
}

assert_args \
  "rewrite split --model sonnet" \
  $'--print\n--model\ncc-normal\nhello' \
  --print --model sonnet hello

assert_args \
  "rewrite equals --model=haiku" \
  $'--print\n--model=cc-lite\nhello' \
  --print --model=haiku hello

assert_args \
  "rewrite short -m opus" \
  $'--print\n-m\ncc-pro\nhello' \
  --print -m opus hello

assert_args \
  "rewrite full claude family name" \
  $'--print\n--model\ncc-normal\nhello' \
  --print --model claude-sonnet-4-5 hello

assert_args \
  "preserve custom explicit model" \
  $'--print\n--model\nmy-custom-model\nhello' \
  --print --model my-custom-model hello

echo "All cc model routing checks passed."
