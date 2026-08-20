<#
.SYNOPSIS
  Prove the Forge install root is always versionless, and that an existing
  version-stamped install is migrated onto it instead of duplicated.

.DESCRIPTION
  This is the failure that kept coming back. Every provider stores the MCP
  server command as a hard absolute path, so a version-stamped install
  directory renames itself out from under five configs on every upgrade, and a
  provider whose MCP command does not exist fails silently -- it just shows no
  tools.

  Live state found while auditing 7.8.0, all three disagreeing:

      SKYRIM_FORGE_ROOT      S:\Apps\Skyrim Tools\Skyrim-Forge-5.1.6   (deleted)
      all 5 provider configs S:\Apps\Skyrim Tools\Skyrim-Forge         (absent)
      actually on disk       S:\Apps\Skyrim Tools\Skyrim-Forge-5.2.0   (no venv)

  Repair-McpPaths.ps1 exists to clean up after exactly this, which is treating
  a symptom. The cure is that the install directory never carries a version at
  all: the ARCHIVE keeps its version for provenance, the INSTALL DIRECTORY
  never does.
#>
[CmdletBinding()]
param([string]$PackRoot)

$ErrorActionPreference = 'Stop'
if (-not $PackRoot) { $PackRoot = Split-Path -Parent $PSScriptRoot }
$script = Join-Path $PackRoot 'TOOLS\Install-SkyrimForge.ps1'
if (-not (Test-Path -LiteralPath $script -PathType Leaf)) { throw "Missing $script" }

$fail = 0
$sand = $null; $sand2 = $null; $sand3 = $null; $sand4 = $null

