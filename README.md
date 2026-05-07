# claudeCodeForDeepseek

Lightweight cross-platform launcher for Claude Code:

- `cc` = official Claude mode (cleans DeepSeek routing env vars)
- `ccd` = DeepSeek mode (sets Anthropic-compatible DeepSeek env vars)

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
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\ccd.ps1" --help
```

### Linux / WSL

```bash
chmod +x install.sh
./install.sh
export PATH="$HOME/.local/bin:$PATH"
```

## Usage

### Official mode

```bash
cc
cc --model sonnet
cc resume
cc doctor
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
ccd setup
ccd
ccd --model deepseek-v4-pro[1m] --max-output 32768
ccd resume
ccd doctor
```

`ccd setup` will:

- Ask for `DEEPSEEK_API_KEY`
- Ask how to persist:
  - current shell only (prints `export DEEPSEEK_API_KEY="..."`)
  - write/update `~/.bashrc` automatically
- Show next steps and optionally run a quick doctor check

## What doctor can fix

`cc doctor` and `ccd doctor` check common Linux/WSL misconfigurations and print copy-paste fixes:

- `claude` not installed / not in `PATH`
- `~/.local/bin` missing from `PATH` (when `cc` / `ccd` are installed there)
- stale `ANTHROPIC_BASE_URL` / `ANTHROPIC_AUTH_TOKEN` that can break official mode
- missing `DEEPSEEK_API_KEY` for DeepSeek mode
- runtime env expectation hints (why `ANTHROPIC_*` may be empty outside `ccd`)

Examples:

```bash
cc doctor
ccd doctor
```

If something is wrong, doctor prints direct fix commands such as:

```bash
pnpm add -g @anthropic-ai/claude-code
export PATH="$HOME/.local/bin:$PATH"
unset ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN
export DEEPSEEK_API_KEY="your_key"
```

Supported `ccd` options:

- `-h`, `--help`
- `setup` (interactive API key setup wizard)
- `prompt` / `dramatic-prompt` (AI-assisted setup template, see below)
- `-C`, `--here`, `--current` (keep current directory)
- `--worktree <name>` (run in `.worktrees/<name>`)
- `--model <id>`
- `--haiku-model <id>`
- `--max-output <n>`
- `--autocompact-pct <n>`

### `ccd prompt` (one-shot AI-assisted setup)

If you'd rather have an AI agent (Claude Code / Codex / Cursor / Aider / ...)
walk you through detection, install, key setup, and `ccd doctor` in your real
terminal, use the built-in dramatic prompt template:

```bash
ccd prompt                  # show template path + copy/paste hints
ccd prompt --print-prompt   # print the full template content to stdout
ccd prompt --help           # subcommand-level help
```

Pipe it straight to your clipboard:

```bash
ccd prompt --print-prompt | xclip -selection clipboard   # Linux
ccd prompt --print-prompt | pbcopy                       # macOS
ccd prompt --print-prompt | clip.exe                     # Windows / WSL
```

Then paste it into any AI coding agent and follow the steps it gives you.

Source template lives at `docs/dramatic-prompt.md`. After `install.sh` it is
also copied to `~/.local/share/ccdeepseek/dramatic-prompt.md`; after `install.ps1`
it is copied to `$HOME\.ccdeepseek\share\dramatic-prompt.md`. You can override
the lookup with `CCD_PROMPT_TEMPLATE=/abs/path/to/your-prompt.md`.

### `--worktree` (Linux / WSL script)

`ccd --worktree <name>` will create or reuse `.worktrees/<name>` under your git repo root, then run `claude` in that directory.

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

`cc` and `ccd` isolate this so switching providers is predictable.

## Roadmap (TODO)

- ~~Add one-shot "dramatic prompt" for AI-assisted setup~~ (done, see `ccd prompt`)
- ~~Mirror `ccd prompt` in the PowerShell launcher (`scripts/ccd.ps1`)~~
- ~~Add proper `--worktree` flow with guardrails~~
- ~~Add richer doctor checks and guided fixes~~
- Add support for other coding CLIs / TUI routing presets (including DeepSeek TUI)
- Package binaries (Windows EXE first) for non-technical users
- Explore a full CLI implementation (plan C) after script MVP stabilizes
