# cc-router Setup Notes & Known Issues

**New to the full stack (9Router + OAuth + cache-fix)?** Start with
[SETUP-GUIDE.md](SETUP-GUIDE.md), then run `ccr setup check`.

This file collects setup quirks, gotchas, and root-cause notes that don't
belong in the main README. Read this if `ccr -9` / `ccr deepseek` behaves strangely,
if `/context` shows unexpected token usage, or if you're debugging a
context-bloat issue.

---

## 1. The MCP Tool Schema Context Bloat (the big one)

### Symptom

After switching to `ccr -9` (or `ccr deepseek` on a small-context model), the
`/context` view shows:

- **`Messages` bucket inflated by 30k+ tokens** even on the very first turn,
  before you've typed anything beyond `hi`
- **No `System tools` / `MCP tools` row** in `/context`, or those rows are
  much smaller than what you see under official `ccr`
- Total context usage at session start is ~30-60% on a 200k model, vs
  ~12% under official mode with the same plugins enabled

### Root Cause

Claude Code v**2.1.70** introduced a proxy-detection patch:

> When `ANTHROPIC_BASE_URL` points at a **non-first-party host**
> (anything other than `*.anthropic.com`), Claude Code automatically
> disables `tool_reference` beta blocks to prevent 400 errors from
> standard proxies that reject the beta schema.

The catch: `tool_reference` is the underlying mechanism for **MCP tool
search / deferred MCP tool loading**. When it gets stripped, **every
configured MCP tool's full JSON schema gets serialized into the first user
message instead of staying in the system tools bucket**. With several MCP
servers enabled, that's a 30-120k token tax on every conversation.

References:

- Official docs entry for `ENABLE_TOOL_SEARCH`:
  <https://code.claude.com/docs/en/env-vars#enable_tool_search>
- The feature request that landed the env var override:
  <https://github.com/anthropics/claude-code/issues/31936>
