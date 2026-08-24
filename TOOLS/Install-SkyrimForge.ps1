<#
.SYNOPSIS
  Install Skyrim Forge from this pack's source tree and prove it runs.

.DESCRIPTION
  Forge is not a downloaded third-party payload any more. Its source lives in
  this repository at BUNDLED-TOOLS\skyrim-forge, so what gets installed is
  whatever this commit contains -- there is no separately released archive that
  can drift out from under the installer.

  That merge fixed a specific failure. Bundle 7.8.0 ended this script with
  `if (-not $contract.compatible) { throw }`. Forge has never emitted a
  `compatible` field, `-not $null` is `$true`, so it threw on EVERY run and
  The previous AIO aborted the whole install on the non-zero exit. Two files that
  had to agree, in two repositories, with no single commit that could test both.

  The install directory carries NO version suffix, and that is the whole point.

  Every provider stores an MCP server command as a hard absolute path: Claude
  JSON, Kimi JSON, Codex TOML, Grok TOML, Hermes YAML. A version-stamped
  install directory renames itself on every upgrade, so each upgrade silently
  disconnects whichever configs were not rewritten -- and the failure is quiet,
  because a provider that cannot spawn its MCP server just shows no tools.

  Observed on the live machine before 7.9.0: SKYRIM_FORGE_ROOT pointed at
  Skyrim-Forge-5.1.6 (deleted), all five provider configs pointed at
  Skyrim-Forge (never created), and the actual install was version-stamped with
  no virtualenv. Three paths, no two agreeing, MCP dead everywhere.

  So: the SOURCE keeps its version in VERSION.txt (provenance), the INSTALL
  DIRECTORY never does (stability), and an existing version-stamped install is
  migrated onto the versionless name instead of being duplicated beside it.
#>
[CmdletBinding()]
param(
  [string]$PackRoot,
  # The directory Forge is installed INTO -- the same thing
  # SKYRIM_FORGE_ROOT names, e.g. 'S:\Apps\Skyrim Tools\Skyrim-Forge', not
  # the tools folder that contains it. Highest precedence: a caller that
  # names a root means it, even if nothing is there yet. Without it, an
  # existing install or SKYRIM_FORGE_ROOT wins, and failing all of that it
  # goes under LOCALAPPDATA, which needs no admin rights and assumes no
  # drive letter.
  [string]$ForgeRoot,
  [string[]]$Providers = @('Claude','Codex','Grok','Kimi','Hermes'),
  # In the all-in-one bundle, provider skill content is owned by the bundle's
  # tailored trees. Forge may add its per-machine INSTALLATION.json descriptor
  # but must not replace that bundle-owned Forge skill with a second copy.
  [switch]$BundleOwnsProviderSkills,
  # Resolve and print the install root, migrate a version-stamped install if one
  # is found, then stop. Path resolution is the part that has broken repeatedly,
  # so it has to be runnable on its own -- TESTS/Test-ForgeRootResolution.ps1
  # drives this switch against synthetic layouts.
  [switch]$ResolveOnly
)
$ErrorActionPreference = 'Stop'
if (-not $PackRoot) { $PackRoot = Split-Path -Parent $PSScriptRoot }
$Providers = @($Providers | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })

# The source tree names the version in exactly one place; nothing here restates
# it. Bump BUNDLED-TOOLS\skyrim-forge\VERSION.txt and this follows.
$source = Join-Path $PackRoot 'BUNDLED-TOOLS\skyrim-forge'
if (-not (Test-Path -LiteralPath (Join-Path $source 'Install-or-Update.ps1') -PathType Leaf)) {
  throw "Bundled Forge source is missing or incomplete: $source"
}
$versionText = [IO.File]::ReadAllText((Join-Path $source 'VERSION.txt'))
if ($versionText -notmatch '(?m)^Skyrim Forge\s+(?<ver>\d+\.\d+\.\d+)\s*$') {
  throw "Cannot read a version from $source\VERSION.txt"
}
$forgeVersion = $Matches['ver']

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

# Process env before the persisted User value: a caller that exported
# SKYRIM_FORGE_ROOT for this run means it, and the persisted value is normally
# the same string anyway. It also keeps the resolver testable without writing to
# the user's registry.
$declared = $env:SKYRIM_FORGE_ROOT
if (-not $declared) { $declared = [Environment]::GetEnvironmentVariable('SKYRIM_FORGE_ROOT', 'User') }
$default = Join-Path (Join-Path $env:LOCALAPPDATA 'Skyrim-Tools') 'Skyrim-Forge'

