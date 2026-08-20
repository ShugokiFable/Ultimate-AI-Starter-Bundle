<#
.SYNOPSIS
  Install the bundled Skyrim Forge release and prove its bundle compatibility.

.DESCRIPTION
  The install directory carries NO version suffix, and that is the whole point.

  Every provider stores an MCP server command as a hard absolute path: Claude
  JSON, Kimi JSON, Codex TOML, Grok TOML, Hermes YAML. A version-stamped
  install directory renames itself on every upgrade, so each upgrade silently
  disconnects whichever configs were not rewritten -- and the failure is quiet,
  because a provider that cannot spawn its MCP server just shows no tools.

  Observed on the live machine before 7.9.0: SKYRIM_FORGE_ROOT pointed at
  Skyrim-Forge-5.1.6 (deleted), all five provider configs pointed at
  Skyrim-Forge (never created), and the actual install was Skyrim-Forge-5.2.0
  with no virtualenv. Three paths, no two agreeing, MCP dead everywhere.

  So: the ARCHIVE keeps its version (provenance), the INSTALL DIRECTORY never
  does (stability), and an existing version-stamped install is migrated to the
  versionless name instead of being duplicated beside it.
#>
[CmdletBinding()]
param(
  [string]$PackRoot,
  [string[]]$Providers = @('Claude','Codex','Grok','Kimi','Hermes'),
  [string]$BundleVersion = '7.9.0',
  # Resolve and print the install root, migrate a version-stamped install if one
  # is found, then stop. Path resolution is the part that has broken repeatedly,
  # so it has to be runnable on its own -- TESTS/Test-V7-Pack.ps1 drives this
  # switch against synthetic layouts.
  [switch]$ResolveOnly
)
$ErrorActionPreference = 'Stop'
if (-not $PackRoot) { $PackRoot = Split-Path -Parent $PSScriptRoot }
$Providers = @($Providers | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })

# The payload names the version; nothing else in this script restates it. Drop a
# newer Skyrim-Forge-x.y.z.zip into BUNDLED-TOOLS\offline and this follows.
$offline = Join-Path $PackRoot 'BUNDLED-TOOLS\offline'
$asset = Get-ChildItem -LiteralPath $offline -Filter 'Skyrim-Forge-*.zip' -File -ErrorAction SilentlyContinue |
  Sort-Object { [version](($_.BaseName -replace '^Skyrim-Forge-', '')) } -Descending | Select-Object -First 1
if (-not $asset) { throw "Bundled Forge asset missing: $offline\Skyrim-Forge-*.zip" }
$forgeVersion = $asset.BaseName -replace '^Skyrim-Forge-', ''
$archiveRoot = 'Skyrim-Forge-' + $forgeVersion

