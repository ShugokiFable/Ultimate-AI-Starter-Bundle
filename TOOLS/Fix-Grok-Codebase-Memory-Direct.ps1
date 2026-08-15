# Fix-Grok-Codebase-Memory-Direct.ps1
# Wires codebase-memory-mcp into %USERPROFILE%\.grok\config.toml
# Prefer existing Programs install. Never invent paths. Does not overwrite other MCP servers.

param(
  [string]$ExePath = ""
)

$ErrorActionPreference = "Stop"

function Find-CodebaseMemoryExe {
  param([string]$Hint)
  if ($Hint -and (Test-Path -LiteralPath $Hint -PathType Leaf)) {
    return (Resolve-Path -LiteralPath $Hint).Path
  }
  if ($env:CODEBASE_MEMORY_MCP -and (Test-Path -LiteralPath $env:CODEBASE_MEMORY_MCP -PathType Leaf)) {
    return (Resolve-Path -LiteralPath $env:CODEBASE_MEMORY_MCP).Path
  }
  $u = [Environment]::GetEnvironmentVariable('CODEBASE_MEMORY_MCP', 'User')
  if ($u -and (Test-Path -LiteralPath $u -PathType Leaf)) {
    return (Resolve-Path -LiteralPath $u).Path
  }
  # Prefer official Programs install over any .local\bin shim
  $programs = Join-Path $env:LOCALAPPDATA "Programs\codebase-memory-mcp\codebase-memory-mcp.exe"
  if (Test-Path -LiteralPath $programs -PathType Leaf) {
    return (Resolve-Path -LiteralPath $programs).Path
  }
  $local = Join-Path $env:USERPROFILE ".local\bin\codebase-memory-mcp.exe"
  if (Test-Path -LiteralPath $local -PathType Leaf) {
    return (Resolve-Path -LiteralPath $local).Path
  }
  return $null
}

$exe = Find-CodebaseMemoryExe -Hint $ExePath
if (-not $exe) {
  Write-Host "codebase-memory-mcp.exe not found." -ForegroundColor Red
  Write-Host "Install with the official installer (do not robocopy over a running MCP):" -ForegroundColor Yellow
  Write-Host "  https://github.com/DeusData/codebase-memory-mcp" -ForegroundColor Yellow
  Write-Host "  or run install.ps1 from the Programs folder with --ui" -ForegroundColor Yellow
  Write-Host "Then re-run: .\Fix-Grok-Codebase-Memory-Direct.ps1" -ForegroundColor Yellow
  exit 1
}

Unblock-File -LiteralPath $exe -ErrorAction SilentlyContinue

Write-Host "Testing codebase-memory-mcp..." -ForegroundColor Cyan
& $exe --version
if ($LASTEXITCODE -ne 0) { throw "codebase-memory-mcp.exe failed to start." }

$grokDir = Join-Path $env:USERPROFILE ".grok"
$configPath = Join-Path $grokDir "config.toml"
New-Item -ItemType Directory -Path $grokDir -Force | Out-Null

if (Test-Path -LiteralPath $configPath) {
  $content = Get-Content -LiteralPath $configPath -Raw
} else {
  $content = ""
}

$tomlExe = $exe.Replace('\', '/')
# If already correct, do nothing (preserves housecarl/headroom/forge blocks)
$already = [regex]::Match([string]$content, '(?ms)^[ \t]*\[mcp_servers\.codebase-memory-mcp\][ \t]*\r?\n(?:.*?\r?\n)*?[ \t]*command[ \t]*=[ \t]*["'']([^"'']+)["'']')
if ($already.Success) {
  $existing = ($already.Groups[1].Value -replace '\\', '/').Trim()
  if ($existing -ieq $tomlExe) {
    Write-Host "Grok already points at the correct codebase-memory exe. No changes." -ForegroundColor Green
    Write-Host "  $exe"
    exit 0
  }
}

if (Test-Path -LiteralPath $configPath) {
  $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $backupPath = "$configPath.before-codebase-memory-fix-$timestamp.bak"
  Copy-Item -LiteralPath $configPath -Destination $backupPath -Force
  Write-Host "Backup created: $backupPath" -ForegroundColor DarkGray
}

$sectionPattern = '(?ms)^[ \t]*\[mcp_servers\.(?:codebase-memory-mcp|"codebase-memory-mcp"|''codebase-memory-mcp'')\][ \t]*\r?\n.*?(?=^[ \t]*\[|\z)'
$content = [regex]::Replace([string]$content, $sectionPattern, "")
$content = [regex]::Replace($content, '(\r?\n){3,}', "`r`n`r`n").Trim()

$block = @"
[mcp_servers.codebase-memory-mcp]
command = "$tomlExe"
args = []
enabled = true
startup_timeout_sec = 90
tool_timeout_sec = 6000
"@

if ($content.Length -gt 0) {
  $newContent = $content.TrimEnd() + "`r`n`r`n" + $block.Trim() + "`r`n"
} else {
  $newContent = $block.Trim() + "`r`n"
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($configPath, $newContent, $utf8NoBom)

# Persist env for other tools
[Environment]::SetEnvironmentVariable('CODEBASE_MEMORY_MCP', $exe, 'User')

Write-Host ""
Write-Host "Grok MCP configuration repaired (other MCP servers preserved)." -ForegroundColor Green
Write-Host "Configured executable:" -ForegroundColor Cyan
Write-Host "  $exe"
Write-Host ""
Write-Host "Close every Grok window, open a fresh session, then use /mcp." -ForegroundColor Yellow