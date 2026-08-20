[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$Python = Join-Path $Root '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $Python)) { throw 'Install Forge first.' }

Write-Host 'Skyrim Forge core configuration' -ForegroundColor Cyan
$Workspace = Read-Host 'Workspace root (blank keeps current)'
if ($Workspace) { & $Python -m skyrim_forge config-set workspace_root $Workspace; if ($LASTEXITCODE) { throw 'Workspace update failed.' } }
$Data = Read-Host 'Skyrim Data directory (blank keeps current)'
if ($Data) { & $Python -m skyrim_forge config-set skyrim_data $Data; if ($LASTEXITCODE) { throw 'Skyrim Data update failed.' } }
$Plugins = Read-Host 'plugins.txt path (blank keeps current)'
if ($Plugins) { & $Python -m skyrim_forge config-set plugins_file $Plugins; if ($LASTEXITCODE) { throw 'plugins.txt update failed.' } }
$External = Read-Host 'Enable external process execution? [y/N]'
if ($External -match '^(?i:y|yes)$') { & $Python -m skyrim_forge config-set allow_external_processes true }
& $Python -m skyrim_forge doctor
