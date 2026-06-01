#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

mkdir -p "${TMP_DIR}/bin" "${TMP_DIR}/home"

cat >"${TMP_DIR}/bin/claude" <<'EOF'
#!/usr/bin/env bash
echo "fake claude"
EOF

cat >"${TMP_DIR}/bin/curl" <<'EOF'
#!/usr/bin/env bash
url="${*: -1}"
case "${url}" in
  */api/health|*/health)
    printf '%s\n' '{"ok":true}'
    ;;
  *)
    exit 1
    ;;
esac
EOF

chmod +x "${TMP_DIR}/bin/claude" "${TMP_DIR}/bin/curl"

assert_contains() {
  local name="$1"
  local needle="$2"
  shift 2
  local output
  output="$("$@" 2>&1)"
  if [[ "${output}" != *"${needle}"* ]]; then
    echo "[FAIL] ${name}" >&2
    echo "Expected to find:" >&2
    printf '%s\n' "${needle}" >&2
    echo "Actual output:" >&2
    printf '%s\n' "${output}" >&2
    exit 1
  fi
  echo "[PASS] ${name}"
}

assert_contains \
  "cc -9 doctor advertises alias rewrite" \
  "OK: agent slot alias rewrite active" \
  env \
    HOME="${TMP_DIR}/home" \
    PATH="${TMP_DIR}/bin:/usr/bin:/bin" \
    NINEROUTER_URL="http://127.0.0.1:20128" \
    NINEROUTER_OPUS_MODEL="cc-pro" \
    NINEROUTER_SONNET_MODEL="cc-normal" \
    NINEROUTER_HAIKU_MODEL="cc-lite" \
    bash "${ROOT_DIR}/scripts/cc" -9 doctor

assert_contains \
  "cc -9 doctor detail shows alias mapping" \
  "agent slot alias rewrite active         = sonnet->cc-normal, haiku->cc-lite, opus->cc-pro" \
  env \
    HOME="${TMP_DIR}/home" \
    PATH="${TMP_DIR}/bin:/usr/bin:/bin" \
    NINEROUTER_URL="http://127.0.0.1:20128" \
    NINEROUTER_OPUS_MODEL="cc-pro" \
    NINEROUTER_SONNET_MODEL="cc-normal" \
    NINEROUTER_HAIKU_MODEL="cc-lite" \
    bash "${ROOT_DIR}/scripts/cc" -9 doctor detail

echo "All cc doctor checks passed."
