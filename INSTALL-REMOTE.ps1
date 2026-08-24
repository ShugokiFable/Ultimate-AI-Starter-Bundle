<#
.SYNOPSIS
  Ultimate AI Starter Bundle - remote one-click install from GitHub.

.DESCRIPTION
  For a FRESH machine with nothing installed. Downloads the latest (or a
  pinned) release of the Ultimate AI Starter Bundle, atomically installs it at
  %LOCALAPPDATA%\Programs\Ultimate-AI-Starter-Bundle, and runs the real installer
  (INSTALL-AIO.ps1) from the pack root.

  One-liner (defaults = all five providers, latest release):

    powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/ShugokiFable/Ultimate-AI-Starter-Bundle/main/INSTALL-REMOTE.ps1 | iex"

  With parameters:

    powershell -NoProfile -ExecutionPolicy Bypass -Command "& ([scriptblock]::Create((irm https://raw.githubusercontent.com/ShugokiFable/Ultimate-AI-Starter-Bundle/main/INSTALL-REMOTE.ps1))) -Providers Claude,Grok"

  Re-running updates the stable install when the release tag changes. Use
  -Force to refresh the same tag.

.PARAMETER Tag
  Release tag to fetch, e.g. 'v8.0.0'. Empty (default) = latest release.

.PARAMETER Providers
  Providers to install for (default: installer default = all five).

.PARAMETER DestRoot
  Where the bundle lives. Default:
  %LOCALAPPDATA%\Programs\Ultimate-AI-Starter-Bundle.

.PARAMETER Force
  Re-download even when a usable copy already exists at DestRoot.

.PARAMETER SkipPreamble
  Forwarded to INSTALL-AIO.ps1 - do not wire the SOUL/AIO preamble blocks.

.PARAMETER SkipHouseCarlSetup
  Forwarded to INSTALL-AIO.ps1 - skip houseCARL MO2/Vortex setup.

.PARAMETER KeepZip
  Keep the downloaded release zip in %TEMP% instead of deleting it.
#>
[CmdletBinding()]
param(
  [string]$Tag = '',
  [string[]]$Providers = @(),
  [string]$DestRoot = (Join-Path $env:LOCALAPPDATA 'Programs\Ultimate-AI-Starter-Bundle'),
  [switch]$Force,
  [switch]$SkipPreamble,
  [switch]$SkipHouseCarlSetup,
  [switch]$KeepZip
)

$ErrorActionPreference = 'Stop'
$Owner = 'ShugokiFable'
$Repo = 'Ultimate-AI-Starter-Bundle'
$Api = "https://api.github.com/repos/$Owner/$Repo"
$H = @{ 'User-Agent' = 'Ultimate-AI-Starter-Bundle/remote-installer' }

function Fail([string]$m) { Write-Host ('XX  ' + $m) -ForegroundColor Red; exit 1 }
function Step([string]$m) { Write-Host ('==> ' + $m) -ForegroundColor Cyan }
function Ok([string]$m)   { Write-Host ('  OK  ' + $m) -ForegroundColor Green }
function Warn([string]$m) { Write-Host ('  !!  ' + $m) -ForegroundColor Yellow }

Write-Host ''
Write-Host '=====================================================' -ForegroundColor Magenta
Write-Host ' Ultimate AI Starter Bundle - REMOTE INSTALLER' -ForegroundColor Magenta
Write-Host '=====================================================' -ForegroundColor Magenta
Write-Host ''

# ---------- 1. Resolve release ----------
$tag = $Tag
if (-not $tag) {
  Step 'Resolving latest release tag'
  try {
    $rel = Invoke-RestMethod -Uri "$Api/releases/latest" -Headers $H -TimeoutSec 60
    $tag = [string]$rel.tag_name
  } catch {
    Fail ("Cannot reach GitHub API: " + $_.Exception.Message)
  }
  if (-not $tag) { Fail 'Latest release returned no tag.' }
  Ok "latest release: $tag"
} else {
  if ($tag -notmatch '^v?[0-9]') { Fail "Tag '$tag' does not look like a version tag." }
  if (-not $tag.StartsWith('v')) { $tag = 'v' + $tag }
  Ok "pinned tag: $tag"
}

