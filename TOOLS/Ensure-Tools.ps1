<#
.SYNOPSIS
  Agent/user helper: detect missing Uabs tools and install/repair from pack or GitHub.
#>
[CmdletBinding()]
param(
  [ValidateSet('BundledFirst','OnlineLatest','BundledOnly')]
  [string]$Mode = 'BundledFirst',
  [string[]]$Components = @(),
  [switch]$DiscoverOnly
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'UABS-Common.ps1')
$root = Get-UabsPackRoot

Write-UabsStep 'discover_tools'
& powershell -NoProfile -File (Join-Path $PSScriptRoot 'discover_tools.ps1')

if ($DiscoverOnly) { return }

# Decide what to fix
$need = New-Object System.Collections.Generic.List[string]
$hc = [Environment]::GetEnvironmentVariable('HOUSECARL_MCP','User')
if (-not $hc) { $hc = $env:HOUSECARL_MCP }
if (-not $hc -or -not (Test-Path $hc)) { [void]$need.Add('housecarl') }
$cm = [Environment]::GetEnvironmentVariable('CODEBASE_MEMORY_MCP','User')
if (-not $cm) { $cm = $env:CODEBASE_MEMORY_MCP }
if (-not $cm -or -not (Test-Path $cm)) { [void]$need.Add('codebase-memory') }
$sp = [Environment]::GetEnvironmentVariable('SPOOKY_AUTOMOD_ROOT','User')
if (-not $sp) { $sp = $env:SPOOKY_AUTOMOD_ROOT }
if (-not $sp -or -not (Test-Path $sp)) { [void]$need.Add('spooky') }
if (-not (Get-Command headroom -EA SilentlyContinue) -and -not $env:HEADROOM_CMD) { [void]$need.Add('headroom') }

if ($Components.Count -gt 0) { $need = [System.Collections.Generic.List[string]]$Components }

if ($need.Count -eq 0) {
  Write-UabsOk 'Core tools look present. Run Setup-HouseCarl.ps1 if instance/shim missing.'
  $inst = [Environment]::GetEnvironmentVariable('SKYRIM_MO2_INSTANCE','User')
  if (-not $inst -or -not (Test-Path (Join-Path $inst 'ModOrganizer.ini'))) {
    Write-UabsWarn 'houseCARL instance unset — running Setup-HouseCarl.ps1'
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Setup-HouseCarl.ps1')
  }
  return
}

Write-UabsStep "Installing missing: $($need -join ', ')"
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'INSTALL-AIO.ps1') `
  -Mode $Mode -Components @($need) -ToolsOnly

