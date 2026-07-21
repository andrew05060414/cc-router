Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ccr.ps1 - Code/Claude Router unified PowerShell entry point

$script:CcrScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Show-CcrHelp {
  @'
ccr - Code/Claude Router: unified launcher for Claude Code

Usage:
  ccr [claude args...]              # official Claude mode (default)
  ccr claude [claude args...]       # official Claude mode
  ccr 9router [claude args...]      # 9Router / cache-fix mode
  ccr deepseek [options]            # DeepSeek mode
  ccr switch [claude args...]       # CC Switch proxy mode
  ccr remote <subcommand> [args...] # remote server onboarding
  ccr setup [check|install-deps|start-cache-fix|intro]
  ccr config [show|setup|set|claude ...]
  ccr doctor [detail|-v|--verbose]
  ccr --help

Legacy aliases (deprecated):
  ccd → ccr deepseek
  ccs → ccr switch
  cck → ccr remote
'@ | Write-Host
}

function Invoke-CcrScript {
  param([string]$Name, [string[]]$Arguments)
  $path = Join-Path $script:CcrScriptDir $Name
  if (-not (Test-Path -LiteralPath $path)) {
    throw "ccr: internal script not found: $path"
  }
  & $path @Arguments
  exit $LASTEXITCODE
}

if ($args.Count -eq 0 -or $args[0] -in @('--help', '-h', 'help')) {
  Show-CcrHelp
  exit 0
}

$sub = $args[0]
$rest = if ($args.Count -gt 1) { $args[1..($args.Count - 1)] } else { @() }

switch ($sub) {
  'claude' { Invoke-CcrScript 'cc.ps1' $rest }
  '9router' { Invoke-CcrScript 'cc.ps1' (@('-9') + $rest) }
  '-9' { Invoke-CcrScript 'cc.ps1' $args }
  '--9router' { Invoke-CcrScript 'cc.ps1' $args }
  'deepseek' { Invoke-CcrScript 'ccd.ps1' $rest }
  'd' { Invoke-CcrScript 'ccd.ps1' $rest }
  'switch' { Invoke-CcrScript 'ccs.ps1' $rest }
  's' { Invoke-CcrScript 'ccs.ps1' $rest }
  'remote' { Invoke-CcrScript 'cc-remote.ps1' $rest }
  'r' { Invoke-CcrScript 'cc-remote.ps1' $rest }
  'setup' { Invoke-CcrScript 'cc.ps1' $args }
  'config' { Invoke-CcrScript 'cc.ps1' $args }
  'doctor' { Invoke-CcrScript 'cc.ps1' $args }
  default {
    # Default is official claude mode; pass the original args through.
    Invoke-CcrScript 'cc.ps1' $args
  }
}
