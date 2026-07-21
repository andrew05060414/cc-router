param(
  [Parameter(Position = 0)]
  [string]$Command = 'help',

  [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
  [string[]]$Arguments
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Resolve script directory and repository root
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDir

# Paths
$packDir = if ($env:CC_REMOTE_PACK_DIR) { $env:CC_REMOTE_PACK_DIR } else { Join-Path $env:USERPROFILE '.local\share\cc-router\remote-pack' }
$sshConfigFile = Join-Path $env:USERPROFILE '.ssh\config'
$claudeDir = Join-Path $env:USERPROFILE '.claude'
$localSettingsFile = Join-Path $claudeDir 'settings.json'
$localClaudeMdFile = Join-Path $claudeDir 'CLAUDE.md'

function Get-RemoteAuthToken {
  if (Test-Path $localSettingsFile) {
    try {
      $settings = Get-Content $localSettingsFile -Raw | ConvertFrom-Json
      if ($settings.env.PSObject.Properties['ANTHROPIC_AUTH_TOKEN']) {
        return $settings.env.ANTHROPIC_AUTH_TOKEN
      }
    } catch {
      # ignore parse errors
    }
  }
  if ($env:CC_REMOTE_AUTH_TOKEN) {
    return $env:CC_REMOTE_AUTH_TOKEN
  }
  return $null
}

function Show-Help {
  @'
cc-remote - Remote server Claude Code one-shot onboarding (Windows)

Usage:
  cc-remote pack [--platforms linux-x64,linux-arm64] [--skip-download]
  cc-remote setup <host|alias>
  cc-remote sync <host|alias>
  cc-remote ssh <host|alias> [claude args...]
  cc-remote config show
  cc-remote skills
  cc-remote ssh-config add <alias> <host> [user] [port] [key]
  cc-remote ssh-config list
  cc-remote doctor <host|alias>

Environment:
  CC_REMOTE_SETTINGS_MODE=local|remote|default
  CC_REMOTE_PACK_DIR

Notes:
  - remote mode reads ANTHROPIC_AUTH_TOKEN from local ~/.claude/settings.json
  - or set CC_REMOTE_AUTH_TOKEN environment variable
  - default mode emits no token; configure it manually on the remote

Examples:
  cc-remote pack
  cc-remote setup lgsj-h100
  cc-remote ssh lgsj-h100 C:\project
'@
}

function Get-ResolvedSshTarget {
  param([string]$InputHost)

  $user = $env:USERNAME
  $hostName = $InputHost

  if ($InputHost -match '^(.+?)@(.+)$') {
    $user = $Matches[1]
    $hostName = $Matches[2]
  }

  # Try ssh config alias resolution
  if (Test-Path $sshConfigFile) {
    $config = Get-Content $sshConfigFile -Raw
    $lines = $config -split "`r?`n"
    $currentAlias = $null
    foreach ($line in $lines) {
      if ($line -match '^\s*Host\s+(.+)$') {
        $currentAlias = $Matches[1].Trim()
      }
      if ($currentAlias -eq $InputHost -and $line -match '^\s*HostName\s+(.+)$') {
        $hostName = $Matches[1].Trim()
      }
      if ($currentAlias -eq $InputHost -and $line -match '^\s*User\s+(.+)$') {
        $user = $Matches[1].Trim()
      }
    }
  }

  return "$user@$hostName"
}

function Get-RemotePackDir {
  '/tmp/cc-router-remote-pack'
}

function Invoke-RemoteCommand {
  param([string]$Target, [string]$Command)
  ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new $Target $Command
}

function Copy-ToRemote {
  param([string]$LocalPath, [string]$Target, [string]$RemoteDest)
  scp -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -r $LocalPath "$Target`:$RemoteDest"
}

function New-RemoteSettings {
  param([string]$Mode)

  switch ($Mode) {
    'local' {
      if (-not (Test-Path $localSettingsFile)) {
        Write-Warning 'Local settings.json not found; using remote template'
        New-RemoteSettings 'remote'
        return
      }
      $settings = Get-Content $localSettingsFile -Raw | ConvertFrom-Json
      $envObj = @{}
      foreach ($key in $settings.env.PSObject.Properties.Name) {
        if ($key -match '^(ANTHROPIC_|CLAUDE_|DISABLE_AUTOUPDATER|ENABLE_TOOL_SEARCH)$') {
          $envObj[$key] = $settings.env.$key
        }
      }
      if (-not $envObj.ContainsKey('DISABLE_AUTOUPDATER')) {
        $envObj['DISABLE_AUTOUPDATER'] = '1'
      }
      $envObj['CLAUDE_CODE_DISABLE_TELEMETRY'] = '1'
      $envObj['ANTHROPIC_DISABLE_TELEMETRY'] = '1'
      $envObj['CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC'] = '1'
      $envObj['API_TIMEOUT_MS'] = '600000'
      $newSettings = [ordered]@{
        env = $envObj
        git = @{ includeCoAuthor = $settings.git.includeCoAuthor }
        model = if ($settings.model) { $settings.model } else { 'opus' }
        skipDangerousModePermissionPrompt = if ($settings.skipDangerousModePermissionPrompt -ne $null) { $settings.skipDangerousModePermissionPrompt } else { $true }
      }
      $newSettings | ConvertTo-Json -Depth 10
    }
    'default' {
      @{
        env = [ordered]@{
          CLAUDE_CODE_DISABLE_TELEMETRY = '1'
          ANTHROPIC_DISABLE_TELEMETRY = '1'
          CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = '1'
          DISABLE_AUTOUPDATER = '1'
          API_TIMEOUT_MS = '600000'
        }
        git = @{ includeCoAuthor = $false }
        model = 'opus'
        skipDangerousModePermissionPrompt = $false
      } | ConvertTo-Json -Depth 10
    }
    default {
      # remote template: kimi coding plan + telemetry off
      $envObj = [ordered]@{
        ANTHROPIC_BASE_URL = 'https://api.kimi.com/coding/'
        ANTHROPIC_DEFAULT_FABLE_MODEL = 'k3[1M]'
        ANTHROPIC_DEFAULT_FABLE_MODEL_NAME = 'k3'
        ANTHROPIC_DEFAULT_HAIKU_MODEL = 'kimi-for-coding'
        ANTHROPIC_DEFAULT_OPUS_MODEL = 'k3[1M]'
        ANTHROPIC_DEFAULT_OPUS_MODEL_NAME = 'k3'
        ANTHROPIC_DEFAULT_SONNET_MODEL = 'kimi-for-coding-highspeed'
        ANTHROPIC_DEFAULT_SONNET_MODEL_NAME = 'kimi-for-coding-highspeed'
        ANTHROPIC_MODEL = 'kimi-for-coding'
        CLAUDE_CODE_AUTO_COMPACT_WINDOW = '262144'
        CLAUDE_CODE_DISABLE_TELEMETRY = '1'
        ANTHROPIC_DISABLE_TELEMETRY = '1'
        CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = '1'
        CLAUDE_CODE_MAX_CONTEXT_TOKENS = '262144'
        API_TIMEOUT_MS = '600000'
        DISABLE_AUTOUPDATER = '1'
        ENABLE_TOOL_SEARCH = 'true'
      }
      $token = Get-RemoteAuthToken
      if ($token) {
        $envObj = [ordered]@{ ANTHROPIC_AUTH_TOKEN = $token } + $envObj
      }
      @{
        env = $envObj
        git = @{ includeCoAuthor = $false }
        model = 'opus'
        skipDangerousModePermissionPrompt = $true
      } | ConvertTo-Json -Depth 10
    }
  }
}

function Invoke-Pack {
  $platforms = 'linux-x64,linux-arm64,linux-x64-musl,linux-arm64-musl'
  $skipDownload = $false

  for ($i = 0; $i -lt $Arguments.Count; $i++) {
    switch ($Arguments[$i]) {
      '--platforms' {
        $platforms = $Arguments[++$i]
      }
      '--skip-download' {
        $skipDownload = $true
      }
    }
  }

  New-Item -ItemType Directory -Path $packDir -Force | Out-Null
  Write-Host "[cc-remote] Pack directory: $packDir"
  Write-Host "[cc-remote] Platforms: $platforms"

  if (-not $skipDownload) {
    Write-Host '[cc-remote] Downloading Claude Code npm packages...'
    Push-Location $packDir
    try {
      Remove-Item -Path 'anthropic-ai-claude-code-*.tgz' -ErrorAction SilentlyContinue
      npm pack @anthropic-ai/claude-code
      foreach ($platform in $platforms -split ',') {
        $platform = $platform.Trim()
        $valid = @('linux-x64','linux-arm64','linux-x64-musl','linux-arm64-musl','win32-x64','win32-arm64','darwin-arm64','darwin-x64')
        if ($valid -contains $platform) {
          npm pack "@anthropic-ai/claude-code-$platform"
        } else {
          Write-Warning "Unknown platform: $platform"
        }
      }
    } finally {
      Pop-Location
    }
  } else {
    Write-Host '[cc-remote] Skipping download, using existing packages'
  }

  $mainTgz = Get-ChildItem -Path $packDir -Name 'anthropic-ai-claude-code-[0-9]*.[0-9]*.[0-9]*.tgz' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if (-not $mainTgz) {
    throw 'Claude Code main npm package not found'
  }
  Write-Host "[cc-remote] Main package: $mainTgz"

  # Generate settings.json
  $settingsMode = if ($env:CC_REMOTE_SETTINGS_MODE) { $env:CC_REMOTE_SETTINGS_MODE } else { 'remote' }
  $settingsJson = New-RemoteSettings $settingsMode
  [System.IO.File]::WriteAllText((Join-Path $packDir 'settings.json'), $settingsJson, [System.Text.Encoding]::UTF8)

  # Copy CLAUDE.md
  if (Test-Path $localClaudeMdFile) {
    Copy-Item -LiteralPath $localClaudeMdFile -Destination (Join-Path $packDir 'CLAUDE.md') -Force
    Write-Host '[cc-remote] Copied CLAUDE.md'
  }

  # Copy bundled skills
  $skillsSource = Join-Path $repoRoot 'skills'
  $skillsDest = Join-Path $packDir 'skills'
  if (Test-Path $skillsSource) {
    if (Test-Path $skillsDest) {
      Remove-Item -Path $skillsDest -Recurse -Force
    }
    New-Item -ItemType Directory -Path $skillsDest -Force | Out-Null
    Get-ChildItem -Path $skillsSource -Directory | ForEach-Object {
      Copy-Item -LiteralPath $_.FullName -Destination $skillsDest -Recurse -Force
    }
    $count = (Get-ChildItem -Path $skillsDest -Directory).Count
    Write-Host "[cc-remote] Packed bundled skills: $count"
  }

  # Generate install script (bash for the remote Linux server)
  $installScript = @'
#!/usr/bin/env bash
set -euo pipefail

PACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${HOME}/.claude"

mkdir -p "$CLAUDE_DIR"

echo "[remote] Installing Claude Code..."
if command -v npm >/dev/null 2>&1; then
  npm install -g ./anthropic-ai-claude-code-*.tgz
else
  echo "ERROR: npm not found on remote" >&2
  exit 1
fi

which claude || true
claude --version || true

if [[ -f "${PACK_DIR}/settings.json" ]]; then
  cp "${PACK_DIR}/settings.json" "${CLAUDE_DIR}/settings.json"
fi
if [[ -f "${PACK_DIR}/CLAUDE.md" ]]; then
  cp "${PACK_DIR}/CLAUDE.md" "${CLAUDE_DIR}/CLAUDE.md"
fi
if [[ -d "${PACK_DIR}/skills" ]]; then
  mkdir -p "${CLAUDE_DIR}/skills"
  cp -r "${PACK_DIR}/skills/"* "${CLAUDE_DIR}/skills/" 2>/dev/null || true
fi

if ! grep -q "CLAUDE_CODE_DISABLE_TELEMETRY" "${HOME}/.profile" 2>/dev/null; then
  cat >>"${HOME}/.profile" <<'ENV_EOF'

# cc-remote: Claude Code telemetry opt-out
export CLAUDE_CODE_DISABLE_TELEMETRY=1
export ANTHROPIC_DISABLE_TELEMETRY=1
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
export DISABLE_AUTOUPDATER=1
ENV_EOF
fi

echo "[remote] Claude Code installation complete"
'@
  [System.IO.File]::WriteAllText((Join-Path $packDir 'install-claude-remote.sh'), $installScript, [System.Text.Encoding]::UTF8)

  Write-Host '[cc-remote] Pack complete'
  Get-ChildItem -Path $packDir
}

function Invoke-Setup {
  param([string]$InputHost)
  if (-not $InputHost) { throw 'Usage: cc-remote setup <host|alias>' }
  $target = Get-ResolvedSshTarget $InputHost
  Write-Host "[cc-remote] Target: $target"

  $mainTgzPattern = Join-Path $packDir 'anthropic-ai-claude-code-*.tgz'
  if (-not (Get-ChildItem -Path $mainTgzPattern -ErrorAction SilentlyContinue)) {
    Write-Host '[cc-remote] No local pack found, running pack first...'
    Invoke-Pack
  }

  $remotePack = Get-RemotePackDir
  Invoke-RemoteCommand $target "rm -rf $remotePack && mkdir -p $remotePack"
  Copy-ToRemote (Join-Path $packDir '*') $target "$remotePack/"

  Invoke-RemoteCommand $target "bash $remotePack/install-claude-remote.sh"
  Write-Host "[cc-remote] Setup complete: $target"
}

function Invoke-Sync {
  param([string]$InputHost)
  if (-not $InputHost) { throw 'Usage: cc-remote sync <host|alias>' }
  $target = Get-ResolvedSshTarget $InputHost
  Write-Host "[cc-remote] Syncing config to: $target"

  $settingsMode = if ($env:CC_REMOTE_SETTINGS_MODE) { $env:CC_REMOTE_SETTINGS_MODE } else { 'remote' }
  $settingsJson = New-RemoteSettings $settingsMode
  [System.IO.File]::WriteAllText((Join-Path $packDir 'settings.json'), $settingsJson, [System.Text.Encoding]::UTF8)
  if (Test-Path $localClaudeMdFile) {
    Copy-Item -LiteralPath $localClaudeMdFile -Destination (Join-Path $packDir 'CLAUDE.md') -Force
  }

  $remotePack = Get-RemotePackDir
  Invoke-RemoteCommand $target "mkdir -p $remotePack"
  Copy-ToRemote (Join-Path $packDir 'settings.json') $target "$remotePack/"
  if (Test-Path (Join-Path $packDir 'CLAUDE.md')) {
    Copy-ToRemote (Join-Path $packDir 'CLAUDE.md') $target "$remotePack/"
  }
  if (Test-Path (Join-Path $packDir 'skills')) {
    Invoke-RemoteCommand $target "rm -rf $remotePack/skills"
    Copy-ToRemote (Join-Path $packDir 'skills') $target "$remotePack/"
  }

  Invoke-RemoteCommand $target @"
mkdir -p ~/.claude
cp $remotePack/settings.json ~/.claude/settings.json 2>/dev/null || true
cp $remotePack/CLAUDE.md ~/.claude/CLAUDE.md 2>/dev/null || true
if [[ -d $remotePack/skills ]]; then
  mkdir -p ~/.claude/skills
  cp -r $remotePack/skills/* ~/.claude/skills/ 2>/dev/null || true
fi
echo sync done
"@
  Write-Host "[cc-remote] Sync complete: $target"
}

function Invoke-Ssh {
  param([string]$InputHost, [string[]]$RemainingArgs)
  if (-not $InputHost) { throw 'Usage: cc-remote ssh <host|alias> [dir] [args]' }
  $target = Get-ResolvedSshTarget $InputHost

  $projectDir = ''
  $claudeArgs = $RemainingArgs
  if ($RemainingArgs.Count -gt 0 -and -not $RemainingArgs[0].StartsWith('--')) {
    $projectDir = $RemainingArgs[0]
    $claudeArgs = $RemainingArgs | Select-Object -Skip 1
  }

  $argString = ($claudeArgs | ForEach-Object { '"{0}"' -f ($_ -replace '"', '\"') }) -join ' '

  if ($projectDir) {
    ssh -t $target "cd '$projectDir' && exec claude $argString"
  } else {
    ssh -t $target "exec claude $argString"
  }
}

function Invoke-ConfigShow {
  $settingsMode = if ($env:CC_REMOTE_SETTINGS_MODE) { $env:CC_REMOTE_SETTINGS_MODE } else { 'remote' }
  Write-Host "[cc-remote] Settings mode: $settingsMode"
  Write-Host '---'
  New-RemoteSettings $settingsMode
  Write-Host '---'
}

function Invoke-Doctor {
  param([string]$InputHost)
  if (-not $InputHost) { throw 'Usage: cc-remote doctor <host|alias>' }
  $target = Get-ResolvedSshTarget $InputHost
  Write-Host "[cc-remote] Checking remote environment: $target"
  Invoke-RemoteCommand $target @'
echo "--- OS ---"; uname -a
echo "--- Node ---"; command -v node && node --version || echo "node not found"
echo "--- npm ---"; command -v npm && npm --version || echo "npm not found"
echo "--- Claude ---"; command -v claude && claude --version || echo "claude not found"
echo "--- Settings ---"; ls -la ~/.claude/settings.json 2>/dev/null || echo "no settings.json"
echo "--- CLAUDE.md ---"; ls -la ~/.claude/CLAUDE.md 2>/dev/null || echo "no CLAUDE.md"
echo "--- Skills ---"; ls -la ~/.claude/skills/ 2>/dev/null | head -20 || echo "no skills"
echo "--- Telemetry env ---"; env | grep -E "TELEMETRY|AUTOUPDATER|NONESSENTIAL" || echo "no telemetry env"
'@
}

function Invoke-SshConfigAdd {
  param([string[]]$ArgsArr)
  if ($ArgsArr.Count -lt 2) { throw 'Usage: cc-remote ssh-config add <alias> <host> [user] [port] [key]' }
  $alias = $ArgsArr[0]
  $hostName = $ArgsArr[1]
  $user = if ($ArgsArr.Count -gt 2) { $ArgsArr[2] } else { $env:USERNAME }
  $port = if ($ArgsArr.Count -gt 3) { $ArgsArr[3] } else { '22' }
  $key = if ($ArgsArr.Count -gt 4) { $ArgsArr[4] } else { '' }

  New-Item -ItemType Directory -Path (Split-Path $sshConfigFile) -Force | Out-Null
  if (-not (Test-Path $sshConfigFile)) {
    New-Item -ItemType File -Path $sshConfigFile -Force | Out-Null
  }

  # Remove existing block for alias
  $content = Get-Content $sshConfigFile -Raw -ErrorAction SilentlyContinue
  if ($content) {
    $lines = $content -split "`r?`n"
    $newLines = @()
    $inBlock = $false
    foreach ($line in $lines) {
      if ($line -match "^\s*Host\s+(.+)\s*\$") {
        $inBlock = ($Matches[1].Trim() -eq $alias)
      }
      if (-not $inBlock) {
        $newLines += $line
      }
    }
    $newLines | Set-Content -Path $sshConfigFile -Encoding UTF8
  }

  $block = @(
    "",
    "Host $alias",
    "    HostName $hostName",
    "    User $user",
    "    Port $port"
  )
  if ($key) {
    $block += "    IdentityFile $key"
  }
  $block += "    ServerAliveInterval 60"
  $block += "    ServerAliveCountMax 3"
  $block | Add-Content -Path $sshConfigFile -Encoding UTF8
  Write-Host "[cc-remote] Added SSH config: $alias -> $user@$hostName`:$port"
}

function Invoke-SshConfigList {
  if (-not (Test-Path $sshConfigFile)) {
    Write-Host 'No SSH config file'
    return
  }
  Write-Host 'Configured SSH hosts:'
  $content = Get-Content $sshConfigFile -Raw
  $lines = $content -split "`r?`n"
  $current = $null
  foreach ($line in $lines) {
    if ($line -match '^\s*Host\s+(.+)$') {
      if ($current) { Write-Host $current }
      $current = $Matches[1].Trim()
    } elseif ($current -and $line -match '^\s*HostName\s+(.+)$') {
      $current += " -> $($Matches[1].Trim())"
    } elseif ($current -and $line -match '^\s*User\s+(.+)$') {
      $current += " (user: $($Matches[1].Trim()))"
    }
  }
  if ($current) { Write-Host $current }
}

function Invoke-SkillsSelect {
  Write-Host '[cc-remote] Skill selection is interactive in bash. On Windows, bundled skills are packed by default.'
  $skillsSource = Join-Path $repoRoot 'skills'
  if (Test-Path $skillsSource) {
    Write-Host 'Bundled skills:'
    Get-ChildItem -Path $skillsSource -Directory | ForEach-Object { Write-Host "  $($_.Name)" }
  }
}

# Dispatch
switch ($Command) {
  'help' { Show-Help }
  'pack' { Invoke-Pack }
  'setup' { Invoke-Setup $Arguments[0] }
  'sync' { Invoke-Sync $Arguments[0] }
  'ssh' { Invoke-Ssh $Arguments[0] ($Arguments | Select-Object -Skip 1) }
  'config' {
    $sub = if ($Arguments.Count -gt 0) { $Arguments[0] } else { 'show' }
    if ($sub -eq 'show' -or $sub -eq 'generate') {
      Invoke-ConfigShow
    } else {
      throw "Unknown config subcommand: $sub"
    }
  }
  'skills' { Invoke-SkillsSelect }
  'ssh-config' {
    $sub = if ($Arguments.Count -gt 0) { $Arguments[0] } else { 'list' }
    if ($sub -eq 'add') {
      Invoke-SshConfigAdd ($Arguments | Select-Object -Skip 1)
    } elseif ($sub -eq 'list' -or $sub -eq 'ls') {
      Invoke-SshConfigList
    } else {
      throw "Unknown ssh-config subcommand: $sub"
    }
  }
  'doctor' { Invoke-Doctor $Arguments[0] }
  default { Show-Help; exit 1 }
}
