# cc-router full stack setup guide

This guide explains **why** the stack has several moving parts, **how** they connect,
and **what to run once** so `ccr`, `ccr -9`, and `ccr deepseek` work reliably. For debugging
symptoms after setup, see [SETUP-NOTES.md](SETUP-NOTES.md).

---

## What you are building

Most cc-router users who hit quota limits on official Anthropic want:

1. **Claude Code** as the client (tools, MCP, `/resume`, etc.)
2. **9Router** as a local gateway (OAuth subscriptions, free/cheap providers, model aliases)
3. **claude-code-cache-fix** as a local request normalizer so **prompt cache** stays healthy through a proxy

cc-router is only the **launcher**: it sets env vars, optional config in
`~/.config/cc-router/config.json`, and runs `claude` with the right routing.

### End-to-end diagram (`ccr -9` with defaults)

```text
┌─────────────────┐
│  Claude Code    │  You type here; builds /v1/messages JSON
│  (ccr 9router)        │
└────────┬────────┘
         │ ANTHROPIC_BASE_URL=http://127.0.0.1:9801/v1
         │ ANTHROPIC_AUTH_TOKEN=<NINEROUTER_KEY>
         │ + cc-router env (ENABLE_TOOL_SEARCH, ATTRIBUTION_HEADER=false, …)
         ▼
┌─────────────────┐
│ cache-fix proxy │  :9801 — strips/stabilizes billing header, tool order,
│ (Node)          │  resume blocks, cache_control markers
└────────┬────────┘
         │ CACHE_FIX_PROXY_UPSTREAM=http://127.0.0.1:20128
         ▼
┌─────────────────┐
│ 9Router         │  :20128 — OAuth accounts, routing, RTK compression,
│                 │  model aliases (cc-pro / cc-normal / cc-lite)
└────────┬────────┘
         │
         ▼
   Anthropic OAuth / Kiro / other providers
```

**Official `ccr`** (subscription direct): same cache-fix on `:9801`, upstream defaults to
`https://api.anthropic.com` (no 9Router).

**`ccr deepseek`** (DeepSeek): skips cache-fix and 9Router; uses `api.deepseek.com/anthropic`.
See [CR-CACHE-BENCH.md](CR-CACHE-BENCH.md) for cache verification there.

---

## Why each layer exists

### Claude Code quirks (why cache-fix exists)

When `ANTHROPIC_BASE_URL` is not `*.anthropic.com`, Claude Code still sends requests
that are hard to cache on third-party gateways:

| Issue | Effect if unfixed |
|--------|-------------------|
| Dynamic `x-anthropic-billing-header` in system prompt | Prefix changes every session/request → **cache miss** |
| `--resume` moving attachment blocks | Prefix changes on resume → **~10–20× cost** on some versions |
| Non-deterministic tool definition order | Prefix bytes differ between turns |
| Git status injected every turn | Working tree changes → prefix bust |

