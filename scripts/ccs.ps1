Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\lib\ccr-common.ps1"

function Show-CcsHelp {
  @'
ccr switch - Start Claude Code via CC Switch proxy

Usage:
  ccr switch [claude args...]
  ccr switch resume [claude args...]
  ccr switch doctor [detail|-v|--verbose]
  ccr switch --help

CC Switch proxy must be running (default http://127.0.0.1:15721).
'@ | Write-Host
}

function Get-CcsProxyUrl {
  if ($env:CC_CCS_PROXY_URL) {
    return $env:CC_CCS_PROXY_URL.TrimEnd('/')
  }
  $cfg = Read-CcRouterConfig
  $url = if ($cfg.ccsProxyUrl) { $cfg.ccsProxyUrl } else { 'http://127.0.0.1:15721' }
  return $url.TrimEnd('/')
}

function Test-CcsProxyHealth {
  param([string]$Url)
  try {
    Invoke-RestMethod -Uri "$Url/health" -TimeoutSec 5 >$null
    return $true
  } catch {
    return $false
  }
}

function Write-CcsStartHint {
  param([string]$Url)
  Write-Host "FAIL: CC Switch proxy not reachable at $Url" -ForegroundColor Red
  Write-Host 'Fix:'
  Write-Host '  1. Open CC Switch desktop app'
  Write-Host '  2. Click "Proxy" (top right) → "Start"'
  Write-Host "  3. Verify: curl -fsS $Url/health"
  Write-Host ''
  Write-Host 'If your proxy is on a non-default port:'
  Write-Host '  CC_CCS_PROXY_URL=http://host:port ccr switch'
  Write-Host '  # or persist:'
  Write-Host '  ccr config set ccsProxyUrl http://host:port'
}

function Invoke-CcsClaude {
  param([string[]]$ClaudeArgs)
  Assert-ClaudeCodeInstalled
  $proxyUrl = Get-CcsProxyUrl
  if (-not (Test-CcsProxyHealth $proxyUrl)) {
    Write-CcsStartHint $proxyUrl
    exit 1
  }

  $bak = Get-CCDSProcessEnvBackup
  try {
    Clear-CCDSEnv
    Initialize-ClaudeCodePowerShellToolEnv $bak
    $env:ANTHROPIC_BASE_URL = "$proxyUrl/v1"
    $env:ENABLE_TOOL_SEARCH = if ($env:CCS_TOOL_SEARCH -ne $null) { $env:CCS_TOOL_SEARCH } else { 'true' }
    $env:CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = '1'
    $env:CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK = '1'
    Set-CcRouterCachePromptEnv
    Invoke-CcRouterClaude @ClaudeArgs
  } finally {
    Clear-CCDSEnv
    Restore-CCDSProcessEnv $bak
  }
}

function Show-CcsDoctor {
  param([switch]$Detail)
  $issues = $false
  Write-Host 'ccr switch doctor'
  Write-Host ''

  Write-Host '  Claude Code'
  $claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
  if ($claudeCmd) {
    Write-Host "    OK: claude found at $($claudeCmd.Source)" -ForegroundColor Green
  } else {
    $issues = $true
    Write-Host '    FAIL: claude not found in PATH' -ForegroundColor Yellow
    Write-Host '    Fix: npm install -g @anthropic-ai/claude-code'
  }
  Write-Host ''

  $proxyUrl = Get-CcsProxyUrl
  Write-Host '  CC Switch proxy'
  Write-Host "    URL: $proxyUrl"
  if (Test-CcsProxyHealth $proxyUrl) {
    Write-Host "    OK: reachable at $proxyUrl/health" -ForegroundColor Green
  } else {
    $issues = $true
    Write-Host "    FAIL: not reachable at $proxyUrl" -ForegroundColor Yellow
    Write-Host '    Fix: start CC Switch proxy and verify /health'
  }
  Write-Host ''

  if ($Detail) {
    Write-Host '  Effective env that ccr switch would inject'
    Write-Host "    ANTHROPIC_BASE_URL = $proxyUrl/v1"
    Write-Host '    ENABLE_TOOL_SEARCH = true'
  }

  if ($issues) {
    Write-Host 'Doctor result: action required' -ForegroundColor Yellow
  } else {
    Write-Host 'Doctor result: healthy' -ForegroundColor Green
  }
}

if ($args.Count -eq 0) {
  Invoke-CcsClaude @()
  exit 0
}

$cmd = $args[0]
$rest = if ($args.Count -gt 1) { $args[1..($args.Count - 1)] } else { @() }

switch ($cmd) {
  '--help' { Show-CcsHelp; exit 0 }
  '-h' { Show-CcsHelp; exit 0 }
  'help' { Show-CcsHelp; exit 0 }
  'doctor' {
    $detail = $rest -contains 'detail' -or $rest -contains '-v' -or $rest -contains '--verbose' -or $rest -contains '-d' -or $rest -contains '--detail'
    Show-CcsDoctor -Detail:$detail
    exit 0
  }
  'resume' {
    Invoke-CcsClaude (@('-c') + $rest)
    exit 0
  }
  default {
    Invoke-CcsClaude $args
    exit 0
  }
}
