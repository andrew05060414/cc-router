---
name: batch-ssh-onboard
description: >-
  Onboard lab machines via direct SSH (password→pubkey, local Cursor/Warp cache
  push, Tailscale, cleanup) OR JumpServer/JMS bastion (token vs asset-format,
  password-only). Use when user has IP+password, JMS tables, or needs handoff cleanup.
---

# Batch SSH Onboard

人类文档：[RUNBOOK.md](./RUNBOOK.md)  
脚本入口：`scripts/lab.sh`（**仅直连**；JumpServer 用 RUNBOOK §5）

## 先判断路径

| 用户给的凭证 | 走哪条 |
|--------------|--------|
| `IP` + root/密码，端口 22 | **直连** → `lab.sh onboard`（§1–§4） |
| `172.16.120.155:2222` + `JMS-<uuid>` 或 `xxx#user#uuid` | **JumpServer** → RUNBOOK **§5**，**不要**跑 `lab.sh onboard` |

## Agent：直连

```bash
SKILL=.agents/skills/batch-ssh-onboard

$SKILL/scripts/lab.sh onboard \
  --alias <ALIAS> --ip <IP> --password '<PASS>' --seed-ide

# IDE：先 donor 拉本地，再推目标（默认不走慢速 CDN）
$SKILL/scripts/lab.sh seed --pull --from H100-1
$SKILL/scripts/lab.sh seed --alias <ALIAS> --all-cached
# 精确当前 commit，且本机/donor 已有：
$SKILL/scripts/lab.sh seed --alias <ALIAS>
# 实在没有才：
$SKILL/scripts/lab.sh seed --alias <ALIAS> --cdn

$SKILL/scripts/lab.sh tailscale --alias <ALIAS> --auth-key '<TS_KEY>'
$SKILL/scripts/lab.sh cleanup --alias <ALIAS> --ip <IP>
```

前置：`brew install sshpass`；密钥默认 `~/.ssh/id_longgang`。

## IDE 缓存约定

| 项 | 值 |
|----|-----|
| 本机目录 | `~/.cache/lab-ide/` |
| Cursor 来源 | `product.json` 的 commit → `cursor.blob.core.windows.net/.../vscode-reh-linux-x64.tar.gz` |
| Warp 来源 | `~/Library/Application Support/dev.warp.Warp-Stable/remote-server/tarballs/` |
| 远程路径 | `~/.cursor-server/bin/linux-x64/<commit>/`、`~/.warp/remote-server/` |

**不要**再用 `--from H100-1` / 种子机 rsync（已废弃）。

## Agent：JumpServer

见 RUNBOOK §5。用户名含 `#` 必须加引号；优先资产格式 + JMS 登录密码。

## 失败时

- 直连：RUNBOOK §7  
- Cursor 下载 403：确认用的是 `cursor.blob.core.windows.net`（脚本已用）；勿用 `downloads.cursor.com`  
- JMS：Token 过期 → 资产格式  
