<#
.SYNOPSIS
  The one place this pack writes an MCP server into a provider config.

.DESCRIPTION
  Four providers keep MCP servers in three different shapes -- two JSON files
  with different section names, two TOML files, and Hermes, which stores them
  through its own Python config API. Every bug this pack has shipped in that
  area was a bug in one of those shapes that the other three did not have:
  a TOML table matcher that stopped at the '[' inside `args = ["-y", ...]`, a
  Hermes check that read `mcp list` output (names only) for a command string, a
  backslash escaped four times instead of two. Two scripts writing configs meant
  the same bug had to be found twice.

  So both writers -- Add-Reasoning-MCPs.ps1 for the always-on core, and
  Set-McpProfile.ps1 for the capability profiles -- dot-source this file and
  share one implementation.

  A server definition is a hashtable:

    id                 name the provider will show
    command            executable; may contain %VARS% and {project}
    args               argument array
    args_by_provider   optional per-provider override of args
    note               one-line comment written above TOML entries
    key                optional env var name; copied into env when set
    env_passthrough    env var names copied into env when set
    requires           optional preconditions (see Test-V5ServerRequirement)
    scope              'global' (default) or 'project'
#>

# Windows PowerShell 5.1's `Set-Content -Encoding utf8` writes a UTF-8 BOM. A BOM
# in a JSON config is a real hazard: a strict reader rejects the file outright.
function Test-V5GrokInheritsClaudeMcp {
  <# grok-cli adopts ~/.claude.json by default, but this pack writes
     [compat.claude] mcps = false because inherited MCP startup cost 65s on the
     first turn of every session and attached zero tools. Assuming inheritance
     after switching it off turns a dedupe into a silent omission. #>
  $cfg = Join-Path $env:USERPROFILE '.grok\config.toml'
  if (-not (Test-Path -LiteralPath $cfg -PathType Leaf)) { return $true }
  $text = [IO.File]::ReadAllText($cfg)
  $m = [regex]::Match($text, '(?ms)^\[compat\.claude\][^\[]*?^\s*mcps\s*=\s*(?<v>true|false)')
  if (-not $m.Success) { return $true }
  return ($m.Groups['v'].Value -ieq 'true')
}

function Get-V5GrokMcpCount {
  $cfg = Join-Path $env:USERPROFILE '.grok\config.toml'
  if (-not (Test-Path -LiteralPath $cfg -PathType Leaf)) { return 0 }
  return @([regex]::Matches([IO.File]::ReadAllText($cfg), '(?m)^\[mcp_servers\.(?<n>[^\].]+)\]')).Count
}

function Select-V5WithinGrokBudget {
  <# grok-cli 1.0.4 wedges at EIGHT servers running, and an enabled Claude
     plugin with a .mcp.json can quietly supply one, so the pack's default
     budget is six. The budget used to be enforced for exactly one server by
     name (skyrim-forge) while every other path added freely -- enumeration
     where a sweep was needed. Returns the servers that fit, and reports the
     rest by name so an omission is never silent. #>
  param([object[]]$Servers, [int]$Budget = 6)
  $have = Get-V5GrokMcpCount
  $room = $Budget - $have
  # No comma operator here: every caller wraps the result in @(), and ,@(...)
  # would hand them a one-element array containing the array.
  if ($room -ge @($Servers).Count) { return @($Servers) }
  if ($room -le 0) {
    Write-Host ("Grok    at {0} MCP server(s), budget {1}: not adding {2}" -f $have, $Budget, ((@($Servers) | ForEach-Object { $_['id'] }) -join ', ')) -ForegroundColor Yellow
    Write-Host  '        grok-cli wedges at eight running. Remove one from ~/.grok/config.toml, or raise -GrokMcpBudget.' -ForegroundColor DarkGray
    return @()
  }
  $fit = @($Servers | Select-Object -First $room)
  $cut = @($Servers | Select-Object -Skip $room | ForEach-Object { $_['id'] })
  Write-Host ("Grok    budget {0} reached: not adding {1}" -f $Budget, ($cut -join ', ')) -ForegroundColor Yellow
  return $fit
}

