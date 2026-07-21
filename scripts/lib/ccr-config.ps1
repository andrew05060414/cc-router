Set-StrictMode -Version Latest

function Get-CcRouterConfigDir {
  if ($env:XDG_CONFIG_HOME) {
    return (Join-Path $env:XDG_CONFIG_HOME 'cc-router')
  }
  return (Join-Path $HOME '.config' 'cc-router')
}

function Get-CcRouterConfigPath {
  return (Join-Path (Get-CcRouterConfigDir) 'config.json')
}

function Get-CcRouterDefaultConfig {
  return [ordered]@{
    allowDangerouslySkipPermissions = $true
    claudePermissionsTarget         = 'none'
    cachePromptEnvEnabled           = $true
    cacheFixEnabled                 = $true
    cacheFixUrl                     = 'http://127.0.0.1:9801'
    cacheFix9routerEnabled          = $true
    nineRouterUrl                   = 'http://127.0.0.1:20128'
  }
}

function Test-CcRouterCachePromptEnvEnabled {
  if ($env:CC_CACHE_PROMPT_ENV_ENABLED) {
    if (Test-CcRouterTruthy $env:CC_CACHE_PROMPT_ENV_ENABLED) { return $true }
    if (Test-CcRouterFalsy $env:CC_CACHE_PROMPT_ENV_ENABLED) { return $false }
    return $false
  }
  $cfg = Read-CcRouterConfig
  if ($null -eq $cfg.cachePromptEnvEnabled) { return $true }
  return [bool]$cfg.cachePromptEnvEnabled
}

function Test-CcRouterCacheFix9routerEnabled {
  if ($env:CC_CACHE_FIX_9ROUTER_ENABLED) {
    if (Test-CcRouterTruthy $env:CC_CACHE_FIX_9ROUTER_ENABLED) { return $true }
    if (Test-CcRouterFalsy $env:CC_CACHE_FIX_9ROUTER_ENABLED) { return $false }
    return $false
  }
  $cfg = Read-CcRouterConfig
  if ($null -eq $cfg.cacheFix9routerEnabled) { return $true }
  return [bool]$cfg.cacheFix9routerEnabled
}

function Get-CcRouterNineRouterRealUrl {
  $base = [Environment]::GetEnvironmentVariable('NINEROUTER_URL', 'Process')
  if (-not $base) { $base = [Environment]::GetEnvironmentVariable('NINEROUTER_URL', 'User') }
  if (-not $base) { $base = [Environment]::GetEnvironmentVariable('NINEROUTER_URL', 'Machine') }
  if ($base) { return $base.TrimEnd('/') }
  $cfg = Read-CcRouterConfig
  $url = [string]$cfg.nineRouterUrl
  if ([string]::IsNullOrWhiteSpace($url)) { $url = 'http://127.0.0.1:20128' }
  return $url.TrimEnd('/')
}

function Get-CcRouterNineRouterClientBaseUrl {
  if (Test-CcRouterCacheFix9routerEnabled) {
    return Get-CcRouterCacheFixUrl
  }
  return Get-CcRouterNineRouterRealUrl
}

function Write-CcRouterCacheFixStartHint {
  $upstream = Get-CcRouterNineRouterRealUrl
  $cf = Get-CcRouterCacheFixUrl
  Write-Host "  CACHE_FIX_PROXY_UPSTREAM=$upstream node `"`$(npm root -g)/claude-code-cache-fix/proxy/server.mjs`" &"
  Write-Host "  curl -fsS $cf/health"
}

