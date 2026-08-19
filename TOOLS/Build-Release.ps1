<#
.SYNOPSIS
  Build the release zips: Core (online) and Full-Offline.

.DESCRIPTION
  Staging comes from `git archive HEAD`, not from a copy of the working tree.
  That single choice removes most of what must never ship, by construction
  rather than by a delete list applied afterwards:

    - .git/            (~200 MB) is not part of an archive
    - BUNDLED-TOOLS/cache/ (~133 MB) is gitignored, so it is never staged
    - __pycache__, .venv, .env, node_modules - same, all gitignored
    - any file the operator has locally but has not committed

  A zip of the working FOLDER carries all of it. That is the difference
  between a 470 MB folder zip and the artifacts this produces, and it is why
  the builder never copies the working tree.

  Two artifacts, because the offline payload is 135 MB of vendored installers
  that most people do not need:

    Core          everything except BUNDLED-TOOLS/offline/ - online installs
    Full-Offline  adds BUNDLED-TOOLS/offline/ - no network needed

  The forbidden-path check still runs against staging, and FAILS the build
  rather than quietly deleting: if one of these appears, something changed
  about what git tracks and that deserves a human look, not a silent fix.

.PARAMETER OutDir
  Where to write the zips. Default: dist/ under the pack root.

.PARAMETER SkipCore / -SkipOffline
  Build only one of the two.
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

# Paths that must never reach a release artifact.
$Forbidden = @(
  '.git', '.github/workflows/.env',
  'BUNDLED-TOOLS/cache',
  'node_modules', '__pycache__', '.venv', 'venv',
  'INSTALLATION.json'
)
# Bare .env only. `.env.example` is an upstream template that ships on
# purpose (ponytail has one) and carries no secrets.
$ForbiddenLeaf = @('.env', '.env.local', 'INSTALLATION.json')

function Fail([string]$m) { Write-Host "  FAIL  $m" -ForegroundColor Red; exit 1 }
function Ok([string]$m)   { Write-Host "  ok    $m" -ForegroundColor Green }
function Step([string]$m) { Write-Host ''; Write-Host "== $m" -ForegroundColor Cyan }

