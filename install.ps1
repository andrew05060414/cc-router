param(
  [switch]$AddToProfile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$shareDir = Join-Path $HOME '.local\share\cc-router'
$binDir = Join-Path $shareDir 'bin'
$libDir = Join-Path $shareDir 'lib'
$templatesDir = Join-Path $shareDir 'templates\remote'
$docsDir = Join-Path $shareDir 'docs'
New-Item -ItemType Directory -Path $binDir -Force | Out-Null
New-Item -ItemType Directory -Path $libDir -Force | Out-Null
New-Item -ItemType Directory -Path $templatesDir -Force | Out-Null
New-Item -ItemType Directory -Path $docsDir -Force | Out-Null

# Migrate old .ccdeepseek dir if present.
$oldBinDir = Join-Path $HOME '.ccdeepseek\bin'
$oldShareDir = Join-Path $HOME '.ccdeepseek\share'
if (Test-Path -LiteralPath $oldBinDir -Or Test-Path -LiteralPath $oldShareDir) {
  Write-Host "[install] Migrating old ~/.ccdeepseek to ~/.local/share/cc-router ..." -ForegroundColor Yellow
  if (Test-Path -LiteralPath (Join-Path $oldShareDir 'dramatic-prompt.md')) {
    Copy-Item -LiteralPath (Join-Path $oldShareDir 'dramatic-prompt.md') -Destination (Join-Path $shareDir 'templates\dramatic-prompt.md') -Force
  }
  if (Test-Path -LiteralPath $oldBinDir) { Remove-Item -LiteralPath $oldBinDir -Recurse -Force -ErrorAction SilentlyContinue }
  if (Test-Path -LiteralPath $oldShareDir) { Remove-Item -LiteralPath $oldShareDir -Recurse -Force -ErrorAction SilentlyContinue }
}

# Main entry and legacy aliases
Copy-Item -LiteralPath (Join-Path $root 'scripts\ccr.ps1') -Destination (Join-Path $binDir 'ccr.ps1') -Force
Copy-Item -LiteralPath (Join-Path $root 'scripts\cc.ps1') -Destination (Join-Path $binDir 'cc.ps1') -Force
Copy-Item -LiteralPath (Join-Path $root 'scripts\ccd.ps1') -Destination (Join-Path $binDir 'ccd.ps1') -Force
Copy-Item -LiteralPath (Join-Path $root 'scripts\ccs.ps1') -Destination (Join-Path $binDir 'ccs.ps1') -Force
Copy-Item -LiteralPath (Join-Path $root 'scripts\cc-remote.ps1') -Destination (Join-Path $binDir 'cc-remote.ps1') -Force

# Libraries
$libs = @('ccr-common.ps1', 'ccr-config.ps1')
foreach ($lib in $libs) {
  Copy-Item -LiteralPath (Join-Path $root 'scripts\lib' $lib) -Destination (Join-Path $libDir $lib) -Force
}

# Templates
if (Test-Path -LiteralPath (Join-Path $root 'templates\remote')) {
  Copy-Item -LiteralPath (Join-Path $root 'templates\remote\*.json') -Destination $templatesDir -Force
}
if (Test-Path -LiteralPath (Join-Path $root 'docs\dramatic-prompt.md')) {
  Copy-Item -LiteralPath (Join-Path $root 'docs\dramatic-prompt.md') -Destination (Join-Path $shareDir 'templates\dramatic-prompt.md') -Force
}

# Docs
$docs = @('SETUP-GUIDE.md', 'SETUP-NOTES.md', 'CR-CACHE-BENCH.md', 'TODO.md', 'PRODUCT.md', 'CR-REMOTE.md')
foreach ($doc in $docs) {
  if (Test-Path -LiteralPath (Join-Path $root 'docs' $doc)) {
    Copy-Item -LiteralPath (Join-Path $root 'docs' $doc) -Destination $docsDir -Force
  }
}

# Example config
if (Test-Path -LiteralPath (Join-Path $root 'config.example.json')) {
  Copy-Item -LiteralPath (Join-Path $root 'config.example.json') -Destination (Join-Path $shareDir 'config.example.json') -Force
}

if ($AddToProfile) {
  if (-not (Test-Path -LiteralPath $PROFILE)) {
    New-Item -ItemType File -Path $PROFILE -Force | Out-Null
  }
  $profileContent = Get-Content -LiteralPath $PROFILE -Raw
  $line = "function ccr { & '$binDir\ccr.ps1' @args }"
  if ($profileContent -notmatch "function ccr \\{") {
    Add-Content -LiteralPath $PROFILE -Value ("`n$line`n")
  }
  # Update any legacy cc/ccd/cc-remote function definitions to point to ccr.
  $profileContent = $profileContent -replace "function\s+cc\s*\{[^}]*\}", "function cc { & '$binDir\ccr.ps1' @args }"
  $profileContent = $profileContent -replace "function\s+ccd\s*\{[^}]*\}", "function ccd { & '$binDir\ccr.ps1' deepseek @args }"
  $profileContent = $profileContent -replace "function\s+ccs\s*\{[^}]*\}", "function ccs { & '$binDir\ccr.ps1' switch @args }"
  $profileContent = $profileContent -replace "function\s+cc-remote\s*\{[^}]*\}", "function cc-remote { & '$binDir\ccr.ps1' remote @args }"
  Set-Content -LiteralPath $PROFILE -Value $profileContent
  Write-Host "Installed via profile: $PROFILE" -ForegroundColor Green
} else {
  Write-Host "Install complete. Add this function to your profile:" -ForegroundColor Yellow
  Write-Host "function ccr { & '$binDir\ccr.ps1' @args }"
}

Write-Host "First-time (9Router + OAuth + cache-fix): ccr setup" -ForegroundColor Cyan
Write-Host "cc-router config (optional): ccr config setup" -ForegroundColor Cyan
Write-Host "  -> %USERPROFILE%\.config\cc-router\config.json"
Write-Host "Remote onboarding: ccr remote pack; ccr remote setup <host|alias>" -ForegroundColor Cyan
