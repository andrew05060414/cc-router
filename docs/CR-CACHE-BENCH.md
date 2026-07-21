# DeepSeek prompt cache bench (ccr deepseek)

Use this when you want to confirm that **ccr deepseek** (or your DeepSeek routing) is
getting **prefix / prompt cache hits** on repeated turns — not just that the
API works.

cc-router injects cache-friendly env on every `ccr`, `ccr -9`, and `ccr deepseek` launch:

```text
CLAUDE_CODE_ATTRIBUTION_HEADER=false
CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS=1
```

See also [`SETUP-NOTES.md`](SETUP-NOTES.md) for attribution header and git
instruction rationale.

---

## Quick automated bench

From the repo (or after `install.sh` copies scripts):

```bash
export DEEPSEEK_API_KEY="sk-..."
chmod +x scripts/ccr deepseek-cache-bench.sh
./scripts/ccr deepseek-cache-bench.sh
```

PowerShell:

```powershell
$env:DEEPSEEK_API_KEY = 'sk-...'
.\scripts\ccr deepseek-cache-bench.ps1
```

Dry run (env only, no API):

```bash
./scripts/ccr deepseek-cache-bench.sh --dry-run
```

The script runs **three** identical `claude --print` calls with a fixed system
prompt and user message so the prefix should stabilize after run 1.

---

## What to look for

In Claude Code / provider usage metadata (wording varies by version):

| Field | Healthy pattern |
| --- | --- |
| `cache_read_input_tokens` | **Increases on run 2+** (cache hit) |
| `cache_creation_input_tokens` | Often **> 0 on run 1 only**, near **0** later |
| Input tokens billed at full price | Should drop when `cache_read` is high |

**Bad signs:**

- Every run shows large `cache_creation` and zero `cache_read` → prefix is
  changing every request (git status injection, different system text, MCP
  bloat, or attribution header).
- Run 2+ still cold → compare with `ccr deepseek doctor` and ensure you are not
  overriding `CC_DISABLE_GIT_INSTRUCTIONS` or `CC_ATTRIBUTION_HEADER`.

Optional overrides (same as launchers):

```bash
export CC_ATTRIBUTION_HEADER=false
export CC_DISABLE_GIT_INSTRUCTIONS=1
export CCD_TOOL_SEARCH=true
```

---

## Manual procedure

1. `export DEEPSEEK_API_KEY=...`
2. `ccr deepseek doctor` — key and URL hints OK.
3. In a clean directory (no huge repo git state if testing without
   `CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS`):

   ```bash
   ccr deepseek --print --model 'deepseek-v4-pro[1m]' 'Reply: OK'
   ```

   Repeat the **exact same** command twice more.

4. Compare usage between invocations.

For interactive sessions, send the same user message twice in a row with no
file changes between turns; check `/cost` or provider dashboards if available.

---

## Env knobs for the bench script

| Variable | Default | Purpose |
| --- | --- | --- |
| `CCD_BENCH_MODEL` | `deepseek-v4-pro[1m]` | Main model |
| `CCD_BENCH_HAIKU_MODEL` | `deepseek-v4-flash` | Subagent slot |
| `CCD_BENCH_RUNS` | `3` | Repeat count |

---

## Related: official `ccr` + claude-code-cache-fix

That path is **Anthropic official** only (`cacheFixEnabled` in
`~/.config/cc-router/config.json`). It does not apply to `ccr deepseek`. See
[SETUP-NOTES.md — claude-code-cache-fix](SETUP-NOTES.md).
