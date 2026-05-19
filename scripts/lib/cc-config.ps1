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
    allowDangerouslySkipPermissions = $false
    claudePermissionsTarget         = 'none'
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
    'none' { throw "claudePermissionsTarget is 'none'. Use -Global or -Project on cc config claude." }
    default { throw "Unknown scope '${Scope}'. Use global or project." }
  }
}

function Get-CcRouterClaudeExtraArgs {
  if (Test-CcRouterAllowDangerouslySkipPermissions) {
    return @('--allow-dangerously-skip-permissions')
  }
  return @()
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
cc config - cc-router settings and Claude Code settings.json

cc-router: %USERPROFILE%\.config\cc-router\config.json (or $env:XDG_CONFIG_HOME\cc-router)
Claude JSON: global (~/.claude/settings.json) or project (<repo>/.claude/settings.json)

  cc config show
  cc config setup
  cc config set allowDangerouslySkipPermissions on|off
  cc config set claudePermissionsTarget none|global|project

  cc config claude show [-Global|-Project]
  cc config claude get <dot.path> [-Global|-Project]
  cc config claude set <dot.path> <value> [-Global|-Project]
  cc config claude unset <dot.path> [-Global|-Project]
  cc config claude enable-bypass-permissions [-Global|-Project]
  cc config claude disable-bypass-permissions [-Global|-Project]
'@ | Write-Host
}

function Show-CcRouterConfig {
  $path = Get-CcRouterConfigPath
  Write-Host "cc-router config: $path"
  if (Test-Path -LiteralPath $path) {
    Get-Content -LiteralPath $path -Raw | Write-Host
  } else {
    Write-Host '(not created yet — run: cc config setup)'
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
}

function Invoke-CcRouterConfigSetup {
  $cfg = Read-CcRouterConfig
  Write-Host '== cc-router config setup =='
  Write-Host "Config file: $(Get-CcRouterConfigPath)"
  Write-Host ''
  $ans = Read-Host 'Pass --allow-dangerously-skip-permissions on every cc / cc -9 / ccd launch? [y/N]'
  $ans = if ($ans) { $ans.Trim() } else { '' }
  if ([string]::IsNullOrWhiteSpace($ans)) { $ans = 'n' }
  try {
    $cfg.allowDangerouslySkipPermissions = (ConvertTo-CcRouterBool $ans 'n')
  } catch {
    Write-Warning "Unrecognized '$ans'; defaulting to disabled (use y/yes or n/no)."
    $cfg.allowDangerouslySkipPermissions = $false
  }
  Write-Host ''
  Write-Host 'Where should cc config claude write permission settings by default?'
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
      if ($rest.Count -lt 2) { throw 'Usage: cc config set <key> <value>' }
      $key = $rest[0]
      $val = $rest[1]
      $cfg = Read-CcRouterConfig
      switch ($key) {
        'allowDangerouslySkipPermissions' {
          $cfg.allowDangerouslySkipPermissions = (ConvertTo-CcRouterBool $val 'false')
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
          if ($actionArgs.Count -lt 1) { throw 'Usage: cc config claude get <dot.path>' }
          Get-CcRouterClaudeSetting -DotPath $actionArgs[0] -Scope $scope
          return
        }
        'set' {
          if ($actionArgs.Count -lt 2) { throw 'Usage: cc config claude set <dot.path> <value>' }
          Set-CcRouterClaudeSetting -DotPath $actionArgs[0] -Value $actionArgs[1] -Scope $scope
          return
        }
        'unset' {
          if ($actionArgs.Count -lt 1) { throw 'Usage: cc config claude unset <dot.path>' }
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
        default { throw "Unknown: cc config claude $action" }
      }
    }
    default { throw "Unknown: cc config $sub" }
  }
}
