#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

tests=(
  "${ROOT_DIR}/scripts/test-bool-parse.sh"
  "${ROOT_DIR}/scripts/test-ccd-worktree.sh"
  "${ROOT_DIR}/scripts/test-cc-model-routing.sh"
  "${ROOT_DIR}/scripts/test-cc-doctor.sh"
)

for test_script in "${tests[@]}"; do
  echo "==> $(basename "${test_script}")"
  bash "${test_script}"
  echo
done

echo "All repository shell checks passed."
