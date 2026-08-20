[CmdletBinding()]
param(
    [ValidateSet('All', 'Codex', 'Claude', 'Grok', 'Kimi', 'Hermes')]
    [string]$Provider = 'All',
    [switch]$BootstrapPython,
    [switch]$Yes
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot

$InstallArguments = @{}
if ($BootstrapPython) { $InstallArguments.BootstrapPython = $true }
& (Join-Path $Root 'Install-or-Update.ps1') @InstallArguments
if ($LASTEXITCODE -ne 0) { throw "Forge installation failed with exit code $LASTEXITCODE." }

& (Join-Path $Root 'Install-Forge-Skill.ps1') -Provider $Provider
if ($LASTEXITCODE -ne 0) { throw "Forge skill installation failed with exit code $LASTEXITCODE." }

& (Join-Path $Root 'Register-MCP.ps1') -Provider $Provider -Yes:$Yes
if ($LASTEXITCODE -ne 0) { throw "Forge provider integration failed with exit code $LASTEXITCODE." }

$Python = Join-Path $Root '.venv\Scripts\python.exe'
& $Python -m skyrim_forge doctor
if ($LASTEXITCODE -ne 0) { throw "Final Forge doctor failed with exit code $LASTEXITCODE." }

Write-Host ''
Write-Host 'Skyrim Forge AI bridge setup completed.' -ForegroundColor Green
Write-Host "Shared runtime: $Python"
Write-Host "Provider report: $(Join-Path $Root 'REPORTS\ai-integration.json')"
