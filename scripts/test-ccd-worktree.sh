#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CCD="${ROOT_DIR}/scripts/ccd"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

assert_fail_with_message() {
  local name="$1"
  local expected="$2"
  shift 2

  set +e
  local output
  output="$("$@" 2>&1)"
  local code=$?
  set -e

  if [[ ${code} -eq 0 ]]; then
    echo "[FAIL] ${name}: expected failure but got success" >&2
    exit 1
  fi
  if [[ "${output}" != *"${expected}"* ]]; then
    echo "[FAIL] ${name}: expected message not found: ${expected}" >&2
    echo "Actual output:" >&2
    echo "${output}" >&2
    exit 1
  fi
  echo "[PASS] ${name}"
}

assert_fail_with_message \
  "reject invalid worktree name" \
  "Invalid worktree name" \
  bash -c "cd '${ROOT_DIR}' && '${CCD}' --worktree 'bad/name'"

assert_fail_with_message \
  "reject non git repo" \
  "--worktree requires running inside a git repository" \
  bash -c "cd '${TMP_DIR}' && '${CCD}' --worktree demo"

echo "All ccd worktree MVP tests passed."
