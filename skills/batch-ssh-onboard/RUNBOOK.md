# 测试机接入 / 交付 Runbook

> 路径：`.agents/skills/batch-ssh-onboard/RUNBOOK.md`  
> **脚本入口**：`scripts/lab.sh`（推荐）｜下文保留纯命令版，方便看懂每一步。

---

## 脚本速用（推荐）

```bash
cd /Users/andrewwang/Code/lgsj/.agents/skills/batch-ssh-onboard

# 一次性
brew install sshpass

# §1+§2 接入 + 拷 IDE 缓存
./scripts/lab.sh onboard \
  --alias H100-3 \
  --ip 221.182.146.99 \
  --user 'username'\
  --password '你的密码' \
  --seed-ide

# §3 Tailscale（可选）
./scripts/lab.sh tailscale \
  --alias H100-3 \
  --auth-key 'tskey-auth-xxxx'

# 离线 Tailscale
./scripts/lab.sh tailscale --alias H100-3 --auth-key 'tskey-...' \
  --deb /tmp/tailscale.deb

# 已接入，只补 IDE：先从有货的机器拉到本机，再推目标
./scripts/lab.sh seed --pull --from H100-1
./scripts/lab.sh seed --alias AMD370-Dual-Channel --all-cached

# 当前 Cursor 版本已在本机缓存时（精确匹配 commit）
./scripts/lab.sh seed --alias AMD370-Dual-Channel

# 仅当 donor/本机都没有、且能接受慢速公网时
./scripts/lab.sh seed --alias AMD370-Dual-Channel --cdn

# §4 交付清理
./scripts/lab.sh cleanup --alias H100-3 --ip 221.182.146.99

# 帮助
./scripts/lab.sh help
./scripts/lab.sh onboard --help
./scripts/lab.sh seed --help
```

| 子命令 | 对应章节 | 做什么 |
|--------|----------|--------|
| `onboard` | §1 | 密码 → 公钥，写 `~/.ssh/config` |
| `seed` | §2 | **donor → 本机缓存 → 目标**（CDN 需 `--cdn`） |
| `tailscale` | §3 | 在线或 `--deb` 离线装 Tailscale |
| `cleanup` | §4 | 退 tailnet、删公钥、清 IDE、删本机 config |

JumpServer（堡垒机）**不用** `lab.sh`，见下方 **§5**。

---



## 变量（先填好）

```bash
# ── 每次改这里 ──
ALIAS=H100-3              # ~/.ssh/config 里的 Host 名
IP=221.182.146.99         # 目标 IP
USER=root                 # 一般是 root
PORT=22
PASS='你的密码'            # 仅第一次用，之后不再需要

KEY=~/.ssh/id_longgang     # lab 默认密钥

# Tailscale（可选）
TS_KEY='tskey-auth-xxxx'  # https://login.tailscale.com/admin/settings/keys
TS_HOSTNAME=$ALIAS
```

**心理模型**：密码只用一次把公钥写进去 → 以后 `ssh $ALIAS` 免密 → 本机缓存 Cursor/Warp 再推上去 → 可选 Tailscale → 交付时反向清理。

---



## 0. 一次性准备（本机 Mac）

```bash
brew install sshpass          # 免交互输密码；不用也行，改用 ssh-copy-id 手输密码
ls -la ~/.ssh/id_longgang ~/.ssh/id_longgang.pub
```

---



## 1. 密码登录一次 → 以后公钥登录



### 方法 A：手输密码（最简单）

```bash
ssh-copy-id -i ~/.ssh/id_longgang.pub -p $PORT ${USER}@${IP}
```



### 方法 B：命令行带密码（批量时省事）

```bash
# 上传公钥
sshpass -p "$PASS" ssh -p $PORT -o StrictHostKeyChecking=accept-new ${USER}@${IP} \
  'mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys'

sshpass -p "$PASS" scp -P $PORT ~/.ssh/id_longgang.pub ${USER}@${IP}:/tmp/mykey.pub

sshpass -p "$PASS" ssh -p $PORT ${USER}@${IP} \
  'grep -qxF -f /tmp/mykey.pub ~/.ssh/authorized_keys || cat /tmp/mykey.pub >> ~/.ssh/authorized_keys; rm -f /tmp/mykey.pub'
```



### 写入 ~/.ssh/config

```bash
cat >> ~/.ssh/config <<EOF

# lab: $ALIAS
Host $ALIAS
  HostName $IP
  User $USER
  Port $PORT
  IdentityFile ~/.ssh/id_longgang
  IdentitiesOnly yes
  AddKeysToAgent yes
  UseKeychain yes
  ServerAliveInterval 20
  ServerAliveCountMax 6
EOF
```



### 验证（不应再要密码）

```bash
ssh $ALIAS 'echo OK && hostname && whoami'
```

---