Push-Location $PackRoot
try {
  $version = ([IO.File]::ReadAllText((Join-Path $PackRoot 'VERSION.txt'))).Trim()
  Step "Ultimate AI Starter Bundle $version"

  # Refuse to cut a release from a dirty tree: `git archive HEAD` would ship
  # the last commit while the operator is looking at uncommitted changes, and
  # the mismatch is invisible in the artifact.
  $dirty = @(git status --porcelain 2>$null | Where-Object { $_ })
  if ($dirty.Count -gt 0) {
    Write-Host "  working tree has $($dirty.Count) uncommitted change(s):" -ForegroundColor Yellow
    $dirty | Select-Object -First 8 | ForEach-Object { Write-Host "    $_" }
    Fail 'commit or stash first - git archive would ship HEAD, not what you see'
  }
  Ok 'working tree clean'

  # The staging directory's NAME becomes the zip's single top-level folder
  # (CreateFromDirectory with includeBaseDirectory). Name it what the operator
  # should see after extracting - a random temp name would ship as
  # 'uasb-stage-c7a366c0/'.
  $stageParent = Join-Path ([IO.Path]::GetTempPath()) ('uasb-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
  $staging = Join-Path $stageParent "Ultimate-AI-Starter-Bundle-$version"
  New-Item -ItemType Directory -Force -Path $staging | Out-Null

  Step 'Staging from git archive HEAD'
  # zip, not tar: on Windows the `tar` first on PATH is frequently Git-Bash's,
  # which reads C:\... as a remote host spec and fails with "Cannot connect to
  # C: resolve failed". .NET's extractor has no such ambiguity.
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $arc = Join-Path ([IO.Path]::GetTempPath()) ('uasb-arc-' + [Guid]::NewGuid().ToString('N').Substring(0, 8) + '.zip')
  & git archive --format=zip -o $arc HEAD
  if ($LASTEXITCODE -ne 0) { Fail 'git archive failed' }
  [System.IO.Compression.ZipFile]::ExtractToDirectory($arc, $staging)
  Remove-Item -LiteralPath $arc -Force
  $staged = @(Get-ChildItem -LiteralPath $staging -Recurse -File)
  Ok ("staged {0} files" -f $staged.Count)

  Step 'Forbidden-path check'
  $hits = @()
  foreach ($f in $staged) {
    $rel = $f.FullName.Substring($staging.Length + 1) -replace '\\', '/'
    foreach ($bad in $Forbidden) {
      if ($rel -eq $bad -or $rel.StartsWith($bad + '/') -or $rel -match ('(^|/)' + [regex]::Escape($bad) + '(/|$)')) {
        $hits += $rel; break
      }
    }
    if ($ForbiddenLeaf -contains $f.Name) { $hits += $rel }
  }
  if ($hits.Count -gt 0) {
    $hits | Select-Object -Unique -First 15 | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
    Fail ("$($hits.Count) forbidden path(s) reached staging")
  }
  Ok 'no .git, cache, venv, node_modules, __pycache__, .env or INSTALLATION.json'

  New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $lvl = [System.IO.Compression.CompressionLevel]::Optimal

  function New-Zip([string]$SourceDir, [string]$ZipPath) {
    if (Test-Path -LiteralPath $ZipPath) { Remove-Item -LiteralPath $ZipPath -Force }
    [System.IO.Compression.ZipFile]::CreateFromDirectory($SourceDir, $ZipPath, $lvl, $true)
    return (Get-Item -LiteralPath $ZipPath).Length
  }

  $offlineRel = 'BUNDLED-TOOLS\offline'
  $offlineDir = Join-Path $staging $offlineRel

  if (-not $SkipOffline) {
    Step 'Full-Offline'
    if (-not (Test-Path -LiteralPath $offlineDir)) {
      Fail "BUNDLED-TOOLS/offline is not in HEAD - the offline artifact would be identical to Core"
    }
    $z = Join-Path $OutDir ("Ultimate-AI-Starter-Bundle-$version-Full-Offline.zip")
    $n = New-Zip $staging $z
    Ok ("{0}  ({1:N1} MB)" -f (Split-Path $z -Leaf), ($n / 1MB))
  }

  if (-not $SkipCore) {
    Step 'Core'
    # Same staging, minus the vendored installers.
    if (Test-Path -LiteralPath $offlineDir) {
      $offCount = @(Get-ChildItem -LiteralPath $offlineDir -Recurse -File).Count
      Remove-Item -LiteralPath $offlineDir -Recurse -Force
      Ok "dropped $offCount offline payload file(s)"
      # Leave a note so a Core user is not left wondering where it went.
      New-Item -ItemType Directory -Force -Path $offlineDir | Out-Null
      $note = @"
This is the Core package: the vendored offline installers are NOT included.

INSTALL-V7-AIO.ps1 downloads what it needs. If this machine has no network,
use Ultimate-AI-Starter-Bundle-$version-Full-Offline.zip instead, which ships
the same tree with this folder populated.
"@
      [IO.File]::WriteAllText((Join-Path $offlineDir 'README-CORE.txt'), $note,
        (New-Object System.Text.UTF8Encoding($false)))
    }
    $z = Join-Path $OutDir ("Ultimate-AI-Starter-Bundle-$version-Core.zip")
    $n = New-Zip $staging $z
    Ok ("{0}  ({1:N1} MB)" -f (Split-Path $z -Leaf), ($n / 1MB))
  }

  Remove-Item -LiteralPath $stageParent -Recurse -Force
  Step 'Done'
  Get-ChildItem -LiteralPath $OutDir -Filter '*.zip' | ForEach-Object {
    Write-Host ("  {0,-52} {1,8:N1} MB" -f $_.Name, ($_.Length / 1MB))
  }
} finally {
  Pop-Location
}
