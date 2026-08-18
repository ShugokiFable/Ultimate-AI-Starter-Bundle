<#
.SYNOPSIS
  Automatic houseCARL setup for MO2 or Vortex (Vortex uses an MO2-shaped shim).

.DESCRIPTION
  - Locates housecarl-mcp.exe
  - Detects Mod Organizer 2 instances (folder with ModOrganizer.ini)
  - OR builds/refreshes a Vortex shim that houseCARL can read
  - Wires MCP config for Grok (and optionally Codex)
  - Sets process + user env hints: HOUSECARL_MCP, SKYRIM_MO2_INSTANCE, HouseCarl__Mo2InstanceDir
  - Never assumes drive letters; discovers or accepts -parameters

.PARAMETER Manager
  Auto | MO2 | Vortex  (default Auto)

.PARAMETER Mo2Instance
  Explicit MO2 instance folder (contains ModOrganizer.ini)

.PARAMETER VortexStaging
  Explicit Vortex mod staging folder (subfolders = mods)

.PARAMETER SkyrimPath
  Skyrim SE install folder

.PARAMETER ShimRoot
  Where to build the Vortex shim (default: %LOCALAPPDATA%\houseCARL-Shim)

.PARAMETER HouseCarlMcp
  Full path to housecarl-mcp.exe

.PARAMETER PreferSymlinkPlugins
  Symlink plugins.txt/loadorder.txt into the shim (needs admin for file symlinks; falls back to copy)

.PARAMETER WireGrok
  Write/update %USERPROFILE%\.grok\config.toml MCP block (default: $true)

.PARAMETER WireCodex
  Best-effort Codex config hint file (default: $true)

.PARAMETER RefreshOnly
  Only refresh Vortex shim plugins/modlist (skip MCP rewrite)

.PARAMETER WhatIf
  Show actions without writing

.EXAMPLE
  .\Setup-HouseCarl.ps1
  .\Setup-HouseCarl.ps1 -Manager Vortex
  .\Setup-HouseCarl.ps1 -Manager MO2 -Mo2Instance "D:\MO2\instances\MyList"
  .\Setup-HouseCarl.ps1 -RefreshOnly
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
  [ValidateSet('Auto','MO2','Vortex')]
  [string]$Manager = 'Auto',
  [string]$Mo2Instance = '',
  [string]$VortexStaging = '',
  [string]$SkyrimPath = '',
  [string]$ShimRoot = '',
  [string]$HouseCarlMcp = '',
  [switch]$PreferSymlinkPlugins,
  [bool]$WireGrok = $true,
  [bool]$WireCodex = $true,
  [switch]$RefreshOnly,
  [switch]$SkipDotNetCheck
)

$ErrorActionPreference = 'Stop'
$script:Report = [ordered]@{}

function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "  OK  $msg" -ForegroundColor Green }
function Write-Warn2($msg){ Write-Host "  !!  $msg" -ForegroundColor Yellow }
function Write-Bad($msg)  { Write-Host "  XX  $msg" -ForegroundColor Red }

function Test-ExistingPath([string]$p) {
  if ([string]::IsNullOrWhiteSpace($p)) { return $false }
  try { return (Test-Path -LiteralPath $p) } catch { return $false }
}

