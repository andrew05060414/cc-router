# cc-router

Lightweight cross-platform quick launcher for Claude Code:

- `ccr` = the default way to boot Claude Code, with sane defaults
- `ccr <subcommand>` = optional variants for routing / setup / advanced modes

Most behavior is controlled through `ccr setup` and `ccr config`, so users can keep
`ccr` simple and opt into more advanced behavior only when they need it.

> **First time with 9Router + OAuth + prompt-cache fix?** Read
> [`docs/SETUP-GUIDE.md`](docs/SETUP-GUIDE.md) and run `ccr setup install-deps` then `ccr setup check`.
> PM-oriented overview: [`docs/PRODUCT.md`](docs/PRODUCT.md).
>
> **Hitting weird `/context` bloat or other quirks?** See
> [`docs/SETUP-NOTES.md`](docs/SETUP-NOTES.md). Planned setup improvements:
> [`docs/TODO.md`](docs/TODO.md).
>
> **Remote server onboarding?** See [`docs/CR-REMOTE.md`](docs/CR-REMOTE.md)
> and [`docs/CCR-USER-MANUAL.md`](docs/CCR-USER-MANUAL.md) §5.
> First-time: `ccr remote pack` then `ccr remote onboard <alias>`.
> Day-to-day sync: `ccr remote setup <alias> --steps sync`.

Supported now:

- Windows (PowerShell)
- Linux / WSL (bash)
- macOS should work via bash/zsh path the same as Linux

## Quick start

### Windows

```powershell
.\install.ps1 -AddToProfile
. $PROFILE
```

Use no-profile mode to avoid old profile function interference during validation:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\ccr.ps1" --help
```

Remote onboarding from Windows:

```powershell
ccr remote pack
ccr remote onboard lgsj-h100
ccr remote ssh lgsj-h100 C:\RemoteProject
```

See [`docs/CR-REMOTE.md`](docs/CR-REMOTE.md) for details.

### Linux / WSL

```bash
chmod +x install.sh
./install.sh
export PATH="$HOME/.local/bin:$PATH"
```

## Usage

### Default mode

```bash
ccr
ccr --model sonnet
ccr resume
ccr setup
ccr setup check
ccr doctor
```

`ccr` is the quick launcher. `ccr setup` and `ccr config` are where users decide
what the launcher should do.

### Advanced mode

```bash
ccr 9router
ccr 9router resume
ccr 9router --model sonnet
ccr 9router doctor
```

In `ccr 9router`, Claude slot selectors such as `sonnet`, `haiku`, `opus`, and
`claude-sonnet-*` are rewritten to the active `NINEROUTER_*_MODEL` targets
before Claude Code launches. This keeps agent/subagent launches aligned with
your `cc-normal` / `cc-lite` / `cc-pro` routing.

`ccr 9router` is the opt-in path for 9Router + cache-fix. It stays available, but it
is not the main story for new users.

`ccr 9router doctor` also reports whether agent slot alias rewrite is active, so you
can confirm that explicit `--model sonnet|haiku|opus` launches will remap onto
your active `cc-*` slots before Claude Code starts.

### CC Switch mode (`ccr switch`)

```bash
ccr switch
ccr switch resume
ccr switch --model sonnet
ccr switch doctor
```

`ccr switch` is the **recommended path for users who do not have an Anthropic
account** and route everything through [CC Switch](https://github.com/farion1231/cc-switch)
instead. It sets `ANTHROPIC_BASE_URL` to the CC Switch proxy
(`http://127.0.0.1:15721` by default) and lets CC Switch handle:

- model mapping (`claude-sonnet-4-X` → `ANTHROPIC_DEFAULT_SONNET_MODEL`, etc.)
- `apiFormat` conversion (`anthropic` ↔ `openai_chat` / `openai_responses` / `gemini_native`)
- failover + circuit-breaker across multiple Provider accounts
- per-request usage logging

`ccr switch` does **not** chain the cache-fix proxy (no Anthropic account → no
prefix cache to optimize) and does **not** rewrite `--model sonnet|haiku|opus`
to `cc-normal/cc-lite/cc-pro` (CC Switch model mapping expects the canonical
`claude-*` name). For 9Router slot alias behavior, keep using `ccr 9router`.

Override the proxy URL when needed:

```bash
CC_CCS_PROXY_URL=http://host:port ccr switch
# or persist:
ccr config set ccsProxyUrl http://host:port
```

`ccr switch doctor` checks that the CC Switch proxy is reachable and prints the
effective env that would be injected.

### Supported now

