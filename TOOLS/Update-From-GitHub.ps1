<#
.SYNOPSIS
  Fetch latest GitHub releases for V5 AIO components into BUNDLED-TOOLS\cache (and optionally install).
#>
[CmdletBinding()]
param(
  [string[]]$Components = @('housecarl','spooky','codebase-memory','headroom','superpowers','ponytail'),
  [switch]$InstallAfter,
  [switch]$UpdateCatalogOffline
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'V6-Common.ps1')
$root = Get-V5PackRoot
$catalog = Get-V5Catalog
$cache = Join-Path $root 'BUNDLED-TOOLS\cache'
$offline = Join-Path $root 'BUNDLED-TOOLS\offline'
New-Item -ItemType Directory -Force -Path $cache | Out-Null

$results = @()
foreach ($id in $Components) {
  $comp = $catalog.components | Where-Object { $_.id -eq $id } | Select-Object -First 1
  if (-not $comp) { Write-V5Warn "Unknown component $id"; continue }
  if (-not $comp.github) { Write-V5Warn "$id has no GitHub source (manual)"; continue }
  Write-V5Step "GitHub latest: $($comp.github.owner)/$($comp.github.repo)"
  try {
    $rel = Invoke-V5GitHubLatest -Owner $comp.github.owner -Repo $comp.github.repo
    Write-V5Ok "tag $($rel.tag_name)"
    $asset = $null
    if ($comp.asset_match) { $asset = Get-V5ReleaseAsset -Release $rel -Patterns @($comp.asset_match) }
    $out = $null
    if ($asset) {
      $out = Join-Path $cache $asset.name
      Save-V5Url -Url $asset.browser_download_url -OutFile $out
      if ($UpdateCatalogOffline -and $comp.offline_asset) {
        Copy-Item $out (Join-Path $offline $comp.offline_asset) -Force
        Write-V5Ok "offline snapshot updated: $($comp.offline_asset)"
      }
    } elseif ($comp.kind -eq 'skills-plugin') {
      # zipball
      $out = Join-Path $cache "$id-$($rel.tag_name).zip"
      $zipUrl = "https://github.com/$($comp.github.owner)/$($comp.github.repo)/archive/refs/tags/$($rel.tag_name).zip"
      try { Save-V5Url -Url $zipUrl -OutFile $out }
      catch { Save-V5Url -Url $rel.zipball_url -OutFile $out }
      if ($UpdateCatalogOffline -and $comp.offline_asset) {
        Copy-Item $out (Join-Path $offline $comp.offline_asset) -Force
      }
    } else {
      Write-V5Warn "No matching asset for $id — open $($rel.html_url)"
    }
    $results += [pscustomobject]@{ id=$id; tag=$rel.tag_name; file=$out; url=$rel.html_url }
  } catch {
    Write-V5Bad "$id : $($_.Exception.Message)"
    $results += [pscustomobject]@{ id=$id; tag=$null; file=$null; error=$_.Exception.Message }
  }
}

$stateDir = Join-Path $env:LOCALAPPDATA 'Skyrim-AI-V5'
New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
$results | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $stateDir 'last-github-update.json') -Encoding UTF8
Write-Host ""
$results | Format-Table -AutoSize
if ($InstallAfter) {
  Write-V5Step "Running INSTALL-V6-AIO.ps1 -Mode BundledFirst (cache preferred via offline update)"
  & (Join-Path $root 'INSTALL-V6-AIO.ps1') -Mode BundledFirst
}