function Get-V5NpxPackageBase {
  <# '@scope/name@1.2.3' -> '@scope/name'; 'name@1.2.3' -> 'name'. The version
     is deliberately dropped: a pin change must still match the same server. #>
  param([string[]]$Arguments)
  foreach ($a in @($Arguments)) {
    if ($a -like '-*') { continue }
    $at = $a.LastIndexOf('@')
    if ($at -gt 0) { return $a.Substring(0, $at) }
    return $a
  }
  return ''
}

function Find-V5ServerByPackage {
  <# Returns the name of an existing entry that already runs this package, or
     ''. Dedupe keys on the server NAME everywhere else, which cannot see the
     same server declared under a different one -- Hermes ended up with both
     `playwright` and `playwright-mcp`. #>
  param([string]$ConfigText, [string]$PackageBase)
  if (-not $PackageBase -or -not $ConfigText) { return '' }
  if ($ConfigText -notmatch [regex]::Escape($PackageBase)) { return '' }
  # YAML (Hermes): two-space server keys, the package somewhere in the block.
  # Walked rather than matched with one multiline regex: `$` against CRLF and a
  # greedy `\s*` made that version match nothing at all.
  $current = ''
  $block = New-Object System.Text.StringBuilder
  foreach ($line in ($ConfigText -split "`r?`n")) {
    if ($line -match '^  (?<name>[^\s:#][^:]*):[ \t]*$') {
      if ($current -and $block.ToString().Contains($PackageBase)) { return $current }
      $current = $Matches['name']
      [void]$block.Clear()
      continue
    }
    if ($line -match '^    \S' -or $line -match '^      ') { [void]$block.AppendLine($line); continue }
    if ($line -notmatch '^\s*$') {
      if ($current -and $block.ToString().Contains($PackageBase)) { return $current }
      $current = ''
      [void]$block.Clear()
    }
  }
  if ($current -and $block.ToString().Contains($PackageBase)) { return $current }
  # JSON (Kimi/Claude): the whole entry is one object under its name.
  $json = [regex]::Matches($ConfigText, '(?ms)"(?<name>[^"]+)"\s*:\s*\{(?<body>[^{}]*)\}')
  foreach ($m in $json) {
    if ($m.Groups['body'].Value -match [regex]::Escape($PackageBase)) { return $m.Groups['name'].Value }
  }
  return ''
}

function Set-Utf8NoBom {
  param([string]$Path, [string]$Text)
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Text, $enc)
}

function Write-JsonFile {
  param([string]$Path, $Object)
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  if (Test-Path -LiteralPath $Path) {
    Copy-Item -LiteralPath $Path -Destination "$Path.bak-mcp-$(Get-Date -Format yyyyMMdd-HHmmss)" -Force
  }
  Set-Utf8NoBom -Path $Path -Text ($Object | ConvertTo-Json -Depth 20)
}

function Get-ClaudeDesktopConfigPath {
  # Claude Desktop ships as either a normal install (%APPDATA%\Claude) or a
  # Microsoft Store package. Its MCP surface is claude_desktop_config.json;
  # ~/.claude.json only feeds Claude Code CLI sessions, so a desktop-only user
  # would otherwise get no servers at all.
  $normal = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'Claude\claude_desktop_config.json'
  if (Test-Path -LiteralPath $normal -PathType Leaf) { return $normal }
  $packages = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Packages'
  if (-not (Test-Path -LiteralPath $packages)) { return $null }
  return Get-ChildItem -LiteralPath $packages -Directory -Filter 'Claude_*' -ErrorAction SilentlyContinue |
    ForEach-Object { Join-Path $_.FullName 'LocalCache\Roaming\Claude\claude_desktop_config.json' } |
    Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
    Select-Object -First 1
}

