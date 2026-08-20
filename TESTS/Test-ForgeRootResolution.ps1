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
$sand = $null; $sand2 = $null; $sand3 = $null

function Resolve-Target([string]$declared) {
  # -ResolveOnly prints exactly one line, the resolved root, and stops before
  # touching the archive or the providers.
  $env:SKYRIM_FORGE_ROOT = $declared
  $out = & (Join-Path $PSHOME 'powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $script -PackRoot $PackRoot -ResolveOnly 2>&1 | Out-String
  return $out.Trim()
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

  # The installer derives the payload version from the asset filename. A
  # restated literal in CODE is how 7.8.0 ended up with '5.2.0' in four places;
  # prose in the comment header is allowed to name the versions it is about.
  $codeOnly = [regex]::Replace($srcText, '(?s)<#.*?#>', '')
  $codeOnly = ($codeOnly -split "`n" | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
  $restated = [regex]::Matches($codeOnly, "Skyrim-Forge-\d+\.\d+")
  Check 'installer code does not hardcode a Forge version' ($restated.Count.ToString()) '0'
}
finally {
  $env:SKYRIM_FORGE_ROOT = $null
  foreach ($d in @($sand, $sand2, $sand3)) {
    if ($d -and (Test-Path -LiteralPath $d)) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
  }
}

Write-Host ''
if ($fail -eq 0) { Write-Host 'FORGE ROOT RESOLUTION: PASS' -ForegroundColor Green; exit 0 }
Write-Host ('FORGE ROOT RESOLUTION: FAIL (' + $fail + ')') -ForegroundColor Red
exit 1
