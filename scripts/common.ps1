Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:CCDS_ENV_KEYS = @(
  'ANTHROPIC_AUTH_TOKEN',
  'ANTHROPIC_API_KEY',
  'ANT_API_KEY',
  'ANTHROPIC_BASE_URL',
  'ANTHROPIC_MODEL',
  'ANTHROPIC_DEFAULT_OPUS_MODEL',
  'ANTHROPIC_DEFAULT_SONNET_MODEL',
  'ANTHROPIC_DEFAULT_HAIKU_MODEL',
  'CLAUDE_CODE_SUBAGENT_MODEL',
  'CLAUDE_CODE_MAX_OUTPUT_TOKENS',
  'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC',
  'CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK',
  'CLAUDE_CODE_EFFORT_LEVEL',
  'CLAUDE_AUTOCOMPACT_PCT_OVERRIDE',
  'CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST',
  'ENABLE_TOOL_SEARCH'
)

function Get-CCDSProcessEnvBackup {
  $saved = @{}
  foreach ($k in $script:CCDS_ENV_KEYS) {
    $v = [Environment]::GetEnvironmentVariable($k, 'Process')
    if ($null -ne $v -and $v -ne '') {
      $saved[$k] = $v
    }
  }
  return $saved
}

function Clear-CCDSEnv {
  foreach ($k in $script:CCDS_ENV_KEYS) {
    Remove-Item ("Env:{0}" -f $k) -ErrorAction SilentlyContinue
  }
}

function Restore-CCDSProcessEnv {
  param([hashtable]$Backup)
  if (-not $Backup) { return }
  foreach ($entry in $Backup.GetEnumerator()) {
    Set-Item -Path ("Env:{0}" -f $entry.Key) -Value $entry.Value
  }
}

function Assert-ClaudeCodeInstalled {
  if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    throw "Claude Code CLI not found. Install first: npm install -g @anthropic-ai/claude-code"
  }
}

function Get-DeepSeekToken {
  $token = [Environment]::GetEnvironmentVariable('DEEPSEEK_API_KEY', 'Process')
  if (-not $token) { $token = [Environment]::GetEnvironmentVariable('DEEPSEEK_API_KEY', 'User') }
  if (-not $token) { $token = [Environment]::GetEnvironmentVariable('DEEPSEEK_API_KEY', 'Machine') }
  return $token
}

$configCandidates = @(
  (Join-Path $PSScriptRoot 'lib\cc-config.ps1')
  (Join-Path $HOME '.ccdeepseek\share\cc-router\lib\cc-config.ps1')
  (Join-Path $HOME '.local\share\cc-router\lib\cc-config.ps1')
)
foreach ($cfgPath in $configCandidates) {
  if (Test-Path -LiteralPath $cfgPath) {
    . $cfgPath
    break
  }
}
