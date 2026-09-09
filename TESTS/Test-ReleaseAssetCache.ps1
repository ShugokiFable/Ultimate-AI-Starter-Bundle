<#
.SYNOPSIS
  Regression gate for GitHub release assets whose filenames are reused.
#>
[CmdletBinding()]
param([string]$PackRoot)

$ErrorActionPreference = 'Stop'
if (-not $PackRoot) { $PackRoot = Split-Path -Parent $PSScriptRoot }
. (Join-Path $PackRoot 'TOOLS\UABS-Common.ps1')
$rtkArchive = Join-Path $PackRoot 'BUNDLED-TOOLS\offline\rtk-x86_64-pc-windows-msvc.zip'

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

  # Exercise the installer's real selector without running the installer.
  $tokens = $null; $errors = $null
  $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PackRoot 'INSTALL-AIO.ps1'), [ref]$tokens, [ref]$errors)
  if ($errors.Count) { throw $errors[0] }
  $selector = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-ComponentAssetPath' }, $true)
  . ([scriptblock]::Create($selector.Extent.Text))
  $PackRoot = $scratch
  $cache = Join-Path $scratch 'cache'; $offline = Join-Path $scratch 'offline'
  New-Item -ItemType Directory -Force -Path $cache,$offline,(Join-Path $scratch 'BUNDLED-TOOLS') | Out-Null
  $manifestPath = Join-Path $scratch 'BUNDLED-TOOLS\OFFLINE-MANIFEST.json'
  $comp = [pscustomobject]@{ id='rtk'; version='0.47.0'; github=@{owner='rtk-ai';repo='rtk'}; offline_asset='tool.zip'; asset_match=@('tool.zip') }
  $script:testPayload = $good
  $script:testUris = @(); $script:testOffline = $false; $script:testTag = 'v0.47.0'
  function Invoke-RestMethod {
    param($Uri, $Headers, $TimeoutSec)
    $script:testUris += $Uri
    if ($script:testOffline) { throw 'fixture network unavailable' }
    # A newer release exists, but is outside this bundle's measured pin.
    if ($Uri -like '*/latest') { return @{tag_name='v0.48.0';assets=@()} }
    return @{tag_name=$script:testTag;assets=@($asset)}
  }
  [IO.File]::WriteAllText($manifestPath, '{"assets":[]}') # Core has no offline RTK.
  [IO.File]::WriteAllBytes((Join-Path $cache 'tool.zip'), $stale)
  foreach ($Mode in @('OnlineLatest', 'BundledFirst')) {
    $selected = Get-ComponentAssetPath -Comp $comp
    if (-not (Test-UabsReleaseAssetFile -Asset $asset -Path $selected -RequireDigest)) { throw "$Mode selected stale RTK" }
  }
  if ($script:testUris.Count -ne 2 -or @($script:testUris | Where-Object { $_ -notlike '*/tags/v0.47.0' }).Count) { throw 'RTK bypassed the catalog tag' }
  $comp.version = '0.99.0'; $script:testTag = 'v0.99.0'
  [void](Get-UabsComponentGitHubRelease -Comp $comp)
  if ($script:testUris[-1] -notlike '*/tags/v0.99.0') { throw 'RTK pin was hardcoded outside the catalog' }
  $comp.version = '0.47.0'
  $rejected = $false
  try { [void](Get-UabsComponentGitHubRelease -Comp $comp) } catch { $rejected = $true }
  if (-not $rejected) { throw 'wrong release tag was accepted' }
  $comp.id = 'another-tool'
  if ((Get-UabsComponentGitHubRelease -Comp $comp).tag_name -ne 'v0.48.0') { throw 'non-RTK latest behavior changed' }
  $comp.id = 'rtk'; $script:testTag = 'v0.47.0'
  $Mode = 'BundledOnly'; $script:testUris = @()
  if (Get-ComponentAssetPath -Comp $comp) { throw 'Core trusted an unrecorded cached RTK' }
  [IO.File]::WriteAllText($manifestPath, (@{assets=@(@{file='tool.zip';size=$good.Length;sha256=$sha})} | ConvertTo-Json -Depth 5))
  foreach ($folder in @($cache,$offline)) { [IO.File]::WriteAllBytes((Join-Path $folder 'tool.zip'), $stale) }
  if (Get-ComponentAssetPath -Comp $comp) { throw 'BundledOnly accepted poisoned RTK fallback' }
  if ($script:testUris.Count) { throw 'BundledOnly attempted a network request' }
  [IO.File]::WriteAllBytes((Join-Path $offline 'tool.zip'), $good)
  $Mode = 'OnlineLatest'; $script:testOffline = $true
  if ((Get-ComponentAssetPath -Comp $comp) -ne (Join-Path $offline 'tool.zip')) { throw 'network failure lost verified offline RTK' }

  # Execute the shipped RTK binary; no compiler, external SDK or download.
  # The old file is opaque data: it must survive any rejected replacement.
  Expand-Archive -LiteralPath $rtkArchive -DestinationPath (Join-Path $scratch 'rtk-payload')
  $newExe = (Get-ChildItem -LiteralPath (Join-Path $scratch 'rtk-payload') -Recurse -Filter rtk.exe | Select-Object -First 1).FullName
  $oldExe = Join-Path $scratch 'wrong-version.cmd'
  [IO.File]::WriteAllText($oldExe, "@echo rtk 0.48.0`r`n@exit /b 0`r`n")
  $installedExe = Join-Path $scratch 'installed\rtk.exe'
  New-Item -ItemType Directory -Path (Split-Path $installedExe) | Out-Null
  Copy-Item -LiteralPath $oldExe -Destination $installedExe
  $oldHash = (Get-FileHash -LiteralPath $installedExe).Hash
  $rejected = $false
  try { [void](Install-UabsRtkExecutable -Source $oldExe -Destination $installedExe -ExpectedVersion '0.47.0') } catch {
    if ($_.Exception.Message -notlike '*candidate version 0.48.0, expected 0.47.0*') { throw }
    $rejected = $true
  }
  if (-not $rejected -or (Get-FileHash -LiteralPath $installedExe).Hash -ne $oldHash) { throw 'wrong RTK candidate modified the live executable' }
  $lock = [IO.File]::Open($installedExe, 'Open', 'Read', 'None')
  $rejected = $false
  try { [void](Install-UabsRtkExecutable -Source $newExe -Destination $installedExe -ExpectedVersion '0.47.0') } catch { $rejected = $true } finally { $lock.Dispose() }
  if (-not $rejected -or (Get-FileHash -LiteralPath $installedExe).Hash -ne $oldHash) { throw 'locked RTK replacement damaged the original' }
  $result = Install-UabsRtkExecutable -Source $newExe -Destination $installedExe -ExpectedVersion '0.47.0'
  if ($result.version -ne '0.47.0' -or (Get-FileHash -LiteralPath $result.backup).Hash -ne $oldHash) { throw 'RTK repair lost the previous executable backup' }
  $freshExe = Join-Path $scratch 'fresh\rtk.exe'
  $result = Install-UabsRtkExecutable -Source $newExe -Destination $freshExe -ExpectedVersion '0.47.0'
  if ($result.backup -or $result.version -ne '0.47.0') { throw 'fresh RTK installation failed' }

  # Force the post-replacement check to fail, retaining the real source check.
  Copy-Item -LiteralPath $oldExe -Destination $installedExe -Force
  $versionCheck = ${function:Get-UabsRtkVersion}
  $script:postReplacementSeen = $false
  function Get-UabsRtkVersion {
    param($Path, $ExpectedVersion)
    if ($Path -eq $installedExe) {
      $script:postReplacementSeen = (Get-FileHash -LiteralPath $Path).Hash -eq (Get-FileHash -LiteralPath $newExe).Hash
      throw 'fixture post-replacement failure'
    }
    & $versionCheck -Path $Path -ExpectedVersion $ExpectedVersion
  }
  $rejected = $false
  try { [void](Install-UabsRtkExecutable -Source $newExe -Destination $installedExe -ExpectedVersion '0.47.0') } catch { $rejected = $true } finally { Set-Item Function:Get-UabsRtkVersion $versionCheck }
  if (-not $rejected -or -not $script:postReplacementSeen -or (Get-FileHash -LiteralPath $installedExe).Hash -ne $oldHash) { throw 'failed post-check did not roll back RTK' }
  if (@(Get-ChildItem -LiteralPath (Split-Path $installedExe) -Filter 'rtk.part-*').Count) { throw 'RTK transaction left staged executables behind' }
  Write-Output 'RELEASE ASSET CACHE GATE: PASS (tag pin, offline trust, prevalidation, backup, fresh install, lock, rollback)'
} finally {
  if ((Test-UabsPathWithin -Path $scratch -Root ([IO.Path]::GetTempPath())) -and (Split-Path $scratch -Leaf) -like 'uabs-release-cache-*') {
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
  }
}
