<#
.SYNOPSIS
  Regression gate for GitHub release assets whose filenames are reused.
#>
[CmdletBinding()]
param([string]$PackRoot)

$ErrorActionPreference = 'Stop'
if (-not $PackRoot) { $PackRoot = Split-Path -Parent $PSScriptRoot }
. (Join-Path $PackRoot 'TOOLS\UABS-Common.ps1')

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('uabs-release-cache-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $scratch | Out-Null
try {
  $good = [byte[]](0..31)
  $stale = [byte[]](31..0)
  $dest = Join-Path $scratch 'tool.zip'
  $source = Join-Path $scratch 'source.bin'
  [IO.File]::WriteAllBytes($source, $good)
  $sha = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
  $asset = [pscustomobject]@{
    name = 'tool.zip'
    size = $good.Length
    digest = 'sha256:' + $sha
    browser_download_url = 'test://tool.zip'
  }

  # Same filename and same byte count is still stale when the digest differs.
  [IO.File]::WriteAllBytes($dest, $stale)
  if (Test-UabsReleaseAssetFile -Asset $asset -Path $dest -RequireDigest) {
    throw 'same-size stale cache passed digest validation'
  }
  [IO.File]::WriteAllBytes($dest, [byte[]](1,2,3))
  if (Test-UabsReleaseAssetFile -Asset $asset -Path $dest -RequireDigest) {
    throw 'wrong-size cache passed validation'
  }
  [IO.File]::WriteAllBytes($dest, $good)
  if (-not (Test-UabsReleaseAssetFile -Asset $asset -Path $dest -RequireDigest)) {
    throw 'exact release asset failed validation'
  }

  $withoutDigest = [pscustomobject]@{ name='tool.zip'; size=$good.Length }
  if (Test-UabsReleaseAssetFile -Asset $withoutDigest -Path $dest -RequireDigest) {
    throw 'cache without an authoritative digest was reused'
  }
  if (-not (Test-UabsReleaseAssetFile -Asset $withoutDigest -Path $dest)) {
    throw 'fresh size-validated download without a published digest was rejected'
  }
  $badDigest = [pscustomobject]@{ name='tool.zip'; size=$good.Length; digest='sha256:not-a-hash' }
  if (Test-UabsReleaseAssetFile -Asset $badDigest -Path $dest) {
    throw 'malformed published digest was ignored'
  }

  # Replace the network primitive so the shared saver can be tested without a
  # network dependency. A stale destination must refresh once, then be reused.
  $script:testPayload = $good
  $script:testDownloads = 0
  function Save-UabsUrl {
    param([string]$Url, [string]$OutFile)
    $script:testDownloads++
    [IO.File]::WriteAllBytes($OutFile, $script:testPayload)
  }
  [IO.File]::WriteAllBytes($dest, $stale)
  [void](Save-UabsReleaseAsset -Asset $asset -OutFile $dest -ReuseValid)
  if ($script:testDownloads -ne 1 -or -not (Test-UabsReleaseAssetFile -Asset $asset -Path $dest -RequireDigest)) {
    throw 'stale cache was not replaced by the validated release asset'
  }
  [void](Save-UabsReleaseAsset -Asset $asset -OutFile $dest -ReuseValid)
  if ($script:testDownloads -ne 1) { throw 'validated cache was downloaded again' }

  # A bad new download must never destroy the last known-good cached copy.
  $script:testPayload = $stale
  $failed = $false
  try { [void](Save-UabsReleaseAsset -Asset $asset -OutFile $dest) } catch { $failed = $true }
  if (-not $failed) { throw 'invalid replacement download was accepted' }
  if (-not (Test-UabsReleaseAssetFile -Asset $asset -Path $dest -RequireDigest)) {
    throw 'invalid replacement destroyed the last known-good cache'
  }

  Write-Output 'RELEASE ASSET CACHE GATE: PASS'
} finally {
  Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}