# An explicitly named root is a decision, not a guess, so its parent is created
# rather than skipped. The other candidates must already exist to be considered.
if ($ForgeRoot) {
  $explicit = Get-VersionlessRoot $ForgeRoot
  # The natural mistake is to pass the tools FOLDER ('S:\Apps\Skyrim Tools')
  # instead of the install directory inside it. That is a directory full of
  # someone else's tools, and this installer replaces the directory it is
  # given. Say so instead of scattering Forge across xEdit.
  $marks = @('Install-or-Update.ps1', 'VERSION.txt', 'skyrim_forge', '.venv', 'Workspaces')
  if ((Test-Path -LiteralPath $explicit -PathType Container) -and
      -not (@($marks | Where-Object { Test-Path -LiteralPath (Join-Path $explicit $_) }).Count) -and
      @(Get-ChildItem -LiteralPath $explicit -Force).Count -gt 0) {
    throw "-ForgeRoot is the directory Forge is installed INTO, and '$explicit' already holds other files. Use '$(Join-Path $explicit 'Skyrim-Forge')'."
  }
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $explicit) | Out-Null
}

$target = $null
$migrationNote = $null
foreach ($candidate in @($ForgeRoot, $declared, $default)) {
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

  # Nothing installed here yet. A named root and the default may be created
  # fresh; a stale SKYRIM_FORGE_ROOT pointing at nothing should not be.
  if ($candidate -eq $ForgeRoot -or $candidate -eq $default) { $target = $wanted; break }
}
if (-not $target) { $target = $default }
if ($target -match '-\d+(?:\.\d+)*$') { throw "Refusing a version-stamped Forge install directory: $target" }
if ($ResolveOnly) { Write-Output $target; exit 0 }
if ($migrationNote) { Write-Host $migrationNote -ForegroundColor DarkCyan }

# ---- Stage the source tree ----------------------------------------------
# Job staging defaults to <install root>\Workspaces, so a replace-in-place that
# deleted the old directory would delete the user's mod work with it. These
# survive an upgrade; everything else is shipped content and is replaced.
$preserve = @('Workspaces', '.venv', 'REPORTS', 'config.toml')

# VERSION.txt alone is not an upgrade key. v7.9.1 ships Forge as in-tree source,
# and a bundle hotfix may legitimately change Forge scripts while keeping the
# product version at 6.0.0. If we gate refreshes only on VERSION.txt, the AIO can
# package a fixed Register-MCP.ps1 and then execute an older live copy forever.
# Compare the live shipped tree against the source MANIFEST instead. This also
# repairs a locally modified/missing shipped file without touching user state.
function Test-ForgeShippedContentCurrent {
  param([string]$SourceRoot, [string]$InstalledRoot)
  if (-not (Test-Path -LiteralPath $InstalledRoot -PathType Container)) { return $false }
  $sourceManifestPath = Join-Path $SourceRoot 'MANIFEST.json'
  $installedManifestPath = Join-Path $InstalledRoot 'MANIFEST.json'
  if (-not (Test-Path -LiteralPath $sourceManifestPath -PathType Leaf)) { throw "Bundled Forge MANIFEST.json missing: $sourceManifestPath" }
  if (-not (Test-Path -LiteralPath $installedManifestPath -PathType Leaf)) { return $false }

  $sourceManifestHash = (Get-FileHash -LiteralPath $sourceManifestPath -Algorithm SHA256).Hash
  $installedManifestHash = (Get-FileHash -LiteralPath $installedManifestPath -Algorithm SHA256).Hash
  if ($sourceManifestHash -ine $installedManifestHash) { return $false }

  $manifest = [IO.File]::ReadAllText($sourceManifestPath) | ConvertFrom-Json
  foreach ($entry in @($manifest.files)) {
    $relative = ([string]$entry.path) -replace '/', '\'
    $installedFile = Join-Path $InstalledRoot $relative
    if (-not (Test-Path -LiteralPath $installedFile -PathType Leaf)) { return $false }
    if ((Get-Item -LiteralPath $installedFile).Length -ne [long]$entry.size) { return $false }
    $actualHash = (Get-FileHash -LiteralPath $installedFile -Algorithm SHA256).Hash
    if ($actualHash -ine [string]$entry.sha256) { return $false }
  }
  return $true
}

$refreshRequired = -not (Test-ForgeShippedContentCurrent -SourceRoot $source -InstalledRoot $target)
if ($refreshRequired) {
  Write-Host '  .. Skyrim Forge shipped content differs from this bundle; refreshing source tree (same-version hotfixes included)' -ForegroundColor DarkCyan
  $base = Split-Path -Parent $target
  New-Item -ItemType Directory -Force -Path $base | Out-Null
  $stage = Join-Path $base ('.forge-stage-' + [guid]::NewGuid().ToString('N'))
  $backup = $target + '.backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
  try {
    Copy-Item -LiteralPath $source -Destination $stage -Recurse -Force
    if (-not (Test-Path -LiteralPath (Join-Path $stage 'Install-or-Update.ps1') -PathType Leaf)) { throw 'Staged Forge tree is incomplete.' }
    if (Test-Path -LiteralPath $target -PathType Container) {
      foreach ($keep in $preserve) {
        $from = Join-Path $target $keep
        if (-not (Test-Path -LiteralPath $from)) { continue }
        $to = Join-Path $stage $keep
        if (Test-Path -LiteralPath $to) { Remove-Item -LiteralPath $to -Recurse -Force }
        Move-Item -LiteralPath $from -Destination $to
      }
      Move-Item -LiteralPath $target -Destination $backup
    }
    try { Move-Item -LiteralPath $stage -Destination $target }
    catch {
      if ((Test-Path -LiteralPath $backup) -and -not (Test-Path -LiteralPath $target)) { Move-Item -LiteralPath $backup -Destination $target }
      throw
    }
    if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Recurse -Force }
  } finally { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
} else {
  Write-Host '  OK  Skyrim Forge shipped content already matches this bundle exactly' -ForegroundColor Green
}