function Set-CcRouterCachePromptEnv {
  if (-not (Test-CcRouterCachePromptEnvEnabled)) { return }
  $attr = [Environment]::GetEnvironmentVariable('CC_ATTRIBUTION_HEADER', 'Process')
  if (-not $attr) { $attr = [Environment]::GetEnvironmentVariable('CC_ATTRIBUTION_HEADER', 'User') }
  if (-not $attr) { $attr = [Environment]::GetEnvironmentVariable('CC_ATTRIBUTION_HEADER', 'Machine') }
  if (-not $attr) { $attr = 'false' }
  $env:CLAUDE_CODE_ATTRIBUTION_HEADER = $attr

  $git = [Environment]::GetEnvironmentVariable('CC_DISABLE_GIT_INSTRUCTIONS', 'Process')
  if (-not $git) { $git = [Environment]::GetEnvironmentVariable('CC_DISABLE_GIT_INSTRUCTIONS', 'User') }
  if (-not $git) { $git = [Environment]::GetEnvironmentVariable('CC_DISABLE_GIT_INSTRUCTIONS', 'Machine') }
  if ($null -eq $git) { $git = '1' }
  if ($git -ne '') {
    $env:CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS = $git
  } else {
    Remove-Item Env:CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS -ErrorAction SilentlyContinue
  }
}

function Test-CcRouterCacheFixEnabled {
  if ($env:CC_CACHE_FIX_ENABLED) {
    if (Test-CcRouterTruthy $env:CC_CACHE_FIX_ENABLED) { return $true }
    if (Test-CcRouterFalsy $env:CC_CACHE_FIX_ENABLED) { return $false }
    return $false
  }
  $cfg = Read-CcRouterConfig
  return [bool]$cfg.cacheFixEnabled
}

function Get-CcRouterCacheFixUrl {
  if ($env:CC_CACHE_FIX_URL) {
    return $env:CC_CACHE_FIX_URL.TrimEnd('/')
  }
  $cfg = Read-CcRouterConfig
  $url = [string]$cfg.cacheFixUrl
  if ([string]::IsNullOrWhiteSpace($url)) { $url = 'http://127.0.0.1:9801' }
  return $url.TrimEnd('/')
}

function Test-CcRouterCacheFixHealth {
  param([string]$BaseUrl)
  $base = $BaseUrl.TrimEnd('/')
  try {
    $resp = Invoke-RestMethod -Uri "$base/health" -Method Get -TimeoutSec 5
    if ($resp.ok -eq $true) { return $true }
    if ($resp.status -eq 'ok') { return $true }
    return $false
  } catch {
    return $false
  }
}

function Read-CcRouterConfig {
  $path = Get-CcRouterConfigPath
  $defaults = Get-CcRouterDefaultConfig
  if (-not (Test-Path -LiteralPath $path)) {
    return [pscustomobject]$defaults
  }
  try {
    $raw = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
  } catch {
    throw "Failed to parse ${path}: $($_.Exception.Message)"
  }
  foreach ($key in $defaults.Keys) {
    if ($null -eq $raw.PSObject.Properties[$key]) {
      $raw | Add-Member -NotePropertyName $key -NotePropertyValue $defaults[$key] -Force
    }
  }
  return $raw
}

function Write-CcRouterConfig {
  param([Parameter(Mandatory = $true)]$Config)
  $dir = Get-CcRouterConfigDir
  $path = Get-CcRouterConfigPath
  New-Item -ItemType Directory -Path $dir -Force | Out-Null
  $Config | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $path -Encoding UTF8
}

function Get-CcRouterBoolNormalized {
  param([string]$Value)
  if ($null -eq $Value) { return '' }
  return $Value.Trim().ToLowerInvariant()
}

function Test-CcRouterTruthy {
  param([string]$Value)
  switch (Get-CcRouterBoolNormalized $Value) {
    { $_ -in @('y', 'yes', 'ye', 'yeah', 'yep', 'yea', 'true', '1', 'on', 'enable', 'enabled', 'sure', 'ok') } { return $true }
    default { return $false }
  }
}

function Test-CcRouterFalsy {
  param([string]$Value)
  switch (Get-CcRouterBoolNormalized $Value) {
    { $_ -in @('n', 'no', 'false', '0', 'off', 'disable', 'disabled', 'nah') } { return $true }
    default { return $false }
  }
}