- `ccr 9router` for 9Router / cache-fix routing
- `ccr switch` for CC Switch proxy routing (recommended when no Anthropic account)
- `ccr deepseek` for DeepSeek mode and AI-assisted setup
- `ccr remote` for one-shot remote server onboarding via SSH/scp
- `ccr setup`, `ccr config`, `ccr doctor` for onboarding and diagnostics

### Permission / bypass settings (`ccr config`)

cc-router keeps its own small config file (separate from Claude Code):

- **Linux/macOS:** `~/.config/cc-router/config.json`
- **Windows:** `%USERPROFILE%\.config\cc-router\config.json`

Interactive setup:

```bash
ccr config setup
```

| Setting | Meaning |
| --- | --- |
| `allowDangerouslySkipPermissions` | When `true`, every `ccr` / `ccr 9router` / `ccr switch` / `ccr deepseek` launch adds `--allow-dangerously-skip-permissions` (Bypass appears in Shift+Tab cycle) |
| `cachePromptEnvEnabled` | When `true` (default), sets `CLAUDE_CODE_ATTRIBUTION_HEADER=false` and `CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS=1` on every launch |
| `cacheFixEnabled` | When `true` (default), **official `ccr`** sets `ANTHROPIC_BASE_URL` to the local cache-fix proxy |
| `cacheFix9routerEnabled` | When `true` (default), **`ccr 9router`** uses cache-fix at `cacheFixUrl` with upstream at `nineRouterUrl` / `NINEROUTER_URL`. Set to `off` if you do not have an Anthropic account — the proxy then has nothing to optimize. |
| `cacheFixUrl` | cache-fix listen URL (default `http://127.0.0.1:9801`) — probed at `/health` by `ccr doctor` |
| `nineRouterUrl` | Fallback 9Router base when `NINEROUTER_URL` is unset (default `http://127.0.0.1:20128`) |
| `ccsProxyUrl` | CC Switch proxy URL for `ccr switch` (default `http://127.0.0.1:15721`) — probed at `/health` by `ccr switch doctor` |
| `claudePermissionsTarget` | Default file for `ccr config claude …`: `none`, `global` (`~/.claude/settings.json`), or `project` (`<repo>/.claude/settings.json`) |

