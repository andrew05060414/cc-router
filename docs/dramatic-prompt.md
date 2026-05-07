# Dramatic Prompt: claudeCodeForDeepseek 一键引导

> 把 `===== BEGIN =====` 到 `===== END =====` 之间的整段内容复制粘贴给任意一个能执行 shell 的 AI Coding Agent
> （Claude Code / Codex / Cursor Agent / Aider 等），让它替你完成 `ccd` 的检测、安装、配置与首次运行。

---

## 这个模板是干什么的

`claudeCodeForDeepseek` 自带的 `install.sh` / `install.ps1` 已经够轻量了，但是新用户依然会卡在：

- 不知道当前系统该走哪条路径
- Node / `@anthropic-ai/claude-code` 没装好
- `DEEPSEEK_API_KEY` 没设、或者只在一个 shell 里设了
- `~/.local/bin` 不在 `PATH` 里
- 老的 `ANTHROPIC_*` 环境变量留在 shell 里污染路由

这个 "dramatic prompt" 的目标是：**把上面所有踩坑步骤打包成一份能直接喂给 AI 的剧本**，让 AI 在你的真实终端里按顺序探测、确认、执行，最后给你一个 `ccd doctor` 通过的环境。

---

## 使用步骤

1. 准备 DeepSeek API Key：<https://platform.deepseek.com/>
2. 打开任意一个能执行 shell 的 AI Agent
3. 复制下面整段 prompt 粘贴进去
4. （可选）把 `<在此填入仓库地址>` 等占位符替换成你自己的值
5. 按 AI 的提示一步步确认 / 粘贴结果即可

终端里直接拿到这段 prompt：

```bash
ccd prompt --print-prompt | less          # 浏览
ccd prompt --print-prompt | xclip -selection clipboard   # Linux 复制到剪贴板
ccd prompt --print-prompt | pbcopy                       # macOS 复制到剪贴板
ccd prompt --print-prompt | clip.exe                     # Windows / WSL 复制到剪贴板
```

---

===== BEGIN =====

# 角色

你是一名熟悉跨平台终端（Windows PowerShell / Linux bash / WSL / macOS zsh+bash）的资深运维工程师。
本次任务：把 `claudeCodeForDeepseek` 的 `ccd` 命令在我当前这台机器上跑通。

# 项目背景（PROJECT_CONTEXT）

`claudeCodeForDeepseek` 提供两个轻量启动器，避免官方 Claude 与 DeepSeek 路由共用一个 shell 时互相污染：

- `cc`：官方 Claude 模式（启动前清理 DeepSeek 相关环境变量）
- `ccd`：DeepSeek 路由模式（注入 Anthropic 兼容的 DeepSeek 环境变量后启动 `claude`）

仓库地址：<在此填入仓库地址，例如 https://github.com/your-name/claudeCodeForDeepseek>
我的本地仓库路径（如果已 clone）：<在此填入本地路径或写 "尚未 clone">

# 我的目标（GOALS）

1. 确认依赖：Node.js + `@anthropic-ai/claude-code` 是否就绪；缺什么就给我**精确**的安装命令。
2. 根据我的操作系统选择正确入口（`install.sh` 或 `install.ps1`）并完成安装。
3. 把 `DEEPSEEK_API_KEY` 注入当前 shell；如果我点头，再写入对应的 profile / rc 文件做持久化。
4. 跑一次 `ccd doctor`，确认 OK。
5. 给我最少够用的"以后怎么用"示例：`ccd`、`ccd resume`、`ccd --model`、`ccd prompt`。

# 约束（CONSTRAINTS）

- **先探测，再建议**：不要假设我装过任何全局工具。
- **不引入新依赖**：能用我系统已有的工具就用，不要装额外的包管理器或第三方 CLI。
- **可见再写入**：任何改 profile / rc / PATH 的操作，先把要写入的内容贴出来给我确认。
- **dry-run 优先**：覆盖文件、改 PATH、`sudo` 这一类操作必须 dry-run 先行。
- **不要回显密钥**：API Key 一旦出现在命令里，输出/日志必须做掩码（如 `sk-***xxxx`）。
- **失败要可排查**：每个失败给 3 条最可能的原因 + 各自的排查命令，不要只丢一句 "请重试"。

# 必须先采集的环境信息（ENV_CHECKLIST）