function Get-V5McpTargets {
  @{
    'Claude' = @{ Path = Join-Path $env:USERPROFILE '.claude.json'; Section = 'mcpServers'; Style = 'json'; Desktop = $true }
    'Kimi'   = @{ Path = Join-Path $env:USERPROFILE '.kimi-code\mcp.json'; Section = 'mcpServers'; Style = 'json'; Desktop = $false }
    'Grok'   = @{ Path = Join-Path $env:USERPROFILE '.grok\config.toml'; Section = 'mcp_servers'; Style = 'toml'; Desktop = $false }
    'Codex'  = @{ Path = Join-Path $env:USERPROFILE '.codex\config.toml'; Section = 'mcp_servers'; Style = 'toml'; Desktop = $false }
  }
}

function Expand-V5Template {
  <# Expand %ENVVAR% and the {project} placeholder. Returns '' for empty input
     so callers can test the result rather than guarding every call. #>
  param([string]$Text, [string]$ProjectPath)
  if ([string]::IsNullOrEmpty($Text)) { return '' }
  $out = [Environment]::ExpandEnvironmentVariables($Text)
  if ($out -like '*{project}*') {
    if ([string]::IsNullOrEmpty($ProjectPath)) { return '' }
    $out = $out.Replace('{project}', $ProjectPath.TrimEnd('\', '/'))
  }
  return $out
}

function Test-V5CommandAvailable {
  <# A bare name is looked up on PATH; anything that looks like a path must
     exist as a file. A server whose command cannot run is worse than an absent
     one -- the provider shows no tools and says nothing about why. #>
  param([string]$Command, [string]$ProjectPath)
  $resolved = Expand-V5Template -Text $Command -ProjectPath $ProjectPath
  if ([string]::IsNullOrEmpty($resolved)) { return $false }
  if ($resolved -match '[\\/]') { return (Test-Path -LiteralPath $resolved -PathType Leaf) }
  return [bool](Get-Command $resolved -ErrorAction SilentlyContinue)
}

function Test-V5AnyPath {
  param([string[]]$Paths, [string]$ProjectPath)
  foreach ($p in @($Paths)) {
    $resolved = Expand-V5Template -Text $p -ProjectPath $ProjectPath
    if ([string]::IsNullOrEmpty($resolved)) { continue }
    # Non-literal on purpose: these entries carry a '*' for a version segment.
    if (Get-Item -Path $resolved -ErrorAction SilentlyContinue) { return $true }
  }
  return $false
}

function Test-V5ServerRequirement {
  <# Returns @{ Ok = bool; Reason = string }. Reason is what gets printed when
     a profile is skipped, so it names the missing thing, not just 'skipped'. #>
  param($Server, [string]$ProjectPath)
  $req = $null
  if ($Server.Contains('requires')) { $req = $Server['requires'] }
  if (-not $req) { return @{ Ok = $true; Reason = '' } }

  if ($req.Contains('command') -and $req['command']) {
    if (-not (Test-V5CommandAvailable -Command $req['command'] -ProjectPath $ProjectPath)) {
      return @{ Ok = $false; Reason = ("command not found: {0}" -f $req['command']) }
    }
  }
  if ($req.Contains('any_path') -and $req['any_path']) {
    if (-not (Test-V5AnyPath -Paths @($req['any_path']) -ProjectPath $ProjectPath)) {
      return @{ Ok = $false; Reason = ("host application not installed (looked for {0})" -f (@($req['any_path'])[0])) }
    }
  }
  if ($req.Contains('env') -and $req['env']) {
    if (-not [Environment]::GetEnvironmentVariable($req['env'])) {
      return @{ Ok = $false; Reason = ("{0} is not set" -f $req['env']) }
    }
  }
  if ($req.Contains('project_rel') -and $req['project_rel']) {
    if ([string]::IsNullOrEmpty($ProjectPath)) {
      return @{ Ok = $false; Reason = 'project-scoped server needs -Path <project directory>' }
    }
    $full = Join-Path $ProjectPath $req['project_rel']
    if (-not (Test-Path -LiteralPath $full)) {
      return @{ Ok = $false; Reason = ("not present in this project: {0}" -f $req['project_rel']) }
    }
  }
  return @{ Ok = $true; Reason = '' }
}

function Resolve-V5ServerArgs {
  param($Server, [string]$Provider, [string]$ProjectPath)
  # Not $args: that is an automatic variable inside a function.
  $argv = $Server['args']
  if ($Server.Contains('args_by_provider') -and $Server['args_by_provider']) {
    $byProvider = $Server['args_by_provider']
    if ($byProvider.Contains($Provider)) { $argv = $byProvider[$Provider] }
  }
  # Comma operator, not plain @(): `return` unrolls a pipeline, so a
  # one-argument server ('uvx blender-mcp') came back as a bare string and
  # was written into JSON as "args": "blender-mcp".
  return ,@(@($argv) | ForEach-Object { Expand-V5Template -Text ([string]$_) -ProjectPath $ProjectPath })
}

function Resolve-V5ServerEnv {
  <# Only variables that are actually set get written. An env block naming a
     variable with no value is indistinguishable, to the server, from a user who
     typed their key wrong. #>
  param($Server)
  $names = @()
  if ($Server.Contains('key') -and $Server['key']) { $names += $Server['key'] }
  if ($Server.Contains('env_passthrough') -and $Server['env_passthrough']) { $names += @($Server['env_passthrough']) }
  $out = @{}
  foreach ($n in ($names | Select-Object -Unique)) {
    $v = [Environment]::GetEnvironmentVariable($n)
    if ($v) { $out[$n] = $v }
  }
  return $out
}

# ---- removal ---------------------------------------------------------------
# One function serves two callers: retiring a withdrawn package (matched on a
# text literal inside the entry) and disabling a profile (matched on the server
# name). Keying only on the name was the bug that would have left every existing
# machine on a dead GitHub package forever -- the name stays valid while the
# command behind it rots.

function Test-V5TextMatchesAny {
  param([string]$Text, [string[]]$Literals)
  foreach ($lit in @($Literals)) {
    if ($lit -and $Text -and $Text.Contains($lit)) { return $true }
  }
  return $false
}

function Remove-V5McpJson {
  param([string]$Path, [string]$Section, [string[]]$Ids = @(), [string[]]$MatchLiterals = @(), [switch]$CheckOnly)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
  $json = [IO.File]::ReadAllText($Path) | ConvertFrom-Json
  if (-not $json.PSObject.Properties[$Section] -or $null -eq $json.$Section) { return @() }
  $dropped = @()
  foreach ($prop in @($json.$Section.PSObject.Properties)) {
    $hit = ($Ids -contains $prop.Name)
    if (-not $hit -and $MatchLiterals.Count) {
      $hit = Test-V5TextMatchesAny -Text ($prop.Value | ConvertTo-Json -Depth 20 -Compress) -Literals $MatchLiterals
    }
    if ($hit) {
      $json.$Section.PSObject.Properties.Remove($prop.Name)
      $dropped += $prop.Name
    }
  }
  if ($dropped.Count -and -not $CheckOnly) { Write-JsonFile -Path $Path -Object $json }
  return $dropped
}

function Remove-V5McpToml {
  param([string]$Path, [string]$Section, [string[]]$Ids = @(), [string[]]$MatchLiterals = @(), [switch]$CheckOnly)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
  $text = [IO.File]::ReadAllText($Path)
  # A table ends at the next line that STARTS a header, not at the next '['.
  # `args = ["-y", "..."]` contains a bracket, and matching to it truncated the
  # block before the package literal -- which is exactly what was being hunted.
  # The optional leading comment is the one-line note written above each
  # entry. Leaving it behind accumulates an orphan per enable/disable cycle.
  $pattern = '(?ms)(?:^[ \t]*#[^\r\n]*\r?\n)?^\[' + [regex]::Escape($Section) + '\.(?<name>[^\].]+)(?<sub>\.[^\]]+)?\].*?(?=^\[|\z)'
  $blocks = [regex]::Matches($text, $pattern)
  # Sub-tables belong to their parent: dropping [x.github] but keeping
  # [x.github.env] leaves an orphan the TOML parser will reject or misread.
  $names = @()
  foreach ($m in $blocks) {
    $name = $m.Groups['name'].Value
    $hit = ($Ids -contains $name)
    if (-not $hit -and $MatchLiterals.Count) {
      $hit = Test-V5TextMatchesAny -Text $m.Value -Literals $MatchLiterals
    }
    if ($hit) { $names += $name }
  }
  $names = @($names | Select-Object -Unique)
  if (-not $names.Count -or $CheckOnly) { return $names }
  foreach ($m in $blocks) {
    if ($names -contains $m.Groups['name'].Value) { $text = $text.Replace($m.Value, '') }
  }
  Copy-Item -LiteralPath $Path -Destination "$Path.bak-mcp-$(Get-Date -Format yyyyMMdd-HHmmss)" -Force
  Set-Utf8NoBom -Path $Path -Text $text
  return $names
}

# ---- addition --------------------------------------------------------------

function Add-V5McpJson {
  param(
    [string]$Path, [string]$Section, [object[]]$Servers, [string]$Provider,
    [switch]$Refresh, [switch]$CheckOnly, [string]$ProjectPath
  )
  $json = if (Test-Path -LiteralPath $Path) {
    [IO.File]::ReadAllText($Path) | ConvertFrom-Json
  } else { [pscustomobject]@{} }

  if ($json.PSObject.Properties.Name -notcontains $Section) {
    $json | Add-Member -NotePropertyName $Section -NotePropertyValue ([pscustomobject]@{})
  }
  $added = @()
  foreach ($s in $Servers) {
    if ($json.$Section.PSObject.Properties.Name -contains $s['id']) {
      if (-not $Refresh) { continue }
      $json.$Section.PSObject.Properties.Remove($s['id'])
    }
    $entry = [ordered]@{
      command = Expand-V5Template -Text $s['command'] -ProjectPath $ProjectPath
      args    = Resolve-V5ServerArgs -Server $s -Provider $Provider -ProjectPath $ProjectPath
    }
    $envBlock = Resolve-V5ServerEnv -Server $s
    if ($envBlock.Count) { $entry['env'] = $envBlock }
    $json.$Section | Add-Member -NotePropertyName $s['id'] -NotePropertyValue ([pscustomobject]$entry)
    $added += $s['id']
  }
  if ($added.Count -and -not $CheckOnly) { Write-JsonFile -Path $Path -Object $json }
  return $added
}

function Add-V5McpToml {
  <# Append rather than round-trip. Re-serializing the user's TOML would
     reorder and strip the comments in a file they own. #>
  param(
    [string]$Path, [string]$Section, [object[]]$Servers, [string]$Provider,
    [switch]$Refresh, [switch]$CheckOnly, [string]$ProjectPath, [switch]$GrokTimeout
  )
  $text = if (Test-Path -LiteralPath $Path) { [IO.File]::ReadAllText($Path) } else { '' }
  $append = ''
  $added = @()
  foreach ($s in $Servers) {
    $header = "[$Section.$($s['id'])]"
    if ($text -match [regex]::Escape($header)) {
      if (-not $Refresh) { continue }
      $dropped = Remove-V5McpToml -Path $Path -Section $Section -Ids @($s['id'])
      if ($dropped.Count) { $text = [IO.File]::ReadAllText($Path) }
    }
    $cmd = Expand-V5Template -Text $s['command'] -ProjectPath $ProjectPath
    $argv = Resolve-V5ServerArgs -Server $s -Provider $Provider -ProjectPath $ProjectPath
    # TOML escapes a backslash as exactly two. Four parses back to a doubled
    # separator and a command that does not exist.
    $cmdToml = $cmd -replace '\\', '\\'
    $argList = ($argv | ForEach-Object { '"' + ($_ -replace '\\', '\\') + '"' }) -join ', '
    $block = "`r`n# $($s['note'])`r`n$header`r`ncommand = `"$cmdToml`"`r`nargs = [$argList]`r`n"
    if ($GrokTimeout) { $block += "startup_timeout_sec = 90`r`n" }
    $envBlock = Resolve-V5ServerEnv -Server $s
    if ($envBlock.Count) {
      $block += "[$Section.$($s['id']).env]`r`n"
      foreach ($k in ($envBlock.Keys | Sort-Object)) {
        $block += ("{0} = `"{1}`"`r`n" -f $k, ($envBlock[$k] -replace '\\', '\\'))
      }
    }
    $append += $block
    $added += $s['id']
  }
  if ($added.Count -and -not $CheckOnly) {
    if (Test-Path -LiteralPath $Path) {
      Copy-Item -LiteralPath $Path -Destination "$Path.bak-mcp-$(Get-Date -Format yyyyMMdd-HHmmss)" -Force -ErrorAction SilentlyContinue
      Set-Utf8NoBom -Path $Path -Text (([IO.File]::ReadAllText($Path)) + $append)
    } else {
      Set-Utf8NoBom -Path $Path -Text $append
    }
  }
  return $added
}

