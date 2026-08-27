# UABS-Common.ps1 - shared helpers for Ultimate AI Starter Bundle AIO installer
$script:UabsPackRoot = $null
$script:UabsHeaders = @{ 'User-Agent' = 'Ultimate-AI-Starter-Bundle-AIO/8.0.0' }

function Get-UabsStateRoot {
  $base = $env:LOCALAPPDATA
  if (-not $base) { $base = $env:TEMP }
  if (-not $base) { throw 'LOCALAPPDATA and TEMP are both unavailable.' }
  return (Join-Path $base 'Ultimate-AI-Starter-Bundle')
}

function Get-UabsCodexCli {
  <# Prefer an independently updatable Codex CLI over Hermes' private copy.
     The desktop AppX resource appears on PATH but Windows does not permit
     launching it out-of-process, so it is not a CLI candidate. #>
  $commands = @(
    @(Get-Command codex -All -ErrorAction SilentlyContinue)
    @(Get-Command codex.exe -All -ErrorAction SilentlyContinue)
    @(Get-Command codex.cmd -All -ErrorAction SilentlyContinue)
  )
  $seen = @{}
  $preferred = @()
  $fallback = @()
  $hermesNode = Join-Path $env:LOCALAPPDATA 'hermes\node'
  foreach ($command in $commands) {
    $source = [string]$command.Source
    if (-not $source) { $source = [string]$command.Path }
    if (-not $source -or $seen.ContainsKey($source.ToLowerInvariant())) { continue }
    if ($source -match '(?i)\\WindowsApps\\OpenAI\.Codex_') { continue }
    $seen[$source.ToLowerInvariant()] = $true
    $candidate = [pscustomobject]@{ Source = $source }
    if (Test-UabsPathWithin -Path $source -Root $hermesNode) { $fallback += $candidate }
    else { $preferred += $candidate }
  }
  foreach ($candidate in @($preferred + $fallback)) {
    $version = Get-UabsNativeOutput -Exe $candidate.Source -CmdArgs @('--version')
    if ($version -match '(?m)^codex-cli\s+\d') { return $candidate }
  }
  return $null
}

function Invoke-UabsLegacyStateMigration {
  <# Move only paths owned by older bundle installers. Conflicts and unknown
     files stay where they are; this is deliberately not a directory mirror. #>
  $old = Join-Path $env:LOCALAPPDATA 'Skyrim-AI-V5'
  $new = Get-UabsStateRoot
  if (-not (Test-Path -LiteralPath $old -PathType Container)) { return }
  New-Item -ItemType Directory -Force -Path $new | Out-Null
  # Old provider sessions may still hold these generated helpers open. Stop
  # only the two bundle-owned command lines before moving their directory.
  try {
    $legacyHelpers = @('\tools\cbm-dashboard-plus.py','\tools\headroom-mcp-launch.py')
    foreach ($proc in @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)) {
      if (-not $proc.CommandLine) { continue }
      $commandLine = $proc.CommandLine.Replace('/', '\')
      if (@($legacyHelpers | Where-Object { $commandLine.IndexOf(($old + $_), [StringComparison]::OrdinalIgnoreCase) -ge 0 }).Count) {
        Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
        Write-UabsOk ('stopped legacy helper process: ' + $proc.ProcessId)
      }
    }
  } catch { Write-UabsWarn ('could not stop a legacy helper process: ' + $_.Exception.Message) }
  # codex-marketplace stays until `codex plugin remove` detaches its official
  # registry entry; moving it first would turn a healthy legacy entry dead.
  $owned = @(
    'backups','cache','github-mcp-server','hermes-plugin-src','hooks','plugins-src',
    'spookys-automod-toolkit','tools','install-state.json','installed-state-doctor.json',
    'mcp-profiles.json','provider-bootstrap.json','toolbelt.json','TOOLBELT.md'
  )
  foreach ($name in $owned) {
    $src = Join-Path $old $name
    $dst = Join-Path $new $name
    if ((Test-Path -LiteralPath $src) -and -not (Test-Path -LiteralPath $dst)) {
      Move-Item -LiteralPath $src -Destination $dst
      Write-UabsOk ('migrated legacy state: ' + $name)
    }
  }
  # These are generated reports or versioned bundle binaries. Once V8 has a
  # replacement, retaining the older copy cannot preserve user data; it only
  # leaves two apparent authorities on disk.
  foreach ($name in @('github-mcp-server','installed-state-doctor.json','provider-bootstrap.json','TOOLBELT.md')) {
    $src = Join-Path $old $name
    $dst = Join-Path $new $name
    if ((Test-Path -LiteralPath $src) -and (Test-Path -LiteralPath $dst)) {
      Remove-Item -LiteralPath $src -Recurse -Force
      Write-UabsOk ('removed replaced legacy state: ' + $name)
    }
  }
  foreach ($envName in @('HEADROOM_CMD','SPOOKY_AUTOMOD_ROOT')) {
    $value = [Environment]::GetEnvironmentVariable($envName, 'User')
    if ($value -and $value.StartsWith($old, [StringComparison]::OrdinalIgnoreCase)) {
      Set-UabsUserEnv $envName ($new + $value.Substring($old.Length))
    }
  }
  if (-not @(Get-ChildItem -LiteralPath $old -Force -ErrorAction SilentlyContinue).Count) {
    Remove-Item -LiteralPath $old -Force
  } else {
    Write-UabsWarn ('legacy state has unowned/conflicting files; preserved: ' + $old)
  }
}

function Get-UabsPackRoot {
  if ($script:UabsPackRoot -and (Test-Path -LiteralPath $script:UabsPackRoot)) { return $script:UabsPackRoot }
  $here = $PSScriptRoot
  if (Test-Path (Join-Path $here 'BUNDLED-TOOLS\CATALOG.json')) { $script:UabsPackRoot = $here; return $here }
  $parent = Split-Path $here -Parent
  if (Test-Path (Join-Path $parent 'BUNDLED-TOOLS\CATALOG.json')) { $script:UabsPackRoot = $parent; return $parent }
  throw 'Cannot locate pack root (BUNDLED-TOOLS\CATALOG.json). Run from the Uabs pack folder.'
}

function Get-UabsCatalog {
  $root = Get-UabsPackRoot
  $path = Join-Path $root 'BUNDLED-TOOLS\CATALOG.json'
  return ([IO.File]::ReadAllText($path) | ConvertFrom-Json)
}

function Expand-UabsEnvPath([string]$p) {
  if ([string]::IsNullOrWhiteSpace($p)) { return $p }
  return [Environment]::ExpandEnvironmentVariables($p)
}

function Test-UabsPath([string]$p) {
  if ([string]::IsNullOrWhiteSpace($p)) { return $false }
  try { return Test-Path -LiteralPath (Expand-UabsEnvPath $p) } catch { return $false }
}