function Find-HouseCarlMcp {
  param([string]$Hint)
  if (Test-ExistingPath $Hint) { return (Resolve-Path -LiteralPath $Hint).Path }
  if (Test-ExistingPath $env:HOUSECARL_MCP) { return (Resolve-Path -LiteralPath $env:HOUSECARL_MCP).Path }
  $candidates = @(
    (Join-Path $env:LOCALAPPDATA 'houseCARL\server\housecarl-mcp.exe'),
    (Join-Path $env:USERPROFILE '.claude\skills\housecarl\server\housecarl-mcp.exe'),
    (Join-Path $env:USERPROFILE '.codex\skills\housecarl\server\housecarl-mcp.exe'),
    (Join-Path $env:USERPROFILE '.agents\skills\housecarl\server\housecarl-mcp.exe')
  )
  foreach ($c in $candidates) {
    if (Test-ExistingPath $c) { return (Resolve-Path -LiteralPath $c).Path }
  }
  if (Test-ExistingPath $env:HOUSECARL_ROOT) {
    $hit = Get-ChildItem -LiteralPath $env:HOUSECARL_ROOT -Filter 'housecarl-mcp.exe' -Recurse -Depth 6 -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($hit) { return $hit.FullName }
  }
  foreach ($letter in @('C','D','E','F','G','H','S','T','Z')) {
    $drive = "${letter}:\"
    if (-not (Test-ExistingPath $drive)) { continue }
    foreach ($tail in @('Apps\Skyrim Tools\houseCARL','Skyrim Tools\houseCARL','Tools\houseCARL','houseCARL')) {
      $root = Join-Path $drive $tail
      if (-not (Test-ExistingPath $root)) { continue }
      $hit = Get-ChildItem -LiteralPath $root -Filter 'housecarl-mcp.exe' -Recurse -Depth 5 -File -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($hit) { return $hit.FullName }
    }
  }
  return $null
}

function Find-SkyrimSe {
  param([string]$Hint)
  if (Test-ExistingPath $Hint) {
    if (Test-ExistingPath (Join-Path $Hint 'SkyrimSE.exe') -or Test-ExistingPath (Join-Path $Hint 'SkyrimSELauncher.exe')) {
      return (Resolve-Path -LiteralPath $Hint).Path
    }
  }
  $regPaths = @(
    'HKLM:\SOFTWARE\WOW6432Node\Bethesda Softworks\Skyrim Special Edition',
    'HKLM:\SOFTWARE\Bethesda Softworks\Skyrim Special Edition'
  )
  foreach ($rp in $regPaths) {
    try {
      $props = Get-ItemProperty -Path $rp -ErrorAction SilentlyContinue
      if ($null -eq $props) { continue }
      foreach ($name in @('Installed Path','installed path','InstallPath')) {
        $inst = $props.$name
        if ($inst -and (Test-ExistingPath $inst)) { return $inst }
      }
    } catch {}
  }
  try {
    $steam = (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -ErrorAction SilentlyContinue).InstallPath
    if ($steam) {
      $p = Join-Path $steam 'steamapps\common\Skyrim Special Edition'
      if (Test-ExistingPath $p) { return $p }
    }
  } catch {}
  # libraryfolders.vdf
  try {
    $steam = (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -ErrorAction SilentlyContinue).InstallPath
    $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
    if (Test-ExistingPath $vdf) {
      $txt = [IO.File]::ReadAllText($vdf)
      $paths = [regex]::Matches($txt, '"path"\s+"([^"]+)"') | ForEach-Object { $_.Groups[1].Value -replace '\\\\','\' }
      foreach ($lib in $paths) {
        $p = Join-Path $lib 'steamapps\common\Skyrim Special Edition'
        if (Test-ExistingPath $p) { return $p }
      }
    }
  } catch {}
  foreach ($letter in @('C','D','E','F','G','H','S','T','Z')) {
    $cands = @(
      "${letter}:\Program Files (x86)\Steam\steamapps\common\Skyrim Special Edition",
      "${letter}:\SteamLibrary\steamapps\common\Skyrim Special Edition",
      "${letter}:\Games\Steam\steamapps\common\Skyrim Special Edition",
      "${letter}:\Steam\steamapps\common\Skyrim Special Edition"
    )
    foreach ($p in $cands) { if (Test-ExistingPath $p) { return $p } }
  }
  return $null
}

function Find-Mo2Instances {
  $found = New-Object System.Collections.Generic.List[string]
  $roots = New-Object System.Collections.Generic.List[string]
  foreach ($p in @(
    $env:SKYRIM_MO2_INSTANCE,
    $env:MO2_INSTANCE,
    $env:HouseCarl__Mo2InstanceDir,
    (Join-Path $env:LOCALAPPDATA 'ModOrganizer'),
    (Join-Path $env:APPDATA 'ModOrganizer')
  )) {
    if (Test-ExistingPath $p) { [void]$roots.Add($p) }
  }
  foreach ($letter in @('C','D','E','F','G','H','S','T','Z')) {
    $drive = "${letter}:\"
    if (-not (Test-ExistingPath $drive)) { continue }
    foreach ($name in @('MO2','Mod Organizer 2','ModOrganizer','Modding\MO2','Games\MO2')) {
      $c = Join-Path $drive $name
      if (Test-ExistingPath $c) { [void]$roots.Add($c) }
    }
  }
  foreach ($root in $roots) {
    if (Test-ExistingPath (Join-Path $root 'ModOrganizer.ini')) {
      if (-not $found.Contains($root)) { [void]$found.Add((Resolve-Path -LiteralPath $root).Path) }
    }
    # portable instances / instances subfolder
    try {
      Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        if (Test-ExistingPath (Join-Path $_.FullName 'ModOrganizer.ini')) {
          $rp = (Resolve-Path -LiteralPath $_.FullName).Path
          if (-not $found.Contains($rp)) { [void]$found.Add($rp) }
        }
        $inst = Join-Path $_.FullName 'instances'
        if (Test-ExistingPath $inst) {
          Get-ChildItem -LiteralPath $inst -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            if (Test-ExistingPath (Join-Path $_.FullName 'ModOrganizer.ini')) {
              $rp = (Resolve-Path -LiteralPath $_.FullName).Path
              if (-not $found.Contains($rp)) { [void]$found.Add($rp) }
            }
          }
        }
      }
    } catch {}
  }
  # Also accept explicit env parent scans shallow
  return @($found)
}