function ConvertTo-CcRouterBool {
  param(
    [string]$Value,
    [string]$Default = 'false'
  )
  $v = Get-CcRouterBoolNormalized $Value
  if ([string]::IsNullOrWhiteSpace($v)) {
    if (Test-CcRouterTruthy $Default) { return $true }
    return $false
  }
  if (Test-CcRouterTruthy $v) { return $true }
  if (Test-CcRouterFalsy $v) { return $false }
  throw "Expected on/off, y/n, yes/no (got: $Value)"
}

function Test-CcRouterAllowDangerouslySkipPermissions {
  if ($env:CC_ALLOW_DANGEROUSLY_SKIP_PERMISSIONS) {
    if (Test-CcRouterTruthy $env:CC_ALLOW_DANGEROUSLY_SKIP_PERMISSIONS) { return $true }
    if (Test-CcRouterFalsy $env:CC_ALLOW_DANGEROUSLY_SKIP_PERMISSIONS) { return $false }
    return $false
  }
  $cfg = Read-CcRouterConfig
  return [bool]$cfg.allowDangerouslySkipPermissions
}

function Get-CcRouterClaudeGlobalSettingsPath {
  return (Join-Path $HOME '.claude' 'settings.json')
}

function Get-CcRouterClaudeProjectSettingsPath {
  $root = & git rev-parse --show-toplevel 2>$null
  if (-not $root) { $root = (Get-Location).Path }
  return (Join-Path $root '.claude' 'settings.json')
}

function Resolve-CcRouterClaudeSettingsPath {
  param([string]$Scope)
  if (-not $Scope) {
    $cfg = Read-CcRouterConfig
    $Scope = [string]$cfg.claudePermissionsTarget
  }
  switch ($Scope) {
    { $_ -in @('global', 'user') } { return (Get-CcRouterClaudeGlobalSettingsPath) }
    { $_ -in @('project', 'repo') } { return (Get-CcRouterClaudeProjectSettingsPath) }
    'none' { throw "claudePermissionsTarget is 'none'. Use -Global or -Project on ccr config claude." }
    default { throw "Unknown scope '${Scope}'. Use global or project." }
  }
}

function Get-CcRouterClaudeExtraArgs {
  if (Test-CcRouterAllowDangerouslySkipPermissions) {
    return @('--allow-dangerously-skip-permissions')
  }
  return @()
}

function Resolve-CcRouterMappedModelName {
  param(
    [string]$Name,
    [string]$OpusModel,
    [string]$SonnetModel,
    [string]$HaikuModel
  )
  switch -Wildcard ($Name) {
    'opus' { return $OpusModel }
    'claude-opus-*' { return $OpusModel }
    'sonnet' { return $SonnetModel }
    'claude-sonnet-*' { return $SonnetModel }
    'haiku' { return $HaikuModel }
    'claude-haiku-*' { return $HaikuModel }
    default { return $Name }
  }
}

function Normalize-CcRouterModelArgs {
  param(
    [string[]]$ClaudeArgs,
    [string]$OpusModel,
    [string]$SonnetModel,
    [string]$HaikuModel
  )
  $normalized = New-Object System.Collections.Generic.List[string]
  for ($i = 0; $i -lt $ClaudeArgs.Count; $i++) {
    $arg = $ClaudeArgs[$i]
    switch -Regex ($arg) {
      '^(--model|-m)$' {
        $normalized.Add($arg)
        if ($i + 1 -lt $ClaudeArgs.Count) {
          $i++
          $normalized.Add((Resolve-CcRouterMappedModelName -Name $ClaudeArgs[$i] -OpusModel $OpusModel -SonnetModel $SonnetModel -HaikuModel $HaikuModel))
        }
        continue
      }
      '^--model=(.*)$' {
        $normalized.Add("--model=$(Resolve-CcRouterMappedModelName -Name $Matches[1] -OpusModel $OpusModel -SonnetModel $SonnetModel -HaikuModel $HaikuModel)")
        continue
      }
      '^-m=(.*)$' {
        $normalized.Add("-m=$(Resolve-CcRouterMappedModelName -Name $Matches[1] -OpusModel $OpusModel -SonnetModel $SonnetModel -HaikuModel $HaikuModel)")
        continue
      }
      default {
        $normalized.Add($arg)
        continue
      }
    }
  }
  return $normalized.ToArray()
}

