#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${HOME}/.local/bin"
SHARE_DIR="${HOME}/.local/share/cc-router"
mkdir -p "${BIN_DIR}" "${SHARE_DIR}/lib" "${SHARE_DIR}/docs" "${SHARE_DIR}/templates/remote" "${SHARE_DIR}/remote-pack"

# Migrate old ccdeepseek share dir if present.
OLD_SHARE_DIR="${HOME}/.local/share/ccdeepseek"
if [[ -d "${OLD_SHARE_DIR}" ]]; then
  echo "[install] Migrating old ${OLD_SHARE_DIR} to ${SHARE_DIR} ..."
  if [[ -f "${OLD_SHARE_DIR}/dramatic-prompt.md" ]]; then
    mv "${OLD_SHARE_DIR}/dramatic-prompt.md" "${SHARE_DIR}/templates/dramatic-prompt.md"
  fi
  rm -rf "${OLD_SHARE_DIR}"
fi

# Main entry point
install -m 755 "${ROOT}/scripts/ccr" "${BIN_DIR}/ccr"

# Legacy aliases
install -m 755 "${ROOT}/scripts/ccd" "${BIN_DIR}/ccd"
install -m 755 "${ROOT}/scripts/ccs" "${BIN_DIR}/ccs"
if [[ -f "${ROOT}/scripts/cck" ]]; then
  install -m 755 "${ROOT}/scripts/cck" "${BIN_DIR}/cck"
fi

# Libraries
for lib in ccr-common.sh ccr-setup.sh ccr-remote.sh ccr-remote-config.sh ccr-remote-ssh.sh ccr-remote-skills.sh; do
  if [[ -f "${ROOT}/scripts/lib/${lib}" ]]; then
    install -m 644 "${ROOT}/scripts/lib/${lib}" "${SHARE_DIR}/lib/${lib}"
  fi
done

# Templates
if [[ -d "${ROOT}/templates/remote" ]]; then
  install -m 644 "${ROOT}/templates/remote/"*.json "${SHARE_DIR}/templates/remote/"
fi
if [[ -f "${ROOT}/docs/dramatic-prompt.md" ]]; then
  install -m 644 "${ROOT}/docs/dramatic-prompt.md" "${SHARE_DIR}/templates/dramatic-prompt.md"
fi

# Docs
for doc in SETUP-GUIDE.md SETUP-NOTES.md CR-CACHE-BENCH.md TODO.md PRODUCT.md CR-REMOTE.md; do
  if [[ -f "${ROOT}/docs/${doc}" ]]; then
    install -m 644 "${ROOT}/docs/${doc}" "${SHARE_DIR}/docs/${doc}"
  fi
done

# Example config
if [[ -f "${ROOT}/config.example.json" ]]; then
  install -m 644 "${ROOT}/config.example.json" "${SHARE_DIR}/config.example.json"
fi

echo "Install complete."
echo "First-time (9Router + OAuth + cache-fix): ccr setup"
echo "  → docs also at ${SHARE_DIR}/docs/SETUP-GUIDE.md"
echo "cc-router config (optional): ccr config setup"
echo "  → writes ~/.config/cc-router/config.json"
echo "Remote onboarding: ccr remote pack && ccr remote setup <host|alias>"
echo "  → docs at ${SHARE_DIR}/docs/CR-REMOTE.md"
echo "If needed, add ~/.local/bin to PATH:"
echo '  export PATH="$HOME/.local/bin:$PATH"'
