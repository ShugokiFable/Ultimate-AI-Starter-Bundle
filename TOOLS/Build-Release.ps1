<#
.SYNOPSIS
  Build deterministic Core and Full-Offline release archives.
.DESCRIPTION
  Compatibility wrapper. TOOLS/build_release.py is the single release-builder
  implementation so Windows and CI cannot drift on ZIP shape, UTF-8 flags,
  exclusions, CRC/extraction checks, or SHA256 generation.
#>
[CmdletBinding()]
param(
  [string]$OutDir,
  [switch]$SkipCore,
  [switch]$SkipOffline
)
$ErrorActionPreference = 'Stop'
$PackRoot = Split-Path -Parent $PSScriptRoot
if (-not $OutDir) { $OutDir = Join-Path $PackRoot 'dist' }
if ($SkipCore -or $SkipOffline) {
  throw 'Selective release builds are disabled: build_release.py always proves Core and Full-Offline together.'
}
$py = Get-Command python -ErrorAction SilentlyContinue
if (-not $py) { $py = Get-Command py -ErrorAction SilentlyContinue }
if (-not $py) { throw 'Python 3 is required to build release artifacts.' }
$args = @((Join-Path $PSScriptRoot 'build_release.py'),'--root',$PackRoot,'--outdir',$OutDir)
if ($py.Name -eq 'py.exe' -or $py.Name -eq 'py') { $args = @('-3') + $args }
& $py.Source @args
if ($LASTEXITCODE -ne 0) { throw "build_release.py failed with exit code $LASTEXITCODE" }