## 2. 同步 Cursor / Warp server（本机缓存 → 远程）

> **不再用种子机。** 本机按当前 Cursor commit 下载一次，缓存在 `~/.cache/lab-ide/`；  
> Cursor 升级换 commit 后，再 `seed --refresh` 或下次 seed 时自动下新包。

### 推荐：脚本

```bash
# 推到已 onboard 的机器（缺缓存则先下载 ~120MB）
./scripts/lab.sh seed --alias $ALIAS

# 只更新本机缓存（Cursor 刚升级时）
./scripts/lab.sh seed --refresh

# 强制重下再推
./scripts/lab.sh seed --alias $ALIAS --force
```

缓存布局：

```
~/.cache/lab-ide/
  cursor/<commit>/vscode-reh-linux-x64.tar.gz
  cursor/<commit>/extracted/          # 解压后的 server
  warp/<warp-version>/                # 从本机 Warp Application Support 解出
```

下载 URL（本机可访问；远程 lab 常 403）：

```
https://cursor.blob.core.windows.net/remote-releases/<commit>/vscode-reh-linux-x64.tar.gz
```

### 2a. 手写等价流程（Cursor）

```bash
COMMIT=$(python3 -c "import json; print(json.load(open('/Applications/Cursor.app/Contents/Resources/app/product.json'))['commit'])")
CACHE=~/.cache/lab-ide/cursor/$COMMIT
mkdir -p "$CACHE/extracted"
curl -fL -o "$CACHE/vscode-reh-linux-x64.tar.gz" \
  "https://cursor.blob.core.windows.net/remote-releases/${COMMIT}/vscode-reh-linux-x64.tar.gz"
tar -xzf "$CACHE/vscode-reh-linux-x64.tar.gz" -C "$CACHE/extracted"
# 若只有一层顶目录，自行摊平后再 rsync

ssh $ALIAS "mkdir -p ~/.cursor-server/bin/linux-x64/${COMMIT}"
rsync -avz --progress "$CACHE/extracted/" "${ALIAS}:~/.cursor-server/bin/linux-x64/${COMMIT}/"
```

### 2b. Warp（脚本会做；手写可选）

本机 tarball 一般在：

```
~/Library/Application Support/dev.warp.Warp-Stable/remote-server/tarballs/v*/linux-x86_64/oz.tar.gz
```

解压推到 `${ALIAS}:~/.warp/remote-server/` 即可。

### 2c. 验证

```bash
COMMIT=$(python3 -c "import json; print(json.load(open('/Applications/Cursor.app/Contents/Resources/app/product.json'))['commit'])")
ssh $ALIAS "ls -la ~/.cursor-server/bin/linux-x64/$COMMIT/ | head"
```

**Cursor 设置（可选）**：`remote.SSH.localServerDownload` → `"always"`（本机已推过则通常用不上）

---



## 3. 安装 Tailscale



### 3a. 在线安装（机器能访问 tailscale.com）

```bash
# 在 Admin 生成 key: https://login.tailscale.com/admin/settings/keys

ssh $ALIAS 'curl -fsSL https://tailscale.com/install.sh | sh'

ssh $ALIAS "tailscale up --auth-key=${TS_KEY} --hostname=${TS_HOSTNAME} --accept-routes --ssh"

ssh $ALIAS 'tailscale status'
```



### 3b. 离线安装（机器不能上网）

在本机 Mac 下载 deb（Ubuntu 22.04 amd64 示例）：

```bash
# 去 https://pkgs.tailscale.com/stable/ 找最新 amd64.deb，或：
curl -L -o /tmp/tailscale.deb \
  'https://pkgs.tailscale.com/stable/ubuntu/jammy/amd64/latest.deb'

scp /tmp/tailscale.deb ${ALIAS}:/tmp/
ssh $ALIAS 'dpkg -i /tmp/tailscale.deb || apt-get -f install -y'
ssh $ALIAS "tailscale up --auth-key=${TS_KEY} --hostname=${TS_HOSTNAME} --accept-routes --ssh"
ssh $ALIAS 'tailscale status'
```

装完后 Tailscale 网内可 `ssh ${TS_HOSTNAME}`（需本机也登录同一 tailnet）。

---



## 4. 交付清理（把机器还给别人之前）

> 在**远程机器**清你的痕迹，在**本机 Mac** 删 config。  
> **Tailscale 一定要退网 + 删节点**，否则机器还在你的 tailnet 里。



### 4a. 远程：退 Tailscale（最重要）

```bash
ssh $ALIAS 'tailscale logout'                    # 从 tailnet 摘掉
ssh $ALIAS 'tailscale uninstall'                  # 卸载客户端（如有此命令）

# 若 uninstall 不可用，手动卸：
ssh $ALIAS 'systemctl stop tailscaled; systemctl disable tailscaled'
ssh $ALIAS 'apt-get purge -y tailscale tailscale-archive-keyring 2>/dev/null; rm -rf /var/lib/tailscale /var/log/tailscale*'
```

