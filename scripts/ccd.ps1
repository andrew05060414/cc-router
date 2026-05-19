Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
trap {
  Write-Host $_.Exception.Message
  exit 1
}

. "$PSScriptRoot\common.ps1"

function Show-Help {
@"
ccd - Start Claude Code routed to DeepSeek

Usage:
  ccd [options] [-- claude args...]
  ccd resume [claude args...]
  ccd doctor
  ccd setup
  ccd prompt [--print-prompt]
  ccd -h | --help

Options:
  -h, --help                 Show help
  -C, --current, --here      Keep current directory
  --worktree <name>          Run in .worktrees/<name> (requires clean git repo)
  --model <id>               Default: deepseek-v4-pro[1m]
  --haiku-model <id>         Default: deepseek-v4-flash
  --max-output <n>           Default: 65536
  --autocompact-pct <n>      Default: 0 (unset override)

Subcommands:
  doctor                     Run environment checks
  setup                      Interactive DEEPSEEK_API_KEY setup
  prompt | dramatic-prompt   Show AI-assisted setup prompt template
"@ | Write-Host
}

function Show-Doctor {
  $issues = $false
  Write-Host "== ccd doctor =="
  Write-Host "Target: DeepSeek routing mode"
  Write-Host

  $token = Get-DeepSeekToken
  if ($token) {
    Write-Host "OK: DEEPSEEK_API_KEY detected in current/user/machine scope" -ForegroundColor Green
  } else {
    $issues = $true
    Write-Host "FAIL: DEEPSEEK_API_KEY is missing" -ForegroundColor Yellow
    Write-Host 'Fix (current shell): $env:DEEPSEEK_API_KEY = "your_key"'
    Write-Host 'Fix (persist profile): Add `$env:DEEPSEEK_API_KEY = "your_key"` to $PROFILE'
  }
  Write-Host

  $claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
  if ($claudeCmd) {
    Write-Host "OK: claude found at $($claudeCmd.Source)" -ForegroundColor Green
  } else {
    $issues = $true
    Write-Host "FAIL: claude not found in PATH" -ForegroundColor Yellow
    Write-Host "Fix (npm): npm install -g @anthropic-ai/claude-code"
    Write-Host "Fix (pnpm): pnpm add -g @anthropic-ai/claude-code"
  }
  Write-Host

  Write-Host "Expected env behavior for ccd:"
  Write-Host "- ANTHROPIC_BASE_URL / ANTHROPIC_AUTH_TOKEN are injected only while launching ccd"
  Write-Host "- Outside running ccd, these are usually empty (normal)"

  if ($env:ANTHROPIC_BASE_URL) {
    if ($env:ANTHROPIC_BASE_URL -eq 'https://api.deepseek.com/anthropic') {
      Write-Host "OK: current ANTHROPIC_BASE_URL matches ccd runtime value" -ForegroundColor Green
    } else {
      $issues = $true
      Write-Host "WARN: current ANTHROPIC_BASE_URL is unexpected: $($env:ANTHROPIC_BASE_URL)" -ForegroundColor Yellow
      Write-Host "Fix: Remove-Item Env:ANTHROPIC_BASE_URL -ErrorAction SilentlyContinue"
    }
  } else {
    Write-Host "OK: ANTHROPIC_BASE_URL not preset in shell (normal for ccd)" -ForegroundColor Green
  }

  if ($env:ANTHROPIC_AUTH_TOKEN) {
    if ($token -and $env:ANTHROPIC_AUTH_TOKEN -eq $token) {
      Write-Host "OK: current ANTHROPIC_AUTH_TOKEN matches DEEPSEEK_API_KEY" -ForegroundColor Green
    } else {
      $issues = $true
      Write-Host "WARN: current ANTHROPIC_AUTH_TOKEN does not match DEEPSEEK_API_KEY" -ForegroundColor Yellow
      Write-Host "Fix: Remove-Item Env:ANTHROPIC_AUTH_TOKEN -ErrorAction SilentlyContinue"
    }
  } else {
    Write-Host "OK: ANTHROPIC_AUTH_TOKEN not preset in shell (normal for ccd)" -ForegroundColor Green
  }
  Write-Host

  Write-Host "MCP tool context-bloat protection (ENABLE_TOOL_SEARCH):"
  $ccdToolSearchOverride = [Environment]::GetEnvironmentVariable('CCD_TOOL_SEARCH', 'Process')
  if (-not $ccdToolSearchOverride) { $ccdToolSearchOverride = [Environment]::GetEnvironmentVariable('CCD_TOOL_SEARCH', 'User') }
  if (-not $ccdToolSearchOverride) { $ccdToolSearchOverride = [Environment]::GetEnvironmentVariable('CCD_TOOL_SEARCH', 'Machine') }
  if ($null -eq $ccdToolSearchOverride) {
    Write-Host "  ccd will inject ENABLE_TOOL_SEARCH=true (default)" -ForegroundColor Green
    Write-Host "  This forces deferred MCP tool loading; prevents the 30k+ token messages bloat"
    Write-Host "  See docs/SETUP-NOTES.md (section 1) for the full root-cause analysis"
  } elseif ($ccdToolSearchOverride -eq '') {
    Write-Host "  ccd will NOT inject ENABLE_TOOL_SEARCH (CCD_TOOL_SEARCH explicitly empty)" -ForegroundColor Yellow
    Write-Host "  This restores pre-fix behavior (eagerly loads all MCP tool schemas into messages)"
    Write-Host "  Re-enable with: Remove-Item Env:CCD_TOOL_SEARCH -ErrorAction SilentlyContinue"
  } else {
    Write-Host ("  ccd will inject ENABLE_TOOL_SEARCH={0} (from CCD_TOOL_SEARCH)" -f $ccdToolSearchOverride) -ForegroundColor Green
  }
  Write-Host

  if ($issues) {
    Write-Host "Doctor result: action required (see Fix commands above)" -ForegroundColor Yellow
  } else {
    Write-Host "Doctor result: healthy" -ForegroundColor Green
  }
}

