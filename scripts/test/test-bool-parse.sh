#!/usr/bin/env bash
# Quick regression check for y/n parsing in cc-router config.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/ccr-common.sh
source "${ROOT}/scripts/lib/ccr-common.sh"

fail=0
assert_true() {
  local label="$1" val="$2"
  if ccr_truthy "${val}"; then
    printf 'OK  true  %s (%s)\n' "${label}" "${val}"
  else
    printf 'FAIL true  %s (%s)\n' "${label}" "${val}" >&2
    fail=1
  fi
}
assert_false() {
  local label="$1" val="$2"
  if ccr_falsy "${val}"; then
    printf 'OK  false %s (%s)\n' "${label}" "${val}"
  elif ccr_truthy "${val}"; then
    printf 'FAIL false %s (%s) parsed as true\n' "${label}" "${val}" >&2
    fail=1
  else
    printf 'OK  false %s (%s) (unknown → not true)\n' "${label}" "${val}"
  fi
}

for v in y Y yes Yes YES ye yeah true on 1 enable enabled sure ok '  yes  '; do
  assert_true "${v}" "${v}"
done

for v in n N no No NO false off 0 disable disabled nah '  no  '; do
  assert_false "${v}" "${v}"
done

# empty defaults to false when default=n
[[ "$(ccr_parse_bool '' n)" == "false" ]] || { echo "FAIL empty default"; fail=1; }
[[ "$(ccr_parse_bool '' y)" == "true" ]] || { echo "FAIL empty default y"; fail=1; }

if [[ "${fail}" -eq 0 ]]; then
  echo "All bool-parse checks passed."
else
  exit 1
fi