function Test-UabsPathWithin([string]$Path, [string]$Root) {
  if (-not $Path -or -not $Root) { return $false }
  try {
    $fullPath = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    return $fullPath.Equals($fullRoot, [StringComparison]::OrdinalIgnoreCase) -or
      $fullPath.StartsWith($fullRoot + '\', [StringComparison]::OrdinalIgnoreCase)
  } catch { return $false }
}

function Write-UabsStep([string]$m) { Write-Host ("==> " + $m) -ForegroundColor Cyan }
function Write-UabsOk([string]$m)   { Write-Host ("  OK  " + $m) -ForegroundColor Green }
function Write-UabsWarn([string]$m) { Write-Host ("  !!  " + $m) -ForegroundColor Yellow }
function Write-UabsBad([string]$m)  { Write-Host ("  XX  " + $m) -ForegroundColor Red }

function Set-UabsUserEnv([string]$Name, [string]$Value) {
  [Environment]::SetEnvironmentVariable($Name, $Value, 'User')
  Set-Item -Path ("Env:" + $Name) -Value $Value
}

function Get-UabsProviderHome([string]$Provider, $Catalog) {
  $p = $Catalog.providers.$Provider
  if (-not $p) { throw ("Unknown provider " + $Provider) }
  $envName = $p.home_env
  # Process BEFORE User. Process is the more specific scope: it is what someone
  # sets to redirect a single run, and honouring User first made that override
  # impossible on any machine where the User variable exists. Two consequences,
  # both real: Get-UabsHermesPaths resolves the same path from $env: (which is
  # process scope), so the two helpers disagreed about the same home; and the
  # installer could not be exercised against an isolated empty home, which is
  # why "installer PASS" was never evidence about fresh installs.
  $fromEnv = [Environment]::GetEnvironmentVariable($envName, 'Process')
  if (-not $fromEnv) { $fromEnv = [Environment]::GetEnvironmentVariable($envName, 'User') }
  if ($fromEnv) { return $fromEnv }
  return (Expand-UabsEnvPath $p.home_default)
}

function Get-UabsProviderSkillsDir([string]$Provider, $Catalog) {
  # Codex still reads $CODEX_HOME\skills for compatibility, but its supported
  # user-level Agent Skills root is $HOME\.agents\skills. Writing both makes
  # Codex index every bundle skill twice and can erase every description.
  if ($Provider -eq 'Codex') { return (Join-Path $env:USERPROFILE '.agents\skills') }
  return (Join-Path (Get-UabsProviderHome -Provider $Provider -Catalog $Catalog) 'skills')
}

function Invoke-UabsGitHubLatest {
  param([string]$Owner, [string]$Repo)
  $uri = "https://api.github.com/repos/$Owner/$Repo/releases/latest"
  return Invoke-RestMethod -Uri $uri -Headers $script:UabsHeaders -TimeoutSec 60
}

function Get-UabsReleaseAsset {
  param($Release, [string[]]$Patterns)
  foreach ($pat in $Patterns) {
    $a = @($Release.assets | Where-Object { $_.name -like $pat }) | Select-Object -First 1
    if ($a) { return $a }
  }
  return $null
}

function Save-UabsUrl {
  param([string]$Url, [string]$OutFile)
  $dir = Split-Path $OutFile -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  Write-UabsStep ("Download " + (Split-Path $OutFile -Leaf))
  Invoke-WebRequest -Uri $Url -OutFile $OutFile -Headers $script:UabsHeaders -TimeoutSec 900
  Write-UabsOk (("{0:N1} MB" -f ((Get-Item $OutFile).Length / 1MB)))
}

function Expand-UabsZip {
  param([string]$Zip, [string]$Dest, [switch]$WipeDest)
  if ($WipeDest -and (Test-Path $Dest)) { Remove-Item -LiteralPath $Dest -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $Dest | Out-Null
  Expand-Archive -LiteralPath $Zip -DestinationPath $Dest -Force
}

function Resolve-UabsSingleRoot {
  param([string]$Dest)
  $kids = @(Get-ChildItem -LiteralPath $Dest -Force | Where-Object { $_.Name -ne '__MACOSX' })
  if ($kids.Count -eq 1 -and $kids[0].PSIsContainer) { return $kids[0].FullName }
  return $Dest
}

function Find-UabsFileUnder {
  param([string]$Root, [string]$Name, [int]$Depth = 6)
  if (-not (Test-Path $Root)) { return $null }
  $hit = Get-ChildItem -LiteralPath $Root -Filter $Name -Recurse -Depth $Depth -File -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($hit) { return $hit.FullName }
  return $null
}

function Test-UabsDotNetRuntime([string]$Pattern) {
  try {
    $r = & dotnet --list-runtimes 2>$null
    return [bool]($r | Where-Object { $_ -match $Pattern })
  } catch { return $false }
}

function Test-UabsDotNetSdk([string]$Pattern) {
  try {
    $r = & dotnet --list-sdks 2>$null
    return [bool]($r | Where-Object { $_ -match $Pattern })
  } catch { return $false }
}

function Install-UabsWinget([string[]]$Ids) {
  $winget = Get-Command winget -ErrorAction SilentlyContinue
  if (-not $winget) { Write-UabsWarn 'winget not available'; return $false }
  foreach ($id in $Ids) {
    Write-UabsStep ("winget install " + $id)
    & winget install --id $id -e --accept-package-agreements --accept-source-agreements --disable-interactivity | Out-Host
    if ($LASTEXITCODE -ne 0) {
      Write-UabsBad ("winget failed for " + $id + " exit=" + $LASTEXITCODE)
      return $false
    }
  }
  return $true
}

function Test-UabsFileLocked([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
  try {
    $fs = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    $fs.Close()
    return $false
  } catch {
    return $true
  }
}

function Stop-UabsProcessUsingExecutable([string]$Path) {
  if (-not $Path) { return 0 }
  $wanted = [IO.Path]::GetFullPath($Path)
  $stopped = 0
  foreach ($proc in @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)) {
    if (-not $proc.ExecutablePath) { continue }
    if (-not [string]::Equals([IO.Path]::GetFullPath($proc.ExecutablePath), $wanted, [StringComparison]::OrdinalIgnoreCase)) { continue }
    Stop-Process -Id $proc.ProcessId -Force -ErrorAction Stop
    $stopped++
  }
  if ($stopped) {
    for ($i = 0; $i -lt 20 -and (Test-UabsFileLocked $wanted); $i++) { Start-Sleep -Milliseconds 250 }
  }
  return $stopped
}

function Find-UabsCodebaseMemoryExe {
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

function Update-UabsGrokMcpBlock {
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
  $argNorm = (@($ArgList | ForEach-Object { ($_ -replace '\\', '/').Trim() }) -join ([char]31))
  if ($SkipIfPresent -and $content) {
    $nameEsc = [regex]::Escape($Name)
    $block = [regex]::Match($content, '(?ms)^[ \t]*\[mcp_servers\.' + $nameEsc + '\][ \t]*\r?\n(?<body>.*?)(?=^[ \t]*\[|\z)')
    if ($block.Success) {
      $body = $block.Groups['body'].Value
      $m = [regex]::Match($body, '(?m)^[ \t]*command[ \t]*=[ \t]*["'']([^"'']+)["'']')
      $existingCmd = if ($m.Success) { ($m.Groups[1].Value -replace '\\', '/').Trim() } else { '' }
      # Every npx server shares one command, so comparing only the command
      # always matched and a drifted pin in the args survived every upgrade.
      $am = [regex]::Match($body, '(?ms)^[ \t]*args[ \t]*=[ \t]*\[(?<v>.*?)\]')
      $existingArgs = @()
      if ($am.Success) {
        foreach ($a in [regex]::Matches($am.Groups['v'].Value, '"(?<v>(?:[^"\\]|\\.)*)"|''(?<v>[^'']*)''')) {
          $existingArgs += (($a.Groups['v'].Value -replace '\\\\', '/' -replace '\\', '/').Trim())
        }
      }
      if (($existingCmd -ieq $cmdNorm) -and ((@($existingArgs) -join ([char]31)) -ieq $argNorm)) {
        Write-UabsOk ('Grok MCP unchanged (already correct): ' + $Name)
        return
      }
      if ($existingCmd -ieq $cmdNorm) {
        Write-UabsWarn ('Grok MCP args drifted, rewriting: ' + $Name + '  was [' + (@($existingArgs) -join ' ') + ']')
      }
    }
  }

  if (Test-Path -LiteralPath $configPath) {
    $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
    $bak = $configPath + '.before-uabs-' + $Name + '-' + $ts + '.bak'
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
  Write-UabsOk ('Grok MCP: ' + $Name)
}

function Copy-UabsRobo([string]$From, [string]$To) {
  New-Item -ItemType Directory -Force -Path $To | Out-Null
  & robocopy $From $To /E /COPY:DAT /R:1 /W:1 /NFL /NDL /NJH /NJS | Out-Null
  $code = $LASTEXITCODE
  if ($code -ge 8) {
    throw ('robocopy failed exit=' + $code + ' from=' + $From + ' to=' + $To)
  }
}

function Get-UabsTreeDigest([string]$Path) {
  $root = (Resolve-Path -LiteralPath $Path).Path.TrimEnd('\') + '\'
  $rows = @(Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction Stop |
    ForEach-Object { $_.FullName.Substring($root.Length).Replace('\','/') + '=' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash } |
    Sort-Object)
  $bytes = [Text.Encoding]::UTF8.GetBytes(($rows -join "`n"))
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','') } finally { $sha.Dispose() }
}

function Sync-UabsProviderSkills([string]$From, [string]$To, [string]$Provider = '') {
  <#
    Bundle-owned provider skills are content-authoritative.

    Deterministic release archives normalize timestamps, so metadata cannot
    prove that an installed skill has the current bytes. Each bundle-owned
    skill is therefore copied into a fresh sibling staging directory, verified
    by SHA-256, swapped into place, and verified again. Only the named
    bundle-owned skill directory is replaced; unrelated user-created sibling
    skills are never mirrored or deleted.
  #>
  if (-not (Test-Path -LiteralPath $From -PathType Container)) {
    throw ('provider skill source missing: ' + $From)
  }
  New-Item -ItemType Directory -Force -Path $To | Out-Null

  # Clean interrupted V8 staging only. The exact prefix is bundle-owned.
  Get-ChildItem -LiteralPath $To -Directory -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like '.uabs-skill-stage-*' -or $_.Name -like '.uabs-skill-backup-*' } |
    Remove-Item -Recurse -Force

  $currentNames = @(Get-ChildItem -LiteralPath $From -Directory -Force |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') } |
    Select-Object -ExpandProperty Name)
  $ledgerPath = $null
  if ($Provider) {
    $ledgerDir = Join-Path (Get-UabsStateRoot) 'managed-skills'
    New-Item -ItemType Directory -Force -Path $ledgerDir | Out-Null
    $ledgerPath = Join-Path $ledgerDir ($Provider.ToLowerInvariant() + '.json')
    if (Test-Path -LiteralPath $ledgerPath -PathType Leaf) {
      try {
        $previous = [IO.File]::ReadAllText($ledgerPath) | ConvertFrom-Json
        foreach ($entry in @($previous.skills)) {
          if ($currentNames -contains [string]$entry.name) { continue }
          $retired = Join-Path $To ([string]$entry.name)
          if (-not (Test-Path -LiteralPath $retired -PathType Container)) { continue }
          if ((Get-UabsTreeDigest $retired) -ceq [string]$entry.digest) {
            Remove-Item -LiteralPath $retired -Recurse -Force
            Write-UabsOk ('retired managed skill removed: ' + $entry.name)
          } else {
            Write-UabsWarn ('retired skill was modified; preserved: ' + $retired)
          }
        }
      } catch { Write-UabsWarn ('managed-skill ledger unreadable; no retired skills removed: ' + $_.Exception.Message) }
    }
  }

  foreach ($skillDir in @(Get-ChildItem -LiteralPath $From -Directory -Force -ErrorAction Stop)) {
    $sourceSkillMd = Join-Path $skillDir.FullName 'SKILL.md'
    if (-not (Test-Path -LiteralPath $sourceSkillMd -PathType Leaf)) { continue }
    if (($skillDir.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
      throw ('provider skill source is a reparse point: ' + $skillDir.FullName)
    }
    foreach ($sourceItem in @(Get-ChildItem -LiteralPath $skillDir.FullName -Recurse -Force -ErrorAction Stop)) {
      if (($sourceItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw ('provider skill source contains a reparse point: ' + $sourceItem.FullName)
      }
    }

    $destSkill = Join-Path $To $skillDir.Name
    $nonce = [Guid]::NewGuid().ToString('N')
    $stage = Join-Path $To ('.uabs-skill-stage-' + $skillDir.Name + '-' + $nonce)
    $backup = Join-Path $To ('.uabs-skill-backup-' + $skillDir.Name + '-' + $nonce)
    $movedExisting = $false

    try {
      New-Item -ItemType Directory -Force -Path $stage | Out-Null
      $sourceRoot = $skillDir.FullName.TrimEnd('\') + '\'
      $expected = @{}

      foreach ($sourceDir in @(Get-ChildItem -LiteralPath $skillDir.FullName -Recurse -Directory -Force -ErrorAction Stop)) {
        $relDir = $sourceDir.FullName.Substring($sourceRoot.Length)
        if ($relDir) { New-Item -ItemType Directory -Force -Path (Join-Path $stage $relDir) | Out-Null }
      }

      foreach ($srcFile in @(Get-ChildItem -LiteralPath $skillDir.FullName -Recurse -File -Force -ErrorAction Stop)) {
        $rel = $srcFile.FullName.Substring($sourceRoot.Length)
        $expected[$rel] = (Get-FileHash -LiteralPath $srcFile.FullName -Algorithm SHA256).Hash
        $stageFile = Join-Path $stage $rel
        $stageParent = Split-Path -Parent $stageFile
        if ($stageParent) { New-Item -ItemType Directory -Force -Path $stageParent | Out-Null }
        Copy-Item -LiteralPath $srcFile.FullName -Destination $stageFile -Force
        $stageHash = (Get-FileHash -LiteralPath $stageFile -Algorithm SHA256).Hash
        if ($stageHash -cne $expected[$rel]) {
          throw ('provider skill staging hash mismatch: ' + $skillDir.Name + '\' + $rel +
            ' expected=' + $expected[$rel] + ' actual=' + $stageHash)
        }
      }

      if (-not (Test-Path -LiteralPath (Join-Path $stage 'SKILL.md') -PathType Leaf)) {
        throw ('provider skill staging missing SKILL.md: ' + $skillDir.Name)
      }

      if (Test-Path -LiteralPath $destSkill) {
        $destItem = Get-Item -LiteralPath $destSkill -Force
        if (($destItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
          throw ('refusing provider skill target that is a reparse point: ' + $destSkill)
        }
        Move-Item -LiteralPath $destSkill -Destination $backup
        $movedExisting = $true
      }

      Move-Item -LiteralPath $stage -Destination $destSkill

      foreach ($rel in @($expected.Keys)) {
        $dstFile = Join-Path $destSkill $rel
        if (-not (Test-Path -LiteralPath $dstFile -PathType Leaf)) {
          throw ('provider skill sync missing file after swap: ' + $skillDir.Name + '\' + $rel)
        }
        $actualHash = (Get-FileHash -LiteralPath $dstFile -Algorithm SHA256).Hash
        if ($actualHash -cne $expected[$rel]) {
          throw ('provider skill sync hash mismatch after swap: ' + $skillDir.Name + '\' + $rel +
            ' expected=' + $expected[$rel] + ' actual=' + $actualHash)
        }
      }
      $destRoot = $destSkill.TrimEnd('\') + '\'
      foreach ($dstFile in @(Get-ChildItem -LiteralPath $destSkill -Recurse -File -Force -ErrorAction Stop)) {
        $rel = $dstFile.FullName.Substring($destRoot.Length)
        if (-not $expected.ContainsKey($rel)) {
          throw ('provider skill sync left unexpected file after swap: ' + $skillDir.Name + '\' + $rel)
        }
      }

      if ($movedExisting -and (Test-Path -LiteralPath $backup)) {
        Remove-Item -LiteralPath $backup -Recurse -Force
        $movedExisting = $false
      }
    }
    catch {
      if ($movedExisting -and (Test-Path -LiteralPath $backup)) {
        if (Test-Path -LiteralPath $destSkill) {
          Remove-Item -LiteralPath $destSkill -Recurse -Force -ErrorAction SilentlyContinue
        }
        if (-not (Test-Path -LiteralPath $destSkill)) {
          Move-Item -LiteralPath $backup -Destination $destSkill -ErrorAction SilentlyContinue
          $movedExisting = $false
        }
      }
      throw
    }
    finally {
      Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
      if (-not $movedExisting) {
        Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction SilentlyContinue
      }
    }
  }

  if ($ledgerPath) {
    $records = @($currentNames | Sort-Object | ForEach-Object {
      $path = Join-Path $To $_
      [ordered]@{ name = $_; digest = Get-UabsTreeDigest $path }
    })
    $doc = [ordered]@{ schema = 1; provider = $Provider; skills = $records }
    $tmp = $ledgerPath + '.tmp-' + [Guid]::NewGuid().ToString('N')
    [IO.File]::WriteAllText($tmp, (($doc | ConvertTo-Json -Depth 5) + "`n"), (New-Object Text.UTF8Encoding $false))
    Move-Item -LiteralPath $tmp -Destination $ledgerPath -Force
  }
}

function Copy-UabsRoboSafe([string]$From, [string]$To, [string[]]$CriticalFiles = @()) {
  foreach ($rel in $CriticalFiles) {
    $destFile = Join-Path $To $rel
    if ((Test-Path -LiteralPath $destFile -PathType Leaf) -and (Test-UabsFileLocked $destFile)) {
      throw ('REFUSE overwrite locked file (MCP likely running): ' + $destFile + ' - stop the AI app or MCP process first, or skip this component.')
    }
  }
  Copy-UabsRobo -From $From -To $To
}

function Set-UabsGrokCompatCells {
  <#
    Turn off Grok's inheritance of Claude Code's hooks, MCP servers, and
    skills.

    Grok ships Claude-Code compatibility ON by default: it adopts
    ~/.claude/skills, ~/.claude/agents, ~/.claude/plugins (with their
    hooks/hooks.json, .mcp.json, and skill dirs), ~/.claude.json and
    ~/.claude/settings.json. Measured on grok-cli 1.0.4 (2026-08-15):

      - inherited Claude hooks cost 60.037s per turn (two Stop hooks at
        timeout 30, and Grok never closes a hook's stdin);
      - MCP startup cost 65s on the first turn of every session and
        attached ZERO tools - tool_count was 26 (the built-in count) in
        all 12 turns recorded, with 8 servers configured and with 0.

    Skills compat is also OFF as of v7.7.4. AIO already copies the pack
    into ~/.grok/skills. Leaving Claude skill scan ON duplicates native
    superpowers skills (systematic-debugging is the one that errors in
    the TUI) and surfaces claude-mem / other Claude plugin skills in
    Grok, which is how mcp-search rides in as an extra running MCP
    server. See GROK-MCP-TROUBLESHOOTING.md.
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
    '# Grok inherits Claude Code config by default. hooks/MCP were measured',
    '# as pure cost on grok-cli 1.0.4. skills is also off: AIO copies the',
    '# pack into ~/.grok/skills; scanning ~/.claude duplicates superpowers',
    '# skills (systematic-debugging) and pulls claude-mem into Grok.',
    '# See GROK-MCP-TROUBLESHOOTING.md.',
    'hooks = false',
    ('mcps = ' + $mcps),
    'skills = false'
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
    Write-UabsWarn 'Grok: Claude hook + skill inheritance OFF, MCP inheritance left ON by request (expect a ~65s first turn)'
  } else {
    Write-UabsOk 'Grok: Claude hook + MCP + skill inheritance disabled (turn time 97s -> ~2s; no claude-mem skill leak)'
  }
}

# v7.5.0: SOUL + AIO preamble wiring. Appends (or replaces) the marked
# preamble block in an agent instruction file. Idempotent, backup first.
# Existing files keep their own encoding; writes are UTF-8 without BOM.
function Install-UabsPreambleBlock {
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
  $ver = 'v8.0.0'
  try {
    $vf = Join-Path (Get-UabsPackRoot) 'VERSION.txt'
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
    # Hermes used to receive the bare SOUL source instead of the marked SOUL +
    # AIO block. That exact byte-owned legacy form is safe to replace; any
    # operator-authored content is still preserved and the block is appended.
    if ($pre.Trim() -ceq $soul) { $pre = '' }
    $pat = '(?ms)^[ \t]*<!--[ \t]*ULTIMATE-AI-STARTER-BUNDLE SOUL.*?^[ \t]*<!--[ \t]*/ULTIMATE-AI-STARTER-BUNDLE SOUL[ \t]*-->[ \t]*\r?\n?'

    $new = ''
    if ([regex]::IsMatch($pre, $pat)) {
      $new = [regex]::Replace($pre, $pat, ($block + $nl))
    } else {
      if ($pre) { $new = $pre.TrimEnd("`r", "`n") + $nl + $nl + $block + $nl }
      else { $new = $block + $nl }
    }
    if (-not $Force -and $new -ceq $pre) {
      Write-UabsOk ('preamble unchanged (already current): ' + $Path)
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
    Write-UabsOk ('preamble wired: ' + $Path)
}

# ---------------------------------------------------------------------------
# Native bundled plugins (superpowers / ponytail) - shared helpers.
# The per-provider orchestration lives in INSTALL-AIO.ps1; these are the
# mechanism pieces: native command output capture, plugin-owned skill name
# discovery, the md5-guarded dedupe, a TOML plugin-section probe, the Hermes
# scan_on_install config fix, and a style-preserving marketplace.json edit.
# ---------------------------------------------------------------------------

function Get-UabsNativeOutput {
  <#
  Run a native command and return its combined output as one string, without
  PowerShell 5.1 turning stderr lines into terminating ErrorRecords under the
  script-wide $ErrorActionPreference='Stop'. (Same disease Invoke-UabsNative
  cures; this variant is for DETECTION, where the output itself is needed.)
  #>
  param([string]$Exe, [string[]]$CmdArgs)
  $prevEap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try { return (& $Exe @CmdArgs 2>&1 | Out-String) } finally { $ErrorActionPreference = $prevEap }
}

function Get-UabsGrokPluginList {
  <#
  Parse `grok plugin list --json`. Returns an array of plugin objects with
  name / repo_key / source / marketplace / path. Empty array on failure.
  #>
  param([string]$GrokExe)
  if (-not $GrokExe) { return @() }
  $out = Get-UabsNativeOutput -Exe $GrokExe -CmdArgs @('plugin', 'list', '--json')
  if ([string]::IsNullOrWhiteSpace($out)) { return @() }
  $start = $out.IndexOf('[')
  if ($start -lt 0) { $start = $out.IndexOf('{') }
  if ($start -lt 0) { return @() }
  try {
    $parsed = $out.Substring($start) | ConvertFrom-Json
    return @($parsed)
  } catch {
    return @()
  }
}

function Get-UabsAutostartTargetPaths {
  <#
  Pull every filesystem path out of an autostart command line or launcher
  script. A .vbs wrapper names two of them - the interpreter and the script it
  runs - and it is normally the SECOND one that has gone missing, so all of
  them are returned and the caller decides.

  Environment variables are expanded, because launcher scripts written by
  other tools use %LOCALAPPDATA% freely and an unexpanded string always
  "does not exist".
  #>
  param([string]$Text)
  $paths = New-Object System.Collections.Generic.List[string]
  if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
  $rx = '(?<p>(?:[A-Za-z]:\\|%[A-Za-z_()0-9]+%\\)[^"''<>|\r\n]*?\.[A-Za-z0-9]{1,6})(?=["''\s,)]|$)'
  foreach ($m in [regex]::Matches($Text, $rx)) {
    $p = $m.Groups['p'].Value.Trim()
    try { $p = [Environment]::ExpandEnvironmentVariables($p) } catch { }
    if ($p -and -not $paths.Contains($p)) { [void]$paths.Add($p) }
  }
  return @($paths)
}

function Get-UabsAiAutostartEntries {
  <#
  Enumerate the boot-time autostarts that launch AI tooling: the per-user
  Startup folder plus the HKCU Run key.

  NOTHING HERE IS OWNED BY THIS PACK. The installer has never written an
  autostart and never will. These entries are created by agent sessions,
  by other tools' installers, and by the user - so this function REPORTS and
  callers must not delete on their own initiative.

  Measured on the maintainer's machine 2026-08-26: three Startup entries, all
  written by past agent sessions, one of them (`cbm-dashboard-plus.vbs`)
  pointing into a `Skyrim-AI-V5` tree that no longer existed at all. A dead
  autostart costs a failed process launch at every single boot and is
  invisible unless someone opens Task Manager's Startup tab.

  Each entry carries: Name, Source, Command, Targets, MissingTargets, Dead.
  `Dead` means at least one path the entry needs is not on disk.
  #>
  [CmdletBinding()] param()
  $out = New-Object System.Collections.Generic.List[object]
  # Broad on purpose: a false positive is only ever printed, never acted on,
  # whereas a miss leaves the user staring at Task Manager. Bare `chroma` is
  # deliberately NOT in this list - it matched Razer's RGB autostart
  # (`--url-params=apps=synapse,chroma-app`) on the maintainer's machine.
  $needle = 'claude|codex|grok|kimi|hermes|housecarl|codebase-memory|cbm[-_]|claude[-_]mem|superpowers|ponytail|headroom|chroma-mcp|skyrim-ai|forge|\bmcp\b|anthropic|openai|openrouter|ollama|spooky'

  $startup = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'
  if (Test-Path -LiteralPath $startup -PathType Container) {
    foreach ($f in Get-ChildItem -LiteralPath $startup -File -ErrorAction SilentlyContinue) {
      if ($f.Name -eq 'desktop.ini') { continue }
      $command = ''
      if ($f.Extension -eq '.lnk') {
        try {
          $sh = New-Object -ComObject WScript.Shell
          $lnk = $sh.CreateShortcut($f.FullName)
          $command = ('{0} {1}' -f $lnk.TargetPath, $lnk.Arguments).Trim()
        } catch { $command = '' }
      } else {
        try { $command = [IO.File]::ReadAllText($f.FullName) } catch { $command = '' }
      }
      $haystack = ($f.Name + ' ' + $command)
      if ($haystack -notmatch $needle) { continue }
      $targets = @(Get-UabsAutostartTargetPaths -Text $command)
      $missing = @($targets | Where-Object { -not (Test-Path -LiteralPath $_) })
      [void]$out.Add([pscustomobject]@{
        Name           = $f.Name
        Source         = 'Startup folder'
        Path           = $f.FullName
        Command        = $command.Trim()
        Targets        = $targets
        MissingTargets = $missing
        Dead           = [bool]($targets.Count -and $missing.Count)
      })
    }
  }

  $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
  if (Test-Path -LiteralPath $runKey) {
    $props = $null
    try { $props = Get-ItemProperty -LiteralPath $runKey -ErrorAction Stop } catch { }
    if ($props) {
      foreach ($p in $props.PSObject.Properties) {
        if ($p.Name -like 'PS*') { continue }
        $command = [string]$p.Value
        if (($p.Name + ' ' + $command) -notmatch $needle) { continue }
        $targets = @(Get-UabsAutostartTargetPaths -Text $command)
        $missing = @($targets | Where-Object { -not (Test-Path -LiteralPath $_) })
        [void]$out.Add([pscustomobject]@{
          Name           = $p.Name
          Source         = 'HKCU Run'
          Path           = $runKey + '\' + $p.Name
          Command        = $command
          Targets        = $targets
          MissingTargets = $missing
          Dead           = [bool]($targets.Count -and $missing.Count)
        })
      }
    }
  }
  # .ToArray(), not @($out): on PS 5.1, wrapping a List[object] whose items
  # carry array-valued properties throws "Argument types do not match".
  # Callers wrap the CALL in @() to survive the single-item unroll.
  return $out.ToArray()
}

function Get-UabsCodexEnabledPluginIds {
  <#
  Read Codex's OWN plugin registry - ~/.codex/config.toml - and return the
  ids (`<plugin>@<marketplace>`) that are not explicitly disabled.

  Why this exists: `codex plugin list --json` fails WHOLESALE when any one
  configured marketplace snapshot is unloadable, even a marketplace unrelated
  to the plugin being asked about. Measured on 2026-08-26:

    Error: failed to load configured marketplace snapshot(s):
    - `headroom-marketplace` at ...\.tmp/marketplaces\headroom-marketplace:
      marketplace root does not contain a supported manifest

  An empty inventory then reads as "the plugin is not installed", which made
  the installer keep its copied skill duplicates. This file is what the CLI
  renders, so it stays right when the CLI cannot answer.

  Only the top-level [plugins."<id>"] table counts. Codex also writes nested
  tables such as [plugins."browser@openai-bundled".ambient] that carry their
  own `enabled` keys; reading those as the plugin's state inverts the answer.
  #>
  param([string]$CodexHome)
  if (-not $CodexHome) { return @() }
  $cfg = Join-Path $CodexHome 'config.toml'
  if (-not (Test-Path -LiteralPath $cfg -PathType Leaf)) { return @() }
  $ids = New-Object System.Collections.Generic.List[string]
  $current = $null
  $disabled = $false
  foreach ($line in [IO.File]::ReadAllLines($cfg)) {
    $t = $line.Trim()
    if ($t.StartsWith('[')) {
      if ($current -and -not $disabled) { [void]$ids.Add($current) }
      $current = $null
      $disabled = $false
      $m = [regex]::Match($t, '^\[plugins\."(?<id>[^"]+)"\]$')
      if ($m.Success) { $current = $m.Groups['id'].Value }
      continue
    }
    if ($current -and $t -match '^enabled\s*=\s*false') { $disabled = $true }
  }
  if ($current -and -not $disabled) { [void]$ids.Add($current) }
  return @($ids)
}

function Get-UabsCodexBuiltinSkillNames {
  <#
  Names of the skills Codex ships ITSELF, from <CodexHome>\skills\.system.

  Why this exists: v8.6.6 adopted `skill-creator` into the canonical tree so
  all five providers would carry it. Codex already ships a `skill-creator` of
  its own, so on Codex alone the pack's copy became a SECOND index entry for a
  capability that was already there -- measured as 184 entries / 48 visible
  description chars with the duplicate, against 183 / 50 without it.

  This is the same class of waste the native-plugin dedupe already removes,
  with a different owner: there the owner is an enabled plugin, here it is
  Codex's own built-in set. Discovered, never hardcoded -- `.system` also holds
  `imagegen`, `openai-docs`, `plugin-creator`, `review-agent` and
  `skill-installer`, and any future canonical skill taking one of those names
  would collide in exactly the same way with no code change to catch it.

  A directory only counts when it actually carries a SKILL.md: an empty or
  half-written folder owns nothing, and treating it as an owner would evict
  the pack's working copy in favour of nothing.
  #>
  param([string]$CodexHome)
  if (-not $CodexHome) { return @() }
  $sys = Join-Path (Join-Path $CodexHome 'skills') '.system'
  if (-not (Test-Path -LiteralPath $sys -PathType Container)) { return @() }
  $names = New-Object System.Collections.Generic.List[string]
  foreach ($d in @(Get-ChildItem -LiteralPath $sys -Directory -EA SilentlyContinue)) {
    if (Test-Path -LiteralPath (Join-Path $d.FullName 'SKILL.md') -PathType Leaf) {
      [void]$names.Add($d.Name)
    }
  }
  return @($names)
}

function Repair-UabsGrokDuplicatePlugins {
  <#
  Grok's official marketplace auto-installs superpowers. The AIO used to
  also `grok plugin install` the staged local copy under
  %LOCALAPPDATA%\Ultimate-AI-Starter-Bundle\plugins-src\superpowers. Two plugins with the
  same name both own systematic-debugging, and the TUI reports that as a
  skill error. Keep the marketplace/git copy; drop extra local clones.

  Do NOT `grok plugin uninstall <name>` while duplicates exist: the CLI
  matches on plugin name only, so it removed the marketplace copy and left
  the local clone (measured). repo_key is not accepted as <NAME>. Edit
  installed-plugins/registry.json and delete the extra repo folder instead.
  #>
  param([string]$GrokExe, [string]$PluginName)
  $hits = @(Get-UabsGrokPluginList -GrokExe $GrokExe | Where-Object { $_.name -eq $PluginName })
  if ($hits.Count -le 1) { return $hits }
  $keep = @($hits | Where-Object { $_.marketplace }) | Select-Object -First 1
  if (-not $keep) {
    $keep = @($hits | Where-Object { $_.source -match '^https?://' }) | Select-Object -First 1
  }
  if (-not $keep) { $keep = $hits[0] }
  $regPath = Join-Path $env:USERPROFILE '.grok\installed-plugins\registry.json'
  foreach ($h in $hits) {
    if ($h.repo_key -eq $keep.repo_key) { continue }
    Write-UabsWarn ("Grok: duplicate {0} ({1}) - dropping registry repo {2}" -f $PluginName, $h.source, $h.repo_key)
    if (Test-Path -LiteralPath $regPath -PathType Leaf) {
      $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
      Copy-Item -LiteralPath $regPath -Destination ($regPath + '.before-dedupe-' + $ts + '.bak') -Force
      $doc = ([IO.File]::ReadAllText($regPath) | ConvertFrom-Json)
      if ($doc.repos -and $doc.repos.PSObject.Properties.Name -contains [string]$h.repo_key) {
        $doc.repos.PSObject.Properties.Remove([string]$h.repo_key)
        $utf8 = New-Object System.Text.UTF8Encoding $false
        [IO.File]::WriteAllText($regPath, (($doc | ConvertTo-Json -Depth 20) + [Environment]::NewLine), $utf8)
      }
    }
    if ($h.path -and (Test-Path -LiteralPath $h.path)) {
      Remove-Item -LiteralPath $h.path -Recurse -Force
    }
  }
  $left = @(Get-UabsGrokPluginList -GrokExe $GrokExe | Where-Object { $_.name -eq $PluginName })
  if ($left.Count -gt 1) {
    Write-UabsWarn ("Grok: still {0} copies of {1} after registry drop - skill names will collide" -f $left.Count, $PluginName)
  } elseif ($left.Count -eq 1) {
    Write-UabsOk ("Grok: one {0} plugin remains ({1})" -f $PluginName, $left[0].repo_key)
  }
  return $left
}

function Get-UabsClaudeMarketplaceName {
  <#
  The marketplace directory name Claude Code caches a bundled plugin under.

  Claude installs a plugin to ~/.claude/plugins/cache/<marketplace>/<plugin>,
  and <marketplace> is the `name` inside the plugin's OWN
  .claude-plugin/marketplace.json - not the plugin id. Superpowers ships as
  'superpowers-dev', ponytail as 'ponytail', so guessing the id is right half
  the time and silently wrong the other half.

  Returns $null when the bundle has no manifest for that plugin, so callers
  can report SKIP instead of inventing a path.

  Restored in 7.9.0: 7.8.0 dropped this function but left
  TESTS\Test-HarnessRealization.ps1 calling it, so that gate died on its first
  Claude check. It is not in CI, so nothing noticed.
  #>
  param([string]$PluginRoot)
  $manifest = Join-Path $PluginRoot '.claude-plugin\marketplace.json'
  if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { return $null }
  try {
    # ReadAllText, never Get-Content -Raw: on Windows PowerShell 5.1 the latter
    # decodes with the ANSI codepage and mojibakes any non-ASCII owner name.
    $json = [IO.File]::ReadAllText($manifest) | ConvertFrom-Json
  } catch { return $null }
  if ($json -and $json.name) { return [string]$json.name }
  return $null
}

function Get-UabsPluginOwnedSkillNames {
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

function Remove-UabsPluginOwnedSkillCopies {
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
      Write-UabsWarn ('dedupe: kept ' + $name + ' - copy has no SKILL.md to verify against canonical')
      if ($Log) { [void]$Log.Add((Get-Date -Format o) + ' dedupe: kept ' + $name + ' in ' + $SkillsDir + ' (no SKILL.md)') }
      continue
    }
    if (-not (Test-Path -LiteralPath $canonMd -PathType Leaf)) {
      # The canonical tree never shipped a skill of this name, so there is
      # nothing to verify the copy against. Keep it.
      $result.skipped += ($name + ' (absent from canonical tree - kept)')
      Write-UabsWarn ('dedupe: kept ' + $name + ' - no canonical SKILL.md to verify against')
      if ($Log) { [void]$Log.Add((Get-Date -Format o) + ' dedupe: kept ' + $name + ' in ' + $SkillsDir + ' (not in canonical)') }
      continue
    }
    $hCopy = (Get-FileHash -LiteralPath $copyMd -Algorithm MD5).Hash
    $hCanon = (Get-FileHash -LiteralPath $canonMd -Algorithm MD5).Hash
    if ($hCopy -ne $hCanon) {
      $result.skipped_modified += $name
      Write-UabsWarn ('dedupe: REFUSED to remove ' + $target + ' - SKILL.md differs from the pack canonical (user-modified?). Back up your changes and remove it by hand if unwanted.')
      if ($Log) { [void]$Log.Add((Get-Date -Format o) + ' dedupe: REFUSED ' + $target + ' (md5 differs from canonical)') }
      continue
    }
    New-Item -ItemType Directory -Force -Path $bkDir | Out-Null
    Copy-UabsRobo -From $target -To (Join-Path $bkDir $name)
    Remove-Item -LiteralPath $target -Recurse -Force
    $result.removed += $name
    Write-UabsOk ('dedupe: removed plugin-owned copy ' + $name + ' (backup: ' + (Join-Path $bkDir $name) + ')')
    if ($Log) { [void]$Log.Add((Get-Date -Format o) + ' dedupe: removed ' + $target + ' (backup ' + $bkDir + ')') }
  }
  return $result
}

function Test-UabsTomlPluginEnabled {
  <#
  True when TOML content has a section whose header starts with
  [<HeaderPrefix> and whose body contains enabled = true. Line-based on
  purpose: regex-over-sections is how config.toml readers have been burned
  before (see the [compat.claude] comment in Set-UabsGrokCompatCells).
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

function Set-UabsHermesPluginScanOff {
  <#
  Ensure plugins.scan_on_install: false in the Hermes config.yaml.

  Hermes' security scanner refuses both bundled plugins with 214
  false-positive 'traversal' findings in upstream test scripts, and --force
  does not override it, so the scanner must be told not to run at install
  time. This is a TEXT edit, never a YAML re-serialize: any comment the
  operator added survives untouched.

  Rules: an operator-owned false value is left exactly as-is, true is changed
  temporarily and restored later, and a missing setting is inserted directly
  under plugins:. Backup to config.yaml.bak-<yyyyMMdd-HHmmss> first.

  Returns 'already-present' | 'inserted' | 'appended-section' | 'created' | 'failed'.
  #>
  param([string]$ConfigPath)
  try {
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
      $dir = Split-Path $ConfigPath -Parent
      New-Item -ItemType Directory -Force -Path $dir | Out-Null
      $enc0 = New-Object System.Text.UTF8Encoding($false)
      [IO.File]::WriteAllText($ConfigPath, ("plugins:`r`n  scan_on_install: false`r`n"), $enc0)
      Write-UabsWarn ('Hermes config.yaml missing - created with plugins.scan_on_install: false (' + $ConfigPath + ')')
      return 'created'
    }
    $text = [IO.File]::ReadAllText($ConfigPath)
    $nl = "`r`n"
    if ($text -notmatch "`r`n") { $nl = "`n" }
    $lines = @($text -split '\r?\n')
    $out = @()
    $inPlugins = $false
    $pluginsFound = $false
    $settingFound = $false
    $changedTrue = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
      $line = $lines[$i]
      if ($line -match '^plugins\s*:') {
        $pluginsFound = $true
        $inPlugins = $true
        $out += $line
        continue
      }
      if ($inPlugins -and $line -match '^\S') { $inPlugins = $false }
      if ($inPlugins -and $line -match '^(\s+scan_on_install\s*:\s*)(true|false)(\s*(?:#.*)?)$') {
        $settingFound = $true
        if ($Matches[2] -eq 'false') {
          Write-UabsOk 'Hermes config: scan_on_install already false - left operator setting unchanged'
          return 'already-present'
        }
        $out += ($Matches[1] + 'false' + $Matches[3])
        $changedTrue = $true
        continue
      }
      $out += $line
    }
    if (-not $settingFound) {
      if ($pluginsFound) {
        $header = 0
        for ($j = 0; $j -lt $out.Count; $j++) {
          if ($out[$j] -match '^plugins\s*:') { $header = $j; break }
        }
        $before = @($out[0..$header])
        $after = if ($header + 1 -lt $out.Count) { @($out[($header + 1)..($out.Count - 1)]) } else { @() }
        $out = @($before + '  scan_on_install: false' + $after)
      } else {
        if ($out.Count -and $out[-1] -ne '') { $out += '' }
        $out += @('plugins:', '  scan_on_install: false')
      }
    }
    Copy-Item -LiteralPath $ConfigPath -Destination ($ConfigPath + '.bak-' + (Get-Date -Format 'yyyyMMdd-HHmmss')) -Force
    $enc = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($ConfigPath, ($out -join $nl), $enc)
    $state = if ($changedTrue) { 'changed-true' } elseif ($pluginsFound) { 'inserted' } else { 'appended-section' }
    Write-UabsWarn 'Hermes config: plugin scanning temporarily disabled for the two bundled, pinned plugins'
    return $state
  } catch {
    Write-UabsWarn ('Hermes scan_on_install override failed: ' + $_.Exception.Message)
    return 'failed'
  }
}

function Install-UabsKimiPlugin {
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
        Write-UabsWarn ('Kimi installed.json was unparseable - kept a copy and rebuilt it')
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

function Restore-UabsHermesPluginScan {
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

  $State is the string returned by Set-UabsHermesPluginScanOff. When it reports
  'already-present' the operator had their own setting and it is left alone.

  Returns 'removed' | 'restored-true' | 'kept-user-setting' | 'absent' | 'failed'.
  #>
  param([string]$ConfigPath, [string]$State)
  try {
    if ($State -eq 'already-present') {
      Write-UabsOk 'Hermes config: scan_on_install was the operator''s own setting - left as-is'
      return 'kept-user-setting'
    }
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { return 'absent' }
    $text = [IO.File]::ReadAllText($ConfigPath)
    $nl = "`r`n"
    if ($text -notmatch "`r`n") { $nl = "`n" }
    $lines = @($text -split '\r?\n')
    $keep = @()
    $dropped = 0
    $inPlugins = $false
    foreach ($line in $lines) {
      if ($line -match '^plugins\s*:') { $inPlugins = $true; $keep += $line; continue }
      if ($inPlugins -and $line -match '^\S') { $inPlugins = $false }
      if ($inPlugins -and $line -match '^(\s+scan_on_install\s*:\s*)false(\s*(?:#.*)?)$') {
        if ($State -eq 'changed-true') { $keep += ($Matches[1] + 'true' + $Matches[2]) }
        $dropped++
        continue
      }
      $keep += $line
    }
    if ($dropped -eq 0) {
      Write-UabsOk 'Hermes config: no scan_on_install override left to remove'
      return 'absent'
    }
    Copy-Item -LiteralPath $ConfigPath -Destination ($ConfigPath + '.bak-' + (Get-Date -Format 'yyyyMMdd-HHmmss')) -Force
    $enc = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($ConfigPath, ($keep -join $nl), $enc)
    if ($State -eq 'changed-true') {
      Write-UabsOk 'Hermes config: operator scan_on_install: true restored'
      return 'restored-true'
    }
    Write-UabsOk 'Hermes config: temporary scan_on_install override removed - plugin scanning is back on'
    return 'removed'
  } catch {
    Write-UabsWarn ('Hermes scan_on_install restore failed: ' + $_.Exception.Message)
    return 'failed'
  }
}

function Add-UabsMarketplacePluginEntry {
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
    Write-UabsWarn ('marketplace manifest is not valid JSON - left untouched: ' + $ManifestPath)
    return $false
  }
  if (-not $parsed -or -not $parsed.plugins) {
    Write-UabsWarn ('marketplace manifest has no plugins array - left untouched: ' + $ManifestPath)
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
      Write-UabsWarn ('could not locate the plugins array in ' + $ManifestPath)
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
    Write-UabsWarn ('marketplace edit failed validation - file left untouched: ' + $_.Exception.Message)
    return $false
  }
  Copy-Item -LiteralPath $ManifestPath -Destination ($ManifestPath + '.bak-' + (Get-Date -Format 'yyyyMMdd-HHmmss')) -Force
  $enc = New-Object System.Text.UTF8Encoding($false)
  [IO.File]::WriteAllText($ManifestPath, $new, $enc)
  return $true
}

<# Resolve a provider CLI without installing anything.

   Shared so INSTALL-AIO.ps1's auto-detection and Ensure-Provider-CLIs.ps1's
   bootstrap agree on what "installed" means. They disagreed before v8.1.0:
   the installer assumed all five providers were wanted and the bootstrap then
   downloaded the missing ones, so a machine with only Claude ended up with
   four vendor CLIs nobody asked for. #>
function Resolve-UabsProviderExe {
  param([Parameter(Mandatory)][string]$Provider)
  $cmd = Get-Command $Provider.ToLowerInvariant() -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $candidates = switch ($Provider) {
    'Claude' { @((Join-Path $env:USERPROFILE '.local\bin\claude.exe')) }
    'Codex'  { @((Join-Path $env:USERPROFILE '.local\bin\codex.exe'), (Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\bin\codex.exe')) }
    'Grok'   { @((Join-Path $env:USERPROFILE '.grok\bin\grok.exe')) }
    'Kimi'   { @((Join-Path $env:USERPROFILE '.local\bin\kimi.exe'), (Join-Path $env:USERPROFILE '.kimi-code\bin\kimi.exe')) }
    'Hermes' { @((Join-Path $env:LOCALAPPDATA 'hermes\hermes-agent\venv\Scripts\hermes.exe'), (Join-Path $env:LOCALAPPDATA 'hermes\bin\hermes.exe')) }
    default  { @() }
  }
  foreach ($candidate in $candidates) {
    if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return $candidate }
  }
  return $null
}

# Providers whose CLI is actually on this machine. Executable presence only:
# a leftover ~/.kimi-code or ~/.codex directory survives an uninstall, and
# treating a stale config folder as an install would keep re-wiring a provider
# the user deliberately removed.
function Get-UabsInstalledProviders {
  param([string[]]$Candidates = @('Claude','Codex','Grok','Kimi','Hermes'))
  return @($Candidates | Where-Object { Resolve-UabsProviderExe -Provider $_ })
}