function Resolve-PromptTemplatePath {
  if ($env:CCD_PROMPT_TEMPLATE) {
    if (Test-Path -LiteralPath $env:CCD_PROMPT_TEMPLATE) {
      return (Resolve-Path -LiteralPath $env:CCD_PROMPT_TEMPLATE).Path
    }
    throw "CCD_PROMPT_TEMPLATE is set but file does not exist: $($env:CCD_PROMPT_TEMPLATE)"
  }

  $scriptDir = Split-Path -Parent $PSCommandPath
  $candidates = @(
    (Join-Path (Join-Path $scriptDir '..') 'docs\dramatic-prompt.md'),
    (Join-Path $HOME '.ccdeepseek\share\dramatic-prompt.md'),
    (Join-Path $HOME '.local\share\ccdeepseek\dramatic-prompt.md'),
    (Join-Path (Get-Location).Path 'docs\dramatic-prompt.md')
  )
  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate) {
      return (Resolve-Path -LiteralPath $candidate).Path
    }
  }

  throw @"
Could not locate dramatic-prompt.md template.

Either:
  - set CCD_PROMPT_TEMPLATE=C:\path\to\dramatic-prompt.md
  - or place file at ~/.ccdeepseek/share/dramatic-prompt.md
  - or run this command from a checkout that contains docs/dramatic-prompt.md
"@
}

function Invoke-PromptSubcommand {
  param([string[]]$PromptArgs)

  $printPrompt = $false
  foreach ($p in $PromptArgs) {
    switch ($p) {
      '--print-prompt' { $printPrompt = $true; continue }
      '--print' { $printPrompt = $true; continue }
      '-h' {
@"
ccd prompt - Show the dramatic prompt template for AI-assisted setup

Usage:
  ccd prompt                  Print the template path and copy/paste hints
  ccd prompt --print-prompt   Print the full template content to stdout
"@ | Write-Host
        return
      }
      '--help' {
@"
ccd prompt - Show the dramatic prompt template for AI-assisted setup

Usage:
  ccd prompt                  Print the template path and copy/paste hints
  ccd prompt --print-prompt   Print the full template content to stdout
"@ | Write-Host
        return
      }
      default { throw "Unknown option for 'ccd prompt': $p" }
    }
  }

  $template = Resolve-PromptTemplatePath
  if ($printPrompt) {
    Get-Content -LiteralPath $template -Raw | Write-Output
    return
  }

@"
Dramatic prompt template:
  $template

Show full content:
  ccd prompt --print-prompt

Copy to clipboard:
  ccd prompt --print-prompt | clip.exe
"@ | Write-Host
}

