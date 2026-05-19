#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${HOME}/.local/bin"
SHARE_DIR="${HOME}/.local/share/ccdeepseek"
ROUTER_SHARE="${HOME}/.local/share/cc-router"
mkdir -p "${BIN_DIR}" "${SHARE_DIR}" "${ROUTER_SHARE}/lib"

install -m 755 "${ROOT}/scripts/cc" "${BIN_DIR}/cc"
install -m 755 "${ROOT}/scripts/ccd" "${BIN_DIR}/ccd"
install -m 644 "${ROOT}/scripts/lib/cc-common.sh" "${ROUTER_SHARE}/lib/cc-common.sh"

if [[ -f "${ROOT}/docs/dramatic-prompt.md" ]]; then
  install -m 644 "${ROOT}/docs/dramatic-prompt.md" "${SHARE_DIR}/dramatic-prompt.md"
fi

if [[ -f "${ROOT}/config.example.json" ]]; then
  install -m 644 "${ROOT}/config.example.json" "${ROUTER_SHARE}/config.example.json"
fi

echo "Install complete."
echo "cc-router config (optional): cc config setup"
echo "  → writes ~/.config/cc-router/config.json"
echo "If needed, add ~/.local/bin to PATH:"
echo '  export PATH="$HOME/.local/bin:$PATH"'
