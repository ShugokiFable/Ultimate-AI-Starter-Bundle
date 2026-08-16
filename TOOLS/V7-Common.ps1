# V7-Common.ps1 - shared helpers for Skyrim AI V5 AIO installer
$script:V5PackRoot = $null
$script:V5Headers = @{ 'User-Agent' = 'Skyrim-AI-V5-AIO/5.2.2' }

function Get-V5PackRoot {
  if ($script:V5PackRoot -and (Test-Path -LiteralPath $script:V5PackRoot)) { return $script:V5PackRoot }
  $here = $PSScriptRoot
  if (Test-Path (Join-Path $here 'BUNDLED-TOOLS\CATALOG.json')) { $script:V5PackRoot = $here; return $here }
  $parent = Split-Path $here -Parent
  if (Test-Path (Join-Path $parent 'BUNDLED-TOOLS\CATALOG.json')) { $script:V5PackRoot = $parent; return $parent }
  throw 'Cannot locate pack root (BUNDLED-TOOLS\CATALOG.json). Run from the V5 pack folder.'
}

function Get-V5Catalog {
  $root = Get-V5PackRoot
  $path = Join-Path $root 'BUNDLED-TOOLS\CATALOG.json'
  return (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json)
}

function Expand-V5EnvPath([string]$p) {
  if ([string]::IsNullOrWhiteSpace($p)) { return $p }
  return [Environment]::ExpandEnvironmentVariables($p)
}

function Test-V5Path([string]$p) {
  if ([string]::IsNullOrWhiteSpace($p)) { return $false }
  try { return Test-Path -LiteralPath (Expand-V5EnvPath $p) } catch { return $false }
}

function Write-V5Step([string]$m) { Write-Host ("==> " + $m) -ForegroundColor Cyan }
function Write-V5Ok([string]$m)   { Write-Host ("  OK  " + $m) -ForegroundColor Green }
function Write-V5Warn([string]$m) { Write-Host ("  !!  " + $m) -ForegroundColor Yellow }
function Write-V5Bad([string]$m)  { Write-Host ("  XX  " + $m) -ForegroundColor Red }

function Set-V5UserEnv([string]$Name, [string]$Value) {
  [Environment]::SetEnvironmentVariable($Name, $Value, 'User')
  Set-Item -Path ("Env:" + $Name) -Value $Value
}

function Get-V5ProviderHome([string]$Provider, $Catalog) {
  $p = $Catalog.providers.$Provider
  if (-not $p) { throw ("Unknown provider " + $Provider) }
  $envName = $p.home_env
  $fromEnv = [Environment]::GetEnvironmentVariable($envName, 'User')
  if (-not $fromEnv) { $fromEnv = [Environment]::GetEnvironmentVariable($envName, 'Process') }
  if ($fromEnv) { return $fromEnv }
  return (Expand-V5EnvPath $p.home_default)
}

function Invoke-V5GitHubLatest {
  param([string]$Owner, [string]$Repo)
  $uri = "https://api.github.com/repos/$Owner/$Repo/releases/latest"
  return Invoke-RestMethod -Uri $uri -Headers $script:V5Headers -TimeoutSec 60
}

function Get-V5ReleaseAsset {
  param($Release, [string[]]$Patterns)
  foreach ($pat in $Patterns) {
    $a = @($Release.assets | Where-Object { $_.name -like $pat }) | Select-Object -First 1
    if ($a) { return $a }
  }
  return $null
}

function Save-V5Url {
  param([string]$Url, [string]$OutFile)
  $dir = Split-Path $OutFile -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  Write-V5Step ("Download " + (Split-Path $OutFile -Leaf))
  Invoke-WebRequest -Uri $Url -OutFile $OutFile -Headers $script:V5Headers -TimeoutSec 900
  Write-V5Ok (("{0:N1} MB" -f ((Get-Item $OutFile).Length / 1MB)))
}