# ---- Resolve ONE versionless install root -------------------------------
# Strip a trailing -1.2 / -1.2.3 from a directory leaf.
function Get-VersionlessRoot([string]$path) {
  if (-not $path) { return $null }
  $path = $path.TrimEnd('\', '/')
  $leaf = Split-Path -Leaf $path
  $parent = Split-Path -Parent $path
  if ($parent -and $leaf -match '^(?<stem>.+?)-\d+(?:\.\d+)*$') { return (Join-Path $parent $Matches['stem']) }
  return $path
}

# Process first: a caller that exported SKYRIM_FORGE_ROOT for this run means it,
# and the persisted User value is normally just the same string anyway. It also
# keeps the resolver testable without writing to the user's registry.
$declared = $env:SKYRIM_FORGE_ROOT
if (-not $declared) { $declared = [Environment]::GetEnvironmentVariable('SKYRIM_FORGE_ROOT', 'User') }
$default = Join-Path (Join-Path $env:LOCALAPPDATA 'Skyrim-Tools') 'Skyrim-Forge'

$target = $null
$migrationNote = $null
foreach ($candidate in @($declared, $default)) {
  if (-not $candidate) { continue }
  $wanted = Get-VersionlessRoot $candidate
  $parent = Split-Path -Parent $wanted
  if (-not $parent -or -not (Test-Path -LiteralPath $parent -PathType Container)) { continue }

  # Already versionless and present: upgrade in place, nothing to migrate.
  if (Test-Path -LiteralPath $wanted -PathType Container) { $target = $wanted; break }

  # A version-stamped install of the same product is the thing that keeps
  # breaking configs. Move it onto the versionless name -- move, never copy, so
  # the machine is not left with two installs and one of them stale.
  $stem = Split-Path -Leaf $wanted
  $stemRx = '^' + [regex]::Escape($stem) + '-(?<ver>\d+(?:\.\d+)*)$'
  $legacy = @()
  foreach ($dir in (Get-ChildItem -LiteralPath $parent -Directory -ErrorAction SilentlyContinue)) {
    if ($dir.Name -notmatch $stemRx) { continue }
    # [version] needs at least two parts, so "6" would not parse on its own.
    $text = $Matches['ver']
    while (($text -split '\.').Count -lt 2) { $text = $text + '.0' }
    $parsed = $null
    if (-not [version]::TryParse($text, [ref]$parsed)) { continue }
    $legacy += [pscustomobject]@{ Version = $parsed; Full = $dir.FullName }
  }
  if ($legacy.Count -gt 0) {
    $from = (($legacy | Sort-Object Version -Descending)[0]).Full
    Move-Item -LiteralPath $from -Destination $wanted
    # Held, not printed yet: under -ResolveOnly this script's stdout is a
    # contract -- exactly one line, the resolved path -- and a chatty notice
    # would be parsed as part of it by any caller.
    $migrationNote = '  ..  migrated version-stamped Forge install: ' + (Split-Path -Leaf $from) + ' -> ' + $stem
    $target = $wanted
    break
  }

  # Nothing installed here yet; only the default root may be created fresh.
  if ($candidate -eq $default) { $target = $wanted; break }
}
if (-not $target) { $target = $default }
if ($target -match '-\d+(?:\.\d+)*$') { throw "Refusing a version-stamped Forge install directory: $target" }
if ($ResolveOnly) { Write-Output $target; exit 0 }
if ($migrationNote) { Write-Host $migrationNote -ForegroundColor DarkCyan }

# ---- Stage the payload --------------------------------------------------
$versionFile = Join-Path $target 'VERSION.txt'
$needsExtract = $true
if (Test-Path -LiteralPath $versionFile -PathType Leaf) {
  $needsExtract = ([IO.File]::ReadAllText($versionFile) -notmatch ('(?m)^Skyrim Forge ' + [regex]::Escape($forgeVersion) + '\s*$'))
}
if ($needsExtract) {
  $base = Split-Path -Parent $target
  New-Item -ItemType Directory -Force -Path $base | Out-Null
  $stage = Join-Path $base ('.forge-stage-' + [guid]::NewGuid().ToString('N'))
  $backup = $target + '.backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
  try {
    Expand-Archive -LiteralPath $asset.FullName -DestinationPath $stage -Force
    $staged = Join-Path $stage $archiveRoot
    if (-not (Test-Path -LiteralPath (Join-Path $staged 'Install-or-Update.ps1') -PathType Leaf)) { throw 'Forge archive shape is invalid.' }
    if (-not (Test-Path -LiteralPath (Join-Path $staged 'skyrim_forge\bundle_contract.py') -PathType Leaf)) { throw 'Forge bundle contract is missing.' }
    if (Test-Path -LiteralPath $target) { Move-Item -LiteralPath $target -Destination $backup }
    try { Move-Item -LiteralPath $staged -Destination $target }
    catch {
      if ((Test-Path -LiteralPath $backup) -and -not (Test-Path -LiteralPath $target)) { Move-Item -LiteralPath $backup -Destination $target }
      throw
    }
    if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Recurse -Force }
  } finally { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
}

& (Join-Path $target 'Install-or-Update.ps1') -BootstrapPython
foreach ($provider in $Providers) {
  & (Join-Path $target 'Install-Forge-Skill.ps1') -Provider $provider
  & (Join-Path $target 'Register-MCP.ps1') -Provider $provider -Yes -ReportPath (Join-Path $target ("REGISTER-$provider.json"))
}
$python = Join-Path $target '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $python -PathType Leaf)) { throw 'Forge venv Python is missing after installation.' }
$contractRaw = (& $python -m skyrim_forge bundle-contract --bundle-version $BundleVersion 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0) { throw "Forge bundle-contract rejected bundle $BundleVersion`n$contractRaw" }
$contract = $contractRaw | ConvertFrom-Json
# `result` is the field the contract actually returns. 7.8.0 tested a field
# name that no version of Forge has ever emitted: the lookup was always
# $null, `-not $null` is always $true, so the installer threw
# "Forge reports incompatible bundle contract" on EVERY run and the AIO
# aborted the whole install on the non-zero exit. A fresh Windows install of
# 7.8.0 could not complete. Nothing caught it because no test read the
# installer and the contract source together; TESTS/test_release_contract.py
# now does exactly that.
if ($contract.result -ne 'PASS') { throw "Forge reports incompatible bundle contract for $BundleVersion`: $($contract.reason)" }
[Environment]::SetEnvironmentVariable('SKYRIM_FORGE_ROOT',$target,'User')
$env:SKYRIM_FORGE_ROOT = $target
Write-Host ("  OK  Skyrim Forge $forgeVersion compatible with bundle $BundleVersion -> $target") -ForegroundColor Green
