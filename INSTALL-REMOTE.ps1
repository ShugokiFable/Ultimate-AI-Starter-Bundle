<#
.SYNOPSIS
  Ultimate AI Starter Bundle - remote one-click install from GitHub.

.DESCRIPTION
  For a FRESH machine with nothing installed. Downloads the latest (or a
  pinned) release of the Ultimate AI Starter Bundle, extracts it under
  %LOCALAPPDATA%\Ultimate-AI-Starter-Bundle, and runs the real installer
  (INSTALL-V7-AIO.ps1) from the pack root.

  One-liner (defaults = all five providers, latest release):

    powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/ShugokiFable/Ultimate-AI-Starter-Bundle/main/INSTALL-REMOTE.ps1 | iex"

  With parameters:

    powershell -NoProfile -ExecutionPolicy Bypass -Command "& ([scriptblock]::Create((irm https://raw.githubusercontent.com/ShugokiFable/Ultimate-AI-Starter-Bundle/main/INSTALL-REMOTE.ps1))) -Providers Claude,Grok -Tag v7.5.0"

  Re-running is a no-op when the bundle is already present. Use -Force to
  re-download anyway.

.PARAMETER Tag
  Release tag to fetch, e.g. 'v7.5.0'. Empty = latest release.

.PARAMETER Providers
  Providers to install for (default: installer default = all five).

.PARAMETER DestRoot
  Where the bundle lives. Default: %LOCALAPPDATA%\Ultimate-AI-Starter-Bundle.

.PARAMETER Force
  Re-download even when a usable copy already exists at DestRoot.

.PARAMETER SkipPreamble
  Forwarded to INSTALL-V7-AIO.ps1 - do not wire the SOUL/AIO preamble blocks.

.PARAMETER SkipHouseCarlSetup
  Forwarded to INSTALL-V7-AIO.ps1 - skip houseCARL MO2/Vortex setup.

.PARAMETER KeepZip
  Keep the downloaded release zip in %TEMP% instead of deleting it.
#>
[CmdletBinding()]
param(
  [string]$Tag = '',
  [string[]]$Providers = @(),
  [string]$DestRoot = (Join-Path $env:LOCALAPPDATA 'Ultimate-AI-Starter-Bundle'),
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

# ---------- 2. Reuse existing copy ----------
$dest = Join-Path $DestRoot $tag
$catalog = Join-Path $dest 'BUNDLED-TOOLS\CATALOG.json'
if (-not $Force -and (Test-Path -LiteralPath $catalog)) {
  Ok ("bundle $tag already at $dest - reusing it (-Force to re-download)")
} else {
  # ---------- 3. Download ----------
  Step "Downloading $tag"
  $zip = Join-Path $env:TEMP ("Ultimate-AI-Starter-Bundle-" + $tag + '.zip')
  try {
    $rel = Invoke-RestMethod -Uri "$Api/releases/tags/$tag" -Headers $H -TimeoutSec 60
    $asset = @($rel.assets | Where-Object { $_.name -like '*.zip' }) | Select-Object -First 1
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
    New-Item -ItemType Directory -Force -Path $DestRoot | Out-Null
    if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
    Move-Item -LiteralPath $root -Destination $dest
    Ok ("bundle -> $dest")
  } finally {
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    if (-not $KeepZip) { Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue }
  }
}

# ---------- 5. Run the real installer ----------
$installer = Join-Path $dest 'INSTALL-V7-AIO.ps1'
if (-not (Test-Path -LiteralPath $installer)) { Fail "installer missing: $installer" }
$args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $installer)
if ($Providers -and $Providers.Count -gt 0) { $args += '-Providers', ($Providers -join ',') }
if ($SkipPreamble) { $args += '-SkipPreamble' }
if ($SkipHouseCarlSetup) { $args += '-SkipHouseCarlSetup' }
Step "Running installer from $dest"
& powershell @args
if ($LASTEXITCODE -ne 0) { Warn ('installer exit code: ' + $LASTEXITCODE) }

Write-Host ''
Write-Host '=====================================================' -ForegroundColor Green
Write-Host ' DONE. Fully restart every AI app you use.' -ForegroundColor Green
Write-Host ' Bundle: ' + $dest -ForegroundColor Green
Write-Host ' Update later: cd to the bundle and run TOOLS\Update-From-GitHub.ps1' -ForegroundColor Green
Write-Host '=====================================================' -ForegroundColor Green