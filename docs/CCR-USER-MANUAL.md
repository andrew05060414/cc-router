# ccr 用户手册

`ccr`（Code/Claude Router）是一个统一的 Claude Code 启动器，把多个供应商（Anthropic 官方、9Router、DeepSeek、CC Switch、Kimi）和远程服务器 onboarding 整合到一个命令里。

---

## 目录

- [ccr 用户手册](#ccr-用户手册)
  - [目录](#目录)
  - [1. 安装](#1-安装)
  - [2. 核心概念](#2-核心概念)
  - [3. 命令总览](#3-命令总览)
  - [4. 本地模式](#4-本地模式)
    - [4.1 官方 Claude](#41-官方-claude)
    - [4.2 9Router](#42-9router)
    - [4.3 DeepSeek](#43-deepseek)
    - [4.4 CC Switch](#44-cc-switch)
    - [4.5 Kimi](#45-kimi)
  - [5. 远程服务器](#5-远程服务器)
    - [5.1 快速 onboarding（推荐）](#51-快速-onboarding推荐)
    - [5.2 分步安装](#52-分步安装)
    - [5.3 远程配置同步](#53-远程配置同步)
    - [5.4 诊断](#54-诊断)
  - [6. 配置管理](#6-配置管理)
  - [7. 诊断工具](#7-诊断工具)
  - [8. 环境变量](#8-环境变量)
  - [9. 常见问题](#9-常见问题)

---

## 1. 安装

```bash
cd cc-router
./install.sh
```

确保 `~/.local/bin` 在 PATH：

```bash
export PATH="$HOME/.local/bin:$PATH"
```

安装后，本地会有：

- `~/.local/bin/ccr` — 主命令
- `~/.local/bin/ccd`, `ccs`, `cck` — 兼容别名（会提示弃用）
- `~/.local/share/cc-router/` — 脚本、模板、文档、配置

---

## 2. 核心概念

| 概念 | 说明 |
|------|------|
| **模式（mode）** | 同一 `claude` 命令，通过环境变量指向不同后端。 |
| **vendor 模板** | `templates/remote/{kimi,deepseek,anthropic,default}.json` 定义远程机器的 env/model。 |
| **持久化（--persist）** | 把某个 vendor 的 env 块写进 shell profile，以后直接 `claude` 即生效。 |
| **bootstrap** | Kimi 模式下自动跳过登录、清理 stale model key。 |
| **remote setup** | 把一台新机器从「只有密码」变成「可免密 SSH + 可 Claude + 可 Cursor/Warp + 可 Tailscale」。 |

---

## 3. 命令总览

```text
ccr                              # 官方 Claude
ccr claude                       # 同上
ccr 9router                      # 9Router / cache-fix
ccr deepseek                     # DeepSeek
ccr switch                       # CC Switch 代理
ccr kimi                         # Kimi for Coding

ccr remote install <host>        # 把 ccr 安装到远程
ccr remote setup [alias] [opts]  # 交互式 all-in-one onboarding
ccr remote sync <host>           # 同步配置到远程
ccr remote ssh <host>            # SSH 进远程并启动 claude
ccr remote doctor <host>         # 检查远程环境

ccr setup                        # 首次环境设置
ccr config setup                 # 创建本地配置
ccr doctor                       # 诊断
ccr --help                       # 帮助
```

---

## 4. 本地模式

### 4.1 官方 Claude

```bash
ccr
# 或
ccr claude
```

直接调用系统 `claude`，不注入任何路由环境。

### 4.2 9Router

```bash
ccr 9router
```

通过 9Router 中转，支持 cache-fix。

### 4.3 DeepSeek

需要 `DEEPSEEK_API_KEY`。

```bash
# 临时一次
DEEPSEEK_API_KEY=sk-xxx ccr deepseek

# 永久写入 shell profile
export DEEPSEEK_API_KEY=sk-xxx
ccr deepseek --persist
```

`--persist` 会在 `~/.bashrc` 或 `~/.zshrc` 里写一个 managed block，以后直接 `claude` 就是 DeepSeek。

选项：

- `--model <id>` — 默认 `deepseek-v4-pro[1m]`
- `--haiku-model <id>` — 默认 `deepseek-v4-flash`
- `--max-output <n>` — 默认 65536

### 4.4 CC Switch

```bash
ccr switch
```

自动探测本地 CC Switch proxy（默认 `http://127.0.0.1:15721`）。

如果 proxy 不在默认端口：

```bash
CC_CCS_PROXY_URL=http://127.0.0.1:8080 ccr switch
```

### 4.5 Kimi

Token 来源优先级：

1. `~/.claude/settings.json` 里的 `env.ANTHROPIC_AUTH_TOKEN`
2. 环境变量 `ANTHROPIC_AUTH_TOKEN` 或 `ANTHROPIC_API_KEY`

```bash
# 临时一次
ANTHROPIC_AUTH_TOKEN=sk-kimi-xxx ccr kimi

# 永久写入 profile（推荐）
ccr kimi --persist
```

首次运行会自动执行 bootstrap：跳过登录、清理 stale model key。加 `--no-bootstrap` 可跳过。

模型映射（Allegretto 及以上）：

| 档位 | 模型 |
|------|------|
| Opus / Fable | `k3[1m]` |
| Sonnet | `kimi-for-coding-highspeed` |
| Haiku / Subagent | `kimi-for-coding` |

---

## 5. 远程服务器

### 5.1 快速 onboarding（推荐）

一条命令完成：上传 SSH 公钥、写 `~/.ssh/config`、安装 Claude Code、同步配置、可选安装 Tailscale / 推送 Cursor/Warp IDE 缓存。

非交互式：

```bash
ccr remote setup nas-2b --ip 10.18.23.131 --user lgsj --password 'Lgsj@123.' --no-confirm
```

纯交互式：

```bash
ccr remote setup
# 按提示输入 alias / ip / user / password，并选择是否执行可选步骤
```

常用选项：

- `--seed-ide` — 自动推送 Cursor/Warp IDE server 缓存
- `--tailscale-auth-key tskey-auth-xxx` — 自动安装并加入 Tailscale
- `--install-node` — 远程没有 npm 时自动安装 Node.js（会测试并选用最快的 npm mirror）
- `--no-install-node` — 远程没有 npm 时跳过安装
- `--dry-run` — 只打印步骤，不执行

### 5.2 分步安装

如果已经能免密 SSH，可以直接装 Claude Code：

```bash
# 1. 把 ccr 自身推过去
ccr remote install nas-2b

# 2. 在远程装 Claude Code（ interactive setup 的精简版）
ccr remote setup nas-2b

# 3. 在远程配置 Kimi key（登录后执行）
ssh nas-2b
ccr kimi --token sk-kimi-xxx --persist
```

### 5.3 远程配置同步

更新本机模板/CLAUDE.md/skills 后，同步到远程：

```bash
ccr remote sync nas-2b
```

### 5.4 诊断

```bash
ccr remote doctor nas-2b
```

检查远程的 OS、Node、npm、Claude、settings、skills。

---

## 6. 配置管理

```bash
ccr config setup        # 创建 ~/.config/cc-router/config.json
ccr config show         # 显示当前配置
ccr config set key val  # 设置键值
```

常用配置项：

- `ccsProxyUrl` — CC Switch proxy 地址
- `allowDangerouslySkipPermissions` — 默认 `true`

---

## 7. 诊断工具

```bash
ccr doctor              # 通用诊断
ccr doctor 9router      # 9Router 专用诊断
ccr deepseek doctor     # DeepSeek 专用诊断
ccr switch doctor       # CC Switch 专用诊断
ccr remote doctor <host># 远程诊断
```

---

## 8. 环境变量

| 变量 | 说明 |
|------|------|
| `CC_ROUTER_REPO_DIR` | ccr 仓库根目录（自动解析） |
| `CC_REMOTE_PACK_DIR` | 远程安装包缓存目录 |
| `CC_REMOTE_VENDOR` | 默认远程 vendor（kimi/deepseek/anthropic/default） |
| `CC_REMOTE_AUTH_TOKEN` | 远程 settings.json 使用的 token |
| `CC_REMOTE_SETTINGS_MODE` | `local` / `remote` / `default` |
| `CC_REMOTE_ONBOARD_DEFAULT_KEY` | remote setup 默认 SSH key |
| `CC_REMOTE_ONBOARD_DEFAULT_USER` | remote setup 默认用户 |
| `CC_REMOTE_ONBOARD_DEFAULT_PORT` | remote setup 默认端口 |
| `DEEPSEEK_API_KEY` | DeepSeek API key |
| `ANTHROPIC_AUTH_TOKEN` | Kimi / 通用 token |
| `ANTHROPIC_API_KEY` | 同上 |

---

## 9. 常见问题

**Q: `ccr remote install` 报 tar 错误？**

用 `-v` 看详细输出，用 `-n` 做 dry-run：

```bash
ccr remote install nas-2b -v
ccr remote install nas-2b -n
```

**Q: 远程 npm global prefix 不可写（如 NixOS）？**

`ccr remote setup` 会自动检测并切换到 `~/.local`，把 `~/.local/bin` 加进 PATH 即可。

**Q: Tailscale 在 NixOS 上怎么装？**

`ccr remote setup nas-2b --tailscale-auth-key xxx` 会检测 NixOS 并给出 `configuration.nix` 配置片段。

**Q: 旧命令还能用吗？**

`ccd`、`ccs`、`cck` 仍可用但会打印弃用提示，建议迁移到 `ccr deepseek`、`ccr switch`、`ccr kimi`。
