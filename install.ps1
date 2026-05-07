Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

param(
  [switch]$AddToProfile
)

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$binDir = Join-Path $HOME '.ccdeepseek\bin'
$shareDir = Join-Path $HOME '.ccdeepseek\share'
New-Item -ItemType Directory -Path $binDir -Force | Out-Null
New-Item -ItemType Directory -Path $shareDir -Force | Out-Null

Copy-Item -LiteralPath (Join-Path $root 'scripts\cc.ps1') -Destination (Join-Path $binDir 'cc.ps1') -Force
Copy-Item -LiteralPath (Join-Path $root 'scripts\ccd.ps1') -Destination (Join-Path $binDir 'ccd.ps1') -Force
Copy-Item -LiteralPath (Join-Path $root 'scripts\common.ps1') -Destination (Join-Path $binDir 'common.ps1') -Force
if (Test-Path -LiteralPath (Join-Path $root 'docs\dramatic-prompt.md')) {
  Copy-Item -LiteralPath (Join-Path $root 'docs\dramatic-prompt.md') -Destination (Join-Path $shareDir 'dramatic-prompt.md') -Force
}

if ($AddToProfile) {
  if (-not (Test-Path -LiteralPath $PROFILE)) {
    New-Item -ItemType File -Path $PROFILE -Force | Out-Null
  }
  $profileContent = Get-Content -LiteralPath $PROFILE -Raw
  $line1 = "function cc { & '$binDir\cc.ps1' @args }"
  $line2 = "function ccd { & '$binDir\ccd.ps1' @args }"
  $appendLines = @()
  if ($profileContent -notmatch "function cc \{") { $appendLines += $line1 }
  if ($profileContent -notmatch "function ccd \{") { $appendLines += $line2 }
  if ($appendLines.Count -gt 0) {
    Add-Content -LiteralPath $PROFILE -Value ("`n{0}`n" -f ($appendLines -join "`n"))
  }
  Write-Host "Installed via profile: $PROFILE" -ForegroundColor Green
} else {
  Write-Host "Install complete. Add these functions to your profile:" -ForegroundColor Yellow
  Write-Host "function cc { & '$binDir\cc.ps1' @args }"
  Write-Host "function ccd { & '$binDir\ccd.ps1' @args }"
}
