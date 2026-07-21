# DeepSeek prompt-cache bench — same env injection as ccd (no worktree).
param(
  [switch]$DryRun,
  [int]$Runs = 3
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\lib\ccr-common.ps1"

function Show-BenchHelp {
@'
ccd-cache-bench — verify DeepSeek prompt cache behavior (same env as ccd)

Usage:
  .\scripts\ccd-cache-bench.ps1 [-DryRun] [-Runs N]

Requires: DEEPSEEK_API_KEY, claude CLI on PATH.
See: docs/CCD-CACHE-BENCH.md
'@ | Write-Host
}

if ($args -contains '-h' -or $args -contains '--help') {
  Show-BenchHelp
  exit 0
}

if ($env:CCD_BENCH_RUNS) { $Runs = [int]$env:CCD_BENCH_RUNS }
$model = if ($env:CCD_BENCH_MODEL) { $env:CCD_BENCH_MODEL } else { 'deepseek-v4-pro[1m]' }
$haikuModel = if ($env:CCD_BENCH_HAIKU_MODEL) { $env:CCD_BENCH_HAIKU_MODEL } else { 'deepseek-v4-flash' }

$token = Get-DeepSeekToken
if (-not $token) {
  throw 'Set DEEPSEEK_API_KEY before running (or: ccd setup).'
}

$bak = Get-CCDSProcessEnvBackup
try {
  Clear-CCDSEnv
  $env:ANTHROPIC_BASE_URL = 'https://api.deepseek.com/anthropic'
  $env:ANTHROPIC_AUTH_TOKEN = $token
  $env:ANTHROPIC_MODEL = $model
  $env:ANTHROPIC_DEFAULT_OPUS_MODEL = $model
  $env:ANTHROPIC_DEFAULT_SONNET_MODEL = $model
  $env:ANTHROPIC_DEFAULT_HAIKU_MODEL = $haikuModel
  $env:CLAUDE_CODE_SUBAGENT_MODEL = $haikuModel
  $env:CLAUDE_CODE_MAX_OUTPUT_TOKENS = '4096'
  $env:CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = '1'
  $env:CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK = '1'
  $env:CLAUDE_CODE_EFFORT_LEVEL = 'low'
  $ccdToolSearch = [Environment]::GetEnvironmentVariable('CCD_TOOL_SEARCH', 'Process')
  if (-not $ccdToolSearch) { $ccdToolSearch = [Environment]::GetEnvironmentVariable('CCD_TOOL_SEARCH', 'User') }
  if (-not $ccdToolSearch) { $ccdToolSearch = [Environment]::GetEnvironmentVariable('CCD_TOOL_SEARCH', 'Machine') }
  if ($null -eq $ccdToolSearch) { $ccdToolSearch = 'true' }
  if ($ccdToolSearch -ne '') { $env:ENABLE_TOOL_SEARCH = $ccdToolSearch }
  Set-CcRouterCachePromptEnv

  Write-Host '== ccd-cache-bench =='
  Write-Host "Model: $model"
  Write-Host "Runs:  $Runs"
  Write-Host ''
  Write-Host 'Injected (ccd-aligned):'
  Write-Host ("  ANTHROPIC_BASE_URL                      = $($env:ANTHROPIC_BASE_URL)")
  Write-Host ("  CLAUDE_CODE_ATTRIBUTION_HEADER          = $($env:CLAUDE_CODE_ATTRIBUTION_HEADER)")
  Write-Host ("  CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS    = $($env:CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS)")
  Write-Host ("  ENABLE_TOOL_SEARCH                      = $($env:ENABLE_TOOL_SEARCH)")
  Write-Host ''

  $benchPrompt = 'Reply with exactly: CACHE_BENCH_OK'
  $stableSystem = 'You are a minimal assistant for cache benchmarking. Do not use tools.'

  if ($DryRun) {
    Write-Host '--DryRun: skipping claude --print calls.'
    Write-Host "Manual: claude --print --model '$model' '$benchPrompt'"
    return
  }

  Assert-ClaudeCodeInstalled

  for ($i = 1; $i -le $Runs; $i++) {
    Write-Host "--- run $i/$Runs ---"
    $out = & claude --print --model $model --system-prompt $stableSystem $benchPrompt 2>&1
    if ($LASTEXITCODE -ne 0) { throw "claude --print failed on run ${i}: $out" }
    ($out | Select-Object -Last 3) | ForEach-Object { Write-Host $_ }
    Write-Host ''
  }

  Write-Host @'
What to look for:
  Run 1: cache_creation_input_tokens may be > 0
  Run 2+: cache_read_input_tokens should dominate
See: docs/CCD-CACHE-BENCH.md
'@
} finally {
  Clear-CCDSEnv
  Restore-CCDSProcessEnv $bak
}