function Find-VortexStaging {
  param([string]$Hint)
  if (Test-ExistingPath $Hint) { return (Resolve-Path -LiteralPath $Hint).Path }
  $cands = @(
    (Join-Path $env:APPDATA 'Vortex\skyrimse\mods'),
    (Join-Path $env:APPDATA 'Vortex\skyrimvr\mods'),
    (Join-Path $env:APPDATA 'Vortex\skyrim\mods')
  )
  foreach ($c in $cands) {
    if (Test-ExistingPath $c) {
      $n = @(Get-ChildItem -LiteralPath $c -Directory -ErrorAction SilentlyContinue).Count
      if ($n -gt 0) { return (Resolve-Path -LiteralPath $c).Path }
    }
  }
  foreach ($letter in @('C','D','E','F','G','H','S','T','Z')) {
    foreach ($tail in @('Vortex Mods\skyrimse','Vortex Mods\skyrimse\mods','Games\Vortex Mods\skyrimse','Vortex\skyrimse\mods')) {
      $p = Join-Path "${letter}:\" $tail
      if (Test-ExistingPath $p) {
        # if parent of mods
        if ((Split-Path $p -Leaf) -ne 'mods') {
          $m = Join-Path $p 'mods'
          if (Test-ExistingPath $m) { $p = $m }
        }
        $n = @(Get-ChildItem -LiteralPath $p -Directory -ErrorAction SilentlyContinue).Count
        if ($n -gt 0) { return (Resolve-Path -LiteralPath $p).Path }
      }
    }
  }
  return $null
}

function Get-SkyrimAppData {
  $p = Join-Path $env:LOCALAPPDATA 'Skyrim Special Edition'
  if (Test-ExistingPath $p) { return $p }
  return $null
}

function New-DirectorySafe([string]$p) {
  if (-not (Test-ExistingPath $p)) {
    New-Item -ItemType Directory -Force -Path $p | Out-Null
  }
}

function Set-JunctionOrSymlinkDir {
  param([string]$Link,[string]$Target)
  if (Test-ExistingPath $Link) {
    $item = Get-Item -LiteralPath $Link -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
      # recreate if target differs
      $cur = $null
      try { $cur = $item.Target } catch {}
      if ($cur -and (($cur -join ';') -eq $Target -or $cur -contains $Target)) {
        Write-Ok "mods link already points at staging"
        return
      }
      cmd /c rmdir "$Link" | Out-Null
    } else {
      throw "Path exists and is not a link: $Link - move it aside and re-run."
    }
  }
  # Junction does not need admin
  $ok = cmd /c mklink /J "$Link" "$Target" 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to create junction $Link -> $Target : $ok"
  }
  Write-Ok "Junction: $Link -> $Target"
}

