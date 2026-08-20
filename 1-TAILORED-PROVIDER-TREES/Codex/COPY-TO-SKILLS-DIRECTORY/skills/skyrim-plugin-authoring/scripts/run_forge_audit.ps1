<#
.SYNOPSIS
  Run the bundled Skyrim Forge over one plugin: doctor, then header/master info.

.DESCRIPTION
  Resolves Forge from SKYRIM_FORGE_ROOT, which the bundle installer sets, and
  falls back to the installer's default root. It never assumes a drive letter
  or a username: the version this replaced hardcoded a personal
  Documents\Apps path to a read-only 0.2.x preview tool that has not existed
  for years, so it could not run on any machine including the one it was
  written on.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Path,
    [string]$ForgeRoot
)
$ErrorActionPreference = 'Stop'

# Try every candidate rather than trusting the first one that is merely SET.
# A stale SKYRIM_FORGE_ROOT left over from an older install is the normal state
# of a machine that has upgraded, and stopping there reports "not found" while a
# working Forge sits one directory away.
$candidates = @(
    $ForgeRoot
    $env:SKYRIM_FORGE_ROOT
    [Environment]::GetEnvironmentVariable('SKYRIM_FORGE_ROOT','User')
    (Join-Path (Join-Path $env:LOCALAPPDATA 'Skyrim-Tools') 'Skyrim-Forge')
) | Where-Object { $_ }

$python = $null
$tried = @()
foreach ($root in $candidates) {
    foreach ($try in @($root, ($root -replace '-\d+(\.\d+)*$', ''))) {
        if ($tried -contains $try) { continue }
        $tried += $try
        $exe = Join-Path $try '.venv\Scripts\python.exe'
        if (Test-Path -LiteralPath $exe -PathType Leaf) { $python = $exe; $ForgeRoot = $try; break }
    }
    if ($python) { break }
}
if (-not $python) {
    throw ("Skyrim Forge not found. Tried: " + ($tried -join '; ') + ". Run the bundle installer, or pass -ForgeRoot.")
}
if (-not (Test-Path -LiteralPath $Path)) { throw "Plugin not found: $Path" }

& $python -m skyrim_forge doctor
if ($LASTEXITCODE -ne 0) { throw "forge doctor failed: $LASTEXITCODE" }
& $python -m skyrim_forge plugin-info $Path
if ($LASTEXITCODE -ne 0) { throw "forge plugin-info failed: $LASTEXITCODE" }