function Invoke-CcRouterClaude {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$ClaudeArgs)
  foreach ($a in $ClaudeArgs) {
    if ($a -in @('--allow-dangerously-skip-permissions', '--dangerously-skip-permissions')) {
      & claude @ClaudeArgs
      return
    }
  }
  $extra = Get-CcRouterClaudeExtraArgs
  if ($extra.Count -eq 0) {
    & claude @ClaudeArgs
  } else {
    & claude @extra @ClaudeArgs
  }
}

function Ensure-CcRouterClaudeSettingsFile {
  param([string]$Path)
  $dir = Split-Path -Parent $Path
  New-Item -ItemType Directory -Path $dir -Force | Out-Null
  if (-not (Test-Path -LiteralPath $Path)) {
    '{}' | Set-Content -LiteralPath $Path -Encoding UTF8
  }
}

function Get-CcRouterJsonFromDotPath {
  param([string]$DotPath)
  $parts = $DotPath.Split('.', [System.StringSplitOptions]::RemoveEmptyEntries)
  return ,$parts
}

function Get-CcRouterClaudeSetting {
  param(
    [string]$DotPath,
    [string]$Scope
  )
  $path = Resolve-CcRouterClaudeSettingsPath $Scope
  Ensure-CcRouterClaudeSettingsFile $path
  $json = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
  $current = $json
  foreach ($part in (Get-CcRouterJsonFromDotPath $DotPath)) {
    if ($null -eq $current -or $null -eq $current.PSObject.Properties[$part]) {
      return $null
    }
    $current = $current.$part
  }
  return $current
}

