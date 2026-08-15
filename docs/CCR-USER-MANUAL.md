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
    - [5.1 首次 onboarding（推荐）](#51-首次-onboarding推荐)
    - [5.1.1 日常配置调整（setup）](#511-日常配置调整setup)

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
| **remote onboard** | 首次一键：密码机 → 免密 SSH + Node/Claude + 配置同步；可选 Tailscale / IDE seed。 |
| **remote setup** | 按步骤菜单选择性配置；默认只做 **sync**，适合日常改 Claude 配置。 |


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
ccr remote onboard [alias] [opts]# 首次 all-in-one onboarding
ccr remote setup [alias] [opts]  # 可选步骤配置菜单（默认 sync）

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

心智模型：`ccr remote *` 在**本机**打包，经 **SSH** 推到远端安装。`onboard` = 首次全流程；`setup` = 事后按步骤微调。

| 场景 | 用哪个 |
|------|--------|
| 新机器只有密码，第一次配 | `ccr remote onboard` |
| 已免密，只想同步 settings / skills | `ccr remote setup --steps sync` 或 `ccr remote sync` |
| 已免密，要重装 Claude / Node | `ccr remote setup --steps node,claude,sync` |

### 5.1 首次 onboarding（推荐）

默认步骤：`ssh` → `node` → `claude` → `sync`。传 `--seed-ide` / `--tailscale-auth-key` 时再追加对应步骤。


非交互式：

```bash
ccr remote onboard nas-2b \
  --ip 10.18.23.131 \
  --user lgsj \
  --password 'Lgsj@123.' \
  --no-confirm

```

纯交互式：

```bash
ccr remote onboard
# 按提示输入 alias / ip / user / password
```

**alias 冲突：** 若 `~/.ssh/config` 里已有同名 `Host`：

- 交互：询问 **[r]eplace** / **re[u]se** / **[a]bort**
- `--no-confirm`：默认 **reuse**（不重灌公钥）。若 config 在、远端公钥却丢了，先删掉该 `Host` 块再 onboard，或交互选 replace

常用选项：

- `--port PORT` — SSH 端口（默认 22；Docker 映射常见 `2222`）
- `--key PATH` — 私钥路径（默认见环境变量）
- `--no-install-node` — 跳过 Node 安装（默认步骤里会去掉 `node`）
- `--seed-ide` — 推送 Cursor/Warp IDE server 缓存
- `--tailscale-auth-key tskey-auth-xxx` — 安装并加入 Tailscale
- `--dry-run` — 只打印步骤，不执行

本机会按远端架构打包（含 **musl**，如 Alpine → `linux-*-musl`）。远端没有 npm 时会测 mirror 速度再装 Node。

### 5.1.1 日常配置调整（setup）

`setup` 默认**只做 sync**。交互会逐步勾选；非交互用 `--steps`。

```bash
# 交互式菜单（默认勾选 sync）
ccr remote setup nas-2b

# 非交互，只同步配置
ccr remote setup nas-2b --steps sync --no-confirm

# 非交互，重做 SSH + Node + Claude + 同步
ccr remote setup nas-2b --steps ssh,node,claude,sync --no-confirm
```

可选步骤：`ssh`、`node`、`claude`、`sync`、`tailscale`、`seed`。

等价捷径：只同步时也可直接 `ccr remote sync nas-2b`。

### 5.2 分步安装

如果已经能免密 SSH：

```bash
# 1. 把 ccr 自身推过去（可选）
ccr remote install nas-2b

# 2. 装 Claude + 同步（不必再走完整 onboard）
ccr remote setup nas-2b --steps node,claude,sync --no-confirm
```


# 3. 在远程配置 Kimi key（登录后执行）
ssh nas-2b
ccr kimi --token sk-kimi-xxx --persist
```

### 5.3 远程配置同步

更新本机模板 / CLAUDE.md / skills 后：

```bash
ccr remote sync nas-2b
# 或
ccr remote setup nas-2b --steps sync --no-confirm

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
| `CC_REMOTE_ONBOARD_DEFAULT_KEY` | onboard / setup 默认 SSH key |
| `CC_REMOTE_ONBOARD_DEFAULT_USER` | onboard / setup 默认用户 |
| `CC_REMOTE_ONBOARD_DEFAULT_PORT` | onboard / setup 默认端口 |

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

**Q: `onboard` 和 `setup` 有啥区别？**

- `onboard`：首次全流程，默认 `ssh,node,claude,sync`
- `setup`：按需选步骤，默认只 `sync`

**Q: `--no-confirm` 时 alias 已存在，为什么没灌公钥？**

非交互默认 **reuse**。若远端 `authorized_keys` 丢了，交互选 **replace**，或删掉 `~/.ssh/config` 里对应 `Host` 块后再跑 onboard。

**Q: Alpine / musl 机器装不上 Claude？**

本机会打 `linux-*-musl` 包。若旧版远端脚本把 musl 误判成 gnu，更新本机 `ccr`（`./install.sh`）后执行：

```bash
ccr remote setup <alias> --steps claude,sync --no-confirm
```

**Q: 远程 Node 版本太旧？**

Claude Code 需要 Node **≥ 22**。部分发行版包管理器仍给 20（会有 `EBADENGINE` 警告，偶发仍能跑）。长期建议在远端装 Node 22+。

**Q: 远程 npm global prefix 不可写（如 NixOS）？**

安装脚本会检测并切到 `~/.local`，把 `~/.local/bin` 加进 PATH 即可。

**Q: Tailscale 在 NixOS 上怎么装？**

```bash
ccr remote onboard nas-2b --tailscale-auth-key xxx
# 或
ccr remote setup nas-2b --steps tailscale --tailscale-auth-key xxx --no-confirm
```

会检测 NixOS 并给出 `configuration.nix` 配置片段。


**Q: 旧命令还能用吗？**

`ccd`、`ccs`、`cck` 仍可用但会打印弃用提示，建议迁移到 `ccr deepseek`、`ccr switch`、`ccr kimi`。