function Invoke-Setup {
  $key = Read-Host "Enter DEEPSEEK_API_KEY"
  if (-not $key) {
    throw "DEEPSEEK_API_KEY cannot be empty."
  }

  Write-Host
  Write-Host "Choose persistence:"
  Write-Host "  1) Current session only"
  Write-Host "  2) Write to PowerShell profile ($PROFILE)"
  $choice = Read-Host "Select [1/2]"

  $escaped = $key.Replace('"', '""')
  $line = '$env:DEEPSEEK_API_KEY = "{0}"' -f $escaped

  switch ($choice) {
    '1' {
      Write-Host
      Write-Host "Current session only selected."
      Write-Host "Run this command in your shell:"
      Write-Host $line
    }
    '2' {
      $profileDir = Split-Path -Parent $PROFILE
      if (-not (Test-Path -LiteralPath $profileDir)) {
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
      }
      if (-not (Test-Path -LiteralPath $PROFILE)) {
        New-Item -ItemType File -Path $PROFILE -Force | Out-Null
      }

      $content = Get-Content -LiteralPath $PROFILE -Raw
      if ($content -match '(?m)^\$env:DEEPSEEK_API_KEY\s*=') {
        $updated = [regex]::Replace($content, '(?m)^\$env:DEEPSEEK_API_KEY\s*=.*$', $line)
        Set-Content -LiteralPath $PROFILE -Value $updated
        Write-Host "Updated existing DEEPSEEK_API_KEY in $PROFILE."
      } else {
        Add-Content -LiteralPath $PROFILE -Value "`n$line"
        Write-Host "Appended DEEPSEEK_API_KEY to $PROFILE."
      }
      $env:DEEPSEEK_API_KEY = $key
      Write-Host "Applied key to current shell process."
    }
    default { throw "Invalid selection: $choice" }
  }

  Write-Host
  Write-Host "Next steps:"
  Write-Host "  1) Run: ccd doctor"
  Write-Host "  2) Run: ccd"
}

function Test-ValidWorktreeName {
  param([string]$Name)
  return ($Name -match '^[A-Za-z0-9._-]+$')
}

function Ensure-WorktreePath {
  param(
    [string]$Name,
    [string]$RepoRoot
  )

  $parent = Join-Path $RepoRoot '.worktrees'
  $target = Join-Path $parent $Name
  $branch = "worktree/$Name"
  New-Item -ItemType Directory -Path $parent -Force | Out-Null

  if (Test-Path -LiteralPath $target) {
    & git -C $target rev-parse --is-inside-work-tree *> $null
    if ($LASTEXITCODE -eq 0) {
      $top = (& git -C $target rev-parse --show-toplevel).Trim()
      if ($top -eq $target) {
        return $target
      }
    }
    throw "Worktree path already exists but is not a reusable git worktree: $target"
  }

  & git -C $RepoRoot show-ref --verify --quiet "refs/heads/$branch" *> $null
  if ($LASTEXITCODE -eq 0) {
    & git -C $RepoRoot worktree add $target $branch *> $null
  } else {
    & git -C $RepoRoot worktree add -b $branch $target *> $null
  }
  return $target
}

function Invoke-DeepSeekClaude {
  param(
    [string]$Model,
    [string]$HaikuModel,
    [int]$MaxOutput,
    [int]$AutocompactPct,
    [string[]]$ClaudeArgs
  )
  Assert-ClaudeCodeInstalled
  $token = Get-DeepSeekToken
  if (-not $token) {
    throw "Set DEEPSEEK_API_KEY before running ccd."
  }

  $bak = Get-CCDSProcessEnvBackup
  try {
    Clear-CCDSEnv
    $env:ANTHROPIC_BASE_URL = 'https://api.deepseek.com/anthropic'
    $env:ANTHROPIC_AUTH_TOKEN = $token
    $env:ANTHROPIC_MODEL = $Model
    $env:ANTHROPIC_DEFAULT_OPUS_MODEL = $Model
    $env:ANTHROPIC_DEFAULT_SONNET_MODEL = $Model
    $env:ANTHROPIC_DEFAULT_HAIKU_MODEL = $HaikuModel
    $env:CLAUDE_CODE_SUBAGENT_MODEL = $HaikuModel
    $env:CLAUDE_CODE_MAX_OUTPUT_TOKENS = $MaxOutput.ToString()
    $env:CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = '1'
    $env:CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK = '1'
    $env:CLAUDE_CODE_EFFORT_LEVEL = 'max'
    # Re-enable deferred MCP tool loading (disabled by Claude Code >= 2.1.70
    # for non-first-party hosts). Without this, all MCP tool schemas load
    # upfront and silently consume context. See docs/SETUP-NOTES.md and
    # https://github.com/anthropics/claude-code/issues/31936
    # Override with $env:CCD_TOOL_SEARCH = '' (disable) or 'auto' (threshold).
    $ccdToolSearch = [Environment]::GetEnvironmentVariable('CCD_TOOL_SEARCH', 'Process')
    if (-not $ccdToolSearch) { $ccdToolSearch = [Environment]::GetEnvironmentVariable('CCD_TOOL_SEARCH', 'User') }
    if (-not $ccdToolSearch) { $ccdToolSearch = [Environment]::GetEnvironmentVariable('CCD_TOOL_SEARCH', 'Machine') }
    if ($null -eq $ccdToolSearch) { $ccdToolSearch = 'true' }
    if ($ccdToolSearch -ne '') {
      $env:ENABLE_TOOL_SEARCH = $ccdToolSearch
    }
    if ($AutocompactPct -gt 0) {
      $env:CLAUDE_AUTOCOMPACT_PCT_OVERRIDE = $AutocompactPct.ToString()
    }
    Invoke-CcRouterClaude @ClaudeArgs
  } finally {
    Clear-CCDSEnv
    Restore-CCDSProcessEnv $bak
  }
}