function Set-CcRouterClaudeSetting {
  param(
    [string]$DotPath,
    [string]$Value,
    [string]$Scope
  )
  $path = Resolve-CcRouterClaudeSettingsPath $Scope
  Ensure-CcRouterClaudeSettingsFile $path
  $json = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
  if ($null -eq $json) { $json = [pscustomobject]@{} }

  $parts = Get-CcRouterJsonFromDotPath $DotPath
  if ($parts.Count -eq 0) { throw 'dot.path is required' }

  $parsed = $Value
  if ($Value -eq 'true') { $parsed = $true }
  elseif ($Value -eq 'false') { $parsed = $false }
  elseif ($Value -match '^-?\d+$') { $parsed = [int]$Value }
  elseif ($Value.StartsWith('{') -or $Value.StartsWith('[')) {
    $parsed = $Value | ConvertFrom-Json
  }

  $cursor = $json
  for ($i = 0; $i -lt $parts.Count - 1; $i++) {
    $p = $parts[$i]
    if ($null -eq $cursor.PSObject.Properties[$p]) {
      $cursor | Add-Member -NotePropertyName $p -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    $cursor = $cursor.$p
  }
  $leaf = $parts[$parts.Count - 1]
  if ($null -eq $cursor.PSObject.Properties[$leaf]) {
    $cursor | Add-Member -NotePropertyName $leaf -NotePropertyValue $parsed -Force
  } else {
    $cursor.$leaf = $parsed
  }

  $json | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding UTF8
  Write-Host "Updated $path"
  Get-CcRouterClaudeSetting -DotPath $DotPath -Scope $Scope
}

function Remove-CcRouterClaudeSetting {
  param(
    [string]$DotPath,
    [string]$Scope
  )
  $path = Resolve-CcRouterClaudeSettingsPath $Scope
  if (-not (Test-Path -LiteralPath $path)) {
    Write-Host "No settings file at $path"
    return
  }
  $json = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
  $parts = Get-CcRouterJsonFromDotPath $DotPath
  if ($parts.Count -eq 0) { throw 'dot.path is required' }

  function Remove-AtPath {
    param($Node, [string[]]$Remaining)
    if ($Remaining.Count -eq 0) { return $Node }
    $head = $Remaining[0]
    $tail = $Remaining[1..($Remaining.Count - 1)]
    if ($tail.Count -eq 0) {
      $Node.PSObject.Properties.Remove($head)
      return $Node
    }
    if ($null -ne $Node.PSObject.Properties[$head]) {
      $Node.$head = Remove-AtPath $Node.$head $tail
    }
    return $Node
  }

  $json = Remove-AtPath $json $parts
  $json | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding UTF8
  Write-Host "Removed $DotPath from $path"
}

function Show-CcRouterConfigHelp {
@'
ccr config - cc-router settings and Claude Code settings.json

cc-router: %USERPROFILE%\.config\cc-router\config.json (or $env:XDG_CONFIG_HOME\cc-router)
Claude JSON: global (~/.claude/settings.json) or project (<repo>/.claude/settings.json)

  ccr config show
  ccr config setup
  ccr config set allowDangerouslySkipPermissions on|off
  ccr config set cachePromptEnvEnabled on|off
  ccr config set cacheFixEnabled on|off
  ccr config set cacheFixUrl http://127.0.0.1:9801
  ccr config set cacheFix9routerEnabled on|off
  ccr config set nineRouterUrl http://127.0.0.1:20128
  ccr config set claudePermissionsTarget none|global|project

  ccr config claude show [-Global|-Project]
  ccr config claude get <dot.path> [-Global|-Project]
  ccr config claude set <dot.path> <value> [-Global|-Project]
  ccr config claude unset <dot.path> [-Global|-Project]
  ccr config claude enable-bypass-permissions [-Global|-Project]
  ccr config claude disable-bypass-permissions [-Global|-Project]
'@ | Write-Host
}

function Show-CcRouterConfig {
  $path = Get-CcRouterConfigPath
  Write-Host "cc-router config: $path"
  if (Test-Path -LiteralPath $path) {
    Get-Content -LiteralPath $path -Raw | Write-Host
  } else {
    Write-Host '(not created yet — run: ccr config setup)'
  }
  Write-Host ''
  if (Test-CcRouterAllowDangerouslySkipPermissions) {
    Write-Host 'allowDangerouslySkipPermissions (effective): enabled → prepends --allow-dangerously-skip-permissions'
  } else {
    Write-Host 'allowDangerouslySkipPermissions (effective): disabled'
  }
  if ($env:CC_ALLOW_DANGEROUSLY_SKIP_PERMISSIONS) {
    Write-Host '  (overridden by CC_ALLOW_DANGEROUSLY_SKIP_PERMISSIONS)'
  }
  $cfg = if (Test-Path -LiteralPath $path) { Read-CcRouterConfig } else { Get-CcRouterDefaultConfig }
  Write-Host "claudePermissionsTarget: $($cfg.claudePermissionsTarget)"
  Write-Host "  global file : $(Get-CcRouterClaudeGlobalSettingsPath)"
  Write-Host "  project file: $(Get-CcRouterClaudeProjectSettingsPath)"
  Write-Host ''
  if (Test-CcRouterCacheFixEnabled) {
    Write-Host "cacheFixEnabled (effective): enabled → official cc sets ANTHROPIC_BASE_URL=$(Get-CcRouterCacheFixUrl)"
  } else {
    Write-Host 'cacheFixEnabled (effective): disabled'
  }
  if ($env:CC_CACHE_FIX_ENABLED) {
    Write-Host '  (overridden by CC_CACHE_FIX_ENABLED)'
  }
  Write-Host "cacheFixUrl (config): $($cfg.cacheFixUrl)"
  Write-Host ''
  if (Test-CcRouterCachePromptEnvEnabled) {
    Write-Host 'cachePromptEnvEnabled (effective): enabled → ATTRIBUTION_HEADER=false, DISABLE_GIT_INSTRUCTIONS=1'
  } else {
    Write-Host 'cachePromptEnvEnabled (effective): disabled'
  }
  if ($env:CC_CACHE_PROMPT_ENV_ENABLED) {
    Write-Host '  (overridden by CC_CACHE_PROMPT_ENV_ENABLED)'
  }
  Write-Host ''
  if (Test-CcRouterCacheFix9routerEnabled) {
    Write-Host "cacheFix9routerEnabled (effective): enabled → ccr 9router uses $(Get-CcRouterCacheFixUrl)/v1 → 9Router at $(Get-CcRouterNineRouterRealUrl)"
  } else {
    Write-Host "cacheFix9routerEnabled (effective): disabled → ccr 9router direct to $(Get-CcRouterNineRouterRealUrl)/v1"
  }
  if ($env:CC_CACHE_FIX_9ROUTER_ENABLED) {
    Write-Host '  (overridden by CC_CACHE_FIX_9ROUTER_ENABLED)'
  }
  Write-Host "nineRouterUrl (config fallback): $($cfg.nineRouterUrl)"
}

function Invoke-CcRouterConfigSetup {
  $cfg = Read-CcRouterConfig
  Write-Host '== cc-router config setup =='
  Write-Host "Config file: $(Get-CcRouterConfigPath)"
  Write-Host ''
  $ans = Read-Host 'Pass --allow-dangerously-skip-permissions on every cc / ccr 9router / ccr deepseek launch? [Y/n]'
  $ans = if ($ans) { $ans.Trim() } else { '' }
  if ([string]::IsNullOrWhiteSpace($ans)) { $ans = 'y' }
  try {
    $cfg.allowDangerouslySkipPermissions = (ConvertTo-CcRouterBool $ans 'y')
  } catch {
    Write-Warning "Unrecognized '$ans'; defaulting to enabled (use y/yes or n/no)."
    $cfg.allowDangerouslySkipPermissions = $true
  }
  Write-Host ''
  Write-Host 'Where should ccr config claude write permission settings by default?'
  Write-Host '  1) none    — only cc-router config.json'
  Write-Host '  2) global  — ~/.claude/settings.json'
  Write-Host '  3) project — <repo>/.claude/settings.json'
  $pick = Read-Host 'Select [1/2/3] (default 1)'
  switch ($pick) {
    '2' { $cfg.claudePermissionsTarget = 'global' }
    '3' { $cfg.claudePermissionsTarget = 'project' }
    default { $cfg.claudePermissionsTarget = 'none' }
  }
  Write-CcRouterConfig $cfg
  if ($cfg.claudePermissionsTarget -ne 'none') {
    $ans2 = Read-Host "Also set permissions.defaultMode to bypassPermissions in that file? [y/N]"
    $ans2 = if ($ans2) { $ans2.Trim() } else { '' }
    if ([string]::IsNullOrWhiteSpace($ans2)) { $ans2 = 'n' }
    try {
      if (ConvertTo-CcRouterBool $ans2 'n') {
        Set-CcRouterClaudeSetting -DotPath 'permissions.defaultMode' -Value 'bypassPermissions' -Scope $cfg.claudePermissionsTarget
      }
    } catch {
      Write-Warning "Skipped bypassPermissions (unrecognized answer: $ans2)."
    }
  }
  Write-Host ''
  Show-CcRouterConfig
}

function Invoke-CcRouterConfigCommand {
  param([string[]]$Args)

  if ($Args.Count -eq 0 -or $Args[0] -in @('help', '-h', '--help')) {
    Show-CcRouterConfigHelp
    return
  }

  $sub = $Args[0]
  $rest = @()
  if ($Args.Count -gt 1) { $rest = $Args[1..($Args.Count - 1)] }

  switch ($sub) {
    'show' { Show-CcRouterConfig; return }
    'setup' { Invoke-CcRouterConfigSetup; return }
    'set' {
      if ($rest.Count -lt 2) { throw 'Usage: ccr config set <key> <value>' }
      $key = $rest[0]
      $val = $rest[1]
      $cfg = Read-CcRouterConfig
      switch ($key) {
        'allowDangerouslySkipPermissions' {
          $cfg.allowDangerouslySkipPermissions = (ConvertTo-CcRouterBool $val 'false')
        }
        'cachePromptEnvEnabled' {
          $cfg.cachePromptEnvEnabled = (ConvertTo-CcRouterBool $val 'true')
        }
        'cacheFixEnabled' {
          $cfg.cacheFixEnabled = (ConvertTo-CcRouterBool $val 'true')
        }
        'cacheFixUrl' {
          $cfg.cacheFixUrl = $val.TrimEnd('/')
        }
        'cacheFix9routerEnabled' {
          $cfg.cacheFix9routerEnabled = (ConvertTo-CcRouterBool $val 'true')
        }
        'nineRouterUrl' {
          $cfg.nineRouterUrl = $val.TrimEnd('/')
        }
        'claudePermissionsTarget' {
          if ($val -notin @('none', 'global', 'project')) {
            throw 'claudePermissionsTarget must be: none, global, or project'
          }
          $cfg.claudePermissionsTarget = $val
        }
        default { throw "Unknown key: $key" }
      }
      Write-CcRouterConfig $cfg
      Write-Host "Set ${key}=$($cfg.$key)"
      return
    }
    'claude' {
      $scope = ''
      $filtered = @()
      foreach ($a in $rest) {
        switch ($a) {
          { $_ -in @('-Global', '--global', '-User', '--user') } { $scope = 'global' }
          { $_ -in @('-Project', '--project', '-Repo', '--repo') } { $scope = 'project' }
          default { $filtered += $a }
        }
      }
      $action = if ($filtered.Count -gt 0) { $filtered[0] } else { '' }
      $actionArgs = @()
      if ($filtered.Count -gt 1) { $actionArgs = $filtered[1..($filtered.Count - 1)] }

      switch ($action) {
        { $_ -in @('', 'help', '-h', '--help') } {
          Show-CcRouterConfigHelp
          return
        }
        'show' {
          $p = Resolve-CcRouterClaudeSettingsPath $scope
          Write-Host $p
          Ensure-CcRouterClaudeSettingsFile $p
          Get-Content -LiteralPath $p -Raw | Write-Host
          return
        }
        'path' {
          Write-Host (Resolve-CcRouterClaudeSettingsPath $scope)
          return
        }
        'get' {
          if ($actionArgs.Count -lt 1) { throw 'Usage: ccr config claude get <dot.path>' }
          Get-CcRouterClaudeSetting -DotPath $actionArgs[0] -Scope $scope
          return
        }
        'set' {
          if ($actionArgs.Count -lt 2) { throw 'Usage: ccr config claude set <dot.path> <value>' }
          Set-CcRouterClaudeSetting -DotPath $actionArgs[0] -Value $actionArgs[1] -Scope $scope
          return
        }
        'unset' {
          if ($actionArgs.Count -lt 1) { throw 'Usage: ccr config claude unset <dot.path>' }
          Remove-CcRouterClaudeSetting -DotPath $actionArgs[0] -Scope $scope
          return
        }
        'enable-bypass-permissions' {
          Set-CcRouterClaudeSetting -DotPath 'permissions.defaultMode' -Value 'bypassPermissions' -Scope $scope
          return
        }
        'disable-bypass-permissions' {
          Remove-CcRouterClaudeSetting -DotPath 'permissions.defaultMode' -Scope $scope
          return
        }
        default { throw "Unknown: ccr config claude $action" }
      }
    }
    default { throw "Unknown: ccr config $sub" }
  }
}
