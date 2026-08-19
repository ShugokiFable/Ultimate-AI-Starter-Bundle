# discover_tools.ps1 — read-only optional tool probe for Skyrim AI V5
param([switch]$Json)
$ErrorActionPreference = 'Continue'

function Find-FirstFile {
  param([string[]]$Candidates)
  foreach ($c in $Candidates) {
    if ([string]::IsNullOrWhiteSpace($c)) { continue }
    try {
      if (Test-Path -LiteralPath $c) { return (Resolve-Path -LiteralPath $c).Path }
    } catch {}
  }
  return $null
}

function Find-Under {
  param([string[]]$Roots,[string]$Filter,[int]$Depth=5)
  foreach ($r in $Roots) {
    if ([string]::IsNullOrWhiteSpace($r)) { continue }
    if (-not (Test-Path -LiteralPath $r)) { continue }
    try {
      $hit = Get-ChildItem -LiteralPath $r -Filter $Filter -Recurse -Depth $Depth -File -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($hit) { return $hit.FullName }
    } catch {}
  }
  return $null
}

function Get-ExistingRoots {
  param([string[]]$Paths)
  $out = @()
  foreach ($p in $Paths) {
    if ([string]::IsNullOrWhiteSpace($p)) { continue }
    try {
      if (Test-Path -LiteralPath $p) { $out += $p }
    } catch {}
  }
  return $out
}

$report = [ordered]@{}

# Forge
$forgeRoot = $env:SKYRIM_FORGE_ROOT
if (-not $forgeRoot) {
  foreach ($p in @(
    (Join-Path $PSScriptRoot '..\skyrim-forge\INSTALLATION.json'),
    (Join-Path $env:USERPROFILE '.grok\skills\skyrim-forge\INSTALLATION.json'),
    (Join-Path $env:USERPROFILE '.claude\skills\skyrim-forge\INSTALLATION.json'),
    (Join-Path $env:USERPROFILE '.codex\skills\skyrim-forge\INSTALLATION.json'),
    (Join-Path $env:USERPROFILE '.agents\skills\skyrim-forge\INSTALLATION.json')
  )) {
    if (Test-Path -LiteralPath $p) {
      try {
        $j = Get-Content -LiteralPath $p -Raw | ConvertFrom-Json
        if ($j.root -and (Test-Path -LiteralPath [string]$j.root)) { $forgeRoot = [string]$j.root; break }
      } catch {}
    }
  }
}
$report['skyrim-forge'] = @{ status = $(if ($forgeRoot) {'FOUND'} else {'MISSING'}); path = $forgeRoot; install = 'Install Skyrim Forge product; set SKYRIM_FORGE_ROOT or skill INSTALLATION.json' }

# houseCARL
$hc = Find-FirstFile @($env:HOUSECARL_MCP)
if (-not $hc -and $env:HOUSECARL_ROOT) { $hc = Find-Under @($env:HOUSECARL_ROOT) 'housecarl-mcp.exe' 8 }
$hcSearchRoots = Get-ExistingRoots @(
  (Join-Path $env:LOCALAPPDATA 'Programs'),
  (Join-Path $env:USERPROFILE '.housecarl'),
  (Join-Path $env:USERPROFILE 'AppData\Local\Programs'),
  (Join-Path $env:USERPROFILE '.agents'),
  (Join-Path $env:USERPROFILE '.claude')
)
# Optional common tool vaults on any fixed drive letter that actually exists
foreach ($letter in @('C','D','E','F','G','H','S','T','Z')) {
  $drive = "${letter}:\"
  if (Test-Path -LiteralPath $drive) {
    foreach ($tail in @('Apps\Skyrim Tools','Skyrim Tools','Tools\Skyrim','Modding\Tools')) {
      $cand = Join-Path $drive $tail
      if (Test-Path -LiteralPath $cand) { $hcSearchRoots += $cand }
    }
  }
}
if (-not $hc) { $hc = Find-Under $hcSearchRoots 'housecarl-mcp.exe' 6 }
$report['housecarl-mcp'] = @{ status = $(if ($hc) {'FOUND'} else {'MISSING'}); path = $hc; install = 'Run houseCARL-Setup.exe; install .NET 9 + ASP.NET Core 9; register MCP; restart AI app' }

# Spooky
$sp = $env:SPOOKY_AUTOMOD_ROOT
if ($sp -and -not (Test-Path -LiteralPath $sp)) { $sp = $null }
if (-not $sp) {
  foreach ($c in @(
    (Join-Path $env:USERPROFILE 'spookys-automod-toolkit'),
    (Join-Path $env:LOCALAPPDATA 'spookys-automod-toolkit')
  )) {
    if (Test-Path -LiteralPath (Join-Path $c 'SpookysAutomod.sln')) { $sp = $c; break }
  }
}
if (-not $sp) {
  foreach ($letter in @('C','D','E','F','G','H','S','T','Z')) {
    $drive = "${letter}:\"
    if (-not (Test-Path -LiteralPath $drive)) { continue }
    $probe = Join-Path $drive 'Apps\Skyrim Tools'
    if (-not (Test-Path -LiteralPath $probe)) { continue }
    try {
      $hit = Get-ChildItem -LiteralPath $probe -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'spookys-automod*' } | Select-Object -First 1
      if ($hit) {
        $inner = Join-Path $hit.FullName 'spookys-automod-toolkit'
        if (Test-Path -LiteralPath (Join-Path $inner 'SpookysAutomod.sln')) { $sp = $inner; break }
        if (Test-Path -LiteralPath (Join-Path $hit.FullName 'SpookysAutomod.sln')) { $sp = $hit.FullName; break }
      }
    } catch {}
  }
}
$report['spookys-automod-toolkit'] = @{ status = $(if ($sp) {'FOUND'} else {'MISSING'}); path = $sp; install = 'https://github.com/SpookyPirate/spookys-automod-toolkit/releases — need .NET 8 SDK' }

