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
    project_args       appended when written project-scoped (path is known)
    global_args        appended instead when written machine-wide (-Global)
    requires           optional preconditions (see Test-V5ServerRequirement)
    scope              'project' (default) or 'global'

  Scope is not decoration. A machine-wide entry puts its tool schemas in every
  session on the box; a project-scoped one is only paid for by the project that
  asked. Get-V5ProviderProjectTarget is where each provider's project mechanism
  lives, and it returns $null for the three that have none.
#>

# Windows PowerShell 5.1's `Set-Content -Encoding utf8` writes a UTF-8 BOM. A BOM
# in a JSON config is a real hazard: a strict reader rejects the file outright.
function Join-V5Path {
  <# Join-V5Path asks the provider to resolve the drive, so it raises "Cannot find
     drive" for a base on a drive that is not mounted -- fatal under
     $ErrorActionPreference = 'Stop', in a function whose whole job is string
     concatenation. [IO.Path]::Combine never touches the filesystem. Same class
     as Test-V5Path, found in the same CI run. #>
  param([string]$Base, [string]$Child)
  if ([string]::IsNullOrEmpty($Base)) { return $Child }
  return [IO.Path]::Combine($Base, $Child)
}

function Test-V5Path {
  <# Test-Path does not answer $false for a path on a drive that is not mounted.
     It writes "Cannot find drive. A drive with the name 'Z' does not exist.",
     and every script here runs with $ErrorActionPreference = 'Stop', which makes
     that fatal. An unmounted drive is exactly where a recorded project path, a
     tool on a removable disk or a UNC share ends up, and the answer wanted there
     is "no". Caught in CI, where a test recorded a project on Z:\ and the gate
     died on a runner that has no Z:. #>
  param(
    [string]$LiteralPath,
    [ValidateSet('Any', 'Leaf', 'Container')][string]$PathType = 'Any'
  )
  if ([string]::IsNullOrEmpty($LiteralPath)) { return $false }
  try { return [bool](Test-Path -LiteralPath $LiteralPath -PathType $PathType -ErrorAction SilentlyContinue) }
  catch { return $false }
}

function Test-V5GrokInheritsClaudeMcp {
  <# grok-cli adopts ~/.claude.json by default, but this pack writes
     [compat.claude] mcps = false because inherited MCP startup cost 65s on the
     first turn of every session and attached zero tools. Assuming inheritance
     after switching it off turns a dedupe into a silent omission. #>
  $cfg = Join-V5Path $env:USERPROFILE '.grok\config.toml'
  if (-not (Test-V5Path -LiteralPath $cfg -PathType Leaf)) { return $true }
  $text = [IO.File]::ReadAllText($cfg)
  $m = [regex]::Match($text, '(?ms)^\[compat\.claude\][^\[]*?^\s*mcps\s*=\s*(?<v>true|false)')
  if (-not $m.Success) { return $true }
  return ($m.Groups['v'].Value -ieq 'true')
}

function Get-V5GrokMcpCount {
  <# Grok runs the union of ~/.grok/config.toml and <project>/.grok/config.toml,
     so the ceiling has to be counted over both. Counting only the user file let
     a project-scoped add push the running total past the budget it was checked
     against. #>
  param([string]$ProjectPath)
  $files = @(Join-V5Path $env:USERPROFILE '.grok\config.toml')
  if ($ProjectPath) { $files += (Join-V5Path $ProjectPath '.grok\config.toml') }
  $names = @()
  foreach ($cfg in $files) {
    if (-not (Test-V5Path -LiteralPath $cfg -PathType Leaf)) { continue }
    foreach ($m in [regex]::Matches([IO.File]::ReadAllText($cfg), '(?m)^\[mcp_servers\.(?<n>[^\].]+)\]')) {
      $names += $m.Groups['n'].Value
    }
  }
  return @($names | Select-Object -Unique).Count
}