function Write-Mo2Ini {
  param([string]$Shim,[string]$GamePath)
  $base = ($Shim -replace '\\','/')
  $game = ($GamePath -replace '\\','/')
  $ini = @"
[General]
gameName=Skyrim Special Edition
selected_profile=@ByteArray(Default)
gamePath=@ByteArray($game)

[Settings]
base_directory=$base
mod_directory=$base/mods
profiles_directory=$base/profiles
overwrite_directory=$base/overwrite
"@
  $path = Join-Path $Shim 'ModOrganizer.ini'
  Set-Content -LiteralPath $path -Value $ini -Encoding UTF8
  Write-Ok "Wrote $path"
}

function Update-VortexShim {
  param(
    [string]$Shim,
    [string]$Staging,
    [string]$GamePath,
    [string]$AppData,
    [switch]$SymlinkPlugins
  )
  New-DirectorySafe (Join-Path $Shim 'profiles\Default')
  New-DirectorySafe (Join-Path $Shim 'overwrite')
  Set-JunctionOrSymlinkDir -Link (Join-Path $Shim 'mods') -Target $Staging

  $prof = Join-Path $Shim 'profiles\Default'
  $pluginsSrc = Join-Path $AppData 'plugins.txt'
  if (-not (Test-ExistingPath $pluginsSrc)) { $pluginsSrc = Join-Path $AppData 'Plugins.txt' }
  $loadSrc = Join-Path $AppData 'loadorder.txt'
  if (-not (Test-ExistingPath $loadSrc)) {
    # try capital L
    $alt = Join-Path $AppData 'Loadorder.txt'
    if (Test-ExistingPath $alt) { $loadSrc = $alt }
  }

  $pluginsDst = Join-Path $prof 'plugins.txt'
  $loadDst = Join-Path $prof 'loadorder.txt'

  if (-not (Test-ExistingPath $pluginsSrc)) {
    throw "Missing $AppData\plugins.txt - launch Skyrim/Vortex once so the game writes plugin lists."
  }

  if ($SymlinkPlugins) {
    foreach ($pair in @(@($pluginsSrc,$pluginsDst), @($loadSrc,$loadDst))) {
      $s=$pair[0]; $d=$pair[1]
      if (-not (Test-ExistingPath $s)) { continue }
      if (Test-ExistingPath $d) { Remove-Item -LiteralPath $d -Force -ErrorAction SilentlyContinue }
      cmd /c mklink "$d" "$s" 2>&1 | Out-Null
      if (-not (Test-ExistingPath $d)) {
        Copy-Item -LiteralPath $s -Destination $d -Force
        Write-Warn2 "Symlink failed for $(Split-Path $d -Leaf); copied instead"
      } else {
        Write-Ok "Symlinked $(Split-Path $d -Leaf)"
      }
    }
  } else {
    Copy-Item -LiteralPath $pluginsSrc -Destination $pluginsDst -Force
    Write-Ok "Copied plugins.txt"
    if (Test-ExistingPath $loadSrc) {
      Copy-Item -LiteralPath $loadSrc -Destination $loadDst -Force
      Write-Ok "Copied loadorder.txt"
    } else {
      Get-Content -LiteralPath $pluginsSrc |
        Where-Object { $_ -and -not $_.StartsWith('#') } |
        ForEach-Object { $_.TrimStart('*') } |
        Set-Content -LiteralPath $loadDst -Encoding UTF8
      Write-Ok "Generated loadorder.txt from plugins.txt"
    }
  }

  # modlist.txt - enabled mods, older mtime first (bottom-to-top = higher priority for last lines)
  $mods = Get-ChildItem -LiteralPath $Staging -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime
  $lines = foreach ($m in $mods) { '+' + $m.Name }
  Set-Content -LiteralPath (Join-Path $prof 'modlist.txt') -Value $lines -Encoding UTF8
  Write-Ok "Generated modlist.txt ($($lines.Count) mods)"

  Write-Mo2Ini -Shim $Shim -GamePath $GamePath

  # marker
  @"
# houseCARL Vortex shim - generated by Setup-HouseCarl.ps1
generated_utc=$([DateTime]::UtcNow.ToString('o'))
vortex_staging=$Staging
skyrim_path=$GamePath
skyrim_appdata=$AppData
note=Loose-file priority is approximate. Plugin order comes from plugins.txt (exact).
refresh=Re-run Setup-HouseCarl.ps1 -RefreshOnly after load-order or mod installs when using copy mode.
patches=houseCARL writes 'houseCARL - *' folders under mods/ (Vortex staging). Import those into Vortex manually (drag folder or zip install) then deploy.
"@ | Set-Content -LiteralPath (Join-Path $Shim 'HOUSECARL-SHIM.txt') -Encoding UTF8
}

