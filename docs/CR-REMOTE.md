# ccr remote - 远程服务器 Claude Code 一键 onboarding

`ccr-remote` 让你在本机打包 Claude Code 安装包、配置和技能，然后通过 SSH 一键部署到远程 Linux/Windows 服务器。核心理念：**尽量通过 scp 从本机传，避免在远程从外网下载**。

## 为什么需要这个

- 公司/远程服务器网络慢，npm install 经常超时
- 每次新服务器都要重复配置 `settings.json`、CLAUDE.md、关闭遥测
- 希望 `ssh` 上去后直接 `claude` 开始干活

## 安装

### macOS / Linux

```bash
cd /path/to/cc-router
./install.sh
export PATH="$HOME/.local/bin:$PATH"
```

### Windows (PowerShell)

```powershell
cd C:\path\to\cc-router
.\install.ps1 -AddToProfile
```

然后重新打开 PowerShell，或使用：

```powershell
. $PROFILE
```

Windows 上的命令是 `ccr-remote`（通过 `ccr-remote.ps1`），用法和 Linux/macOS 基本一致。

> Windows 上命令相同，使用 `ccr-remote`（通过 `ccr-remote.ps1`）。路径用 Windows 格式，如 `C:\RemoteProject`。

## 快速开始

### 1. 本机打包

```bash
ccr remote pack
```

这会：
- 用 `npm pack` 下载 Claude Code 主包 + Linux 平台 native 二进制
- 生成远程版 `settings.json`（kimi coding plan + 关闭遥测）
- 复制本机 `~/.claude/CLAUDE.md`
- 打包默认内置技能（llm-env、llm-inference-benchmark、batch-ssh-onboard）

支持的平台：`linux-x64`、`linux-arm64`、`linux-x64-musl`、`linux-arm64-musl`、`win32-x64`、`win32-arm64`、`darwin-arm64`、`darwin-x64`。

```bash
# 只下 Linux x64
ccr remote pack --platforms linux-x64

# Linux + Windows
ccr remote pack --platforms linux-x64,linux-arm64,win32-x64

# 使用已下载好的包，不再重新 npm pack
ccr remote pack --skip-download
```

打包目录：`~/.local/share/cc-router/remote-pack/`

### 2. 添加 SSH 主机

`ccr remote setup` 会自动把 pubkey 上传到只有密码的新机器，并写入 `~/.ssh/config`。如果你已经配好了免密 SSH，可以直接用 alias。

```bash
# 新机器：交互式 onboarding
ccr remote setup lgsj-h100
# 按提示输入 IP / user / password

# 或者一次性传参
ccr remote setup lgsj-h100 --ip 192.168.1.100 --user lgsj --password 'xxx' --no-confirm

# 已有免密 SSH 时
ccr remote setup user@192.168.1.100
```

### 3. 部署到远程

```bash
ccr remote setup lgsj-h100
```

流程：
1. 如果还没有免密 SSH，用密码上传 pubkey 并写入 `~/.ssh/config`
2. 探测远程 OS / 架构
3. 如果远程没有 npm，提示并自动安装 Node.js（会测试并选用最快的 npm mirror）
4. scp 传安装包到 `/tmp/cc-router-remote-pack/`
5. 远程执行安装脚本
6. 写入 `~/.claude/settings.json`、`~/.claude/CLAUDE.md`、技能包
7. 在 `~/.profile` 追加 telemetry 关闭环境变量
8. 可选：安装 Tailscale、推送 Cursor/Warp IDE server 缓存
9. 运行 `ccr remote doctor` 检查环境

### 4. 连接并启动 Claude Code

```bash
# 直接启动
ccr remote ssh lgsj-h100

# 进入项目目录后启动
ccr remote ssh lgsj-h100 /home/lgsj/my-project

# 带参数
ccr remote ssh lgsj-h100 /home/lgsj/my-project --model sonnet
```

### 5. 只同步配置

如果你只改了 settings 或技能，不想重装：

```bash
ccr remote sync lgsj-h100
```

## settings.json 模式

通过 `CC_REMOTE_SETTINGS_MODE` 选择远程 settings 来源：

```bash
# 默认：kimi coding plan + 关闭遥测
CC_REMOTE_SETTINGS_MODE=remote ccr remote pack

# 从本地 settings.json 提取关键字段（需要 jq）
CC_REMOTE_SETTINGS_MODE=local ccr remote pack

# 最精简默认模板
CC_REMOTE_SETTINGS_MODE=default ccr remote pack
```

也可以单独预览生成的 settings：

```bash
ccr remote config show
```

## 技能包管理

默认会自动打包 cc-router 内置技能：

- `llm-env`：离线构建 AI 推理环境（vLLM/SGLang/Ollama/llama.cpp）
- `llm-inference-benchmark`：大模型推理基准测试
- `batch-ssh-onboard`：批量 SSH 服务器 onboarding

如需调整同步的技能：

```bash
ccr remote skills
```

会列出：
- 本机 `~/.claude/skills/` 下的技能
- cc-router 自带技能
- 项目目录下 `.claude/skills/` 的技能

输入编号空格分隔，空输入表示使用默认内置技能。

## 命令参考

| 命令 | 说明 |
|------|------|
| `ccr-remote pack` | 本机预下载和打包 |
| `ccr-remote setup [alias]` | 交互式 all-in-one onboarding |
| `ccr-remote sync <host>` | 只同步配置和技能 |
| `ccr-remote ssh <host> [dir] [args]` | SSH 并启动 Claude Code |

Windows 命令相同，路径用 `C:\project` 格式。
| `ccr-remote config show` | 预览远程版 settings |
| `ccr-remote skills` | 选择技能包 |
| `ccr-remote ssh-config add <alias> <host> [user] [port] [key]` | 添加 SSH 别名 |
| `ccr-remote ssh-config list` | 列出 SSH 配置 |
| `ccr-remote doctor <host>` | 检查远程环境 |

## 环境变量

| 变量 | 说明 |
|------|------|
| `CC_REMOTE_SETTINGS_MODE=local\|remote\|default` | settings.json 来源 |
| `CC_REMOTE_PACK_DIR` | 本地打包目录，默认 `~/.local/share/cc-router/remote-pack` |
| `CC_REMOTE_SYNC_SKILLS=0\|1` | 是否同步技能包 |

## 安全提醒

远程版 `settings.json` 默认会携带本机的 `ANTHROPIC_AUTH_TOKEN`（读取自 `~/.claude/settings.json`，或可通过 `CC_REMOTE_AUTH_TOKEN` 环境变量指定）。这个 token 会随安装包一起 scp 到远程服务器。如果远程服务器是多人共用或不够安全，建议：

1. 使用 `CC_REMOTE_SETTINGS_MODE=default`，然后在远程手动设置 token
2. 或设置 `CC_REMOTE_AUTH_TOKEN=your-token` 后打包
3. 或在远程 `.profile` 中写入：
   ```bash
   export ANTHROPIC_AUTH_TOKEN=your-token
   ```

如果本地 `~/.claude/settings.json` 没有 `ANTHROPIC_AUTH_TOKEN`，`remote` 模式会生成不含 token 的配置，需要你手动在远程配置。

## 已知限制

- 远程最好已安装 Node.js + npm；没有时 `ccr remote setup` 会提示安装
- Windows 远程需要 PowerShell + OpenSSH 服务端，目前主要优化 Linux 场景
- 技能包中的符号链接会被复制为实际文件（`-L`）
- macOS 默认 bash 为 3.2，脚本已做兼容