function Resolve-Target([string]$declared) {
  # -ResolveOnly prints exactly one line, the resolved root, and stops before
  # touching the archive or the providers.
  $env:SKYRIM_FORGE_ROOT = $declared
  $out = & (Join-Path $PSHOME 'powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $script -PackRoot $PackRoot -ResolveOnly 2>&1 | Out-String
  return $out.Trim()
}

function Resolve-Explicit([string]$forgeRoot, [string]$declared) {
  # -ForgeRoot is what the user typed. It outranks a stale SKYRIM_FORGE_ROOT,
  # and unlike one it may name a directory that does not exist yet: naming a
  # root is a decision, not a guess left over from a previous install.
  $env:SKYRIM_FORGE_ROOT = $declared
  $out = & (Join-Path $PSHOME 'powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $script -PackRoot $PackRoot -ForgeRoot $forgeRoot -ResolveOnly 2>&1 | Out-String
  return $out.Trim()
}

function Resolve-Rejected([string]$forgeRoot) {
  # -ForgeRoot pointed at a populated non-Forge directory must fail loudly.
  $env:SKYRIM_FORGE_ROOT = $null
  # This is the one call that expects a non-zero child. Windows PowerShell
  # 5.1 turns a native exe's stderr into ErrorRecords, which under this
  # script's ErrorActionPreference = 'Stop' throws before the message can be
  # read. Relax it for the duration of the call, not the file.
  $previous = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $out = & (Join-Path $PSHOME 'powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $script -PackRoot $PackRoot -ForgeRoot $forgeRoot -ResolveOnly 2>&1 | Out-String
  } finally { $ErrorActionPreference = $previous }
  if ($LASTEXITCODE -eq 0) { return 'accepted' }
  if ($out -match 'installed INTO') { return 'refused' }
  return ('other: ' + $out.Trim())
}

function Check([string]$label, [string]$got, [string]$want) {
  if ($got -eq $want) { Write-Host ("  ok   " + $label) -ForegroundColor Green }
  else {
    Write-Host ("  FAIL " + $label) -ForegroundColor Red
    Write-Host ("       got  " + $got) -ForegroundColor Red
    Write-Host ("       want " + $want) -ForegroundColor Red
    $script:fail++
  }
}

try {
  $sand = Join-Path $env:TEMP ('forgeroot-a-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path $sand | Out-Null

  $stamped = Join-Path $sand 'Skyrim-Forge-5.2.0'
  New-Item -ItemType Directory -Force -Path $stamped | Out-Null
  Set-Content -LiteralPath (Join-Path $stamped 'marker.txt') -Value 'keep me' -Encoding ASCII
  Check 'version-stamped install migrates' (Resolve-Target $stamped) (Join-Path $sand 'Skyrim-Forge')
  Check 'migration moved rather than copied' ((Test-Path -LiteralPath $stamped).ToString()) 'False'
  Check 'migration preserved the install' ((Test-Path -LiteralPath (Join-Path $sand 'Skyrim-Forge\marker.txt')).ToString()) 'True'

  Check 'versionless install used as-is' (Resolve-Target (Join-Path $sand 'Skyrim-Forge')) (Join-Path $sand 'Skyrim-Forge')

  # The exact live failure: the declared root is a version that was deleted,
  # and the version that really exists sits beside it under another name.
  $sand2 = Join-Path $env:TEMP ('forgeroot-b-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path (Join-Path $sand2 'Skyrim-Forge-5.2.0') | Out-Null
  Check 'dead versioned root finds the live sibling' (Resolve-Target (Join-Path $sand2 'Skyrim-Forge-5.1.6')) (Join-Path $sand2 'Skyrim-Forge')

  # Whatever is declared, the answer never carries a version suffix.
  Check 'resolved root is never version-stamped' (((Resolve-Target '') -match '-\d+(\.\d+)*$').ToString()) 'False'
  $srcText = [IO.File]::ReadAllText($script)
  Check 'default root is LOCALAPPDATA\Skyrim-Tools\Skyrim-Forge' `
    (($srcText -match "Join-Path \(Join-Path \`$env:LOCALAPPDATA 'Skyrim-Tools'\) 'Skyrim-Forge'").ToString()) 'True'

  # 5.10.0 must beat 5.2.0. String ordering gets this wrong.
  $sand3 = Join-Path $env:TEMP ('forgeroot-c-' + [guid]::NewGuid().ToString('N'))
  foreach ($n in @('Skyrim-Forge-5.1.0', 'Skyrim-Forge-5.2.0', 'Skyrim-Forge-5.10.0')) {
    New-Item -ItemType Directory -Force -Path (Join-Path $sand3 $n) | Out-Null
    Set-Content -LiteralPath (Join-Path $sand3 ($n + '\which.txt')) -Value $n -Encoding ASCII
  }
  Check 'several stamped installs collapse to one' (Resolve-Target (Join-Path $sand3 'Skyrim-Forge-5.1.0')) (Join-Path $sand3 'Skyrim-Forge')
  Check 'the highest version is the one kept' ([IO.File]::ReadAllText((Join-Path $sand3 'Skyrim-Forge\which.txt')).Trim()) 'Skyrim-Forge-5.10.0'


  # -ForgeRoot: the user says where their Skyrim tools live.
  $sand4 = Join-Path $env:TEMP ('forgeroot-d-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path $sand4 | Out-Null
  $stale = Join-Path $sand4 'Stale-Elsewhere\Skyrim-Forge'
  $chosen = Join-Path $sand4 'My Skyrim Tools\Skyrim-Forge'
  Check '-ForgeRoot outranks SKYRIM_FORGE_ROOT' (Resolve-Explicit $chosen $stale) $chosen
  Check '-ForgeRoot creates a parent that does not exist yet' `
    ((Test-Path -LiteralPath (Split-Path -Parent $chosen) -PathType Container).ToString()) 'True'
  # Someone WILL pass a version-stamped path, because that is the habit this
  # whole gate exists to break. Strip it rather than honour it.
  Check '-ForgeRoot is stripped of a version suffix' (Resolve-Explicit ($chosen + '-6.0.0') $null) $chosen
  # Passing the tools FOLDER instead of the install directory would unpack
  # Forge over whatever already lives there.
  $tools = Join-Path $sand4 'Shared Skyrim Tools'
  New-Item -ItemType Directory -Force -Path (Join-Path $tools 'xEdit') | Out-Null
  Check '-ForgeRoot refuses a populated non-Forge directory' (Resolve-Rejected $tools) 'refused'
  Check '-ForgeRoot still accepts a real Forge install root' (Resolve-Explicit $chosen $null) $chosen

  # An upgrade re-stages the install directory. Job staging defaults to
  # <install root>\Workspaces, so a replace-in-place would delete the user's mod
  # work; these names must survive the swap. CI proves it end to end by
  # downgrading VERSION.txt to force a re-stage and checking a marker file.
  Check 'installer preserves Workspaces across an upgrade' `
    (($srcText -match "(?m)^\s*\`$preserve\s*=\s*@\('Workspaces'").ToString()) 'True'

  # The installer derives its version from the in-tree source tree. A
  # restated literal in CODE is how 7.8.0 ended up with '5.2.0' in four places;
  # prose in the comment header is allowed to name the versions it is about.
  $codeOnly = [regex]::Replace($srcText, '(?s)<#.*?#>', '')
  $codeOnly = ($codeOnly -split "`n" | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
  $restated = [regex]::Matches($codeOnly, "Skyrim-Forge-\d+\.\d+")
  Check 'installer code does not hardcode a Forge version' ($restated.Count.ToString()) '0'
}
finally {
  $env:SKYRIM_FORGE_ROOT = $null
  foreach ($d in @($sand, $sand2, $sand3, $sand4)) {
    if ($d -and (Test-Path -LiteralPath $d)) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
  }
}

Write-Host ''
if ($fail -eq 0) { Write-Host 'FORGE ROOT RESOLUTION: PASS' -ForegroundColor Green; exit 0 }
Write-Host ('FORGE ROOT RESOLUTION: FAIL (' + $fail + ')') -ForegroundColor Red
exit 1