然后去 [Tailscale Admin → Machines](https://login.tailscale.com/admin/machines) 确认节点已消失；没有就手动 **Delete**。

### 4b. 远程：删你的 SSH 公钥

```bash
# 查看
ssh $ALIAS 'cat ~/.ssh/authorized_keys'

# 删掉含 longgang 的那行（先确认再执行）
ssh $ALIAS "grep -v 'longgang' ~/.ssh/authorized_keys > /tmp/ak && mv /tmp/ak ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```



### 4c. 远程：删 Cursor / Warp 缓存

```bash
ssh $ALIAS 'rm -rf ~/.cursor-server ~/.warp ~/.config/warp-terminal'
```



### 4d. 本机 Mac：删 config 条目 + known_hosts

```bash
# 删 Host 块（手动编辑也行）
sed -i '' "/# lab: ${ALIAS}/,/^$/d" ~/.ssh/config
# 或：code ~/.ssh/config  删掉 Host $ALIAS 那段

ssh-keygen -R ${IP}
ssh-keygen -R ${ALIAS} 2>/dev/null || true
```



### 4e. 一键清理（远程合并版，执行前看清）

```bash
ssh $ALIAS bash -s <<'REMOTE'
set -e
# Tailscale
tailscale logout 2>/dev/null || true
systemctl stop tailscaled 2>/dev/null || true
systemctl disable tailscaled 2>/dev/null || true
apt-get purge -y tailscale tailscale-archive-keyring 2>/dev/null || true
rm -rf /var/lib/tailscale

# SSH key（按注释删 longgang；有其他 key 请手动改）
if [[ -f ~/.ssh/authorized_keys ]]; then
  grep -v 'longgang' ~/.ssh/authorized_keys > /tmp/ak || true
  mv /tmp/ak ~/.ssh/authorized_keys
  chmod 600 ~/.ssh/authorized_keys
fi

# IDE 缓存
rm -rf ~/.cursor-server ~/.warp ~/.config/warp-terminal

echo "REMOTE CLEANUP DONE"
REMOTE
```

然后本机执行 **4d**，并在 Tailscale Admin 确认节点已删。

---



## 5. JumpServer（堡垒机）接入

> 龙岗部分机器**不能直连**，只能经 JumpServer（JMS）。  
> 这和 §1–§4 的直连 onboard **不是同一条路**：通常**不能灌公钥、不能 rsync seed、不能装 Tailscale**。



### 5a. 两种登录方式


| 方式           | 用户名形态             | 密码                | 稳定性           |
| ------------ | ----------------- | ----------------- | ------------- |
| **Token**    | `JMS-<uuid>`      | 控制台给的 Token 密码    | 短时（几分钟～几小时）过期 |
| **资产格式（推荐）** | `登录名#系统账号#资产UUID` | **你的 JMS 系统登录密码** | 长期可用          |


示例（w7900-242-测试，内网 `10.18.23.242`）：

```bash
# 变量
JMS_HOST=172.16.120.155
JMS_PORT=2222
# Token（过期需换）
JMS_TOKEN_USER=JMS-26d59035-40e6-4906-b741-f27a271b418b
JMS_TOKEN_PASS='...'
# 资产格式（# 必须加引号，否则 shell 当注释）
JMS_ASSET_USER='wangshiyuan#user#3f91ad2f-ae47-47cd-b5bd-08811df3e9c1'
JMS_PASS='200356'   # JMS 登录密码；勿提交 git
```

```bash
# Token 连一次
sshpass -p "$JMS_TOKEN_PASS" ssh -p $JMS_PORT \
  -o StrictHostKeyChecking=accept-new \
  "${JMS_TOKEN_USER}@${JMS_HOST}" 'hostname; whoami; ip -br a | head'

# 资产格式（推荐日常）
sshpass -p "$JMS_PASS" ssh -p $JMS_PORT \
  -o StrictHostKeyChecking=accept-new \
  "${JMS_ASSET_USER}@${JMS_HOST}" 'hostname; whoami'
```



### 5b. 写入 ~/.ssh/config

```bash
cat >> ~/.ssh/config <<'EOF'

# JumpServer → w7900-242（资产格式，用 JMS 登录密码）
Host w7900-242-jms
  HostName 172.16.120.155
  Port 2222
  User wangshiyuan#user#3f91ad2f-ae47-47cd-b5bd-08811df3e9c1
  ServerAliveInterval 20
  ServerAliveCountMax 6

# Token（过期后改 User；仅临时用）
# Host w7900-242
#   HostName 172.16.120.155
#   Port 2222
#   User JMS-<新uuid>
#   ServerAliveInterval 20
EOF

ssh w7900-242-jms   # 提示密码 → 输入 JMS 登录密码
```

Cursor Remote-SSH：选 `w7900-242-jms`，每次仍可能要输密码（堡垒机一般不接受你本机公钥）。

### 5c. 落机后常见情况

```bash
# 你可能不是 root，而是 user（在 sudo 组）
whoami; id
sudo -l          # 有的机子是 NOPASSWD: ALL → sudo -i 直接进

# 目标内网 IP 在网卡上，例如
ip -br a | grep 10.18
```


| 能做                   | 通常不能做                        |
| -------------------- | ---------------------------- |
| 交互 SSH / Cursor 带密码连 | `lab.sh onboard` 灌公钥         |
| 落机后 `sudo` 跑 docker  | 经 JMS `rsync` 种子 Cursor/Warp |
| 查日志、改容器              | 在目标机装 Tailscale（除非另有直连）      |




### 5d. 与直连的选择

1. **有 JMS 凭证** → 先按 §5 连上，确认落地主机名/IP。
2. **能拿到内网直连 + root/专用账号**（或经 `Nas-B` ProxyJump）→ 改走 §1–§4，再 `lab.sh onboard`。
3. **只测几天的临时机** → 留在 JMS 密码登录即可，不必强行 pubkey。



### 5e. Agent 注意

- 用户粘贴「主机连接信息」表时：识别 `172.16.120.155:2222` + `JMS-` / `xxx#user#uuid` → 走 JumpServer，**不要**当直连 IP 跑 `lab.sh onboard`。  
- Token 过期 → 让用户控制台换新，或改用资产格式 + JMS 登录密码。  
- 用户名含 `#` → SSH 命令里**必须加引号**。

---



## 6. 批量多台（纯命令，无脚本）

```bash
# 示例：三台机器
# 格式：ALIAS IP PASS
while IFS=',' read -r ALIAS IP PASS; do
  [[ "$ALIAS" =~ ^#|^$ ]] && continue
  echo "=== $ALIAS ==="
  sshpass -p "$PASS" ssh-copy-id -i ~/.ssh/id_longgang.pub -o StrictHostKeyChecking=accept-new root@"$IP"
  # config 建议还是手动写，避免重复追加
done <<'EOF'
H100-3,221.182.146.99,pass1
H100-4,221.182.146.100,pass2
EOF
```

每台配完 config 后，分别跑 **§2** 的 rsync。

---



## 7. 故障排除


| 症状                             | 命令 / 处理                                       |
| ------------------------------ | --------------------------------------------- |
| `Permission denied`            | 查密码、`ssh -p $PORT`；JMS 查 Token 是否过期或改用资产格式    |
| `Host key verification failed` | `ssh-keygen -R $IP`                           |
| Cursor `fetch failed`          | 跑 **§2a** + **§2c**；JMS 机通常无法 seed，只能本机下载或忍一次 |
| Warp 首次连很慢                     | 跑 **§2b**                                     |
| Tailscale 在线装失败                | 改 **§3b** 离线 deb                              |
| 交付后还能连                         | 查 **§4a** Admin 删节点 + **§4b** authorized_keys |
| JMS 用户名被截断                     | `#` 未加引号 → `'user#sys#uuid'`                  |
| Token 突然连不上                    | 看过期时间；换新 Token 或改 `w7900-242-jms` 资产格式        |


---



## 8. 速查

```bash
# 直连接入
ssh-copy-id -i ~/.ssh/id_longgang.pub root@$IP
# → 写 config → ssh $ALIAS

# IDE 缓存（本机 → 远程）
./scripts/lab.sh seed --alias $ALIAS
./scripts/lab.sh seed --refresh

# Tailscale
ssh $ALIAS 'curl -fsSL https://tailscale.com/install.sh | sh'
ssh $ALIAS "tailscale up --auth-key=$TS_KEY --hostname=$ALIAS --ssh"

# JumpServer（资产格式）
ssh -p 2222 'wangshiyuan#user#<资产uuid>@172.16.120.155'
# 或: ssh w7900-242-jms

# 交付
ssh $ALIAS 'tailscale logout; rm -rf ~/.cursor-server ~/.warp'
ssh $ALIAS "grep -v longgang ~/.ssh/authorized_keys > /tmp/ak && mv /tmp/ak ~/.ssh/authorized_keys"
# + 本机删 config + Admin 删 Tailscale 节点
```

---



## 9. 密钥对照


| 密钥            | 用途                              |
| ------------- | ------------------------------- |
| `id_longgang` | 龙岗 / NAS / H100 测试机（直连）         |
| JumpServer 密码 | `172.16.120.155:2222` 堡垒机（不灌公钥） |
| `id_ed25519`  | 家里 arknights-win / wsl          |
| `id_rsa`      | GitHub                          |


