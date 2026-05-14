Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\common.ps1"

function Show-Help {
@"
cc - Start Claude Code in official mode (clean env)

Usage:
  cc [claude args...]
  cc -9 [claude args...]
  cc resume [claude args...]
  cc doctor [detail|-v|--verbose]
  cc --help

Examples:
  cc
  cc -9
  cc -9 resume
  cc --model sonnet
  cc resume
  cc resume -r "session-name"
  cc doctor
  cc -9 doctor detail
"@ | Write-Host
}

function Invoke-OfficialClaude {
  param([string[]]$ClaudeArgs)
  Assert-ClaudeCodeInstalled
  $bak = Get-CCDSProcessEnvBackup
  try {
    Clear-CCDSEnv
    Initialize-ClaudeCodePowerShellToolEnv $bak
    # Ignore provider routing keys in settings files; route by wrapper env only.
    $env:CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST = '1'
    & claude @ClaudeArgs
  } finally {
    Restore-CCDSProcessEnv $bak
  }
}

function Invoke-NineRouterClaude {
  param([string[]]$ClaudeArgs)
  Assert-ClaudeCodeInstalled
  $base = [Environment]::GetEnvironmentVariable('NINEROUTER_URL', 'Process')
  if (-not $base) { $base = [Environment]::GetEnvironmentVariable('NINEROUTER_URL', 'User') }
  if (-not $base) { $base = [Environment]::GetEnvironmentVariable('NINEROUTER_URL', 'Machine') }
  if (-not $base) {
    throw "Set NINEROUTER_URL before running cc -9. Example: `$env:NINEROUTER_URL = 'http://localhost:20128'"
  }
  $base = $base.TrimEnd('/')
  $token = [Environment]::GetEnvironmentVariable('NINEROUTER_KEY', 'Process')
  if (-not $token) { $token = [Environment]::GetEnvironmentVariable('NINEROUTER_KEY', 'User') }
  if (-not $token) { $token = [Environment]::GetEnvironmentVariable('NINEROUTER_KEY', 'Machine') }
  # Model names exposed to Claude Code as the three default-slot aliases.
  # Custom names like 'cc-pro/cc-normal/cc-lite' DO route through 9Router fine;
  # the only side effect is that the client falls back to unknown-model defaults
  # for things like max output tokens, model intro text, and the title-bar label.
  # Tool schemas and context behavior are unaffected (handled by ENABLE_TOOL_SEARCH).
  # Override per-shell via $env:NINEROUTER_{OPUS,SONNET,HAIKU}_MODEL.
  $opusModel = [Environment]::GetEnvironmentVariable('NINEROUTER_OPUS_MODEL', 'Process')
  if (-not $opusModel) { $opusModel = [Environment]::GetEnvironmentVariable('NINEROUTER_OPUS_MODEL', 'User') }
  if (-not $opusModel) { $opusModel = [Environment]::GetEnvironmentVariable('NINEROUTER_OPUS_MODEL', 'Machine') }
  if (-not $opusModel) { $opusModel = 'cc-pro' }
  $sonnetModel = [Environment]::GetEnvironmentVariable('NINEROUTER_SONNET_MODEL', 'Process')
  if (-not $sonnetModel) { $sonnetModel = [Environment]::GetEnvironmentVariable('NINEROUTER_SONNET_MODEL', 'User') }
  if (-not $sonnetModel) { $sonnetModel = [Environment]::GetEnvironmentVariable('NINEROUTER_SONNET_MODEL', 'Machine') }
  if (-not $sonnetModel) { $sonnetModel = 'cc-normal' }
  $haikuModel = [Environment]::GetEnvironmentVariable('NINEROUTER_HAIKU_MODEL', 'Process')
  if (-not $haikuModel) { $haikuModel = [Environment]::GetEnvironmentVariable('NINEROUTER_HAIKU_MODEL', 'User') }
  if (-not $haikuModel) { $haikuModel = [Environment]::GetEnvironmentVariable('NINEROUTER_HAIKU_MODEL', 'Machine') }
  if (-not $haikuModel) { $haikuModel = 'cc-lite' }

  $bak = Get-CCDSProcessEnvBackup
  try {
    Clear-CCDSEnv
    Initialize-ClaudeCodePowerShellToolEnv $bak
    # NOTE: deliberately NOT setting CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST=1.
    # Empirically that flag forces Claude Code into a fallback path where the
    # full system tools + MCP tools schema is serialized into the first user
    # message (messages bucket bloats by ~30k+, no 'System tools' bucket shows
    # up in /context). ccd also does not set it. Settings.json env block is
    # checked by `cc -9 doctor` instead.
    $env:ANTHROPIC_BASE_URL = "$base/v1"
    $env:ANTHROPIC_MODEL = $sonnetModel
    $env:ANTHROPIC_DEFAULT_OPUS_MODEL = $opusModel
    $env:ANTHROPIC_DEFAULT_SONNET_MODEL = $sonnetModel
    $env:ANTHROPIC_DEFAULT_HAIKU_MODEL = $haikuModel
    $env:CLAUDE_CODE_SUBAGENT_MODEL = $haikuModel
    $env:CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = '1'
    $env:CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK = '1'
    # CRITICAL: Claude Code >= 2.1.70 disables MCP tool_reference blocks (and
    # therefore deferred MCP tool loading / MCPSearch) by default whenever
    # ANTHROPIC_BASE_URL points at a non-first-party host. That makes ALL MCP
    # tool schemas get serialized into the first user message, inflating the
    # messages bucket by 30k+ tokens for users with many MCP servers enabled.
    # ENABLE_TOOL_SEARCH=true forces deferred loading back on. Requires the
    # upstream proxy (9Router) to forward `tool_reference` blocks correctly.
    # See: https://code.claude.com/docs/en/env-vars#enable_tool_search
    # See: https://github.com/anthropics/claude-code/issues/31936
    # If 9Router cannot forward tool_reference, set NINEROUTER_TOOL_SEARCH=auto
    # or NINEROUTER_TOOL_SEARCH= (empty) to fall back to default behavior.
    $toolSearch = [Environment]::GetEnvironmentVariable('NINEROUTER_TOOL_SEARCH', 'Process')
    if (-not $toolSearch) { $toolSearch = [Environment]::GetEnvironmentVariable('NINEROUTER_TOOL_SEARCH', 'User') }
    if (-not $toolSearch) { $toolSearch = [Environment]::GetEnvironmentVariable('NINEROUTER_TOOL_SEARCH', 'Machine') }
    if ($null -eq $toolSearch) { $toolSearch = 'true' }
    if ($toolSearch -ne '') {
      $env:ENABLE_TOOL_SEARCH = $toolSearch
    }
    if ($token) {
      $env:ANTHROPIC_AUTH_TOKEN = $token
    }
    & claude @ClaudeArgs
  } finally {
    Clear-CCDSEnv
    Restore-CCDSProcessEnv $bak
  }
}