Anthropic’s **own API** often strips the billing line server-side; **9Router does not**
implement the full [claude-code-cache-fix](https://github.com/cnighswonger/claude-code-cache-fix)
repair set. Putting cache-fix **in front of** 9Router fixes the **client-shaped** body
before routing.

References: [cc-cache-audit](https://github.com/motiful/cc-cache-audit),
[SETUP-NOTES.md §7](SETUP-NOTES.md#7-prompt-cache-hygiene-all-modes),
[9ROUTER-CACHE-RESEARCH.md](9ROUTER-CACHE-RESEARCH.md) (if present).

### cc-router env (why not only cache-fix)

| Env / setting | Purpose |
|---------------|---------|
| `CLAUDE_CODE_ATTRIBUTION_HEADER=false` | Stops CC from injecting the dynamic billing line (config: `cachePromptEnvEnabled`) |
| `CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS=1` | Stops live `git status` in system prompt every turn |
| `ENABLE_TOOL_SEARCH=true` | Re-enables deferred MCP tool loading when using a proxy ([issue #31936](https://github.com/anthropics/claude-code/issues/31936)) |

These are applied by cc-router on **every** launch; cache-fix adds **structural** repairs on the wire.

### 9Router (why you use it)

- Central place for **OAuth** (Claude Max/Pro via gateway) and **fallback models** when 5h quota is tight
- **RTK** (default on in 9Router) compresses large `tool_result` blobs before the upstream sees them
- Does **not** replace cache-fix for CC-specific prefix bugs

### Optional: Clash / corporate proxy

- **Clash (e.g. :7897)** is for **outbound internet** from your machine or from a process
- **cache-fix (:9801)** is an **application-level** rewrite proxy; CC talks to localhost only
- Typical pattern: set `HTTPS_PROXY=http://127.0.0.1:7897` on the **cache-fix process** if
  9Router or Anthropic need the tunnel—not “double proxy” in the sense of chaining two CC base URLs

```text
Claude Code → 127.0.0.1:9801 (cache-fix) → 127.0.0.1:20128 (9Router) → HTTPS_PROXY → internet
```

TUN mode on Clash is optional; many users only need `HTTPS_PROXY` on cache-fix or 9Router.

---

## Prerequisites

| Component | Check | Install |
|-----------|--------|---------|
| Claude Code CLI | `claude --version` | `npm install -g @anthropic-ai/claude-code` |
| Node.js 18+ | `node --version` | For cache-fix proxy |
| cc-router on PATH | `which cc` | `./install.sh` from this repo |
| 9Router running | `curl http://127.0.0.1:20128/api/health` | [9router](https://github.com/decolua/9router) — configure OAuth in dashboard |
| cache-fix installed | `npm root -g`/claude-code-cache-fix | `npm install -g claude-code-cache-fix` |

---

## One-time setup (recommended order)

### 1. Install cc-router

```bash
cd /path/to/cc-router
./install.sh
# ensure ~/.local/bin is on PATH
cc --help
```

### 2. Configure 9Router

1. Start 9Router (default `http://127.0.0.1:20128`).
2. In the dashboard: add your **Claude OAuth** (or other) connections.
3. Create an API key if required → save as `NINEROUTER_KEY`.

```bash
export NINEROUTER_URL=http://127.0.0.1:20128    # optional if nineRouterUrl in config
export NINEROUTER_KEY=your-9router-api-key
curl -fsS http://127.0.0.1:20128/api/health
```

### 3. Install npm dependencies (required for default `ccr -9`)

cc-router can install these for you:

```bash
ccr setup install-deps
```

That runs (when missing):

- `npm install -g @anthropic-ai/claude-code` — Claude Code CLI
- `npm install -g claude-code-cache-fix` — local cache-fix proxy

On `ccr -9`, if packages are missing and your terminal is interactive, you’ll be **prompted** to install (skip with `CC_ROUTER_NO_INSTALL_PROMPT=1`).

### 4. Start cache-fix (required for default `ccr -9`)

**Important:** Start cache-fix **after** 9Router is up, with **upstream = 9Router**:

```bash
# if not already installed:
ccr setup install-deps
# or: npm install -g claude-code-cache-fix

export CACHE_FIX_PROXY_UPSTREAM=http://127.0.0.1:20128
node "$(npm root -g)/claude-code-cache-fix/proxy/server.mjs" &
```

Wait until listening (do not `curl` in the same millisecond):

```bash
for i in 1 2 3 4 5 6 7 8 9 10; do
  curl -fsS http://127.0.0.1:9801/health && break
  sleep 0.5
done
```

Expected: `{"status":"ok"}` (or similar JSON with ok).

**Persist across reboots (pick one):**

```bash
cache-fix-proxy install-service   # writes launchd/systemd user unit; set env in unit or re-run install-service after changing CACHE_FIX_PROXY_UPSTREAM
```

Or add the `export` + `node … &` lines to your shell profile (less reliable than a service).

### 5. cc-router config (defaults are already “on”)

New installs use `config.example.json` defaults:

| Key | Default | Meaning |
|-----|---------|---------|
| `cachePromptEnvEnabled` | `true` | Attribution + git env |
| `cacheFix9routerEnabled` | `true` | `ccr -9` → cache-fix → 9Router |
| `cacheFixEnabled` | `true` | `ccr` → cache-fix → Anthropic |
| `cacheFixUrl` | `http://127.0.0.1:9801` | cache-fix listen URL |
| `nineRouterUrl` | `http://127.0.0.1:20128` | Fallback if `NINEROUTER_URL` unset |

```bash
ccr config show
ccr config setup          # optional: permissions / bypass prompts
```

If you have an **old** `config.json` with `"cacheFixEnabled": false`, run:

```bash
ccr config set cacheFixEnabled on
ccr config set cacheFix9routerEnabled on
```

### 6. Verify

```bash
ccr 9router doctor
ccr 9router doctor detail
```

Healthy summary:

- 9Router `api/health` → ok
- cache-fix `/health` → ok
- `[4]` / prompt cache env shows `ENABLE_TOOL_SEARCH=true`, attribution off
- `[5]` shows chain: `Claude Code → cache-fix (9801) → 9Router (20128)`

Start a session:

```bash
ccr 9router
```

Inside CC: `/context` after `hi` — Messages bucket should stay modest if MCP deferred loading works (see SETUP-NOTES §1).

---

## What cc-router sets on launch (`ccr -9`)

| Variable | Typical value | Set by |
|----------|---------------|--------|
| `ANTHROPIC_BASE_URL` | `http://127.0.0.1:9801/v1` | cc-router (`cacheFix9routerEnabled`) |
| `ANTHROPIC_AUTH_TOKEN` | `NINEROUTER_KEY` | cc-router |
| `ANTHROPIC_MODEL` / `ANTHROPIC_DEFAULT_*` | `ccr-normal`, `ccr-pro`, `ccr-lite` | cc-router (overridable via `NINEROUTER_*_MODEL`) |
| `ENABLE_TOOL_SEARCH` | `true` | cc-router |
| `CLAUDE_CODE_ATTRIBUTION_HEADER` | `false` | cc-router |
| `CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS` | `1` | cc-router |

You do **not** set `NINEROUTER_URL` to `9801`; cc-router points CC at cache-fix automatically.

---

## Daily workflow

1. Ensure **9Router** is running (`curl …/api/health`).
2. Ensure **cache-fix** is running (`curl http://127.0.0.1:9801/health`).
3. `ccr -9` (or `ccr` for official-only path).

Quick check command:

```bash
ccr setup check
```

(See [TODO.md](TODO.md) for planned improvements to this command.)

---

## Turning features off

| Goal | Command |
|------|---------|
| `ccr -9` direct to 9Router (no cache-fix) | `ccr config set cacheFix9routerEnabled off` |
| Official `ccr` direct to Anthropic | `ccr config set cacheFixEnabled off` |
| Stop attribution/git env injection | `ccr config set cachePromptEnvEnabled off` |
| Disable MCP deferred loading (debug only) | `export NINEROUTER_TOOL_SEARCH=` then new shell |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `curl :9801` fails right after `node … &` | Race: proxy not listening yet | Wait/retry loop; see §3 |
| `curl :9801` always fails | cache-fix not running | Start with `CACHE_FIX_PROXY_UPSTREAM` set |
| `ccr -9` works but cache still expensive | cache-fix down or `cacheFix9routerEnabled off` | `ccr -9 doctor`; start proxy |
| 9Router errors upstream | OAuth expired / wrong model alias | 9Router dashboard |
| `/context` 30%+ on `hi` | `ENABLE_TOOL_SEARCH` off or 9Router strips `tool_reference` | `ccr -9 doctor detail` §4–5 |
| Official `ccr` broken with cache-fix on | cache-fix upstream still pointing at 20128 | Run **two** processes or one process with upstream switched—official needs default Anthropic upstream; use separate terminal profiles or install-service env |

**Running official `ccr` and `ccr -9` at the same time:** one cache-fix process can only have **one**
`CACHE_FIX_PROXY_UPSTREAM`. For simultaneous use you need either:

- Two cache-fix instances on different ports (advanced), or
- Stop/restart cache-fix when switching modes, or
- Disable `cacheFixEnabled` for official and only chain 9Router path

---

## Related docs

- [SETUP-NOTES.md](SETUP-NOTES.md) — MCP bloat, model aliases, diagnosis cheat sheet
- [CR-CACHE-BENCH.md](CR-CACHE-BENCH.md) — DeepSeek cache bench
- [9ROUTER-CACHE-RESEARCH.md](9ROUTER-CACHE-RESEARCH.md) — what 9Router does vs cache-fix
- [TODO.md](TODO.md) — planned setup CLI improvements
