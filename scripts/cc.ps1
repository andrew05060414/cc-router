Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\common.ps1"

function Show-Help {
@"
cc - Start Claude Code in official mode (clean env)

Usage:
  cc [claude args...]
  cc resume [claude args...]
  cc doctor
  cc --help

Examples:
  cc
  cc --model sonnet
  cc resume
  cc resume -r "session-name"
"@ | Write-Host
}

function Invoke-OfficialClaude {
  param([string[]]$ClaudeArgs)
  Assert-ClaudeCodeInstalled
  $bak = Get-CCDSProcessEnvBackup
  try {
    Clear-CCDSEnv
    & claude @ClaudeArgs
  } finally {
    Restore-CCDSProcessEnv $bak
  }
}

function Show-Doctor {
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
}

if ($args.Count -eq 0) {
  Invoke-OfficialClaude @()
  exit 0
}

$cmd = $args[0]
if ($cmd -in @('--help', '-help', '-?', 'help')) {
  Show-Help
  exit 0
}

if ($cmd -eq 'doctor') {
  Show-Doctor
  exit 0
}

if ($cmd -eq 'resume') {
  $rest = @('-c')
  if ($args.Count -gt 1) {
    $rest += $args[1..($args.Count - 1)]
  }
  Invoke-OfficialClaude $rest
  exit 0
}

Invoke-OfficialClaude $args