function Select-V5WithinGrokBudget {
  <# grok-cli 1.0.4 wedges at EIGHT servers running, and an enabled Claude
     plugin with a .mcp.json can quietly supply one, so the pack's default
     budget is six. The budget used to be enforced for exactly one server by
     name (skyrim-forge) while every other path added freely -- enumeration
     where a sweep was needed. Returns the servers that fit, and reports the
     rest by name so an omission is never silent. #>
  param([object[]]$Servers, [int]$Budget = 6, [string]$ProjectPath)
  $have = Get-V5GrokMcpCount -ProjectPath $ProjectPath
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
  if ($dir -and -not (Test-V5Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  if (Test-V5Path -LiteralPath $Path) {
    Copy-Item -LiteralPath $Path -Destination "$Path.bak-mcp-$(Get-Date -Format yyyyMMdd-HHmmss)" -Force
  }
  Set-Utf8NoBom -Path $Path -Text ($Object | ConvertTo-Json -Depth 20)
}

function Get-V5AppDataRoot {
  <# %APPDATA% / %LOCALAPPDATA% first: every other path in this pack comes from
     an environment variable, and GetFolderPath returns an EMPTY STRING when the
     folder does not exist -- which is not an error, but does make the next
     Join-V5Path throw and take the whole run with it. #>
  param([ValidateSet('Roaming', 'Local')][string]$Which)
  $fromEnv = if ($Which -eq 'Roaming') { $env:APPDATA } else { $env:LOCALAPPDATA }
  if ($fromEnv) { return $fromEnv }
  $folder = if ($Which -eq 'Roaming') { 'ApplicationData' } else { 'LocalApplicationData' }
  $resolved = [Environment]::GetFolderPath($folder)
  if ([string]::IsNullOrEmpty($resolved)) { return '' }
  return $resolved
}

function Get-ClaudeDesktopConfigPath {
  # Claude Desktop ships as either a normal install (%APPDATA%\Claude) or a
  # Microsoft Store package. Its MCP surface is claude_desktop_config.json;
  # ~/.claude.json only feeds Claude Code CLI sessions, so a desktop-only user
  # would otherwise get no servers at all.
  #
  # Both roots are checked for emptiness before use. "Claude Desktop is not
  # installed" is the right answer when a folder does not resolve; a crash
  # inside this helper is not.
  $roaming = Get-V5AppDataRoot -Which 'Roaming'
  if ($roaming) {
    $normal = Join-V5Path $roaming 'Claude\claude_desktop_config.json'
    if (Test-V5Path -LiteralPath $normal -PathType Leaf) { return $normal }
  }
  $local = Get-V5AppDataRoot -Which 'Local'
  if (-not $local) { return $null }
  $packages = Join-V5Path $local 'Packages'
  if (-not (Test-V5Path -LiteralPath $packages)) { return $null }
  return Get-ChildItem -LiteralPath $packages -Directory -Filter 'Claude_*' -ErrorAction SilentlyContinue |
    ForEach-Object { Join-V5Path $_.FullName 'LocalCache\Roaming\Claude\claude_desktop_config.json' } |
    Where-Object { Test-V5Path -LiteralPath $_ -PathType Leaf } |
    Select-Object -First 1
}

function Get-V5McpTargets {
  @{
    'Claude' = @{ Path = Join-V5Path $env:USERPROFILE '.claude.json'; Section = 'mcpServers'; Style = 'json'; Desktop = $true }
    'Kimi'   = @{ Path = Join-V5Path $env:USERPROFILE '.kimi-code\mcp.json'; Section = 'mcpServers'; Style = 'json'; Desktop = $false }
    'Grok'   = @{ Path = Join-V5Path $env:USERPROFILE '.grok\config.toml'; Section = 'mcp_servers'; Style = 'toml'; Desktop = $false }
    'Codex'  = @{ Path = Join-V5Path $env:USERPROFILE '.codex\config.toml'; Section = 'mcp_servers'; Style = 'toml'; Desktop = $false }
  }
}

function Get-V5ProviderProjectTarget {
  <# Where a provider keeps MCP servers for ONE project, or $null when it keeps
     them only machine-wide. Each answer was verified against the installed CLI,
     not recalled:

       Claude  projects["<abs>"].mcpServers in ~/.claude.json -- where
               `claude mcp add --scope local` writes, and what `claude mcp list`
               reads back inside that directory. Chosen over the project's
               .mcp.json because it leaves no file in the user's repository and
               raises no trust prompt.
       Grok    <project>\.grok\config.toml -- `grok mcp add -s project`. This one
               is a file in the project, because grok-cli has no other form.
       Codex   none. A .codex/config.toml inside a project did not appear in
               `codex mcp list` run from that project.
       Kimi    none found. `kimi doctor` in a project holding .kimi-code/mcp.json
               reported only the home configs.
       Hermes  none. `hermes mcp add` has no scope option. #>
  param([string]$Provider, [string]$ProjectPath)
  if ([string]::IsNullOrEmpty($ProjectPath)) { return $null }
  switch ($Provider) {
    'Claude' {
      return @{
        Style      = 'json'
        Path       = (Join-V5Path $env:USERPROFILE '.claude.json')
        Section    = 'mcpServers'
        ProjectKey = $ProjectPath.TrimEnd('\', '/')
      }
    }
    'Grok' {
      return @{
        Style      = 'toml'
        Path       = (Join-V5Path $ProjectPath '.grok\config.toml')
        Section    = 'mcp_servers'
        ProjectKey = ''
      }
    }
  }
  return $null
}

function Test-V5ServerIsProjectBound {
  <# True when the server cannot exist outside one project: its command or its
     arguments are resolved from {project}. Unity-MCP is the case -- the server
     executable is generated inside that project's Library folder, so a
     machine-wide entry for it would be a path that is wrong everywhere else.
     project_args are deliberately not consulted: those are only appended when
     the entry IS project-scoped. #>
  param($Server)
  $parts = @([string]$Server['command']) + @($Server['args'])
  if ($Server.Contains('args_by_provider') -and $Server['args_by_provider']) {
    foreach ($k in $Server['args_by_provider'].Keys) { $parts += @($Server['args_by_provider'][$k]) }
  }
  foreach ($p in $parts) { if ([string]$p -like '*{project}*') { return $true } }
  return $false
}

function Get-V5ProviderNoProjectScope {
  <# The exact reason, so a skipped provider is a decision the user can read
     rather than a capability that silently went missing. #>
  param([string]$Provider)
  switch ($Provider) {
    'Codex'  { return 'codex-cli has no project-scoped MCP config (a project .codex/config.toml is ignored)' }
    'Kimi'   { return 'kimi-code reads only %USERPROFILE%\.kimi-code\mcp.json' }
    'Hermes' { return 'hermes mcp add has no scope option; its config is one file' }
  }
  return ('{0} has no project-scoped MCP config' -f $Provider)
}

function Get-V5ClaudeProjectKeys {
  <# Claude Code keys a project by the working directory string as its shell
     reported it, and ~/.claude.json on this machine holds both
     a backslash form and a slash form of the same tree -- one written from
     PowerShell, one from a POSIX shell. Write the Windows form, and mirror
     into a slash form
     only when the file already has one, so an entry is never invisible in
     whichever shell the user actually opens. #>
  param([string]$ProjectPath, [string]$ConfigPath)
  $canonical = $ProjectPath.TrimEnd('\', '/')
  $keys = @($canonical)
  $alt = $canonical -replace '\\', '/'
  if ($alt -ne $canonical -and (Test-V5Path -LiteralPath $ConfigPath -PathType Leaf)) {
    try {
      $existing = [IO.File]::ReadAllText($ConfigPath) | ConvertFrom-Json
      if ($existing.projects -and ($existing.projects.PSObject.Properties.Name -contains $alt)) { $keys += $alt }
    } catch { }
  }
  return ,@($keys)
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
  if ($resolved -match '[\\/]') { return (Test-V5Path -LiteralPath $resolved -PathType Leaf) }
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
    $full = Join-V5Path $ProjectPath $req['project_rel']
    if (-not (Test-V5Path -LiteralPath $full)) {
      return @{ Ok = $false; Reason = ("not present in this project: {0}" -f $req['project_rel']) }
    }
  }
  return @{ Ok = $true; Reason = '' }
}

function Resolve-V5ServerArgs {
  param($Server, [string]$Provider, [string]$ProjectPath, [string]$Scope = 'project')
  # Not $args: that is an automatic variable inside a function.
  $argv = $Server['args']
  if ($Server.Contains('args_by_provider') -and $Server['args_by_provider']) {
    $byProvider = $Server['args_by_provider']
    if ($byProvider.Contains($Provider)) { $argv = $byProvider[$Provider] }
  }
  # A server that has to know its project gets told, but only in the form that
  # can be true where the entry lands. Serena takes `--project <path>` for a
  # registration written for one known project, and `--project-from-cwd` for a
  # machine-wide one -- a baked absolute path in a global config would activate
  # that one project in every unrelated session.
  $argv = @($argv)
  if ($Scope -eq 'global') {
    if ($Server.Contains('global_args') -and $Server['global_args']) { $argv += @($Server['global_args']) }
  } elseif ($ProjectPath -and $Server.Contains('project_args') -and $Server['project_args']) {
    $argv += @($Server['project_args'])
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

function Get-V5JsonScopeContainer {
  <# Returns the object that holds the server section: the document itself for a
     machine-wide entry, or projects["<abs path>"] for a project-scoped one.
     Returns $null when -Create was not asked for and the project is absent. #>
  param($Json, [string]$ProjectKey, [switch]$Create)
  if (-not $ProjectKey) { return $Json }
  if ($Json.PSObject.Properties.Name -notcontains 'projects') {
    if (-not $Create) { return $null }
    $Json | Add-Member -NotePropertyName 'projects' -NotePropertyValue ([pscustomobject]@{})
  }
  if ($Json.projects.PSObject.Properties.Name -notcontains $ProjectKey) {
    if (-not $Create) { return $null }
    $Json.projects | Add-Member -NotePropertyName $ProjectKey -NotePropertyValue ([pscustomobject]@{})
  }
  return $Json.projects.$ProjectKey
}

function Remove-V5McpJson {
  param([string]$Path, [string]$Section, [string[]]$Ids = @(), [string[]]$MatchLiterals = @(), [switch]$CheckOnly, [string]$ProjectKey)
  if (-not (Test-V5Path -LiteralPath $Path -PathType Leaf)) { return @() }
  $doc = [IO.File]::ReadAllText($Path) | ConvertFrom-Json
  $json = Get-V5JsonScopeContainer -Json $doc -ProjectKey $ProjectKey
  if ($null -eq $json) { return @() }
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
  if ($dropped.Count -and -not $CheckOnly) { Write-JsonFile -Path $Path -Object $doc }
  return $dropped
}

function Remove-V5McpToml {
  param([string]$Path, [string]$Section, [string[]]$Ids = @(), [string[]]$MatchLiterals = @(), [switch]$CheckOnly)
  if (-not (Test-V5Path -LiteralPath $Path -PathType Leaf)) { return @() }
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
  # Otherwise every enable/disable cycle leaves another run of blank lines.
  $text = [regex]::Replace($text, '(\r?\n){3,}', "`r`n`r`n")
  Copy-Item -LiteralPath $Path -Destination "$Path.bak-mcp-$(Get-Date -Format yyyyMMdd-HHmmss)" -Force
  Set-Utf8NoBom -Path $Path -Text $text
  return $names
}

# ---- addition --------------------------------------------------------------

function Add-V5McpJson {
  param(
    [string]$Path, [string]$Section, [object[]]$Servers, [string]$Provider,
    [switch]$Refresh, [switch]$CheckOnly, [string]$ProjectPath,
    [string]$ProjectKey, [string]$Scope = 'global'
  )
  $doc = if (Test-V5Path -LiteralPath $Path) {
    [IO.File]::ReadAllText($Path) | ConvertFrom-Json
  } else { [pscustomobject]@{} }
  $json = Get-V5JsonScopeContainer -Json $doc -ProjectKey $ProjectKey -Create

  if ($json.PSObject.Properties.Name -notcontains $Section) {
    $json | Add-Member -NotePropertyName $Section -NotePropertyValue ([pscustomobject]@{})
  }
  $added = @()
  foreach ($s in $Servers) {
    $entry = [ordered]@{
      command = Expand-V5Template -Text $s['command'] -ProjectPath $ProjectPath
      args    = Resolve-V5ServerArgs -Server $s -Provider $Provider -ProjectPath $ProjectPath -Scope $Scope
    }
    $envBlock = Resolve-V5ServerEnv -Server $s
    if ($envBlock.Count) { $entry['env'] = $envBlock }
    if ($json.$Section.PSObject.Properties.Name -contains $s['id']) {
      if (-not $Refresh) { continue }
      # Rewriting a byte-identical entry is not a change. Reporting it as one is
      # noise; taking a timestamped backup for it is litter.
      $before = $json.$Section.($s['id']) | ConvertTo-Json -Depth 20 -Compress
      $after  = ([pscustomobject]$entry) | ConvertTo-Json -Depth 20 -Compress
      if ($before -eq $after) { continue }
      $json.$Section.PSObject.Properties.Remove($s['id'])
    }
    $json.$Section | Add-Member -NotePropertyName $s['id'] -NotePropertyValue ([pscustomobject]$entry)
    $added += $s['id']
  }
  if ($added.Count -and -not $CheckOnly) { Write-JsonFile -Path $Path -Object $doc }
  return $added
}

function Add-V5McpToml {
  <# Append rather than round-trip. Re-serializing the user's TOML would
     reorder and strip the comments in a file they own. #>
  param(
    [string]$Path, [string]$Section, [object[]]$Servers, [string]$Provider,
    [switch]$Refresh, [switch]$CheckOnly, [string]$ProjectPath, [switch]$GrokTimeout,
    [string]$Scope = 'global'
  )
  $text = if (Test-V5Path -LiteralPath $Path) { [IO.File]::ReadAllText($Path) } else { '' }
  $append = ''
  $added = @()
  foreach ($s in $Servers) {
    $header = "[$Section.$($s['id'])]"
    $declared = $text -match [regex]::Escape($header)
    if ($declared -and -not $Refresh) { continue }
    $cmd = Expand-V5Template -Text $s['command'] -ProjectPath $ProjectPath
    $argv = Resolve-V5ServerArgs -Server $s -Provider $Provider -ProjectPath $ProjectPath -Scope $Scope
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
    if ($declared) {
      # Same rule as JSON: an identical rewrite is not a change, and taking a
      # backup for it drops a .bak file into the user's project every run.
      $existing = [regex]::Match($text, '(?ms)(?:^[ \t]*#[^\r\n]*\r?\n)?^' + [regex]::Escape($header) + '.*?(?=^\[|\z)')
      if ($existing.Success -and $existing.Value.Trim() -eq $block.Trim()) { continue }
      $dropped = Remove-V5McpToml -Path $Path -Section $Section -Ids @($s['id']) -CheckOnly:$CheckOnly
      if ($dropped.Count -and -not $CheckOnly) { $text = [IO.File]::ReadAllText($Path) }
    }
    $append += $block
    $added += $s['id']
  }
  if ($added.Count -and -not $CheckOnly) {
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-V5Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    if (Test-V5Path -LiteralPath $Path) {
      Copy-Item -LiteralPath $Path -Destination "$Path.bak-mcp-$(Get-Date -Format yyyyMMdd-HHmmss)" -Force -ErrorAction SilentlyContinue
      Set-Utf8NoBom -Path $Path -Text ($text + $append)
    } else {
      Set-Utf8NoBom -Path $Path -Text $append
    }
  }
  return $added
}

# ---- Hermes ----------------------------------------------------------------

function Test-V5ServerDeclared {
  <# Is this server registered in that config right now? The add functions
     answer "did I change anything", which is a different question: once an
     identical rewrite correctly stopped counting as a change, a re-run reported
     nothing written and the profile state went back to off while the server was
     still registered. State has to record registration, or -Disable cannot find
     what to remove. #>
  param([string]$Path, [string]$Style, [string]$Section, [string]$Id, [string]$ProjectKey)
  if (-not (Test-V5Path -LiteralPath $Path -PathType Leaf)) { return $false }
  $text = [IO.File]::ReadAllText($Path)
  if ($Style -eq 'toml') { return [bool]($text -match [regex]::Escape("[$Section.$Id]")) }
  try { $doc = $text | ConvertFrom-Json } catch { return $false }
  $c = Get-V5JsonScopeContainer -Json $doc -ProjectKey $ProjectKey
  if ($null -eq $c) { return $false }
  if (-not $c.PSObject.Properties[$Section] -or $null -eq $c.$Section) { return $false }
  return ($c.$Section.PSObject.Properties.Name -contains $Id)
}

function Test-V5HermesServerDeclared {
  param([string]$Id)
  $paths = Get-V5HermesPaths
  if (-not (Test-V5Path -LiteralPath $paths.Config -PathType Leaf)) { return $false }
  return [bool]([IO.File]::ReadAllText($paths.Config) -match ('(?m)^[ \t]{2,}' + [regex]::Escape($Id) + '[ \t]*:'))
}

function Get-V5HermesPaths {
  $home_ = if ($env:HERMES_HOME) { $env:HERMES_HOME } else { Join-V5Path $env:LOCALAPPDATA 'hermes' }
  $exe = Join-V5Path $env:LOCALAPPDATA 'hermes\hermes-agent\venv\Scripts\hermes.exe'
  @{
    Home   = $home_
    Config = Join-V5Path $home_ 'config.yaml'
    Exe    = $exe
    Python = Join-V5Path (Split-Path -Parent $exe) 'python.exe'
  }
}

function Invoke-V5HermesConfig {
  <# Hermes' `mcp add` is interactive after discovery, and hidden stdin piping
     can block on Windows PowerShell 5.1. Drive its own config API instead. #>
  param([string]$Script, [hashtable]$EnvVars)
  $paths = Get-V5HermesPaths
  if (-not (Test-V5Path -LiteralPath $paths.Python -PathType Leaf)) { throw 'Hermes Python runtime missing' }
  $tmp = Join-V5Path ([IO.Path]::GetTempPath()) ('uabs-hermes-' + [guid]::NewGuid().ToString('N') + '.py')
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
  param([object[]]$Servers, [switch]$Refresh, [switch]$CheckOnly, [string]$ProjectPath, [string]$Scope = 'global')
  $paths = Get-V5HermesPaths
  $existing = ''
  if (Test-V5Path -LiteralPath $paths.Config -PathType Leaf) { $existing = [IO.File]::ReadAllText($paths.Config) }
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
      UABS_HERMES_MCP_ARGS_JSON = ((Resolve-V5ServerArgs -Server $s -Provider 'Hermes' -ProjectPath $ProjectPath -Scope $Scope) | ConvertTo-Json -Compress)
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
  if (-not (Test-V5Path -LiteralPath $paths.Config -PathType Leaf)) { return $false }
  return (Test-V5TextMatchesAny -Text ([IO.File]::ReadAllText($paths.Config)) -Literals $Literals)
}

function Remove-V5McpHermes {
  <# Removes exactly the ids it is given, and only those that are declared.
     Deciding WHICH ids is the caller's job -- an earlier version folded the
     retired-literal test in here and ended up deleting every id it was handed
     on every run, rewriting a healthy config for no reason. #>
  param([string[]]$Ids, [switch]$CheckOnly)
  $paths = Get-V5HermesPaths
  if (-not (Test-V5Path -LiteralPath $paths.Config -PathType Leaf)) { return @() }
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