按下面顺序用最少命令收集结果，并以表格形式回显给我后再继续：

| 项 | Linux / WSL / macOS | Windows PowerShell |
| --- | --- | --- |
| OS | `uname -a` | `(Get-CimInstance Win32_OperatingSystem).Caption` |
| Shell | `echo $SHELL` | `$PSVersionTable.PSEdition`, `$PSVersionTable.PSVersion` |
| 用户 / HOME | `whoami; echo $HOME` | `whoami; $env:USERPROFILE` |
| Node | `node -v` | `node -v` |
| npm | `npm -v` | `npm -v` |
| claude CLI | `command -v claude` | `Get-Command claude -ErrorAction SilentlyContinue` |
| 残留 ANTHROPIC_* | `env \| grep -E '^ANTHROPIC_\|^CLAUDE_'` | `Get-ChildItem Env: \| Where-Object Name -match '^ANTHROPIC_\|^CLAUDE_'` |
| PATH 里有没有安装目录 | `echo $PATH \| tr ':' '\n' \| grep -E '\.local/bin'` | `$env:PATH -split ';' \| Select-String 'ccdeepseek\\bin'` |
| DEEPSEEK_API_KEY 是否已设 | `[ -n "$DEEPSEEK_API_KEY" ] && echo SET \|\| echo MISSING` | `if ($env:DEEPSEEK_API_KEY) { 'SET' } else { 'MISSING' }` |

# 操作步骤模板（STEPS，按需执行，每一步先解释"为什么"再给命令）

## Step 1 - 准备 Claude Code CLI

如果上面表里 `claude CLI` 缺失：

```bash
npm install -g @anthropic-ai/claude-code
```

如果连 Node 都没装：先按当前操作系统给我**官方推荐**的 Node 安装方式（建议 LTS），不要让我手动下 tarball。

## Step 2 - 安装 `cc` / `ccd` 启动器

Linux / WSL / macOS：

```bash
cd <repo-path>
chmod +x install.sh
./install.sh
# 如果 ~/.local/bin 不在 PATH 里，再追加：
export PATH="$HOME/.local/bin:$PATH"
```

Windows PowerShell：

```powershell
cd <repo-path>
.\install.ps1 -AddToProfile
. $PROFILE
```

## Step 3 - 设置 DEEPSEEK_API_KEY

会话内（必须先做）：

```bash
export DEEPSEEK_API_KEY="<paste-key-here>"
```

```powershell
$env:DEEPSEEK_API_KEY = "<paste-key-here>"
```

持久化（**先问我要不要做，再执行**）：

- bash → 追加到 `~/.bashrc` 或 `~/.profile`
- zsh → 追加到 `~/.zshrc`
- PowerShell → 追加到 `$PROFILE`

写之前先把那一行 `export ...` / `$env:... = ...` 完整贴出来让我点头。

## Step 4 - 自检

```bash
ccd doctor
```

期望输出包含两行 `OK:`。任何 `Missing:` 都要立刻给我对应的修复指令。

## Step 5 - 试跑

```bash
ccd --help
ccd prompt          # 看模板路径
ccd                 # 真正启动一次
```

# 输出格式要求（OUTPUT_FORMAT）

- 每一步先用一句话告诉我"**为什么要做**"。
- 命令必须放在独立代码块里，方便我直接复制。
- 步骤之间用 `---` 分隔。
- 失败时按"3 条可能原因 + 3 条排查命令"的格式给我，不要只丢一句报错。
- 全程使用简体中文回复。

# 现在开始

请先执行 **ENV_CHECKLIST**，把表格结果贴给我。我确认之后，你再继续 Step 1。

===== END =====

---

## 占位符速查

| 占位符 | 含义 |
| --- | --- |
| `<在此填入仓库地址>` | GitHub / GitLab 仓库 URL |
| `<repo-path>` | 你本地 clone 出来的仓库路径 |
| `<paste-key-here>` | DeepSeek 平台申请的 API Key |

## 可改进方向

- 拆分为 "minimal / full" 两个版本，给老手更短的引导
- 接入 `--lang en` 输出英文版本
- 让 `ccd prompt` 支持把模板直接打到剪贴板（依赖系统 `xclip` / `pbcopy` / `clip.exe`，按平台条件启用）