& (Join-Path $target 'Install-or-Update.ps1') -BootstrapPython

$bundleCatalog = $null
if ($BundleOwnsProviderSkills) {
  $commonPath = Join-Path $PackRoot 'TOOLS\UABS-Common.ps1'
  $catalogPath = Join-Path $PackRoot 'BUNDLED-TOOLS\CATALOG.json'
  if (-not (Test-Path -LiteralPath $commonPath -PathType Leaf)) { throw "Bundle common helpers missing: $commonPath" }
  if (-not (Test-Path -LiteralPath $catalogPath -PathType Leaf)) { throw "Bundle catalog missing: $catalogPath" }
  . $commonPath
  $bundleCatalog = [IO.File]::ReadAllText($catalogPath) | ConvertFrom-Json
}

foreach ($provider in $Providers) {
  if ($BundleOwnsProviderSkills) {
    # The all-in-one bundle already installed the canonical skill. Preserve that
    # single writer and add only Forge's per-machine launch descriptor beside it.
    $providerHome = Get-UabsProviderHome -Provider $provider -Catalog $bundleCatalog
    $providerSkill = Join-Path $providerHome 'skills\skyrim-forge'
    $providerSkillMd = Join-Path $providerSkill 'SKILL.md'
    if (-not (Test-Path -LiteralPath $providerSkillMd -PathType Leaf)) {
      throw "Expected bundle-owned Forge skill is missing for ${provider}: $providerSkillMd"
    }
    $descriptorSource = Join-Path $target 'INSTALLATION.json'
    if (-not (Test-Path -LiteralPath $descriptorSource -PathType Leaf)) {
      throw "Forge installation descriptor missing after install: $descriptorSource"
    }
    Copy-Item -LiteralPath $descriptorSource -Destination (Join-Path $providerSkill 'INSTALLATION.json') -Force
    Write-Host ("  OK  {0}: bundle-owned Forge skill preserved; descriptor refreshed" -f $provider) -ForegroundColor Green
  } else {
    & (Join-Path $target 'Install-Forge-Skill.ps1') -Provider $provider
  }
  & (Join-Path $target 'Register-MCP.ps1') -Provider $provider -Yes -ReportPath (Join-Path $target ("REGISTER-$provider.json"))
}

# ---- Prove it actually runs ---------------------------------------------
# Not a version handshake. Forge and this installer ship in the same commit, so
# a negotiated compatibility range between them cannot fail for a real reason --
# it can only go stale and start rejecting the pack it lives inside, which is
# one edit away from the 7.8.0 bug. `doctor` answers a question that can still
# genuinely be no: does this install run, find its native helper, and read its
# config? TESTS/test_release_contract.py checks that every field read below is
# one Forge actually emits.
$python = Join-Path $target '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $python -PathType Leaf)) { throw 'Forge venv Python is missing after installation.' }
$installedText = [IO.File]::ReadAllText((Join-Path $target 'VERSION.txt'))
if ($installedText -notmatch ('(?m)^Skyrim Forge\s+' + [regex]::Escape($forgeVersion) + '\s*$')) {
  throw "Installed Forge is not the version this pack ships ($forgeVersion): $target"
}
$prevEap=$ErrorActionPreference; $ErrorActionPreference='Continue'
$doctorRaw = (& $python -m skyrim_forge doctor 2>&1 | Out-String)
$ErrorActionPreference=$prevEap
if ($LASTEXITCODE -ne 0) { throw "Forge doctor failed after installation.`n$doctorRaw" }
$doctor = $doctorRaw | ConvertFrom-Json
if ($doctor.result -ne 'PASS') { throw "Forge doctor reports $($doctor.result) after installation.`n$doctorRaw" }
if (-not $doctor.read_only_ready) { throw "Forge installed but is not read-only ready.`n$doctorRaw" }

[Environment]::SetEnvironmentVariable('SKYRIM_FORGE_ROOT',$target,'User')
$env:SKYRIM_FORGE_ROOT = $target
Write-Host ("  OK  Skyrim Forge $forgeVersion installed and healthy -> $target") -ForegroundColor Green