# ---- Hermes ----------------------------------------------------------------

function Get-V5HermesPaths {
  $home_ = if ($env:HERMES_HOME) { $env:HERMES_HOME } else { Join-Path $env:LOCALAPPDATA 'hermes' }
  $exe = Join-Path $env:LOCALAPPDATA 'hermes\hermes-agent\venv\Scripts\hermes.exe'
  @{
    Home   = $home_
    Config = Join-Path $home_ 'config.yaml'
    Exe    = $exe
    Python = Join-Path (Split-Path -Parent $exe) 'python.exe'
  }
}

function Invoke-V5HermesConfig {
  <# Hermes' `mcp add` is interactive after discovery, and hidden stdin piping
     can block on Windows PowerShell 5.1. Drive its own config API instead. #>
  param([string]$Script, [hashtable]$EnvVars)
  $paths = Get-V5HermesPaths
  if (-not (Test-Path -LiteralPath $paths.Python -PathType Leaf)) { throw 'Hermes Python runtime missing' }
  $tmp = Join-Path ([IO.Path]::GetTempPath()) ('uabs-hermes-' + [guid]::NewGuid().ToString('N') + '.py')
  $saved = @{}
  try {
    foreach ($k in $EnvVars.Keys) {
      $saved[$k] = [Environment]::GetEnvironmentVariable($k)
      Set-Item -Path ("Env:" + $k) -Value $EnvVars[$k]
    }
    Set-Utf8NoBom -Path $tmp -Text $Script
    & $paths.Python $tmp
    if ($LASTEXITCODE -ne 0) { throw "Hermes MCP config update failed with exit code $LASTEXITCODE" }
  } finally {
    foreach ($k in $saved.Keys) {
      if ($null -eq $saved[$k]) { Remove-Item ("Env:" + $k) -ErrorAction SilentlyContinue }
      else { Set-Item -Path ("Env:" + $k) -Value $saved[$k] }
    }
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
  }
}

