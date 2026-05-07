#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${HOME}/.local/bin"
SHARE_DIR="${HOME}/.local/share/ccdeepseek"
mkdir -p "${BIN_DIR}" "${SHARE_DIR}"

install -m 755 "${ROOT}/scripts/cc" "${BIN_DIR}/cc"
install -m 755 "${ROOT}/scripts/ccd" "${BIN_DIR}/ccd"

if [[ -f "${ROOT}/docs/dramatic-prompt.md" ]]; then
  install -m 644 "${ROOT}/docs/dramatic-prompt.md" "${SHARE_DIR}/dramatic-prompt.md"
fi

echo "Install complete."
echo "If needed, add ~/.local/bin to PATH:"
echo '  export PATH="$HOME/.local/bin:$PATH"'