$model = 'deepseek-v4-pro[1m]'
$haikuModel = 'deepseek-v4-flash'
$maxOutput = 65536
$autocompactPct = 0
$worktreeName = ''
$useCurrentDir = $false
$remaining = New-Object System.Collections.Generic.List[string]

for ($i = 0; $i -lt $args.Count; $i++) {
  $arg = $args[$i]
  switch ($arg) {
    '-h' { Show-Help; exit 0 }
    '--help' { Show-Help; exit 0 }
    'help' { Show-Help; exit 0 }
    'doctor' { Show-Doctor; exit 0 }
    'setup' { Invoke-Setup; exit 0 }
    'prompt' {
      $promptArgs = @()
      for ($j = $i + 1; $j -lt $args.Count; $j++) { $promptArgs += $args[$j] }
      Invoke-PromptSubcommand -PromptArgs $promptArgs
      exit 0
    }
    'dramatic-prompt' {
      $promptArgs = @()
      for ($j = $i + 1; $j -lt $args.Count; $j++) { $promptArgs += $args[$j] }
      Invoke-PromptSubcommand -PromptArgs $promptArgs
      exit 0
    }
    '-C' { $useCurrentDir = $true; continue }
    '--here' { $useCurrentDir = $true; continue }
    '--current' { $useCurrentDir = $true; continue }
    '--worktree' {
      $i++; if ($i -ge $args.Count) { throw "--worktree requires a value" }
      $worktreeName = $args[$i]; continue
    }
    '--model' {
      $i++; if ($i -ge $args.Count) { throw "--model requires a value" }
      $model = $args[$i]; continue
    }
    '--haiku-model' {
      $i++; if ($i -ge $args.Count) { throw "--haiku-model requires a value" }
      $haikuModel = $args[$i]; continue
    }
    '--max-output' {
      $i++; if ($i -ge $args.Count) { throw "--max-output requires a value" }
      $maxOutput = [int]$args[$i]; continue
    }
    '--autocompact-pct' {
      $i++; if ($i -ge $args.Count) { throw "--autocompact-pct requires a value" }
      $autocompactPct = [int]$args[$i]; continue
    }
    'resume' {
      $remaining.Add('-c')
      continue
    }
    '--' {
      for ($j = $i + 1; $j -lt $args.Count; $j++) {
        $remaining.Add($args[$j])
      }
      $i = $args.Count
      continue
    }
    default {
      $remaining.Add($arg)
    }
  }
}

if ($worktreeName -and $useCurrentDir) {
  throw "--worktree cannot be used with --current/--here"
}

if ($worktreeName) {
  if (-not (Test-ValidWorktreeName -Name $worktreeName)) {
    throw "Invalid worktree name: use only letters, numbers, '.', '_' or '-'"
  }
  $repoRoot = (& git rev-parse --show-toplevel 2>$null).Trim()
  if (-not $repoRoot) {
    throw "--worktree requires running inside a git repository"
  }
  $dirty = & git -C $repoRoot status --porcelain
  if ($dirty) {
    throw "Refusing to create/reuse worktree from a dirty repo. Commit/stash changes first."
  }
  $targetDir = Ensure-WorktreePath -Name $worktreeName -RepoRoot $repoRoot
  Push-Location $targetDir
  try {
    Invoke-DeepSeekClaude -Model $model -HaikuModel $haikuModel -MaxOutput $maxOutput -AutocompactPct $autocompactPct -ClaudeArgs $remaining.ToArray()
  } finally {
    Pop-Location
  }
} else {
  Invoke-DeepSeekClaude -Model $model -HaikuModel $haikuModel -MaxOutput $maxOutput -AutocompactPct $autocompactPct -ClaudeArgs $remaining.ToArray()
}