function Get-FirstNonEmptyEnv {
  param([string]$Name)
  $v = [Environment]::GetEnvironmentVariable($Name, 'Process')
  if (-not $v) { $v = [Environment]::GetEnvironmentVariable($Name, 'User') }
  if (-not $v) { $v = [Environment]::GetEnvironmentVariable($Name, 'Machine') }
  return $v
}

function Get-EnvWithSource {
  param([string]$Name)
  foreach ($scope in @('Process','User','Machine')) {
    $v = [Environment]::GetEnvironmentVariable($Name, $scope)
    if ($v) { return @{ Value = $v; Source = $scope } }
  }
  return @{ Value = $null; Source = $null }
}

function Format-EnvDisplay {
  param([string]$Name)
  $info = Get-EnvWithSource $Name
  if ($info.Value) {
    $shown = $info.Value
    if ($Name -match 'TOKEN|KEY' -and $shown.Length -gt 12) {
      $shown = $shown.Substring(0, 6) + '...' + $shown.Substring($shown.Length - 4)
    }
    return ("{0,-38} = {1}  [{2}]" -f $Name, $shown, $info.Source)
  } else {
    return ("{0,-38} = <not set>" -f $Name)
  }
}

function Show-Doctor {
  param(
    [switch]$NineRouter,
    [switch]$Detail
  )
  $claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
  if ($claudeCmd) {
    Write-Host "OK: claude -> $($claudeCmd.Source)" -ForegroundColor Green
  } else {
    Write-Host "Missing: claude (install with npm install -g @anthropic-ai/claude-code)" -ForegroundColor Yellow
  }

  if ([Environment]::GetEnvironmentVariable('ANTHROPIC_BASE_URL', 'Process')) {
    Write-Host "Notice: ANTHROPIC_BASE_URL is set in this process. 'cc' will clear it before launching." -ForegroundColor Yellow
  } else {
    Write-Host "OK: process ANTHROPIC_BASE_URL not set." -ForegroundColor Green
  }

  if ($NineRouter) {
    $base = [Environment]::GetEnvironmentVariable('NINEROUTER_URL', 'Process')
    if (-not $base) { $base = [Environment]::GetEnvironmentVariable('NINEROUTER_URL', 'User') }
    if (-not $base) { $base = [Environment]::GetEnvironmentVariable('NINEROUTER_URL', 'Machine') }
    if ($base) {
      $base = $base.TrimEnd('/')
      Write-Host "OK: NINEROUTER_URL -> $base" -ForegroundColor Green
      Write-Host "Hint: health check endpoint is $base/api/health"
      try {
        $resp = Invoke-RestMethod -Uri "$base/api/health" -Method Get -TimeoutSec 5
        if ($resp.ok -eq $true) {
          Write-Host "OK: 9Router health check returned ok=true" -ForegroundColor Green
        } else {
          Write-Host "WARN: 9Router health check responded but ok!=true" -ForegroundColor Yellow
        }
      } catch {
        Write-Host "WARN: failed to reach $base/api/health ($($_.Exception.Message))" -ForegroundColor Yellow
      }
    } else {
      Write-Host "Missing: NINEROUTER_URL (required for cc -9 mode)" -ForegroundColor Yellow
      Write-Host "Fix: `$env:NINEROUTER_URL = 'http://localhost:20128'"
    }

    $token = [Environment]::GetEnvironmentVariable('NINEROUTER_KEY', 'Process')
    if (-not $token) { $token = [Environment]::GetEnvironmentVariable('NINEROUTER_KEY', 'User') }
    if (-not $token) { $token = [Environment]::GetEnvironmentVariable('NINEROUTER_KEY', 'Machine') }
    if ($token) {
      Write-Host "OK: NINEROUTER_KEY detected (will map to ANTHROPIC_AUTH_TOKEN)." -ForegroundColor Green
    } else {
      Write-Host "Notice: NINEROUTER_KEY not found. This is fine only when 9Router auth is disabled." -ForegroundColor Yellow
    }

    $modelPattern = '^claude-(opus|sonnet|haiku)-'
    $effOpus   = (Get-FirstNonEmptyEnv 'NINEROUTER_OPUS_MODEL')   ; if (-not $effOpus)   { $effOpus   = 'cc-pro'    }
    $effSonnet = (Get-FirstNonEmptyEnv 'NINEROUTER_SONNET_MODEL') ; if (-not $effSonnet) { $effSonnet = 'cc-normal' }
    $effHaiku  = (Get-FirstNonEmptyEnv 'NINEROUTER_HAIKU_MODEL')  ; if (-not $effHaiku)  { $effHaiku  = 'cc-lite'   }
    foreach ($pair in @(@('opus',$effOpus), @('sonnet',$effSonnet), @('haiku',$effHaiku))) {
      if ($pair[1] -match $modelPattern) {
        Write-Host ("OK:   {0,-6} -> {1}  (claude family, client uses official defaults)" -f $pair[0], $pair[1]) -ForegroundColor Green
      } else {
        Write-Host ("INFO: {0,-6} -> {1}  (custom name; client uses unknown-model defaults -- context unaffected)" -f $pair[0], $pair[1]) -ForegroundColor Cyan
      }
    }

    $settingsPath = Join-Path $HOME ".claude\settings.json"
    if (Test-Path $settingsPath) {
      try {
        $settingsRaw = Get-Content $settingsPath -Raw
        if ($settingsRaw -match '"ANTHROPIC_DEFAULT_(OPUS|SONNET|HAIKU)_MODEL"\s*:') {
          Write-Host "NOTICE: ~/.claude/settings.json has ANTHROPIC_DEFAULT_*_MODEL entries in its `env` block." -ForegroundColor Yellow
          Write-Host "        These take precedence over what cc -9 injects. Remove them from settings.json's" -ForegroundColor Yellow
          Write-Host "        env block if you want NINEROUTER_*_MODEL (or cc-router defaults) to be authoritative." -ForegroundColor Yellow
        }
      } catch { }
    }
  }

  if ($Detail) {
    Write-Host ""
    Write-Host "=== Detail ===" -ForegroundColor Cyan

    Write-Host ""
    Write-Host "[1] Launcher resolution" -ForegroundColor Cyan
    $ccCmd = Get-Command cc -ErrorAction SilentlyContinue
    if ($ccCmd) {
      Write-Host ("  cc command type   : {0}" -f $ccCmd.CommandType)
      if ($ccCmd.CommandType -eq 'Function') {
        $body = $ccCmd.ScriptBlock.ToString().Trim()
        Write-Host ("  cc function body  : {0}" -f $body)
        if ($body -match '\$([A-Za-z_][A-Za-z0-9_]*)') {
          $varName = $Matches[1]
          $varVal = Get-Variable -Name $varName -Scope Global -ErrorAction SilentlyContinue
          if ($varVal) {
            Write-Host ("  cc resolves to    : {0}" -f $varVal.Value)
          }
        }
      } else {
        Write-Host ("  cc source         : {0}" -f $ccCmd.Source)
      }
    } else {
      Write-Host "  cc command        : NOT FOUND on PATH" -ForegroundColor Yellow
    }
    $thisScript = $null
    try { $thisScript = $PSCommandPath } catch { }
    if (-not $thisScript) {
      try { $thisScript = $script:MyInvocation.MyCommand.Path } catch { }
    }
    if (-not $thisScript) { $thisScript = '<unknown>' }
    Write-Host ("  this script path  : {0}" -f $thisScript)

    Write-Host ""
    Write-Host "[2] Current shell ANTHROPIC_* env (would be cleared by cc / cc -9)" -ForegroundColor Cyan
    foreach ($n in @('ANTHROPIC_BASE_URL','ANTHROPIC_AUTH_TOKEN','ANTHROPIC_API_KEY','ANTHROPIC_MODEL','ANTHROPIC_DEFAULT_OPUS_MODEL','ANTHROPIC_DEFAULT_SONNET_MODEL','ANTHROPIC_DEFAULT_HAIKU_MODEL','CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST','CLAUDE_CODE_SUBAGENT_MODEL')) {
      Write-Host ("  " + (Format-EnvDisplay $n))
    }

    Write-Host ""
    Write-Host "[3] NINEROUTER_* env (precedence: Process > User > Machine > built-in default)" -ForegroundColor Cyan
    foreach ($n in @('NINEROUTER_URL','NINEROUTER_KEY','NINEROUTER_OPUS_MODEL','NINEROUTER_SONNET_MODEL','NINEROUTER_HAIKU_MODEL')) {
      Write-Host ("  " + (Format-EnvDisplay $n))
    }

    Write-Host ""
    Write-Host "[4] Effective env that 'cc -9' would inject" -ForegroundColor Cyan
    $simBase = Get-FirstNonEmptyEnv 'NINEROUTER_URL'
    if ($simBase) { $simBase = $simBase.TrimEnd('/') + '/v1' } else { $simBase = '<NINEROUTER_URL missing>' }
    $simOpus   = Get-FirstNonEmptyEnv 'NINEROUTER_OPUS_MODEL'   ; if (-not $simOpus)   { $simOpus   = 'cc-pro'    }
    $simSonnet = Get-FirstNonEmptyEnv 'NINEROUTER_SONNET_MODEL' ; if (-not $simSonnet) { $simSonnet = 'cc-normal' }
    $simHaiku  = Get-FirstNonEmptyEnv 'NINEROUTER_HAIKU_MODEL'  ; if (-not $simHaiku)  { $simHaiku  = 'cc-lite'   }
    $simToken  = Get-FirstNonEmptyEnv 'NINEROUTER_KEY'
    $tokenLine = if ($simToken) { ($simToken.Substring(0,[Math]::Min(6,$simToken.Length)) + '...') } else { '<not set>' }
    Write-Host ("  ANTHROPIC_BASE_URL                       = {0}" -f $simBase)
    Write-Host ("  ANTHROPIC_AUTH_TOKEN                     = {0}" -f $tokenLine)
    Write-Host ("  ANTHROPIC_MODEL                          = {0}" -f $simSonnet)
    Write-Host ("  ANTHROPIC_DEFAULT_OPUS_MODEL             = {0}" -f $simOpus)
    Write-Host ("  ANTHROPIC_DEFAULT_SONNET_MODEL           = {0}" -f $simSonnet)
    Write-Host ("  ANTHROPIC_DEFAULT_HAIKU_MODEL            = {0}" -f $simHaiku)
    Write-Host ("  CLAUDE_CODE_SUBAGENT_MODEL               = {0}" -f $simHaiku)
    Write-Host ("  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = 1")
    Write-Host ("  CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK= 1")
    Write-Host ("  CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST     = <unset>")
    $simToolSearch = Get-FirstNonEmptyEnv 'NINEROUTER_TOOL_SEARCH'
    if ($null -eq $simToolSearch) { $simToolSearch = 'true' }
    if ($simToolSearch -eq '') {
      Write-Host ("  ENABLE_TOOL_SEARCH                       = <unset>  (NINEROUTER_TOOL_SEARCH explicitly empty)") -ForegroundColor Yellow
      Write-Host ("    -> MCP tools will load eagerly into messages bucket (~30k+ extra)") -ForegroundColor Yellow
    } else {
      Write-Host ("  ENABLE_TOOL_SEARCH                       = {0}  (forces deferred MCP tool loading via tool_reference)" -f $simToolSearch) -ForegroundColor Green
      Write-Host ("    -> Requires 9Router to forward tool_reference blocks. If you see 400 errors,") -ForegroundColor DarkGray
      Write-Host ("       set `$env:NINEROUTER_TOOL_SEARCH = '' or 'auto' to disable.") -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "[5] ~/.claude/settings.json check" -ForegroundColor Cyan
    $settingsPath2 = Join-Path $HOME ".claude\settings.json"
    Write-Host ("  path              : {0}" -f $settingsPath2)
    if (Test-Path $settingsPath2) {
      Write-Host "  exists            : YES"
      try {
        $obj = Get-Content $settingsPath2 -Raw | ConvertFrom-Json -ErrorAction Stop
        if ($obj.PSObject.Properties.Name -contains 'env' -and $obj.env) {
          Write-Host "  env block         : PRESENT" -ForegroundColor Yellow
          Write-Host "  env keys          :"
          foreach ($p in $obj.env.PSObject.Properties) {
            $v = $p.Value
            if ($p.Name -match 'TOKEN|KEY' -and $v -is [string] -and $v.Length -gt 12) {
              $v = $v.Substring(0,6) + '...' + $v.Substring($v.Length - 4)
            }
            Write-Host ("    {0,-38} = {1}" -f $p.Name, $v)
          }
          Write-Host "  Note: settings.json env keys may override 'cc -9' process env in some Claude Code versions." -ForegroundColor Yellow
          Write-Host "        If 'cc -9' picks up wrong models even though scripts/env are right, suspect this block." -ForegroundColor Yellow
        } else {
          Write-Host "  env block         : <none> (good)"
        }
      } catch {
        Write-Host ("  parse error       : {0}" -f $_.Exception.Message) -ForegroundColor Yellow
      }
    } else {
      Write-Host "  exists            : NO (using built-in defaults only)"
    }

    Write-Host ""
    Write-Host "[6] PowerShell profile check" -ForegroundColor Cyan
    foreach ($pp in @($PROFILE.CurrentUserAllHosts, $PROFILE.CurrentUserCurrentHost, $PROFILE.AllUsersAllHosts, $PROFILE.AllUsersCurrentHost)) {
      $exists = Test-Path $pp
      $hasCc = $false
      if ($exists) {
        try {
          $raw = Get-Content $pp -Raw -ErrorAction Stop
          if ($raw -match '(?im)^\s*function\s+(global:)?cc\b') { $hasCc = $true }
        } catch { }
      }
      $tag = if ($exists) { if ($hasCc) { 'has cc()' } else { 'no cc' } } else { '<missing>' }
      Write-Host ("  [{0}] {1}" -f $tag, $pp)
    }

    Write-Host ""
    Write-Host "[7] Common things to check if context bloats" -ForegroundColor Cyan
    Write-Host "  - Restart ALL Claude Code windows after editing scripts/env. Running processes hold a snapshot."
    Write-Host "  - Confirm 'cc' resolves to your installed cc-router script (see [1])."
    Write-Host "  - Confirm ENABLE_TOOL_SEARCH is 'true' in section [4] (this is what keeps MCP tools deferred)."
    Write-Host "  - Confirm 9Router exposes the model aliases shown in section [4] (cc-pro / cc-normal / cc-lite by default)."
    Write-Host "  - If MCP tools list is huge, disable unused MCP servers via 'claude mcp list' / 'claude mcp remove <name>'."
    Write-Host "  - Inside Claude Code: '/context' should show a 'System tools' bucket. If absent, ENABLE_TOOL_SEARCH may have been stripped by 9Router."
    Write-Host ""
    Write-Host "[8] Quick A/B"
    Write-Host "  Window 1:  cc      -> /context  (official baseline)"
    Write-Host "  Window 2:  cc -9   -> /context  (compare buckets)"
    Write-Host "  Healthy diff: similar System tools (~6-10k), Messages < 6k, total < 30k after 'hi'."
  }
}

if ($args.Count -eq 0) {
  Invoke-OfficialClaude @()
  exit 0
}

$nineRouterMode = $false
$effectiveArgs = @($args)
if ($effectiveArgs.Count -gt 0 -and $effectiveArgs[0] -in @('-9', '--9router')) {
  $nineRouterMode = $true
  if ($effectiveArgs.Count -gt 1) {
    $effectiveArgs = @($effectiveArgs[1..($effectiveArgs.Count - 1)])
  } else {
    $effectiveArgs = @()
  }
}

if ($effectiveArgs.Count -eq 0) {
  if ($nineRouterMode) { Invoke-NineRouterClaude @() } else { Invoke-OfficialClaude @() }
  exit 0
}

$cmd = $effectiveArgs[0]
if ($cmd -in @('--help', '-help', '-?', 'help')) {
  Show-Help
  exit 0
}

if ($cmd -eq 'doctor') {
  $detailMode = $false
  if ($effectiveArgs.Count -gt 1) {
    foreach ($a in $effectiveArgs[1..($effectiveArgs.Count - 1)]) {
      if ($a -in @('detail', '-v', '--verbose', '-d', '--detail')) {
        $detailMode = $true
      }
    }
  }
  Show-Doctor -NineRouter:$nineRouterMode -Detail:$detailMode
  exit 0
}

if ($cmd -eq 'resume') {
  $rest = @('-c')
  if ($effectiveArgs.Count -gt 1) {
    $rest += $effectiveArgs[1..($effectiveArgs.Count - 1)]
  }
  if ($nineRouterMode) { Invoke-NineRouterClaude $rest } else { Invoke-OfficialClaude $rest }
  exit 0
}

if ($nineRouterMode) {
  Invoke-NineRouterClaude $effectiveArgs
} else {
  Invoke-OfficialClaude $effectiveArgs
}
