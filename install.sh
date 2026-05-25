#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${HOME}/.local/bin"
SHARE_DIR="${HOME}/.local/share/ccdeepseek"
ROUTER_SHARE="${HOME}/.local/share/cc-router"
mkdir -p "${BIN_DIR}" "${SHARE_DIR}" "${ROUTER_SHARE}/lib" "${ROUTER_SHARE}/docs"

install -m 755 "${ROOT}/scripts/cc" "${BIN_DIR}/cc"
install -m 755 "${ROOT}/scripts/ccd" "${BIN_DIR}/ccd"
if [[ -f "${ROOT}/scripts/ccd-cache-bench.sh" ]]; then
  install -m 755 "${ROOT}/scripts/ccd-cache-bench.sh" "${BIN_DIR}/ccd-cache-bench"
fi
install -m 644 "${ROOT}/scripts/lib/cc-common.sh" "${ROUTER_SHARE}/lib/cc-common.sh"
if [[ -f "${ROOT}/scripts/lib/cc-setup.sh" ]]; then
  install -m 644 "${ROOT}/scripts/lib/cc-setup.sh" "${ROUTER_SHARE}/lib/cc-setup.sh"
fi
for doc in SETUP-GUIDE.md SETUP-NOTES.md CCD-CACHE-BENCH.md TODO.md PRODUCT.md; do
  if [[ -f "${ROOT}/docs/${doc}" ]]; then
    install -m 644 "${ROOT}/docs/${doc}" "${ROUTER_SHARE}/docs/${doc}"
  fi
done

if [[ -f "${ROOT}/docs/dramatic-prompt.md" ]]; then
  install -m 644 "${ROOT}/docs/dramatic-prompt.md" "${SHARE_DIR}/dramatic-prompt.md"
fi

if [[ -f "${ROOT}/config.example.json" ]]; then
  install -m 644 "${ROOT}/config.example.json" "${ROUTER_SHARE}/config.example.json"
fi

echo "Install complete."
echo "First-time (9Router + OAuth + cache-fix): cc setup"
echo "  → docs also at ${ROUTER_SHARE}/docs/SETUP-GUIDE.md"
echo "cc-router config (optional): cc config setup"
echo "  → writes ~/.config/cc-router/config.json"
echo "If needed, add ~/.local/bin to PATH:"
echo '  export PATH="$HOME/.local/bin:$PATH"'