# codebase-memory
$cm = Find-FirstFile @(
  $env:CODEBASE_MEMORY_MCP,
  (Join-Path $env:LOCALAPPDATA 'Programs\codebase-memory-mcp\codebase-memory-mcp.exe')
)
$report['codebase-memory-mcp'] = @{ status = $(if ($cm) {'FOUND'} else {'MISSING'}); path = $cm; install = 'https://github.com/DeusData/codebase-memory-mcp' }

# headroom
$hr = $null
try { $c = Get-Command headroom -ErrorAction SilentlyContinue; if ($c) { $hr = $c.Source } } catch {}
if (-not $hr -and $env:HEADROOM_CMD) { $hr = $env:HEADROOM_CMD }
$report['headroom'] = @{ status = $(if ($hr) {'FOUND'} else {'MISSING'}); path = $hr; install = 'pip install "headroom-ai[mcp]" — https://github.com/headroomlabs-ai/headroom' }

# codeburn
$cb = $null
try { $c = Get-Command codeburn -ErrorAction SilentlyContinue; if ($c) { $cb = $c.Source } } catch {}
if (-not $cb) { try { $npx = Get-Command npx -ErrorAction SilentlyContinue; if ($npx) { $cb = 'npx codeburn' } } catch {} }
$report['codeburn'] = @{ status = $(if ($cb) {'FOUND'} else {'MISSING'}); path = $cb; install = 'npm i -g codeburn or npx codeburn — https://github.com/getagentseal/codeburn' }

# MO2 / houseCARL instance (real MO2 or Vortex shim)
$mo2 = $env:SKYRIM_MO2_INSTANCE
if (-not $mo2) { $mo2 = $env:HouseCarl__Mo2InstanceDir }
$shimDefault = Join-Path $env:LOCALAPPDATA 'houseCARL-Shim'
if (-not $mo2 -and (Test-Path -LiteralPath (Join-Path $shimDefault 'ModOrganizer.ini'))) { $mo2 = $shimDefault }
# User-scope env may not be visible in this process yet — read from registry
if (-not $mo2) {
  try {
    $mo2 = [Environment]::GetEnvironmentVariable('SKYRIM_MO2_INSTANCE','User')
  } catch {}
}
if (-not $mo2) {
  try {
    $mo2 = [Environment]::GetEnvironmentVariable('HouseCarl__Mo2InstanceDir','User')
  } catch {}
}
$mo2Status = 'UNSET'
if ($mo2) {
  try {
    if (Test-Path -LiteralPath (Join-Path $mo2 'ModOrganizer.ini')) {
      if (Test-Path -LiteralPath (Join-Path $mo2 'HOUSECARL-SHIM.txt')) { $mo2Status = 'VORTEX-SHIM' }
      else { $mo2Status = 'MO2-INSTANCE' }
    } else { $mo2Status = 'INVALID'; $mo2 = $null }
  } catch { $mo2Status = 'INVALID'; $mo2 = $null }
}
$report['mo2-instance'] = @{ status = $mo2Status; path = $mo2; install = 'Run TOOLS\Setup-HouseCarl.ps1 (MO2 or Vortex) or set SKYRIM_MO2_INSTANCE' }

# dotnet
$dn = $null
try { $c = Get-Command dotnet -ErrorAction SilentlyContinue; if ($c) { $dn = $c.Source } } catch {}
$report['dotnet'] = @{ status = $(if ($dn) {'FOUND'} else {'MISSING'}); path = $dn; install = 'https://dotnet.microsoft.com/download' }


# houseCARL instance / Vortex shim
$hcInst = $env:SKYRIM_MO2_INSTANCE
if (-not $hcInst) { $hcInst = $env:HouseCarl__Mo2InstanceDir }
$shimDefault = Join-Path $env:LOCALAPPDATA 'houseCARL-Shim'
$stateFile = Join-Path $env:LOCALAPPDATA 'houseCARL-data\v5-setup-state.json'
if (-not $hcInst -and (Test-Path -LiteralPath (Join-Path $shimDefault 'ModOrganizer.ini'))) { $hcInst = $shimDefault }
$hcInstStatus = 'UNSET'
if ($hcInst -and (Test-Path -LiteralPath (Join-Path $hcInst 'ModOrganizer.ini'))) {
  if (Test-Path -LiteralPath (Join-Path $hcInst 'HOUSECARL-SHIM.txt')) { $hcInstStatus = 'VORTEX-SHIM' }
  else { $hcInstStatus = 'MO2-INSTANCE' }
} elseif ($hcInst) { $hcInstStatus = 'INVALID' }
$report['housecarl-instance'] = @{ status = $hcInstStatus; path = $hcInst; install = 'Run TOOLS\Setup-HouseCarl.ps1 (MO2 or Vortex)' }
$report['housecarl-setup-state'] = @{ status = $(if (Test-Path -LiteralPath $stateFile) {'FOUND'} else {'MISSING'}); path = $(if (Test-Path -LiteralPath $stateFile) {$stateFile} else {$null}); install = 'Run TOOLS\Setup-HouseCarl.ps1' }

if ($Json) {
  $report | ConvertTo-Json -Depth 5
} else {
  foreach ($k in $report.Keys) {
    $r = $report[$k]
    '{0,-28} {1,-8} {2}' -f $k, $r.status, $(if ($r.path) { $r.path } else { $r.install })
  }
}
