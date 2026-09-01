<#
.SYNOPSIS
  Write a machine-local inventory of MCP servers and CLIs that actually exist.

.DESCRIPTION
  Agents assume partly because they do not know what they have. This script
  does not guess: it reads each provider's real config and runs Get-Command /
  Test-Path. The result is written to %LOCALAPPDATA%\Ultimate-AI-Starter-Bundle\TOOLBELT.md
  (and optionally -OutFile). It is never committed: another machine's inventory
  is an assumption.

.PARAMETER OutFile
  Extra copy of the report. Default location is always written as well.
#>
[CmdletBinding()]
param(
  [string]$OutFile
)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'UABS-Mcp-Write.ps1')

function Test-Has {
  param([string]$Name)
  $cmd = Get-Command $Name -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  return $null
}

function Read-JsonFile {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  try { return ([IO.File]::ReadAllText($Path) | ConvertFrom-Json) } catch { return $null }
}

function Get-TomlMcpIds {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return @() }
  $text = [IO.File]::ReadAllText($Path)
  $ids = [System.Collections.Generic.List[string]]::new()
  foreach ($m in [regex]::Matches($text, '(?m)^\[mcp_servers\.([^\]]+)\]')) {
    $ids.Add($m.Groups[1].Value)
  }
  return @($ids)
}

function Get-JsonMcpIds {
  param([string]$Path, [string]$Section = 'mcpServers')
  $json = Read-JsonFile $Path
  if (-not $json) { return @() }
  if ($json.PSObject.Properties.Name -notcontains $Section) { return @() }
  return @($json.$Section.PSObject.Properties.Name)
}

$lines = New-Object System.Collections.Generic.List[string]
$now = [DateTime]::Now.ToString('yyyy-MM-dd HH:mm')
$lines.Add('# Toolbelt')
$lines.Add('')
$lines.Add("Generated: $now")
$lines.Add('Machine-local. Another machine must re-run TOOLS\Build-Toolbelt.ps1.')
$lines.Add('Do not copy these paths into a shareable release.')
$lines.Add('')

$lines.Add('## MCP servers actually registered')
$lines.Add('')

$mcpMaps = @(
  @{ Name = 'Claude'; Path = (Join-Path $env:USERPROFILE '.claude.json'); Kind = 'json-claude' }
  @{ Name = 'Grok (own toml)'; Path = (Join-Path $env:USERPROFILE '.grok\config.toml'); Kind = 'toml' }
  @{ Name = 'Codex'; Path = (Join-Path $env:USERPROFILE '.codex\config.toml'); Kind = 'toml' }
  @{ Name = 'Kimi'; Path = (Join-Path $env:USERPROFILE '.kimi-code\mcp.json'); Kind = 'json-kimi' }
)

# Grok inherits ~/.claude.json only while its compatibility cell permits it.
$grokOwn = Get-TomlMcpIds (Join-Path $env:USERPROFILE '.grok\config.toml')
$claudeIds = Get-JsonMcpIds (Join-Path $env:USERPROFILE '.claude.json') 'mcpServers'

foreach ($m in $mcpMaps) {
  if ($m.Kind -eq 'toml') { $ids = Get-TomlMcpIds $m.Path }
  elseif ($m.Kind -eq 'json-kimi') { $ids = Get-JsonMcpIds $m.Path 'mcpServers' }
  else { $ids = Get-JsonMcpIds $m.Path 'mcpServers' }
  $present = Test-Path -LiteralPath $m.Path
  if (-not $present) {
    $lines.Add("- **$($m.Name):** not installed (no $($m.Path))")
    continue
  }
  if ($ids.Count) {
    $lines.Add("- **$($m.Name):** $($ids -join ', ')")
  } else {
    $lines.Add("- **$($m.Name):** config exists, 0 servers declared")
  }
}

if ((Test-UabsGrokInheritsClaudeMcp) -and $grokOwn.Count -eq 0 -and $claudeIds.Count) {
  $lines.Add("- **Grok (inherited from ~/.claude.json):** $($claudeIds -join ', ')")
}

$hx = Test-Has 'hermes'
if (-not $hx) {
  $cand = Join-Path $env:LOCALAPPDATA 'hermes\hermes-agent\venv\Scripts\hermes.exe'
  if (Test-Path -LiteralPath $cand) { $hx = $cand }
}
if ($hx) {
  try {
    $hlist = & $hx mcp list 2>&1 | Out-String
    $hlist = $hlist.Trim()
    if ($hlist) { $lines.Add("- **Hermes:** ``hermes mcp list`` reported:`n``````text`n$hlist`n``````") }
    else { $lines.Add('- **Hermes:** installed, mcp list empty') }
  } catch {
    $lines.Add("- **Hermes:** installed at $hx, mcp list failed")
  }
} else {
  $lines.Add('- **Hermes:** not on PATH')
}

$lines.Add('')
$lines.Add('## CLIs actually on PATH or well-known locations')
$lines.Add('')

$cli = @(
  'python','python3','git','gh','node','npx','npm','hermes','headroom',
  'codebase-memory-mcp','forge','dotnet'
)
foreach ($name in $cli) {
  $src = Test-Has $name
  if ($src) { $lines.Add("- $name = $src") }
  else { $lines.Add("- $name = MISSING") }
}

$known = @(
  @{ Name = 'housecarl-mcp'; Path = @(
      $env:HOUSECARL_MCP,
      (Join-Path $env:LOCALAPPDATA 'houseCARL\server\housecarl-mcp.exe'),
      (Join-Path $env:LOCALAPPDATA 'Programs\houseCARL\housecarl-mcp.exe')
    ) }
  @{ Name = 'codebase-memory-mcp.exe'; Path = @(
      $env:CODEBASE_MEMORY_MCP,
      (Join-Path $env:LOCALAPPDATA 'Programs\codebase-memory-mcp\codebase-memory-mcp.exe')
    ) }
)
foreach ($k in $known) {
  $hit = $null
  foreach ($p in $k.Path) {
    if ($p -and (Test-Path -LiteralPath $p)) { $hit = $p; break }
  }
  if ($hit) { $lines.Add("- $($k.Name) = $hit") }
  else { $lines.Add("- $($k.Name) = MISSING") }
}

$lines.Add('')
$lines.Add('## How to refresh')
$lines.Add('')
$lines.Add('```powershell')
$lines.Add('powershell -NoProfile -ExecutionPolicy Bypass -File .\TOOLS\Build-Toolbelt.ps1')
$lines.Add('```')

$text = ($lines -join "`r`n") + "`r`n"
$stateDir = Join-Path $env:LOCALAPPDATA 'Ultimate-AI-Starter-Bundle'
New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
$default = Join-Path $stateDir 'TOOLBELT.md'
$enc = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($default, $text, $enc)
Write-Host "wrote $default"
if ($OutFile) {
  $dir = Split-Path -Parent $OutFile
  if ($dir -and -not (Test-Path -LiteralPath $dir)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
  [System.IO.File]::WriteAllText($OutFile, $text, $enc)
  Write-Host "wrote $OutFile"
}
