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
  return ([IO.File]::ReadAllText($path) | ConvertFrom-Json)
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
    $content = [IO.File]::ReadAllText($configPath)
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
    $content = [IO.File]::ReadAllText($ConfigPath)
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

    if ($content -match '(?m)^[ \t]*\[compat\.claude\][^\r\n]*(?:\r?\n(?![ \t]*\[)[^\r\n]*)*') {
    # WARNING: the old pattern used `(?ms)...(?:(?![ \t]*\[).*\r?\n?)*` - the
    # singleline `.` swallowed the WHOLE tail after [compat.claude], deleting
    # every [mcp_servers.*] block on any machine that already had the section.
    # The correct section body = lines that do NOT start with '[' - matched
    # line-by-line above (see V7.5.1-CHANGELOG.md).
    $content = [regex]::Replace(
      $content,
      '(?m)^[ \t]*\[compat\.claude\][^\r\n]*(?:\r?\n(?![ \t]*\[)[^\r\n]*)*',
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
  # ReadAllText, NOT Get-Content -Raw. On PS 5.1 Get-Content without -Encoding
  # decodes using the ANSI codepage (Windows-1252 here), so a UTF-8 em dash
  # (E2 80 94) comes back as three chars and gets written out as mojibake.
  # v7.5.6 swept the mojibake out of the pack files but left this read path,
  # so every install re-created it. ReadAllText honours the UTF-8 encoding.
  $soul = ([IO.File]::ReadAllText($SoulFile)).Trim()
  $aio  = ([IO.File]::ReadAllText($AioFile)).Trim()
  $nl = "`r`n"
  # Stamp the pack version that wired the block, so a stale block is visible
  # on sight. The replace pattern keys on the marker prefix, not the version,
  # so an older stamp is still found and replaced.
  $ver = 'v7.5.0'
  try {
    $vf = Join-Path (Get-V5PackRoot) 'VERSION.txt'
    if (Test-Path -LiteralPath $vf) { $ver = ([IO.File]::ReadAllText($vf)).Trim() }
  } catch { }
  $open = '<!-- ULTIMATE-AI-STARTER-BUNDLE SOUL ' + $ver + ' -->'
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

# ---------------------------------------------------------------------------
# Native bundled plugins (superpowers / ponytail) - shared helpers.
# The per-provider orchestration lives in INSTALL-V7-AIO.ps1; these are the
# mechanism pieces: native command output capture, plugin-owned skill name
# discovery, the md5-guarded dedupe, a TOML plugin-section probe, the Hermes
# scan_on_install config fix, and a style-preserving marketplace.json edit.
# ---------------------------------------------------------------------------

function Get-V5NativeOutput {
  <#
  Run a native command and return its combined output as one string, without
  PowerShell 5.1 turning stderr lines into terminating ErrorRecords under the
  script-wide $ErrorActionPreference='Stop'. (Same disease Invoke-V5Native
  cures; this variant is for DETECTION, where the output itself is needed.)
  #>
  param([string]$Exe, [string[]]$CmdArgs)
  $prevEap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try { return (& $Exe @CmdArgs 2>&1 | Out-String) } finally { $ErrorActionPreference = $prevEap }
}

function Get-V5PluginOwnedSkillNames {
  <#
  Skill names a bundled plugin owns, computed from the tree at install time -
  never a hardcoded list, so a plugin version bump that adds/renames a skill
  is picked up automatically.
  #>
  param([string]$PluginRoot)
  $sk = Join-Path $PluginRoot 'skills'
  if (-not (Test-Path -LiteralPath $sk -PathType Container)) { return @() }
  return @(Get-ChildItem -LiteralPath $sk -Directory | Select-Object -ExpandProperty Name)
}

function Remove-V5PluginOwnedSkillCopies {
  <#
  Remove provider-skills copies that a natively installed plugin now owns.

  Safety rules (the destructive step of the native-plugin rework):
    - skip names with no <SkillsDir>\<name> directory (nothing to do);
    - NEVER remove a copy whose SKILL.md md5 differs from the pack canonical
      (<CanonicalRoot>\<name>\SKILL.md) - a difference means the user may have
      modified the copy, so warn loudly and record it as skipped_modified;
    - a copy with no SKILL.md, or a name absent from the canonical tree, is
      unverifiable - keep it and record why;
    - before any Remove-Item, robocopy the directory to
      <BackupRoot>\dedupe-<Provider>-<yyyyMMdd-HHmmss>\<name>.

  Returns an ordered dict: removed / skipped_modified / skipped (string lists).
  #>
  param(
    [string]$Provider,
    [string]$SkillsDir,
    [string[]]$Names,
    [string]$CanonicalRoot,
    [string]$BackupRoot,
    [System.Collections.Generic.List[string]]$Log
  )
  $result = [ordered]@{ removed = @(); skipped_modified = @(); skipped = @() }
  if (-not (Test-Path -LiteralPath $SkillsDir -PathType Container)) { return $result }
  $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
  $bkDir = Join-Path $BackupRoot ('dedupe-' + $Provider + '-' + $ts)
  foreach ($name in $Names) {
    $target = Join-Path $SkillsDir $name
    if (-not (Test-Path -LiteralPath $target -PathType Container)) { continue }
    $copyMd = Join-Path $target 'SKILL.md'
    $canonMd = Join-Path (Join-Path $CanonicalRoot $name) 'SKILL.md'
    if (-not (Test-Path -LiteralPath $copyMd -PathType Leaf)) {
      $result.skipped += ($name + ' (copy has no SKILL.md - unverifiable, kept)')
      Write-V5Warn ('dedupe: kept ' + $name + ' - copy has no SKILL.md to verify against canonical')
      if ($Log) { [void]$Log.Add((Get-Date -Format o) + ' dedupe: kept ' + $name + ' in ' + $SkillsDir + ' (no SKILL.md)') }
      continue
    }
    if (-not (Test-Path -LiteralPath $canonMd -PathType Leaf)) {
      # The canonical tree never shipped a skill of this name, so there is
      # nothing to verify the copy against. Keep it.
      $result.skipped += ($name + ' (absent from canonical tree - kept)')
      Write-V5Warn ('dedupe: kept ' + $name + ' - no canonical SKILL.md to verify against')
      if ($Log) { [void]$Log.Add((Get-Date -Format o) + ' dedupe: kept ' + $name + ' in ' + $SkillsDir + ' (not in canonical)') }
      continue
    }
    $hCopy = (Get-FileHash -LiteralPath $copyMd -Algorithm MD5).Hash
    $hCanon = (Get-FileHash -LiteralPath $canonMd -Algorithm MD5).Hash
    if ($hCopy -ne $hCanon) {
      $result.skipped_modified += $name
      Write-V5Warn ('dedupe: REFUSED to remove ' + $target + ' - SKILL.md differs from the pack canonical (user-modified?). Back up your changes and remove it by hand if unwanted.')
      if ($Log) { [void]$Log.Add((Get-Date -Format o) + ' dedupe: REFUSED ' + $target + ' (md5 differs from canonical)') }
      continue
    }
    New-Item -ItemType Directory -Force -Path $bkDir | Out-Null
    Copy-V5Robo -From $target -To (Join-Path $bkDir $name)
    Remove-Item -LiteralPath $target -Recurse -Force
    $result.removed += $name
    Write-V5Ok ('dedupe: removed plugin-owned copy ' + $name + ' (backup: ' + (Join-Path $bkDir $name) + ')')
    if ($Log) { [void]$Log.Add((Get-Date -Format o) + ' dedupe: removed ' + $target + ' (backup ' + $bkDir + ')') }
  }
  return $result
}

function Test-V5TomlPluginEnabled {
  <#
  True when TOML content has a section whose header starts with
  [<HeaderPrefix> and whose body contains enabled = true. Line-based on
  purpose: regex-over-sections is how config.toml readers have been burned
  before (see the [compat.claude] comment in Set-V5GrokCompatCells).
  #>
  param([string]$Content, [string]$HeaderPrefix)
  if ([string]::IsNullOrEmpty($Content)) { return $false }
  $inSection = $false
  foreach ($ln in ($Content -split "\r?\n")) {
    $t = $ln.Trim()
    if ($t.StartsWith('[')) {
      $inSection = $t.StartsWith('[' + $HeaderPrefix)
      continue
    }
    if ($inSection -and $t -match '^enabled\s*=\s*true\s*$') { return $true }
  }
  return $false
}

function Set-V5HermesPluginScanOff {
  <#
  Ensure plugins.scan_on_install: false in the Hermes config.yaml.

  Hermes' security scanner refuses both bundled plugins with 214
  false-positive 'traversal' findings in upstream test scripts, and --force
  does not override it, so the scanner must be told not to run at install
  time. This is a TEXT edit, never a YAML re-serialize: any comment the
  operator added survives untouched.

  Rules: a scan_on_install: line already under plugins: is left exactly as
  is; otherwise insert '  scan_on_install: false' right after the
  'disabled: []' line under plugins: (or right after 'plugins:' when there
  is no disabled key). Backup to config.yaml.bak-<yyyyMMdd-HHmmss> first.

  Returns 'already-present' | 'inserted' | 'appended-section' | 'created' | 'failed'.
  #>
  param([string]$ConfigPath)
  try {
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
      $dir = Split-Path $ConfigPath -Parent
      New-Item -ItemType Directory -Force -Path $dir | Out-Null
      $enc0 = New-Object System.Text.UTF8Encoding($false)
      [IO.File]::WriteAllText($ConfigPath, ("plugins:`r`n  scan_on_install: false`r`n"), $enc0)
      Write-V5Warn ('Hermes config.yaml missing - created with plugins.scan_on_install: false (' + $ConfigPath + ')')
      return 'created'
    }
    $text = [IO.File]::ReadAllText($ConfigPath)
    $nl = "`r`n"
    if ($text -notmatch "`r`n") { $nl = "`n" }
    $lines = @($text -split "\r?\n")
    $pIdx = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
      if ($lines[$i] -match '^plugins\s*:') { $pIdx = $i; break }
    }
    if ($pIdx -lt 0) {
      # No plugins: key at all - append a minimal one.
      Copy-Item -LiteralPath $ConfigPath -Destination ($ConfigPath + '.bak-' + (Get-Date -Format 'yyyyMMdd-HHmmss')) -Force
      $add = $text
      if (-not $add.EndsWith("`n")) { $add += $nl }
      $add += $nl + 'plugins:' + $nl + '  scan_on_install: false' + $nl
      $enc1 = New-Object System.Text.UTF8Encoding($false)
      [IO.File]::WriteAllText($ConfigPath, $add, $enc1)
      Write-V5Ok 'Hermes config: appended plugins.scan_on_install: false (no plugins: key existed)'
      return 'appended-section'
    }
    # Section body = the indented/blank lines following 'plugins:'.
    $secEnd = $lines.Count - 1
    for ($i = $pIdx + 1; $i -lt $lines.Count; $i++) {
      if ($lines[$i] -match '^\S') { $secEnd = $i - 1; break }
    }
    for ($i = $pIdx + 1; $i -le $secEnd; $i++) {
      if ($lines[$i] -match '^\s+scan_on_install\s*:') {
        Write-V5Ok 'Hermes config: plugins.scan_on_install already set - left as-is'
        return 'already-present'
      }
    }
    $insertAfter = $pIdx
    for ($i = $pIdx + 1; $i -le $secEnd; $i++) {
      if ($lines[$i] -match '^\s+disabled\s*:') {
        $insertAfter = $i
        # 'disabled:' with an empty value may own a '- item' block sequence;
        # inserting between the key and its items would break the YAML.
        if ($lines[$i] -match '^\s+disabled\s*:\s*(#.*)?$') {
          for ($j = $i + 1; $j -le $secEnd; $j++) {
            if ($lines[$j] -match '^\s+-\s') { $insertAfter = $j } else { break }
          }
        }
        break
      }
    }
    Copy-Item -LiteralPath $ConfigPath -Destination ($ConfigPath + '.bak-' + (Get-Date -Format 'yyyyMMdd-HHmmss')) -Force
    $newLines = @()
    $newLines += $lines[0..$insertAfter]
    $newLines += '  scan_on_install: false'
    if (($insertAfter + 1) -le ($lines.Count - 1)) { $newLines += $lines[($insertAfter + 1)..($lines.Count - 1)] }
    $enc2 = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($ConfigPath, ($newLines -join $nl), $enc2)
    Write-V5Ok 'Hermes config: plugins.scan_on_install: false (bundled plugins trip the scanner with false-positive traversal findings)'
    return 'inserted'
  } catch {
    Write-V5Warn ('Hermes scan_on_install edit failed: ' + $_.Exception.Message)
    return 'failed'
  }
}

function Get-V5ClaudeMarketplaceName {
  <#
  The marketplace name a bundled plugin publishes itself under, read from its
  own .claude-plugin\marketplace.json.

  Never hardcode this: superpowers publishes as 'superpowers-dev' and ponytail
  as 'ponytail', and the name is what Claude uses for BOTH the install target
  (<plugin>@<marketplace>) and the cache directory it lands in
  (plugins\cache\<marketplace>\<plugin>). A guessed name makes the
  post-install check look at the wrong path and report a false failure on an
  install that actually worked.

  Returns the name, or '' when the plugin ships no Claude marketplace.
  #>
  param([Parameter(Mandatory)][string]$PluginRoot)
  try {
    $mk = Join-Path $PluginRoot '.claude-plugin\marketplace.json'
    if (-not (Test-Path -LiteralPath $mk -PathType Leaf)) { return '' }
    $doc = ([IO.File]::ReadAllText($mk)) | ConvertFrom-Json
    if ($doc -and $doc.name) { return [string]$doc.name }
    return ''
  } catch {
    Write-V5Warn ('could not read marketplace name from ' + $PluginRoot + ': ' + $_.Exception.Message)
    return ''
  }
}

function Install-V5KimiPlugin {
  <#
  Install a bundled plugin into Kimi Code natively, without the TUI.

  kimi-code 0.27.0 has no `kimi plugin` SUBCOMMAND, which is what earlier
  versions of this installer observed - and then wrongly concluded that Kimi
  has no plugin system at all, so Kimi got copied skills only. It does have
  one; it is driven by the in-session `/plugins` slash command, and prompt
  mode cannot stand in for that because it demands a login first.

  Reading the shipped CLI settles the contract:
    - `/plugins install` copies the source to <home>\plugins\managed\<id>
    - the registry is <home>\plugins\installed.json, {version:1, plugins:[]}
    - each persisted entry is thin: id, root, source, enabled, installedAt,
      updatedAt, originalSource, capabilities, github
    - on load, materialize(entry) re-runs parseManifest(entry.root), so
      manifest, skillCount and state are DERIVED from disk every time

  That last point is what makes writing the registry safe rather than
  brittle: nothing here has to reproduce Kimi's manifest parsing, and a Kimi
  upgrade that changes the manifest schema cannot leave a stale record behind.

  The manifest itself is read from <root>\plugin.json, else
  <root>\.kimi-plugin\plugin.json - which is where the bundled Superpowers
  Kimi adapter (sessionStart.skill + the Kimi tool mapping) already lives.

  Returns @{ ok; status; root; reason }.
  #>
  param(
    [Parameter(Mandatory)][string]$KimiHome,
    [Parameter(Mandatory)][string]$PluginId,
    [Parameter(Mandatory)][string]$SourceRoot
  )
  $res = [ordered]@{ ok = $false; status = 'failed'; root = ''; reason = '' }
  try {
    if (-not (Test-Path -LiteralPath $SourceRoot -PathType Container)) {
      $res.reason = 'source plugin tree missing: ' + $SourceRoot
      return $res
    }
    # Refuse to install something Kimi will only reject at load time.
    $mRoot = Join-Path $SourceRoot 'plugin.json'
    $mDir  = Join-Path $SourceRoot '.kimi-plugin\plugin.json'
    if (-not (Test-Path -LiteralPath $mRoot -PathType Leaf) -and
        -not (Test-Path -LiteralPath $mDir -PathType Leaf)) {
      $res.reason = 'no plugin.json or .kimi-plugin\plugin.json in ' + $SourceRoot
      return $res
    }

    $managedDir  = Join-Path (Join-Path $KimiHome 'plugins') 'managed'
    $managedRoot = Join-Path $managedDir $PluginId
    New-Item -ItemType Directory -Force -Path $managedDir | Out-Null

    # Stage then swap, the way the CLI does: a half-copied plugin tree left in
    # place by an interrupted copy would load as a broken plugin.
    $staging = Join-Path $managedDir ($PluginId + '-staging-' + (Get-Date -Format 'yyyyMMddHHmmssfff'))
    Copy-Item -LiteralPath $SourceRoot -Destination $staging -Recurse -Force
    if (Test-Path -LiteralPath $managedRoot) {
      Remove-Item -LiteralPath $managedRoot -Recurse -Force
    }
    Move-Item -LiteralPath $staging -Destination $managedRoot -Force
    $res.root = $managedRoot

    # Merge into installed.json, preserving every other plugin's entry as-is.
    $store = Join-Path (Join-Path $KimiHome 'plugins') 'installed.json'
    $plugins = @()
    if (Test-Path -LiteralPath $store -PathType Leaf) {
      $existing = $null
      try {
        $existing = ([IO.File]::ReadAllText($store)) | ConvertFrom-Json
      } catch {
        Copy-Item -LiteralPath $store -Destination ($store + '.bad-' + (Get-Date -Format 'yyyyMMdd-HHmmss')) -Force
        Write-V5Warn ('Kimi installed.json was unparseable - kept a copy and rebuilt it')
      }
      if ($existing -and $existing.plugins) {
        foreach ($p in @($existing.plugins)) {
          if ($p.id -eq $PluginId) { continue }   # replaced below
          $keep = [ordered]@{}
          foreach ($prop in $p.PSObject.Properties) { $keep[$prop.Name] = $prop.Value }
          $plugins += ,$keep
        }
      }
    }

    $now = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    $entry = [ordered]@{
      id          = $PluginId
      root        = $managedRoot
      source      = 'local-path'
      enabled     = $true
      installedAt = $now
      updatedAt   = $now
    }
    $plugins += ,$entry

    $doc = [ordered]@{ version = 1; plugins = $plugins }
    $json = $doc | ConvertTo-Json -Depth 12
    $enc = New-Object System.Text.UTF8Encoding($false)
    New-Item -ItemType Directory -Force -Path (Split-Path $store -Parent) | Out-Null
    $tmp = $store + '.tmp'
    [IO.File]::WriteAllText($tmp, $json, $enc)
    if (Test-Path -LiteralPath $store) { Remove-Item -LiteralPath $store -Force }
    Move-Item -LiteralPath $tmp -Destination $store -Force

    $res.ok = $true
    $res.status = 'installed'
    return $res
  } catch {
    $res.reason = $_.Exception.Message
    return $res
  }
}

function Restore-V5HermesPluginScan {
  <#
  Undo the temporary scan_on_install override once the bundled plugins are in.

  Turning Hermes' install-time security scanner off permanently would weaken
  every FUTURE third-party plugin the operator installs, which is not ours to
  decide - Hermes treats plugin loading as an explicit trust boundary. So the
  override is scoped to our own install window and removed here.

  This removes a single line rather than restoring a snapshot of the file: the
  Hermes gateway re-serializes config.yaml on its own schedule (observed ~13
  min after start), so a whole-file restore taken before the install would
  clobber whatever the gateway legitimately wrote in between.

  $State is the string returned by Set-V5HermesPluginScanOff. When it reports
  'already-present' the operator had their own setting and it is left alone.

  Returns 'removed' | 'kept-user-setting' | 'absent' | 'failed'.
  #>
  param([string]$ConfigPath, [string]$State)
  try {
    if ($State -eq 'already-present') {
      Write-V5Ok 'Hermes config: scan_on_install was the operator''s own setting - left as-is'
      return 'kept-user-setting'
    }
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { return 'absent' }
    $text = [IO.File]::ReadAllText($ConfigPath)
    $nl = "`r`n"
    if ($text -notmatch "`r`n") { $nl = "`n" }
    $lines = @($text -split "?
")
    $keep = @()
    $dropped = 0
    $inPlugins = $false
    foreach ($line in $lines) {
      if ($line -match '^plugins\s*:') { $inPlugins = $true; $keep += $line; continue }
      if ($inPlugins -and $line -match '^\S') { $inPlugins = $false }
      if ($inPlugins -and $line -match '^\s+scan_on_install\s*:\s*false\s*$') { $dropped++; continue }
      $keep += $line
    }
    if ($dropped -eq 0) {
      Write-V5Ok 'Hermes config: no scan_on_install override left to remove'
      return 'absent'
    }
    Copy-Item -LiteralPath $ConfigPath -Destination ($ConfigPath + '.bak-' + (Get-Date -Format 'yyyyMMdd-HHmmss')) -Force
    $enc = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($ConfigPath, ($keep -join $nl), $enc)
    Write-V5Ok 'Hermes config: scan_on_install override removed - plugin scanning is back on'
    return 'removed'
  } catch {
    Write-V5Warn ('Hermes scan_on_install restore failed: ' + $_.Exception.Message)
    return 'failed'
  }
}

function Add-V5MarketplacePluginEntry {
  <#
  Idempotently add a plugin entry to a marketplace.json, preserving the
  file's own style: existing newline convention, 2-space indentation (entry
  object at 4, fields at 6, matching the canonical ultimate-bundle manifest),
  UTF-8 no BOM. This is a TEXT insertion because PS 5.1's ConvertTo-Json
  emits CRLF with 4-space indents and would reformat the whole file.

  The edit is validated (re-parse + entry present) BEFORE anything is
  written; the original is backed up to marketplace.json.bak-<ts>.
  Returns $true when the entry is present at the end (already or added).
  #>
  param(
    [string]$ManifestPath,
    [string]$EntryName,
    [string]$EntryDescription,
    [string]$EntrySource,
    [string]$EntryCategory
  )
  if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { return $false }
  $text = [IO.File]::ReadAllText($ManifestPath)
  if ($text -match ('"name"\s*:\s*"' + [regex]::Escape($EntryName) + '"')) { return $true }
  try { $parsed = $text | ConvertFrom-Json } catch {
    Write-V5Warn ('marketplace manifest is not valid JSON - left untouched: ' + $ManifestPath)
    return $false
  }
  if (-not $parsed -or -not $parsed.plugins) {
    Write-V5Warn ('marketplace manifest has no plugins array - left untouched: ' + $ManifestPath)
    return $false
  }
  $nl = "`n"
  if ($text -match "`r`n") { $nl = "`r`n" }
  $entry = '    {' + $nl +
           '      "name": "' + $EntryName + '",' + $nl +
           '      "description": "' + $EntryDescription + '",' + $nl +
           '      "source": "' + $EntrySource + '",' + $nl +
           '      "category": "' + $EntryCategory + '"' + $nl +
           '    },'
  $new = $null
  $m = [regex]::Match($text, '"plugins"\s*:\s*\[\s*\r?\n')
  if ($m.Success) {
    # insert as the first element of the non-empty array
    $idx = $m.Index + $m.Length
    $new = $text.Substring(0, $idx) + $entry + $nl + $text.Substring($idx)
  } else {
    $m2 = [regex]::Match($text, '"plugins"\s*:\s*\[\s*\]')
    if (-not $m2.Success) {
      Write-V5Warn ('could not locate the plugins array in ' + $ManifestPath)
      return $false
    }
    $replacement = '"plugins": [' + $nl + $entry.TrimEnd(',') + $nl + '  ]'
    $new = $text.Substring(0, $m2.Index) + $replacement + $text.Substring($m2.Index + $m2.Length)
  }
  try {
    $check = $new | ConvertFrom-Json
    $found = $false
    foreach ($pl in @($check.plugins)) { if ($pl.name -eq $EntryName) { $found = $true } }
    if (-not $found) { throw 'entry missing after edit' }
  } catch {
    Write-V5Warn ('marketplace edit failed validation - file left untouched: ' + $_.Exception.Message)
    return $false
  }
  Copy-Item -LiteralPath $ManifestPath -Destination ($ManifestPath + '.bak-' + (Get-Date -Format 'yyyyMMdd-HHmmss')) -Force
  $enc = New-Object System.Text.UTF8Encoding($false)
  [IO.File]::WriteAllText($ManifestPath, $new, $enc)
  return $true
}