$script:V5HermesAddScript = @'
import json, os
from hermes_cli.config import load_config, save_config
cfg = load_config()
servers = cfg.setdefault("mcp_servers", {})
entry = {
    "command": os.environ["UABS_HERMES_MCP_COMMAND"],
    "args": json.loads(os.environ["UABS_HERMES_MCP_ARGS_JSON"]),
    "enabled": True,
    "connect_timeout": 30,
}
env = json.loads(os.environ.get("UABS_HERMES_MCP_ENV_JSON") or "{}")
if env:
    entry["env"] = env
servers[os.environ["UABS_HERMES_MCP_ID"]] = entry
save_config(cfg)
'@

$script:V5HermesRemoveScript = @'
import json, os
from hermes_cli.config import load_config, save_config
cfg = load_config()
servers = cfg.get("mcp_servers") or {}
for name in json.loads(os.environ["UABS_HERMES_MCP_IDS_JSON"]):
    servers.pop(name, None)
save_config(cfg)
'@

function Add-V5McpHermes {
  param([object[]]$Servers, [switch]$Refresh, [switch]$CheckOnly, [string]$ProjectPath)
  $paths = Get-V5HermesPaths
  $existing = ''
  if (Test-Path -LiteralPath $paths.Config -PathType Leaf) { $existing = [IO.File]::ReadAllText($paths.Config) }
  $added = @()
  foreach ($s in $Servers) {
    # Match the config, never `mcp list`: that prints server NAMES and not the
    # commands behind them, so it can never reveal a stale or withdrawn entry.
    $declared = $existing -match ('(?m)^[ \t]{2,}' + [regex]::Escape($s['id']) + '[ \t]*:')
    if ($declared -and -not $Refresh) { continue }
    if ($CheckOnly) { $added += $s['id']; continue }
    Invoke-V5HermesConfig -Script $script:V5HermesAddScript -EnvVars @{
      UABS_HERMES_MCP_ID        = $s['id']
      UABS_HERMES_MCP_COMMAND   = (Expand-V5Template -Text $s['command'] -ProjectPath $ProjectPath)
      UABS_HERMES_MCP_ARGS_JSON = ((Resolve-V5ServerArgs -Server $s -Provider 'Hermes' -ProjectPath $ProjectPath) | ConvertTo-Json -Compress)
      UABS_HERMES_MCP_ENV_JSON  = ((Resolve-V5ServerEnv -Server $s) | ConvertTo-Json -Compress)
    }
    $added += $s['id']
  }
  return $added
}

