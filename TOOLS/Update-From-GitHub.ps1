<#
.SYNOPSIS
  Update the stable bundle installation and re-run the AIO installer.
#>
[CmdletBinding()]
param(
  [string[]]$Components = @('housecarl','spooky','codebase-memory','headroom','superpowers','ponytail'),
  [ValidateSet('Claude','Codex','Grok','Kimi','Hermes')]
  [string[]]$Providers = @('Claude','Codex','Grok','Kimi','Hermes'),
  [switch]$ComponentsOnly,
  [switch]$InstallAfter,
  [switch]$UpdateCatalogOffline
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'UABS-Common.ps1')
$root = Get-UabsPackRoot
$catalog = Get-UabsCatalog

if (-not $ComponentsOnly) {
  $remote = Join-Path $root 'INSTALL-REMOTE.ps1'
  if (-not (Test-Path -LiteralPath $remote -PathType Leaf)) { throw 'INSTALL-REMOTE.ps1 missing from pack.' }
  Write-UabsStep 'Updating stable bundle installation, plugins, skills, MCPs, and tools'
  & (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File $remote -Providers ($Providers -join ',')
  if ($LASTEXITCODE -ne 0) { throw "bundle update failed with exit code $LASTEXITCODE" }
  return
}

$cache = Join-Path $root 'BUNDLED-TOOLS\cache'
$offline = Join-Path $root 'BUNDLED-TOOLS\offline'
New-Item -ItemType Directory -Force -Path $cache | Out-Null

$results = @()
foreach ($id in $Components) {
  $comp = $catalog.components | Where-Object { $_.id -eq $id } | Select-Object -First 1
  if (-not $comp) { Write-UabsWarn "Unknown component $id"; continue }
  if (-not $comp.github) { Write-UabsWarn "$id has no GitHub source (manual)"; continue }
  Write-UabsStep "GitHub latest: $($comp.github.owner)/$($comp.github.repo)"
  try {
    $rel = Invoke-UabsGitHubLatest -Owner $comp.github.owner -Repo $comp.github.repo
    Write-UabsOk "tag $($rel.tag_name)"
    $asset = $null
    if ($comp.asset_match) { $asset = Get-UabsReleaseAsset -Release $rel -Patterns @($comp.asset_match) }
    $out = $null
    if ($asset) {
      $out = Join-Path $cache $asset.name
      [void](Save-UabsReleaseAsset -Asset $asset -OutFile $out)
      if ($UpdateCatalogOffline -and $comp.offline_asset) {
        Copy-Item $out (Join-Path $offline $comp.offline_asset) -Force
        Write-UabsOk "offline snapshot updated: $($comp.offline_asset)"
      }
    } elseif ($comp.kind -eq 'skills-plugin') {
      # zipball
      $out = Join-Path $cache "$id-$($rel.tag_name).zip"
      $zipUrl = "https://github.com/$($comp.github.owner)/$($comp.github.repo)/archive/refs/tags/$($rel.tag_name).zip"
      try { Save-UabsUrl -Url $zipUrl -OutFile $out }
      catch { Save-UabsUrl -Url $rel.zipball_url -OutFile $out }
      if ($UpdateCatalogOffline -and $comp.offline_asset) {
        Copy-Item $out (Join-Path $offline $comp.offline_asset) -Force
      }
    } else {
      Write-UabsWarn "No matching asset for $id — open $($rel.html_url)"
    }
    $results += [pscustomobject]@{ id=$id; tag=$rel.tag_name; file=$out; url=$rel.html_url }
  } catch {
    Write-UabsBad "$id : $($_.Exception.Message)"
    $results += [pscustomobject]@{ id=$id; tag=$null; file=$null; error=$_.Exception.Message }
  }
}

$stateDir = Join-Path $env:LOCALAPPDATA 'Ultimate-AI-Starter-Bundle'
New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
$results | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $stateDir 'last-github-update.json') -Encoding UTF8
Write-Host ""
$results | Format-Table -AutoSize
if ($InstallAfter) {
  Write-UabsStep "Running INSTALL-AIO.ps1 -Mode OnlineLatest"
  & (Join-Path $root 'INSTALL-AIO.ps1') -Mode OnlineLatest
}
