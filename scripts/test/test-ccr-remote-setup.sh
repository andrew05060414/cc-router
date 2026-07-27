#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Source dependencies (ccr-remote.sh relies on helpers from common/ssh/config/skills)
source "${ROOT_DIR}/scripts/lib/ccr-common.sh"
source "${ROOT_DIR}/scripts/lib/ccr-remote-ssh.sh"
source "${ROOT_DIR}/scripts/lib/ccr-remote-config.sh"
source "${ROOT_DIR}/scripts/lib/ccr-remote-skills.sh"
source "${ROOT_DIR}/scripts/lib/ccr-remote.sh"

# Test 1: onboard help output
printf '==> test: ccr remote onboard --help\n'
if ! ccr_remote_onboard --help | grep -q "Interactive all-in-one remote onboarding"; then
  echo "[FAIL] onboard --help did not show expected text" >&2
  exit 1
fi
echo "[PASS] onboard --help shows expected text"

# Test 2: setup help output
printf '\n==> test: ccr remote setup --help\n'
if ! ccr_remote_setup --help | grep -q "Selective remote configuration"; then
  echo "[FAIL] setup --help did not show expected text" >&2
  exit 1
fi
echo "[PASS] setup --help shows expected text"

# Test 2b: required helper functions exist
printf '\n==> test: setup helper functions exist\n'
for helper in \
  ccr_remote_setup_alias_exists \
  ccr_remote_setup_prompt_alias_conflict \
  ccr_remote_setup_prompt_steps \
  ccr_remote_run_steps \
  ccr_remote_onboard \
  ccr_remote_setup \
  ccr_remote_setup_show_help \
  ccr_remote_setup_show_nixos_help \
  ccr_remote_setup_test_ssh \
  ccr_remote_setup_read_yes_no \
  ccr_remote_setup_probe_npm_mirror \
  ccr_remote_setup_install_nodejs; do
  if ! type -t "$helper" | grep -q "function"; then
    echo "[FAIL] helper missing: $helper" >&2
    exit 1
  fi
done
echo "[PASS] all setup helpers present"

# Test 3: non-interactive mode requires alias
printf '\n==> test: missing alias in non-interactive mode\n'
if ccr_remote_onboard --no-confirm >/dev/null 2>&1; then
  echo "[FAIL] expected failure when alias missing" >&2
  exit 1
fi
echo "[PASS] missing alias fails in non-interactive mode"

# Test 4: onboard dry-run with all flags parses correctly
printf '\n==> test: onboard dry-run with all flags\n'
local_log="$(mktemp)"
if ! ccr_remote_onboard \
  --dry-run testbox \
  --ip 1.2.3.4 \
  --user testuser \
  --password secretpass \
  --port 2222 \
  --key ~/.ssh/id_test \
  --seed-ide \
  --tailscale-auth-key tskey-auth-xxx \
  --tailscale-hostname testbox-ts \
  --no-confirm >"$local_log" 2>&1; then
  echo "[FAIL] onboard dry-run with all flags failed" >&2
  cat "$local_log" >&2
  rm -f "$local_log"
  exit 1
fi

for expected in "dry-run" "testbox" "Tailscale" "IDE server"; do
  if ! grep -q "$expected" "$local_log"; then
    echo "[FAIL] onboard dry-run log missing expected: $expected" >&2
    cat "$local_log" >&2
    rm -f "$local_log"
    exit 1
  fi
done
rm -f "$local_log"
echo "[PASS] onboard dry-run with all flags"

# Test 5: setup dry-run with explicit steps
printf '\n==> test: setup --steps in dry-run\n'
local_log="$(mktemp)"
if ! ccr_remote_setup \
  --dry-run testbox \
  --steps ssh,node,sync \
  --ip 1.2.3.4 \
  --user testuser \
  --password secretpass \
  --no-confirm >"$local_log" 2>&1; then
  echo "[FAIL] setup --steps dry-run failed" >&2
  cat "$local_log" >&2
  rm -f "$local_log"
  exit 1
fi
for expected in "dry-run" "testbox" "settings.json" "CLAUDE.md" "skills"; do
  if ! grep -q "$expected" "$local_log"; then
    echo "[FAIL] setup dry-run log missing expected: $expected" >&2
    cat "$local_log" >&2
    rm -f "$local_log"
    exit 1
  fi
done
rm -f "$local_log"
echo "[PASS] setup --steps dry-run"

# Test 6: setup reuses existing alias in non-interactive mode
printf '\n==> test: setup reuses existing alias\n'
tmp_ssh_config="$(mktemp)"
cat >"$tmp_ssh_config" <<EOF
# ccr remote setup: testbox
Host testbox
  HostName 1.2.3.4
  User testuser
  Port 2222
  IdentityFile ~/.ssh/id_test
EOF
local_log="$(mktemp)"
CC_REMOTE_ONBOARD_SSH_CONFIG="$tmp_ssh_config" \
  ccr_remote_setup --dry-run testbox --steps sync --no-confirm >"$local_log" 2>&1
if ! grep -q "复用现有 SSH 配置" "$local_log"; then
  echo "[FAIL] setup did not report reusing existing alias" >&2
  cat "$local_log" >&2
  rm -f "$local_log" "$tmp_ssh_config"
  exit 1
fi
rm -f "$local_log" "$tmp_ssh_config"
echo "[PASS] setup reuses existing alias"

printf '\nAll ccr remote onboard/setup checks passed.\n'