- Related regressions and complaints:
  - [#31425](https://github.com/anthropics/claude-code/issues/31425) Regression in 2.1.70
  - [#32343](https://github.com/anthropics/claude-code/issues/32343) Tool search broken between 2.1.67 and 2.1.71
  - [#28711](https://github.com/anthropics/claude-code/issues/28711) "MCP tool schemas consume context unconditionally"
  - [#40314](https://github.com/anthropics/claude-code/issues/40314) HTTP MCP transports still not deferred even with the flag set

### Fix (already applied to cc-router)

Both `ccr -9` and `ccr deepseek` now set:

```text
ENABLE_TOOL_SEARCH=true
```

This forces deferred MCP tool loading back on. **Requires the upstream
proxy (9Router / DeepSeek / whatever) to forward `tool_reference` blocks
correctly**.

### If your upstream proxy does NOT support `tool_reference`

You'll see runtime errors (often HTTP 400, sometimes a generic provider
error) on the very first `claude` request. To fall back to the old
"eager-load everything" behavior:

```bash
# 9Router mode
export NINEROUTER_TOOL_SEARCH=''         # empty string disables it
# or use the threshold mode:
export NINEROUTER_TOOL_SEARCH='auto'

# DeepSeek mode
export CCD_TOOL_SEARCH=''
# or
export CCD_TOOL_SEARCH='auto'
```

PowerShell:

```powershell
$env:NINEROUTER_TOOL_SEARCH = ''
# or
$env:CCD_TOOL_SEARCH = 'auto'
```

`auto` means "load upfront only if MCP tools fit in <10% of context".

### How to verify the fix

Open a **new shell** (running processes hold a snapshot of env vars) and:

```bash
ccr 9router doctor detail
```

In section `[4] Effective env that 'ccr 9router' would inject`, look for:

```text
ENABLE_TOOL_SEARCH                       = true  (forces deferred MCP tool loading)
```

Then start `ccr -9`, type `hi`, run `/context`. Expected:

- A separate `MCP tools` (and possibly `System tools`) bucket exists
- `Messages` bucket is < 8k
- Total usage similar to official `ccr` (typically 10-15% on a 200k model)

If `/context` still shows 30%+ messages: see the upstream-proxy section
above, or open an issue with your `ccr -9 doctor detail` output.

---

## 2. Model Names — Claude-Family vs. Custom Aliases

> **Earlier versions of this doc claimed custom names cause context bloat.
> That was a misdiagnosis** — the bloat was 100% from `ENABLE_TOOL_SEARCH`
> being disabled (section 1), independent of model names. This section is
> the corrected analysis.

### What actually happens with custom names

Claude Code's client recognizes only model names matching:

- `claude-opus-*`
- `claude-sonnet-*`
- `claude-haiku-*`

A custom name like `ccr-pro` / `ccr-normal` / `ccr-lite` falls into an
**unknown-model branch**, where the client uses its own defaults for:

- Max output tokens (default fallback value)
- Model self-description / intro text in the system prompt
- Title-bar / status-line label (shows the literal custom name)
- Some capability assumptions (e.g. tool/vision feature detection)

### What is NOT affected

- **MCP tool schema serialization** — controlled by `ENABLE_TOOL_SEARCH`
  (section 1), entirely independent of model name.
- **Context bucket sizes** — `System tools` / `MCP tools` / `Messages`
  buckets behave the same regardless of name.
- **Routing through 9Router / DeepSeek** — name is just a routing key
  the upstream gateway maps to a real provider+model.

### cc-router's current defaults

| Slot   | Default name |
|--------|--------------|
| Opus   | `ccr-pro`     |
| Sonnet | `ccr-normal`  |
| Haiku  | `ccr-lite`    |

These match the historical 9Router alias convention. Your 9Router config
must expose routes for these names (or you must override them — see below).

### Switching to claude-family names (for client-side polish)

If you want the official defaults (proper title-bar text, max output, etc.):

```powershell
[Environment]::SetEnvironmentVariable('NINEROUTER_OPUS_MODEL',   'claude-opus-4-5',   'User')
[Environment]::SetEnvironmentVariable('NINEROUTER_SONNET_MODEL', 'claude-sonnet-4-5', 'User')
[Environment]::SetEnvironmentVariable('NINEROUTER_HAIKU_MODEL',  'claude-haiku-4-5',  'User')
```

```bash
export NINEROUTER_OPUS_MODEL='claude-opus-4-5'
export NINEROUTER_SONNET_MODEL='claude-sonnet-4-5'
export NINEROUTER_HAIKU_MODEL='claude-haiku-4-5'
```

Then add matching alias routes inside 9Router that point at your real
upstream models. `ccr -9 doctor` will switch its line for that slot from
`INFO` (custom) to `OK` (claude family).

### Precedence (when multiple sources set the same model)

```text
[wins] ~/.claude/settings.json  env  block
       ↓
       ccr 9router process env (from NINEROUTER_*_MODEL or cc-router defaults)
       ↓
[loses] Claude Code built-in defaults
```

If `settings.json` has an `env` block setting `ANTHROPIC_DEFAULT_*_MODEL`,
it overrides whatever `ccr -9` injects. `ccr -9 doctor detail` section [5]
prints the contents of that block. Remove those keys from settings.json
if you want `ccr -9` to be authoritative.

---

## 3. install.ps1 Copies Scripts (this surprised me)

### What `install.ps1` actually does

```text
D:\Andrew\Code\cc-router\scripts\cc.ps1   ─── copy ───>   $HOME\cc-router\bin\cc.ps1
D:\Andrew\Code\cc-router\scripts\ccr deepseek.ps1  ─── copy ───>   $HOME\cc-router\bin\ccr deepseek.ps1
D:\Andrew\Code\cc-router\scripts\common.ps1 ── copy ───>  $HOME\cc-router\bin\common.ps1
```

If you ran `install.ps1 -AddToProfile`, the profile entry it added looks
like:

```powershell
function cc { & 'C:\Users\Andrew\cc-router\bin\cc.ps1' @args }
```

i.e. it points at the **copy**, not at the source repo.

### Implication

After editing the source scripts in `D:\...\cc-router\scripts\`, your
`ccr` / `ccr deepseek` commands keep running the OLD copies until you **re-run
`install.ps1`** to refresh them.

```powershell
cd D:\Andrew\Code\cc-router
.\install.ps1                # do NOT pass -AddToProfile if profile already has the entries
```

### Alternative: dev mode (point profile straight at the repo)

If you actively edit cc-router and don't want to re-install every time,
replace the install-generated profile entries with:

```powershell
$ccRouterRoot = 'D:\path\to\cc-router'
function global:cc  { & "$ccRouterRoot\scripts\cc.ps1"  @args }
function global:ccr deepseek { & "$ccRouterRoot\scripts\ccr deepseek.ps1" @args }
```

Now your `ccr` always runs the latest source. No more sync needed.

`ccr -9 doctor detail` section `[1] Launcher resolution` will show you
which path your `ccr` actually resolves to.

---

## 4. Restart Windows After Changing Scripts or Env

A running Claude Code process holds a snapshot of environment variables
from the moment it was launched. Editing `ccr.ps1` or your shell env does
**not** propagate into an already-running session.

After any change to scripts/env:

1. Exit the Claude Code TUI (`/exit` or `Ctrl+C`)
2. Close the shell window (recommended; ensures `$ccScript` and friends
   are re-resolved)
3. Open a fresh shell and re-launch `ccr -9` / `ccr deepseek`

If you suspect a stale window is causing weird behavior, `ccr -9 doctor
detail` will print the **simulated** env that a fresh launch would inject.
Compare it against what you actually see inside the running session.

---

## 5. PowerShell 5.1 vs PowerShell 7 — They Are Different Products

| Product | Version | Executable | Profile folder |
|---|---|---|---|
| Windows PowerShell | 5.1.x (built-in, frozen) | `powershell.exe` | `Documents\WindowsPowerShell\` |
| PowerShell | 7.x (separate install) | `pwsh.exe` | `Documents\PowerShell\` |

`install.ps1` writes into `$PROFILE`, which resolves to the **host-specific
profile of whichever PowerShell ran the install**. If you install under
PS 5.1 and later open PS 7, the function won't be defined there - and
vice versa.

Quick check:

```powershell
$PSVersionTable.PSVersion
$PSVersionTable.PSEdition   # Desktop = 5.1, Core = 7+
```

If you use both, run `install.ps1` from each, or share a profile by
dot-sourcing one from the other.

---

## 6. settings.json `env` Block Can Override `ccr -9` Process Env

`~/.claude/settings.json` accepts an `env` block:

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "...",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "..."
  }
}
```

In some Claude Code versions, this block **takes precedence over** env
vars set by the wrapper script. If `ccr -9` injects fresh model names but
your settings.json still has stale values, the stale ones win.

`ccr -9 doctor detail` section `[5]` will print the contents of this block
(secrets redacted). If you see entries here that conflict with what your
wrapper sets, delete the `env` block from `settings.json` and let the
wrapper own provider routing entirely.

---

## 7. Prompt cache env (all launch modes)

cc-router sets on every `ccr`, `ccr -9`, and `ccr deepseek` launch:

```text
CLAUDE_CODE_ATTRIBUTION_HEADER=false
CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS=1
```

**Why:**

- **Attribution header** — Anthropic billing attribution on third-party /
  proxied endpoints can invalidate or bypass provider prompt caches.
- **Git instructions** — injecting `git status` into the system prompt changes
  the prefix every time the working tree moves, so prefix cache misses.

Optional one-shot overrides (same pattern as `NINEROUTER_TOOL_SEARCH`):

```bash
export CC_ATTRIBUTION_HEADER=false          # default when unset
export CC_DISABLE_GIT_INSTRUCTIONS=1        # default when unset; empty string unsets
```

Verify DeepSeek cache hits at home: [`CR-CACHE-BENCH.md`](CR-CACHE-BENCH.md)
and `scripts/ccr deepseek-cache-bench.sh`.

---

## 8. claude-code-cache-fix (default on for `ccr` and `ccr -9`)

[claude-code-cache-fix](https://github.com/cnighswonger/claude-code-cache-fix)
is a local proxy that stabilizes Claude Code request prefixes (billing header,
resume block layout, tool order, etc.) so **prompt cache** hits stay high.

cc-router enables it by default (`cacheFixEnabled`, `cacheFix9routerEnabled`).
Turn off with `ccr config set cacheFix9routerEnabled off` (or `cacheFixEnabled off`
for official mode only).

### Install and start (one-time)

```bash
npm install -g claude-code-cache-fix
```

**For `ccr -9` (OAuth / model switching via 9Router)** — upstream must be 9Router:

```bash
export CACHE_FIX_PROXY_UPSTREAM=http://127.0.0.1:20128   # or your NINEROUTER_URL
node "$(npm root -g)/claude-code-cache-fix/proxy/server.mjs" &
curl http://127.0.0.1:9801/health
```

**For official `ccr` only** — upstream defaults to `https://api.anthropic.com`; same
listen on `:9801`, no `CACHE_FIX_PROXY_UPSTREAM` needed unless you chain elsewhere.

`ccr -9 doctor` prints the exact start command when cache-fix health fails.

### What cc-router sets

| Mode | `cacheFix*` config | `ANTHROPIC_BASE_URL` | cache-fix upstream |
|------|-------------------|----------------------|--------------------|
| `ccr` | `cacheFixEnabled` (default on) | `http://127.0.0.1:9801` (no `/v1`) | Anthropic API |
| `ccr -9` | `cacheFix9routerEnabled` (default on) | `http://127.0.0.1:9801/v1` | `nineRouterUrl` or `NINEROUTER_URL` |

Chain for `ccr -9`:

```text
Claude Code → cache-fix (:9801) → 9Router (:20128) → provider (OAuth Claude, etc.)
```

`NINEROUTER_KEY` is still passed as `ANTHROPIC_AUTH_TOKEN` to authenticate to
9Router. OAuth accounts are configured in the 9Router dashboard, not in cc-router.

### Config toggles

```bash
ccr config show
ccr config set cachePromptEnvEnabled off    # stop ATTRIBUTION_HEADER / git env injection
ccr config set cacheFix9routerEnabled off   # ccr 9router direct to 9Router (no cache-fix)
ccr config set cacheFixEnabled off            # official cc direct to Anthropic
ccr config set nineRouterUrl http://127.0.0.1:20128
```

Env overrides: `CC_CACHE_FIX_9ROUTER_ENABLED`, `CC_CACHE_FIX_ENABLED`,
`CC_CACHE_PROMPT_ENV_ENABLED`, `CC_CACHE_FIX_URL`.

### Existing `config.json`

New installs and `ccr config setup` use defaults **on**. If your file still has
`"cacheFixEnabled": false` from an older example, run `ccr config set cacheFixEnabled on`
and `ccr config set cacheFix9routerEnabled on`, or merge from `config.example.json`.

---

## 9. Quick Diagnosis Cheat Sheet

| Symptom | Most likely cause | First thing to try |
|---|---|---|
| New `ccr -9` window: `/context` shows 30%+ on `hi` | `ENABLE_TOOL_SEARCH` not active or 9Router stripped `tool_reference` | `ccr -9 doctor detail` → check `[4]` shows `ENABLE_TOOL_SEARCH = true`. If yes, try `$env:NINEROUTER_TOOL_SEARCH = 'auto'` to confirm 9Router compatibility |
| Title bar shows `ccr-normal` and you wanted `claude-sonnet-*` | cc-router defaults are the cc-* aliases (this is by design — section 2). Change them via `NINEROUTER_*_MODEL`. | `[Environment]::SetEnvironmentVariable('NINEROUTER_SONNET_MODEL','claude-sonnet-4-5','User')` then open a new shell |
| Title bar shows the WRONG model name even after setting env var | `~/.claude/settings.json` `env` block is overriding it | `ccr -9 doctor detail` → section `[5]` shows the block contents. Remove `ANTHROPIC_DEFAULT_*_MODEL` keys from there. |
| Edited `ccr.ps1` but behavior didn't change | `ccr` resolves to install-time copy, not source | re-run `.\install.ps1` (no `-AddToProfile`) OR switch to dev-mode profile (section 3 above) |
| `ccr -9 doctor detail` says `ccr command : NOT FOUND on PATH` | running under `-NoProfile` or wrong PowerShell host | open a normal shell; verify `$PROFILE` matches expected host |
| `hi` returns 400 / "model not found" / weird upstream error | upstream proxy doesn't support `tool_reference` blocks (now that you enabled them) | `$env:NINEROUTER_TOOL_SEARCH = 'auto'` or `''` and retry |
| Connection refused / timeout | 9Router not running or wrong port | `ccr -9 doctor` → check `9Router health check returned ok=true` |

---

## 10. Where to Get Help

- Run `ccr -9 doctor detail` first - it covers ~80% of common
  misconfigurations and prints copy-paste fixes.
- For the MCP tool bloat issue specifically, the relevant Anthropic docs
  page is <https://code.claude.com/docs/en/env-vars> (search for
  `ENABLE_TOOL_SEARCH`).
- For new bugs: file an issue with the full output of
  `ccr -9 doctor detail` (it auto-redacts tokens) plus a screenshot of
  `/context` after typing `hi` in a fresh session.