Prompt-cache defaults and [claude-code-cache-fix](https://github.com/cnighswonger/claude-code-cache-fix) chaining are documented in [`docs/SETUP-NOTES.md`](docs/SETUP-NOTES.md) §7–§8.

Examples:

```bash
ccr config set allowDangerouslySkipPermissions on
ccr config set cacheFix9routerEnabled on   # default on; ccr 9router → cache-fix → 9Router
ccr config set cacheFixEnabled on          # default on; official ccr → cache-fix → Anthropic
ccr config set cacheFixUrl http://127.0.0.1:9801
ccr config set claudePermissionsTarget global
ccr config claude set permissions.defaultMode acceptEdits --global
ccr config claude enable-bypass-permissions --project
ccr config show
```

One-shot without editing JSON:

```bash
CC_ALLOW_DANGEROUSLY_SKIP_PERMISSIONS=1 ccr
```

See `config.example.json` in the repo root.

If you want a guided first run, `ccr setup` is the setup path; if you want
to make the launcher more opinionated, `ccr config` is where those defaults live.

9Router env:

```bash
export NINEROUTER_URL="http://localhost:20128"
export NINEROUTER_KEY="sk-..."   # optional when 9Router auth disabled
```

PowerShell:

```powershell
$env:NINEROUTER_URL = "http://localhost:20128"
$env:NINEROUTER_KEY = "sk-..."   # optional when 9Router auth disabled
```

### DeepSeek mode

Set your API key first:

```bash
export DEEPSEEK_API_KEY="your_key"
```

PowerShell:

```powershell
$env:DEEPSEEK_API_KEY = "your_key"
```

Then run:

```bash
ccr deepseek setup
ccr deepseek
ccr deepseek --model deepseek-v4-pro[1M] --max-output 32768
ccr deepseek resume
ccr deepseek doctor
```

DeepSeek **prompt cache** verification: [`docs/CR-CACHE-BENCH.md`](docs/CR-CACHE-BENCH.md) and `scripts/test/test-ccr-cache-bench.sh`.

`ccr deepseek setup` will:

- Ask for `DEEPSEEK_API_KEY`
- Ask how to persist:
  - current shell only (prints `export DEEPSEEK_API_KEY="..."`)
  - write/update `~/.bashrc` automatically
- Show next steps and optionally run a quick doctor check

## What doctor can fix

`ccr doctor` and `ccr deepseek doctor` check common Linux/WSL misconfigurations and print copy-paste fixes:

- `claude` not installed / not in `PATH`
- `~/.local/bin` missing from `PATH` (when `ccr` / `ccr deepseek` are installed there)
- stale `ANTHROPIC_BASE_URL` / `ANTHROPIC_AUTH_TOKEN` that can break official mode
- missing `DEEPSEEK_API_KEY` for DeepSeek mode
- runtime env expectation hints (why `ANTHROPIC_*` may be empty outside `ccr deepseek`)

Examples:

```bash
ccr doctor
ccr deepseek doctor
```

If something is wrong, doctor prints direct fix commands such as:

```bash
pnpm add -g @anthropic-ai/claude-code
export PATH="$HOME/.local/bin:$PATH"
unset ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN
export DEEPSEEK_API_KEY="your_key"
```

For verbose diagnostics with a full env / launcher / settings.json
breakdown, use `ccr 9router doctor detail` (or `ccr doctor detail` / `ccr deepseek doctor`).
For the underlying root causes behind common bloat / routing issues, see
[`docs/SETUP-NOTES.md`](docs/SETUP-NOTES.md).

For local shell regressions, run:

```bash
bash scripts/test/test-ccr.sh
```

Supported `ccr deepseek` options:

- `-h`, `--help`
- `setup` (interactive API key setup wizard)
- `prompt` / `dramatic-prompt` (AI-assisted setup template, see below)
- `-C`, `--here`, `--current` (keep current directory)
- `--worktree <name>` (run in `.worktrees/<name>`)
- `--model <id>`
- `--haiku-model <id>`
- `--max-output <n>`
- `--autocompact-pct <n>`

### `ccr deepseek prompt` (one-shot AI-assisted setup)

If you'd rather have an AI agent (Claude Code / Codex / Cursor / Aider / ...)
walk you through detection, install, key setup, and `ccr deepseek doctor` in your real
terminal, use the built-in dramatic prompt template:

```bash
ccr deepseek prompt                  # show template path + copy/paste hints
ccr deepseek prompt --print-prompt   # print the full template content to stdout
ccr deepseek prompt --help           # subcommand-level help
```

Pipe it straight to your clipboard:

```bash
ccr deepseek prompt --print-prompt | xclip -selection clipboard   # Linux
ccr deepseek prompt --print-prompt | pbcopy                       # macOS
ccr deepseek prompt --print-prompt | clip.exe                     # Windows / WSL
```

Then paste it into any AI coding agent and follow the steps it gives you.

Source template lives at `docs/dramatic-prompt.md`. After `install.sh` it is
also copied to `~/.local/share/cc-router/templates/dramatic-prompt.md`; after `install.ps1`
it is copied to `$HOME\.local\share\cc-router\templates\dramatic-prompt.md`. You can override
the lookup with `CCD_PROMPT_TEMPLATE=/abs/path/to/your-prompt.md`.

### `--worktree` (Linux / WSL script)

`ccr deepseek --worktree <name>` will create or reuse `.worktrees/<name>` under your git repo root, then run `claude` in that directory.

Guardrails:

- Must run inside a git repo
- Repo must be clean (`git status --porcelain` empty), otherwise it fails fast
- `name` must match `[A-Za-z0-9._-]+` (no slash, no spaces)
- `--worktree` cannot be combined with `--current` / `--here`

Predictable existing-path behavior:

- If `.worktrees/<name>` already exists and is a valid git worktree root, it is reused
- If the path exists but is not a valid reusable git worktree, command errors out (no destructive fallback)

## Why this tool exists

Mixing official Claude and DeepSeek routing in one shell can easily create bad env state:

- official login breaks if `ANTHROPIC_AUTH_TOKEN` points to DeepSeek key
- requests go to wrong endpoint if `ANTHROPIC_BASE_URL` is left over

`ccr` and `ccr deepseek` isolate this so switching providers is predictable.

## Roadmap (TODO)

- ~~Add one-shot "dramatic prompt" for AI-assisted setup~~ (done, see `ccr deepseek prompt`)
- ~~Mirror `ccr deepseek prompt` in the PowerShell launcher (`scripts/ccd.ps1`)~~
- ~~Add proper `--worktree` flow with guardrails~~
- ~~Add richer doctor checks and guided fixes~~
- Add support for other coding CLIs / TUI routing presets (including DeepSeek TUI)
- Package binaries (Windows EXE first) for non-technical users
- Explore a full CLI implementation (plan C) after script MVP stabilizes
