#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Source dependencies (ccr-remote.sh relies on helpers from common/ssh/config/skills)
source "${ROOT_DIR}/scripts/lib/ccr-common.sh"
source "${ROOT_DIR}/scripts/lib/ccr-remote-ssh.sh"
source "${ROOT_DIR}/scripts/lib/ccr-remote-config.sh"
source "${ROOT_DIR}/scripts/lib/ccr-remote-skills.sh"
source "${ROOT_DIR}/scripts/lib/ccr-remote.sh"

# Test 1: help output
printf '==> test: ccr remote setup --help\n'
if ! ccr_remote_setup --help | grep -q "Interactive all-in-one remote onboarding"; then
  echo "[FAIL] setup --help did not show expected text" >&2
  exit 1
fi
echo "[PASS] setup --help shows expected text"

# Test 2: non-interactive mode requires alias
printf '\n==> test: missing alias in non-interactive mode\n'
if ccr_remote_setup --no-confirm >/dev/null 2>&1; then
  echo "[FAIL] expected failure when alias missing" >&2
  exit 1
fi
echo "[PASS] missing alias fails in non-interactive mode"

# Test 3: dry-run with all flags parses correctly and does not execute SSH
printf '\n==> test: dry-run with all flags\n'
local_log="$(mktemp)"
if ! ccr_remote_setup \
  --dry-run testbox \
  --ip 1.2.3.4 \
  --user testuser \
  --password secretpass \
  --port 2222 \
  --key ~/.ssh/id_test \
  --seed-ide \
  --tailscale-auth-key tskey-auth-xxx \
  --tailscale-hostname testbox-ts \
  --install-node \
  --no-confirm >"$local_log" 2>&1; then
  echo "[FAIL] dry-run with all flags failed" >&2
  cat "$local_log" >&2
  rm -f "$local_log"
  exit 1
fi

for expected in "dry-run" "testbox" "Tailscale" "IDE server"; do
  if ! grep -q "$expected" "$local_log"; then
    echo "[FAIL] dry-run log missing expected: $expected" >&2
    cat "$local_log" >&2
    rm -f "$local_log"
    exit 1
  fi
done
rm -f "$local_log"
echo "[PASS] dry-run with all flags"

# Test 4: --no-install-node flag is accepted and skips node install prompt
printf '\n==> test: --no-install-node in dry-run\n'
local_log="$(mktemp)"
if ! ccr_remote_setup \
  --dry-run testbox \
  --ip 1.2.3.4 \
  --user testuser \
  --password secretpass \
  --no-install-node \
  --no-confirm >"$local_log" 2>&1; then
  echo "[FAIL] dry-run with --no-install-node failed" >&2
  cat "$local_log" >&2
  rm -f "$local_log"
  exit 1
fi
echo "[PASS] --no-install-node accepted"
rm -f "$local_log"

printf '\nAll ccr remote setup checks passed.\n'