function Expand-V5Zip {
  param([string]$Zip, [string]$Dest, [switch]$WipeDest)
  if ($WipeDest -and (Test-Path $Dest)) { Remove-Item -LiteralPath $Dest -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $Dest | Out-Null
  Expand-Archive -LiteralPath $Zip -DestinationPath $Dest -Force
}

function Resolve-V5SingleRoot {
  param([string]$Dest)
  $kids = @(Get-ChildItem -LiteralPath $Dest -Force | Where-Object { $_.Name -ne '__MACOSX' })
  if ($kids.Count -eq 1 -and $kids[0].PSIsContainer) { return $kids[0].FullName }
  return $Dest
}

function Find-V5FileUnder {
  param([string]$Root, [string]$Name, [int]$Depth = 6)
  if (-not (Test-Path $Root)) { return $null }
  $hit = Get-ChildItem -LiteralPath $Root -Filter $Name -Recurse -Depth $Depth -File -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($hit) { return $hit.FullName }
  return $null
}

function Test-V5DotNetRuntime([string]$Pattern) {
  try {
    $r = & dotnet --list-runtimes 2>$null
    return [bool]($r | Where-Object { $_ -match $Pattern })
  } catch { return $false }
}

function Install-V5Winget([string[]]$Ids) {
  $winget = Get-Command winget -ErrorAction SilentlyContinue
  if (-not $winget) { Write-V5Warn 'winget not available - install runtime manually'; return $false }
  foreach ($id in $Ids) {
    Write-V5Step ("winget install " + $id)
    & winget install --id $id -e --accept-package-agreements --accept-source-agreements | Out-Host
  }
  return $true
}

function Test-V5FileLocked([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
  try {
    $fs = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    $fs.Close()
    return $false
  } catch {
    return $true
  }
}

function Find-V5CodebaseMemoryExe {
  $cands = @()
  if ($env:CODEBASE_MEMORY_MCP) { $cands += $env:CODEBASE_MEMORY_MCP }
  $u = [Environment]::GetEnvironmentVariable('CODEBASE_MEMORY_MCP', 'User')
  if ($u) { $cands += $u }
  $cands += (Join-Path $env:LOCALAPPDATA 'Programs\codebase-memory-mcp\codebase-memory-mcp.exe')
  $cands += (Join-Path $env:USERPROFILE '.local\bin\codebase-memory-mcp.exe')
  foreach ($c in $cands) {
    if ($c -and (Test-Path -LiteralPath $c -PathType Leaf)) {
      return (Resolve-Path -LiteralPath $c).Path
    }
  }
  return $null
}

function Update-V5GrokMcpBlock {
  param(
    [string]$Name,
    [string]$Command,
    [string[]]$ArgList = @(),
    [hashtable]$EnvMap = $null,
    [int]$Startup = 90,
    [int]$Tool = 6000,
    [switch]$SkipIfPresent,
    # Codex uses the same [mcp_servers.<name>] TOML shape as Grok, so the same
    # writer serves both. Defaults to ~/.grok/config.toml.
    [string]$ConfigPath = $null
  )
  if ($ConfigPath) {
    $configPath = $ConfigPath
    $grokDir = Split-Path $configPath -Parent
  } else {
    $grokDir = Join-Path $env:USERPROFILE '.grok'
    $configPath = Join-Path $grokDir 'config.toml'
  }
  New-Item -ItemType Directory -Force -Path $grokDir | Out-Null
  $content = ''
  if (Test-Path -LiteralPath $configPath) {
    $content = Get-Content -LiteralPath $configPath -Raw
  }

  $cmdNorm = ($Command -replace '\\', '/').Trim()
  if ($SkipIfPresent -and $content) {
    $nameEsc = [regex]::Escape($Name)
    $m = [regex]::Match($content, '(?ms)^[ \t]*\[mcp_servers\.(?:' + $nameEsc + ')\][ \t]*\r?\n(?:.*?\r?\n)*?[ \t]*command[ \t]*=[ \t]*["'']([^"'']+)["'']')
    if ($m.Success) {
      $existingCmd = ($m.Groups[1].Value -replace '\\', '/').Trim()
      if ($existingCmd -ieq $cmdNorm) {
        Write-V5Ok ('Grok MCP unchanged (already correct): ' + $Name)
        return
      }
    }
  }

  if (Test-Path -LiteralPath $configPath) {
    $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
    $bak = $configPath + '.before-v5-' + $Name + '-' + $ts + '.bak'
    Copy-Item -LiteralPath $configPath -Destination $bak -Force
  }

  $nameEsc = [regex]::Escape($Name)
  $q = [char]39
  $pat1 = '(?ms)^[ \t]*\[mcp_servers\.(?:' + $nameEsc + '|"' + $nameEsc + '|' + $q + $nameEsc + $q + ')\][ \t]*\r?\n.*?(?=^[ \t]*\[|\z)'
  $pat2 = '(?ms)^[ \t]*\[mcp_servers\.' + $nameEsc + '\.env\][ \t]*\r?\n.*?(?=^[ \t]*\[|\z)'
  $content = [regex]::Replace([string]$content, $pat1, '')
  $content = [regex]::Replace([string]$content, $pat2, '')
  $content = [regex]::Replace([string]$content, '(\r?\n){3,}', "`r`n`r`n").Trim()

  $cmd = $Command.Replace('\', '/')
  $argsToml = ''
  if ($ArgList -and $ArgList.Count -gt 0) {
    $parts = foreach ($a in $ArgList) { '"' + ($a -replace '\\', '/') + '"' }
    $argsToml = ($parts -join ', ')
  }

  $nl = "`r`n"
  $block = '[mcp_servers.' + $Name + ']' + $nl
  $block += 'command = "' + $cmd + '"' + $nl
  $block += 'args = [' + $argsToml + ']' + $nl
  $block += 'enabled = true' + $nl
  $block += 'startup_timeout_sec = ' + $Startup + $nl
  $block += 'tool_timeout_sec = ' + $Tool + $nl

  if ($EnvMap -and $EnvMap.Count -gt 0) {
    $block += $nl + '[mcp_servers.' + $Name + '.env]' + $nl
    foreach ($k in $EnvMap.Keys) {
      $v = [string]$EnvMap[$k]
      if ($v -match '^%(.+)%$') {
        $en = $Matches[1]
        $ev = [Environment]::GetEnvironmentVariable($en, 'User')
        if (-not $ev) { $ev = [Environment]::GetEnvironmentVariable($en, 'Process') }
        if ($ev) { $v = $ev }
      }
      $block += $k + ' = "' + ($v.Replace('\', '/')) + '"' + $nl
    }
  }

  if ($content.Length -gt 0) {
    $new = $content.TrimEnd() + $nl + $nl + $block.Trim() + $nl
  } else {
    $new = $block.Trim() + $nl
  }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [IO.File]::WriteAllText($configPath, $new, $enc)
  Write-V5Ok ('Grok MCP: ' + $Name)
}

function Copy-V5Robo([string]$From, [string]$To) {
  New-Item -ItemType Directory -Force -Path $To | Out-Null
  & robocopy $From $To /E /COPY:DAT /R:1 /W:1 /NFL /NDL /NJH /NJS | Out-Null
  $code = $LASTEXITCODE
  if ($code -ge 8) {
    throw ('robocopy failed exit=' + $code + ' from=' + $From + ' to=' + $To)
  }
}

function Copy-V5RoboSafe([string]$From, [string]$To, [string[]]$CriticalFiles = @()) {
  foreach ($rel in $CriticalFiles) {
    $destFile = Join-Path $To $rel
    if ((Test-Path -LiteralPath $destFile -PathType Leaf) -and (Test-V5FileLocked $destFile)) {
      throw ('REFUSE overwrite locked file (MCP likely running): ' + $destFile + ' - stop the AI app or MCP process first, or skip this component.')
    }
  }
  Copy-V5Robo -From $From -To $To
}

function Set-V5GrokCompatCells {
  <#
    Turn off Grok's inheritance of Claude Code's hooks and MCP servers.

    Grok ships Claude-Code compatibility ON by default: it adopts
    ~/.claude/skills, ~/.claude/agents, ~/.claude/plugins (with their
    hooks/hooks.json and .mcp.json), ~/.claude.json and
    ~/.claude/settings.json. Measured on grok-cli 1.0.4 (2026-08-15):

      - inherited Claude hooks cost 60.037s per turn (two Stop hooks at
        timeout 30, and Grok never closes a hook's stdin);
      - MCP startup cost 65s on the first turn of every session and
        attached ZERO tools - tool_count was 26 (the built-in count) in
        all 12 turns recorded, with 8 servers configured and with 0.

    Skills, rules and agents compat stay ON: those work and are the reason
    Grok sees the canonical skill set without a second copy on disk.
    See GROK-MCP-TROUBLESHOOTING.md.
  #>
  param(
    [string]$ConfigPath = $null,
    [switch]$AllowMcp
  )
  if (-not $ConfigPath) {
    $grokDir = Join-Path $env:USERPROFILE '.grok'
    $ConfigPath = Join-Path $grokDir 'config.toml'
  } else {
    $grokDir = Split-Path $ConfigPath -Parent
  }
  New-Item -ItemType Directory -Force -Path $grokDir | Out-Null

  $content = ''
  if (Test-Path -LiteralPath $ConfigPath) {
    $content = Get-Content -LiteralPath $ConfigPath -Raw
    $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
    Copy-Item -LiteralPath $ConfigPath -Destination ($ConfigPath + '.before-compat-' + $ts + '.bak') -Force
  }

  $mcps = if ($AllowMcp) { 'true' } else { 'false' }
  $block = @(
    '[compat.claude]',
    '# Grok inherits Claude Code config by default. Both cells below were',
    '# measured as pure cost on grok-cli 1.0.4: hooks cost 60.037s/turn and',
    '# MCP cost 65s/session while attaching zero tools (tool_count stayed at',
    '# 26, the built-in count). See GROK-MCP-TROUBLESHOOTING.md.',
    'hooks = false',
    ('mcps = ' + $mcps)
  ) -join "`r`n"

  if ($content -match '(?ms)^[ \t]*\[compat\.claude\][ \t]*\r?\n(?:(?![ \t]*\[).*\r?\n?)*') {
    $content = [regex]::Replace(
      $content,
      '(?ms)^[ \t]*\[compat\.claude\][ \t]*\r?\n(?:(?![ \t]*\[).*\r?\n?)*',
      ($block + "`r`n`r`n"))
  } else {
    if ($content -and -not $content.EndsWith("`n")) { $content += "`r`n" }
    $content = $content + "`r`n" + $block + "`r`n"
  }
  # UTF-8 with NO BOM: PS 5.1's -Encoding utf8 emits a BOM, and a BOM makes the
  # first line unparseable TOML ("Invalid statement at line 1, column 1").
  [System.IO.File]::WriteAllText($ConfigPath, $content, (New-Object System.Text.UTF8Encoding $false))
  if ($AllowMcp) {
    Write-V5Warn 'Grok: Claude hook inheritance OFF, MCP inheritance left ON by request (expect a ~65s first turn)'
  } else {
    Write-V5Ok 'Grok: Claude hook + MCP inheritance disabled (turn time 97s -> ~2s)'
  }
}

# v7.5.0: SOUL + AIO preamble wiring. Appends (or replaces) the marked
# preamble block in an agent instruction file. Idempotent, backup first.
# Existing files keep their own encoding; writes are UTF-8 without BOM.
function Install-V5PreambleBlock {
  param(
    [string]$Path,
    [string]$SoulFile,
    [string]$AioFile,
    [switch]$Force
  )
  if (-not (Test-Path -LiteralPath $SoulFile)) { throw 'preamble SOUL file missing: ' + $SoulFile }
  if (-not (Test-Path -LiteralPath $AioFile))  { throw 'preamble AIO file missing: ' + $AioFile }
  $soul = (Get-Content -LiteralPath $SoulFile -Raw).Trim()
  $aio  = (Get-Content -LiteralPath $AioFile -Raw).Trim()
  $nl = "`r`n"
  $open = '<!-- ULTIMATE-AI-STARTER-BUNDLE SOUL v7.5.0 -->'
  $mid  = '<!-- ULTIMATE-AI-STARTER-BUNDLE AIO (operating contract) -->'
  $end  = '<!-- /ULTIMATE-AI-STARTER-BUNDLE SOUL -->'
  $block = $open + $nl + $soul + $nl + $nl + $mid + $nl + $aio + $nl + $end
  $dir = Split-Path $Path -Parent
  if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $pre = ''
    $origBom = $false
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
      $pre = [IO.File]::ReadAllText($Path)
      $pb = [IO.File]::ReadAllBytes($Path)
      $origBom = ($pb.Length -ge 3 -and $pb[0] -eq 0xEF -and $pb[1] -eq 0xBB -and $pb[2] -eq 0xBF)
    }
    $pat = '(?ms)^[ \t]*<!--[ \t]*ULTIMATE-AI-STARTER-BUNDLE SOUL.*?^[ \t]*<!--[ \t]*/ULTIMATE-AI-STARTER-BUNDLE SOUL[ \t]*-->[ \t]*\r?\n?'

    $new = ''
    if ([regex]::IsMatch($pre, $pat)) {
      $new = [regex]::Replace($pre, $pat, ($block + $nl))
    } else {
      if ($pre) { $new = $pre.TrimEnd("`r", "`n") + $nl + $nl + $block + $nl }
      else { $new = $block + $nl }
    }
    if (-not $Force -and $new -ceq $pre) {
      Write-V5Ok ('preamble unchanged (already current): ' + $Path)
      return
    }
    $ts = Get-Date -Format 'yyyyMMdd-HHmmssfff'
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
      Copy-Item -LiteralPath $Path -Destination ($Path + '.before-soul-' + $ts + '.bak') -Force
    }
    # UTF-8. A file that already had a BOM keeps it (ReadAllText strips it, so
    # write it back); a BOM-less file stays BOM-less. PS 5.1 -Encoding utf8 would
    # add one and break strict readers.
    [IO.File]::WriteAllText($Path, $new, (New-Object System.Text.UTF8Encoding $origBom))
    Write-V5Ok ('preamble wired: ' + $Path)
}
