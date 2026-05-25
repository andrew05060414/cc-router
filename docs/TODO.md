# cc-router backlog

## Setup & onboarding

- [x] **`cc setup install-deps`** + prompt on `cc -9` / `cc setup check` when npm packages missing
- [ ] **`cc setup` wizard (v2)** — write launchd/systemd unit with `CACHE_FIX_PROXY_UPSTREAM` from `nineRouterUrl`, optional Clash `HTTPS_PROXY` prompt
- [ ] **`cc setup start-cache-fix`** — foreground or background start with correct upstream and health wait loop (no race on `curl`)
- [ ] **`cc setup stop-cache-fix`** — kill listener on `cacheFixUrl` port if owned by cache-fix
- [ ] **Dual cache-fix profiles** — official (`→ anthropic.com`) and `cc -9` (`→ 9router`) on two ports so both modes work without restart
- [ ] **Windows service helper** — document or script for running cache-fix on login (Task Scheduler)

## Docs

- [x] [SETUP-GUIDE.md](SETUP-GUIDE.md) — full stack context and one-time setup
- [ ] Diagram in README linking SETUP-GUIDE for OAuth + 9Router users
- [ ] Short 中文 quick-start page (optional) if users prefer

## Diagnostics

- [ ] `cc -9 doctor` — suggest exact `CACHE_FIX_PROXY_UPSTREAM` from resolved `nineRouterUrl`
- [ ] Surface cache_read / cache_creation hints when `CACHE_FIX_DEBUG=1` and quota files exist

## 9Router integration

- [ ] Track upstream 9Router PRs for billing-header strip; auto-disable redundant cache-fix extensions when merged