function Test-DotNet9 {
  try {
    $runtimes = & dotnet --list-runtimes 2>$null
    $hasNet = $runtimes | Where-Object { $_ -match '^Microsoft\.NETCore\.App 9\.' }
    $hasAsp = $runtimes | Where-Object { $_ -match '^Microsoft\.AspNetCore\.App 9\.' }
    return @{ net = [bool]$hasNet; asp = [bool]$hasAsp; raw = $runtimes }
  } catch {
    return @{ net = $false; asp = $false; raw = @() }
  }
}

function Update-GrokMcp {
  param([string]$McpExe,[string]$InstanceDir)
  $grokDir = Join-Path $env:USERPROFILE '.grok'
  $configPath = Join-Path $grokDir 'config.toml'
  New-DirectorySafe $grokDir
  $content = ''
  if (Test-ExistingPath $configPath) {
    $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
    Copy-Item -LiteralPath $configPath -Destination "$configPath.before-housecarl-$ts.bak" -Force
    $content = [IO.File]::ReadAllText($configPath)
  }
  $sectionPattern = '(?ms)^[ \t]*\[mcp_servers\.(?:housecarl|"housecarl"|''housecarl'')\][ \t]*\r?\n.*?(?=^[ \t]*\[|\z)'
  $content = [regex]::Replace($content, $sectionPattern, '')
  $content = [regex]::Replace($content, '(\r?\n){3,}', "`r`n`r`n").Trim()
  $exe = $McpExe.Replace('\','/')
  $inst = $InstanceDir.Replace('\','/')
  $block = @"
[mcp_servers.housecarl]
command = "$exe"
args = []
enabled = true
startup_timeout_sec = 120
tool_timeout_sec = 6000

[mcp_servers.housecarl.env]
HouseCarl__Mo2InstanceDir = "$inst"
HOUSECARL_DATA_DIR = "$($env:LOCALAPPDATA.Replace('\','/'))/houseCARL-data"
"@
  # Note: some TOML MCP hosts want env inline - if nested table fails, also document flat form in examples
  if ($content.Length -gt 0) {
    $newContent = $content.TrimEnd() + "`r`n`r`n" + $block.Trim() + "`r`n"
  } else {
    $newContent = $block.Trim() + "`r`n"
  }
  $utf8 = New-Object System.Text.UTF8Encoding($false)
  [IO.File]::WriteAllText($configPath, $newContent, $utf8)
  Write-Ok "Updated Grok MCP: $configPath"
}

function Update-GrokMcp-FlatEnv {
  # Grok may not support nested env tables - write a safer flat form used by many hosts:
  # command + args only, and rely on user/machine env vars.
  param([string]$McpExe,[string]$InstanceDir)
  $grokDir = Join-Path $env:USERPROFILE '.grok'
  $configPath = Join-Path $grokDir 'config.toml'
  New-DirectorySafe $grokDir
  $content = ''
  if (Test-ExistingPath $configPath) {
    $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
    Copy-Item -LiteralPath $configPath -Destination "$configPath.before-housecarl-$ts.bak" -Force
    $content = [IO.File]::ReadAllText($configPath)
  }
  $sectionPattern = '(?ms)^[ \t]*\[mcp_servers\.(?:housecarl|"housecarl"|''housecarl'')\][ \t]*\r?\n.*?(?=^[ \t]*\[|\z)'
  $content = [regex]::Replace($content, $sectionPattern, '')
  # also strip nested env table if present
  $content = [regex]::Replace($content, '(?ms)^[ \t]*\[mcp_servers\.housecarl\.env\][ \t]*\r?\n.*?(?=^[ \t]*\[|\z)', '')
  $content = [regex]::Replace($content, '(\r?\n){3,}', "`r`n`r`n").Trim()
  $exe = $McpExe.Replace('\','/')
  $block = @"
[mcp_servers.housecarl]
command = "$exe"
args = []
enabled = true
startup_timeout_sec = 120
tool_timeout_sec = 6000
"@
  if ($content.Length -gt 0) {
    $newContent = $content.TrimEnd() + "`r`n`r`n" + $block.Trim() + "`r`n"
  } else {
    $newContent = $block.Trim() + "`r`n"
  }
  $utf8 = New-Object System.Text.UTF8Encoding($false)
  [IO.File]::WriteAllText($configPath, $newContent, $utf8)
  Write-Ok "Updated Grok MCP (flat): $configPath"
}

function Set-UserEnv([string]$Name,[string]$Value) {
  [Environment]::SetEnvironmentVariable($Name, $Value, 'User')
  Set-Item -Path "Env:$Name" -Value $Value
  Write-Ok "User env $Name = $Value"
}

function Write-StateFile([hashtable]$State) {
  $dir = Join-Path $env:LOCALAPPDATA 'houseCARL-data'
  New-DirectorySafe $dir
  $path = Join-Path $dir 'v5-setup-state.json'
  ($State | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $path -Encoding UTF8
  Write-Ok "State: $path"
  return $path
}

function Write-CodexHint([string]$McpExe,[string]$InstanceDir) {
  $dir = Join-Path $env:USERPROFILE '.codex'
  New-DirectorySafe $dir
  $path = Join-Path $dir 'housecarl-mcp.snippet.toml'
  @"
# Paste into Codex MCP config (format varies by Codex version).
# houseCARL MCP
# command = "$($McpExe.Replace('\','/'))"
# env HouseCarl__Mo2InstanceDir = "$($InstanceDir.Replace('\','/'))"
# After edit: fully restart Codex.
"@ | Set-Content -LiteralPath $path -Encoding UTF8
  Write-Ok "Codex hint: $path"
}

# ---------------- main ----------------
Write-Host ""
Write-Host "houseCARL V5 automatic setup (MO2 + Vortex shim)" -ForegroundColor Magenta
Write-Host ""

if (-not $ShimRoot) { $ShimRoot = Join-Path $env:LOCALAPPDATA 'houseCARL-Shim' }

if (-not $SkipDotNetCheck) {
  Write-Step "Checking .NET 9 runtimes"
  $dn = Test-DotNet9
  if ($dn.net) { Write-Ok ".NET 9 runtime present" } else { Write-Bad ".NET 9 Runtime MISSING - winget install Microsoft.DotNet.Runtime.9" }
  if ($dn.asp) { Write-Ok "ASP.NET Core 9 runtime present" } else { Write-Bad "ASP.NET Core 9 Runtime MISSING - winget install Microsoft.DotNet.AspNetCore.9" }
  $script:Report['dotnet9'] = $dn.net
  $script:Report['aspnet9'] = $dn.asp
}

Write-Step "Locating housecarl-mcp.exe"
$mcp = Find-HouseCarlMcp -Hint $HouseCarlMcp
if (-not $mcp) {
  Write-Bad "housecarl-mcp.exe not found."
  Write-Host @"

INSTALL houseCARL first:
  1. Run houseCARL-Setup.exe from the houseCARL distribution
     (or copy the housecarl\ folder so server\housecarl-mcp.exe exists)
  2. Install .NET 9 Runtime + ASP.NET Core Runtime 9
  3. Re-run this script

Optional: -HouseCarlMcp 'D:\path\housecarl-mcp.exe'
"@
  exit 2
}
Write-Ok $mcp
$script:Report['mcp'] = $mcp

Write-Step "Locating Skyrim SE"
$game = Find-SkyrimSe -Hint $SkyrimPath
if (-not $game) {
  Write-Warn2 "Skyrim SE path not auto-detected. Pass -SkyrimPath 'C:\...\Skyrim Special Edition'"
} else {
  Write-Ok $game
}
$script:Report['skyrim'] = $game

$appData = Get-SkyrimAppData
if ($appData) { Write-Ok "Skyrim AppData: $appData" } else { Write-Warn2 "No %LOCALAPPDATA%\Skyrim Special Edition yet" }

# Detect managers
$mo2List = @()
if ($Mo2Instance) {
  if (-not (Test-ExistingPath (Join-Path $Mo2Instance 'ModOrganizer.ini'))) {
    throw "Mo2Instance does not contain ModOrganizer.ini: $Mo2Instance"
  }
  $mo2List = @((Resolve-Path -LiteralPath $Mo2Instance).Path)
} else {
  # @() is load-bearing. Find-Mo2Instances returns a List[string], and a
  # single-element return unrolls to a bare [string] on the way out. A string
  # still answers .Count = 1, so the MO2 branch is taken, and $mo2List[0] then
  # indexes the STRING - yielding its first character ("C" of "C:\..."). That
  # is how SKYRIM_MO2_INSTANCE ends up set to "C".
  $mo2List = @(Find-Mo2Instances)
}

$staging = $null
if ($VortexStaging) {
  $staging = (Resolve-Path -LiteralPath $VortexStaging).Path
} else {
  $staging = Find-VortexStaging
}

Write-Step "Manager detection"
Write-Host "  MO2 instances found: $($mo2List.Count)"
foreach ($m in $mo2List) { Write-Host "    - $m" }
Write-Host "  Vortex staging: $(if($staging){$staging}else{'not found'})"

$mode = $Manager
$instanceDir = $null

if ($mode -eq 'Auto') {
  if ($mo2List.Count -ge 1) { $mode = 'MO2' }
  elseif ($staging) { $mode = 'Vortex' }
  else {
    Write-Bad "Neither MO2 instance nor Vortex staging found."
    Write-Host "Pass -Mo2Instance or -VortexStaging explicitly."
    exit 3
  }
}

if ($RefreshOnly) {
  if (-not (Test-ExistingPath (Join-Path $ShimRoot 'ModOrganizer.ini'))) {
    throw "RefreshOnly requires an existing shim at $ShimRoot - run full setup first."
  }
  if (-not $staging) { $staging = Find-VortexStaging }
  if (-not $staging) { throw "Vortex staging required for refresh" }
  if (-not $game) { $game = Find-SkyrimSe -Hint $SkyrimPath }
  if (-not $game) { throw "Skyrim path required for refresh" }
  if (-not $appData) { throw "Skyrim AppData plugins.txt not found" }
  Write-Step "Refreshing Vortex shim at $ShimRoot"
  Update-VortexShim -Shim $ShimRoot -Staging $staging -GamePath $game -AppData $appData -SymlinkPlugins:$PreferSymlinkPlugins
  $instanceDir = $ShimRoot
} elseif ($mode -eq 'MO2') {
  if ($mo2List.Count -eq 0) { throw "MO2 mode but no instance found. Pass -Mo2Instance" }
  if ($mo2List.Count -gt 1 -and -not $Mo2Instance) {
    Write-Warn2 "Multiple MO2 instances - selecting the first. Pass -Mo2Instance to override."
  }
  $instanceDir = $mo2List[0]
  Write-Step "Using MO2 instance"
  Write-Ok $instanceDir
} elseif ($mode -eq 'Vortex') {
  if (-not $staging) { throw "Vortex staging not found. Pass -VortexStaging" }
  if (-not $game) { throw "Skyrim path required for Vortex shim. Pass -SkyrimPath" }
  if (-not $appData) { throw "Need %LOCALAPPDATA%\Skyrim Special Edition\plugins.txt - run the game or Vortex once." }
  Write-Step "Building Vortex shim (MO2-shaped) at $ShimRoot"
  Write-Host "  Based on: TOOLS/housecarl/houseCARL-Vortex-shim-setup.pdf"
  Update-VortexShim -Shim $ShimRoot -Staging $staging -GamePath $game -AppData $appData -SymlinkPlugins:$PreferSymlinkPlugins
  $instanceDir = $ShimRoot
  Write-Warn2 "Loose-file priority in modlist.txt is approximate; plugin order is exact."
  Write-Warn2 "After Vortex load-order changes: re-run with -RefreshOnly (unless plugins are symlinked)."
  Write-Warn2 "Import houseCARL - * patch folders into Vortex manually, then Deploy."
}

$script:Report['mode'] = $mode
$script:Report['instance'] = $instanceDir

# Refuse to persist an instance that is not a real MO2-shaped directory. A
# malformed value here is silent: houseCARL starts, then every load-order read
# fails against a path that never existed.
if (-not (Test-ExistingPath (Join-Path $instanceDir 'ModOrganizer.ini'))) {
  Write-Bad "Refusing to persist a bogus MO2 instance: '$instanceDir'"
  Write-Host "  Expected a directory containing ModOrganizer.ini."
  Write-Host "  Pass -Mo2Instance <path>, or -VortexStaging <path> to build a shim."
  exit 4
}

Write-Step "Persisting environment"
Set-UserEnv -Name 'HOUSECARL_MCP' -Value $mcp
Set-UserEnv -Name 'SKYRIM_MO2_INSTANCE' -Value $instanceDir
Set-UserEnv -Name 'HouseCarl__Mo2InstanceDir' -Value $instanceDir
if ($game) { Set-UserEnv -Name 'SKYRIM_SE_PATH' -Value $game }

if ($WireGrok -and -not $RefreshOnly) {
  Write-Step "Wiring Grok MCP"
  try {
    # Prefer flat config + env vars (more portable across Grok versions)
    Update-GrokMcp-FlatEnv -McpExe $mcp -InstanceDir $instanceDir
  } catch {
    Write-Warn2 "Grok config update failed: $($_.Exception.Message)"
  }
}

if ($WireCodex -and -not $RefreshOnly) {
  Write-Step "Writing Codex hint"
  try { Write-CodexHint -McpExe $mcp -InstanceDir $instanceDir } catch { Write-Warn2 $_ }
}

$statePath = Write-StateFile @{
  version = '5.0.0'
  generated_utc = [DateTime]::UtcNow.ToString('o')
  mode = $mode
  housecarl_mcp = $mcp
  mo2_instance_or_shim = $instanceDir
  vortex_staging = $staging
  skyrim_path = $game
  skyrim_appdata = $appData
  shim_root = $ShimRoot
  notes = @(
    'Claude Code: run houseCARL-Setup.exe or set plugin user_config mo2_instance_dir to the instance/shim path.',
    'Grok: restart Grok fully after MCP edit; env HouseCarl__Mo2InstanceDir is set at user scope.',
    'Vortex: re-run -RefreshOnly after load order / new mods when using copy mode.'
  )
}

Write-Host ""
Write-Host "========== SETUP COMPLETE ==========" -ForegroundColor Green
Write-Host "Mode:     $mode"
Write-Host "Instance: $instanceDir"
Write-Host "MCP:      $mcp"
Write-Host "State:    $statePath"
Write-Host ""
Write-Host "NEXT:" -ForegroundColor Yellow
Write-Host "  1. FULLY restart your AI app (Grok / Claude / Codex)."
Write-Host "  2. Confirm houseCARL MCP tools are visible."
Write-Host "  3. Ask: what does my Skyrim load order look like?"
Write-Host "  4. Claude plugin users: set MO2 instance folder to:"
Write-Host "       $instanceDir"
Write-Host "  5. Vortex users: after load-order changes run:"
Write-Host "       .\Setup-HouseCarl.ps1 -RefreshOnly"
Write-Host ""
if ($mode -eq 'Vortex') {
  Write-Host "Vortex patch hand-off: houseCARL writes mods under staging as 'houseCARL - <name>'." -ForegroundColor Yellow
  Write-Host "Drag that folder into Vortex Mods (or zip + Install From File), enable, Deploy." -ForegroundColor Yellow
}
Write-Host "Reference PDF: TOOLS\housecarl\houseCARL-Vortex-shim-setup.pdf"
Write-Host ""

# exit non-zero if critical runtimes missing (still wrote shim)
if (-not $SkipDotNetCheck -and (-not $script:Report['dotnet9'] -or -not $script:Report['aspnet9'])) {
  Write-Warn2 "Setup wrote paths but .NET 9 pair is incomplete - houseCARL MCP may fail until installed."
  exit 4
}
exit 0

