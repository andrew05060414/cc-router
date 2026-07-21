# cc-router — product overview (PM)

## One sentence

**cc-router is a quick launcher for Claude Code.** It keeps the default boot path simple, while `ccr setup` and `ccr config` let users opt into routing, OAuth, cache fixes, and other advanced behavior when they actually need it.

## Problem we solve

Power users want:

1. **Claude Code** as the daily driver (tools, MCP, resume).
2. **9Router** to use subscription OAuth and **fall back to other models** when the 5-hour quota is tight.
3. **Fair billing** — Claude Code’s request format can **break prompt caching** on third-party gateways, silently increasing cost 10×+.

Manually managing `ANTHROPIC_BASE_URL`, API keys, model aliases, and cache-related flags is error-prone. cc-router automates that when asked, but keeps the default launcher path lightweight.

## What cc-router is / is not

| cc-router **is** | cc-router **is not** |
|------------------|----------------------|
| A thin CLI wrapper with a simple default launcher (`ccr`) | A replacement for Claude Code, 9Router, or cache-fix |
| Config in `~/.config/cc-router/config.json` | A hosted service |
| Doctor/setup commands for health checks | An npm package published separately (ships with this repo) |

## User-facing modes

| Command | User intent | Where requests go |
|---------|-------------|-------------------|
| `ccr` | Default boot path / quick launcher | Defaults decided by `setup` / `config` |
| `ccr -9` | 9Router + OAuth + model switching | cache-fix → 9Router → providers |
| `ccr deepseek` | Personal DeepSeek path / compatibility alias | DeepSeek directly |

## Public naming

For the README and launch copy, prefer telling people about `ccr` and `ccr -*`.
Then list the supported variants that actually exist today:

- `-9`
- `ccr deepseek`
- `setup`
- `config`
- `doctor`

Keep `-d` and `-a` as future alias ideas unless they are implemented in code.

## Default launch philosophy

`ccr` should feel like the obvious thing to type: one command, sensible defaults,
minimal friction. The advanced stack exists, but it is hidden behind setup and
config so users only think about it when they need to.

## Configuration philosophy

- **Good defaults on** — whatever helps the quick launcher work out of the box.
- **Toggles to opt out** — `ccr config set cacheFix9routerEnabled off`, etc.
- **Discoverability** — `ccr setup`, `ccr setup check`, `ccr doctor`, then `ccr -9` only when needed.

## Setup model

- Human users can run `ccr setup` and `ccr config`.
- An agent can also help finish setup for them, but the end result should still be the same simple `ccr` entrypoint.
- `ccr deepseek` stays available for personal use and compatibility, but a public-facing release can prefer `ccr -d` as the more neutral variant if you add it later.

## Success metrics (how we know it works)

- A new user can install and run `ccr` without learning the whole stack.
- `ccr setup check` passes when advanced routing is enabled.
- Users can opt into `ccr -9` or DeepSeek modes without changing the primary story.

## Risks / limitations

- **Two services must be running** for default `ccr -9`: 9Router + cache-fix.
- **One cache-fix process = one upstream** — switching official `ccr` and `ccr -9` simultaneously may need two ports or restart (see SETUP-GUIDE).
- **9Router does not fully replace cache-fix** for CC-specific cache bugs (documented in 9ROUTER-CACHE-RESEARCH.md).

## Roadmap (see TODO.md)

- Richer `ccr setup` wizard (install npm deps, start cache-fix, detect Clash).
- Dual cache-fix ports for parallel official + 9Router use.