function Test-V5HermesRetired {
  <# Read the stored config, never `mcp list`: that prints server NAMES and not
     the commands behind them, so a withdrawn package can never show up in it. #>
  param([string[]]$Literals)
  $paths = Get-V5HermesPaths
  if (-not (Test-Path -LiteralPath $paths.Config -PathType Leaf)) { return $false }
  return (Test-V5TextMatchesAny -Text ([IO.File]::ReadAllText($paths.Config)) -Literals $Literals)
}

function Remove-V5McpHermes {
  <# Removes exactly the ids it is given, and only those that are declared.
     Deciding WHICH ids is the caller's job -- an earlier version folded the
     retired-literal test in here and ended up deleting every id it was handed
     on every run, rewriting a healthy config for no reason. #>
  param([string[]]$Ids, [switch]$CheckOnly)
  $paths = Get-V5HermesPaths
  if (-not (Test-Path -LiteralPath $paths.Config -PathType Leaf)) { return @() }
  $text = [IO.File]::ReadAllText($paths.Config)
  $targets = @()
  foreach ($id in @($Ids)) {
    if ($text -match ('(?m)^[ \t]{2,}' + [regex]::Escape($id) + '[ \t]*:')) { $targets += $id }
  }
  if (-not $targets.Count -or $CheckOnly) { return $targets }
  Copy-Item -LiteralPath $paths.Config -Destination "$($paths.Config).bak-mcp-$(Get-Date -Format yyyyMMdd-HHmmss)" -Force -ErrorAction SilentlyContinue
  Invoke-V5HermesConfig -Script $script:V5HermesRemoveScript -EnvVars @{
    UABS_HERMES_MCP_IDS_JSON = ($targets | ConvertTo-Json -Compress)
  }
  return $targets
}