# ---------- 2. Reuse current stable copy ----------
$dest = $DestRoot
$catalog = Join-Path $dest 'BUNDLED-TOOLS\CATALOG.json'
$installedVersion = ''
$versionFile = Join-Path $dest 'VERSION.txt'
if (Test-Path -LiteralPath $versionFile -PathType Leaf) { $installedVersion = ([IO.File]::ReadAllText($versionFile)).Trim() }
if (-not $Force -and (Test-Path -LiteralPath $catalog) -and $installedVersion -eq $tag) {
  Ok ("bundle $tag already current at $dest - reusing it (-Force to refresh)")
} else {
  # ---------- 3. Download ----------
  Step "Downloading $tag"
  $zip = Join-Path $env:TEMP ("Ultimate-AI-Starter-Bundle-" + $tag + '.zip')
  try {
    $rel = Invoke-RestMethod -Uri "$Api/releases/tags/$tag" -Headers $H -TimeoutSec 60
    # Prefer the self-contained release deterministically. GitHub asset order is
    # not an API contract; selecting the first ZIP could silently choose Core.
    $asset = @($rel.assets | Where-Object { $_.name -like '*-Full-Offline.zip' }) | Select-Object -First 1
    if (-not $asset) { $asset = @($rel.assets | Where-Object { $_.name -like '*-Core.zip' }) | Select-Object -First 1 }
    if (-not $asset) { $asset = @($rel.assets | Where-Object { $_.name -like '*.zip' }) | Select-Object -First 1 }
    if ($asset) {
      Ok ("release asset: " + $asset.name)
      Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -Headers $H -TimeoutSec 1800
    } else {
      Warn 'no zip asset on the release - falling back to the source archive'
      Invoke-WebRequest -Uri "https://codeload.github.com/$Owner/$Repo/zip/refs/tags/$tag" -OutFile $zip -Headers $H -TimeoutSec 1800
    }
  } catch {
    Fail ("download failed: " + $_.Exception.Message)
  }
  if (-not (Test-Path -LiteralPath $zip) -or (Get-Item $zip).Length -lt 10000) {
    Fail 'downloaded archive is missing or empty'
  }
  Ok ("downloaded {0:N1} MB" -f ((Get-Item $zip).Length / 1MB))

  # ---------- 4. Extract ----------
  Step 'Extracting'
  $stage = Join-Path $env:TEMP ("uabs-$tag-" + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path $stage | Out-Null
  try {
    Expand-Archive -LiteralPath $zip -DestinationPath $stage -Force
    $kids = @(Get-ChildItem -LiteralPath $stage -Force | Where-Object { $_.Name -ne '__MACOSX' })
    $root = $stage
    if ($kids.Count -eq 1 -and $kids[0].PSIsContainer) { $root = $kids[0].FullName }
    if (-not (Test-Path (Join-Path $root 'BUNDLED-TOOLS\CATALOG.json'))) {
      Fail 'extracted archive does not look like the bundle (no BUNDLED-TOOLS\CATALOG.json)'
    }
    $extractedVersionFile = Join-Path $root 'VERSION.txt'
    if (-not (Test-Path -LiteralPath $extractedVersionFile -PathType Leaf)) { Fail 'extracted archive has no VERSION.txt' }
    $extractedVersion = ([IO.File]::ReadAllText($extractedVersionFile)).Trim()
    if ($extractedVersion -ne $tag) { Fail "archive version $extractedVersion does not match requested tag $tag" }

    $destParent = Split-Path -Parent $dest
    New-Item -ItemType Directory -Force -Path $destParent | Out-Null
    $previous = $dest + '.previous'
    if (Test-Path -LiteralPath $previous) {
      if (-not (Test-Path -LiteralPath (Join-Path $previous 'BUNDLED-TOOLS\CATALOG.json'))) {
        Fail "refusing to delete unrecognized rollback directory: $previous"
      }
      Remove-Item -LiteralPath $previous -Recurse -Force
    }
    if (Test-Path -LiteralPath $dest) { Move-Item -LiteralPath $dest -Destination $previous }
    try {
      Move-Item -LiteralPath $root -Destination $dest
    } catch {
      if ((Test-Path -LiteralPath $previous) -and -not (Test-Path -LiteralPath $dest)) {
        Move-Item -LiteralPath $previous -Destination $dest
      }
      throw
    }
    Ok ("bundle -> $dest")
  } finally {
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    if (-not $KeepZip) { Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue }
  }
}

# ---------- 5. Run the real installer ----------
$installer = Join-Path $dest 'INSTALL-AIO.ps1'
if (-not (Test-Path -LiteralPath $installer)) { Fail "installer missing: $installer" }
$args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $installer)
if ($Providers -and $Providers.Count -gt 0) { $args += '-Providers', ($Providers -join ',') }
if ($SkipPreamble) { $args += '-SkipPreamble' }
if ($SkipHouseCarlSetup) { $args += '-SkipHouseCarlSetup' }
Step "Running installer from $dest"
& powershell @args
if ($LASTEXITCODE -ne 0) { Fail ('installer exit code: ' + $LASTEXITCODE) }

# V7 remote installs used version-named children inside the state directory.
# Delete only children that carry the bundle catalog marker.
$legacyRoot = Join-Path $env:LOCALAPPDATA 'Ultimate-AI-Starter-Bundle'
if (Test-Path -LiteralPath $legacyRoot -PathType Container) {
  foreach ($legacy in @(Get-ChildItem -LiteralPath $legacyRoot -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^v\d' })) {
    if (Test-Path -LiteralPath (Join-Path $legacy.FullName 'BUNDLED-TOOLS\CATALOG.json')) {
      Remove-Item -LiteralPath $legacy.FullName -Recurse -Force
      Ok ('removed obsolete version-stamped bundle: ' + $legacy.FullName)
    }
  }
}

Write-Host ''
Write-Host '=====================================================' -ForegroundColor Green
Write-Host ' DONE. Fully restart every AI app you use.' -ForegroundColor Green
Write-Host ' Bundle: ' + $dest -ForegroundColor Green
Write-Host ' Update later: run TOOLS\Update-From-GitHub.ps1' -ForegroundColor Green
Write-Host '=====================================================' -ForegroundColor Green
