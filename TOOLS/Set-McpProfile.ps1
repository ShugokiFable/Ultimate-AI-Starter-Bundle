<#
.SYNOPSIS
  Turn a named set of MCP servers on or off, for one project, across providers.

.DESCRIPTION
  Skills are lazy: a skill costs nothing until its description matches the task.
  MCP servers are not. Every connected server puts all of its tool schemas into
  the model's context on every turn of every session, related or not. Measured in
  this pack: 144 skill bodies are ~154,000 tokens against a ~5,500-token
  description index. There is no equivalent discount for MCP.

  Two words that are not the same thing, and 7.9.5 shipped them conflated:

    INSTALLED  the executable exists on disk. Costs disk. Costs no context.
    ENABLED    an entry is registered in a provider config, so the server is
               spawned and its schemas ride in context on every turn of every
               session that config covers.

  7.9.5 wrote every capability profile with scope "global", so enabling one for
  a single project registered it machine-wide until someone ran -Disable by
  hand. Since 7.9.6 a profile is wired for ONE project, using each provider's
  own project mechanism:

    Claude   projects["<abs path>"].mcpServers in ~/.claude.json
    Grok     <project>\.grok\config.toml
    Codex    no project-scoped MCP config exists
    Kimi     no project-scoped MCP config exists
    Hermes   no project-scoped MCP config exists

  The last three are skipped with the reason printed rather than registered
  machine-wide behind a comment that says "project-scoped". -Global is the
  explicit opt-in, and it says what it costs.

  A profile whose requirements are not met is skipped with the reason printed,
  never written as a config entry that fails on first call. A provider that
  cannot spawn a server just shows no tools and says nothing about why, which is
  the single most expensive failure mode this pack has.

.EXAMPLE
  Set-McpProfile.ps1 -List
  Set-McpProfile.ps1 -Detect  -Path C:\code\my-app
  Set-McpProfile.ps1 -Auto    -Path C:\code\my-app
  Set-McpProfile.ps1 -Enable  code-intel -Path C:\code\my-app
  Set-McpProfile.ps1 -Enable  code-intel -Global
  Set-McpProfile.ps1 -Disable code-intel
#>
[CmdletBinding(DefaultParameterSetName = 'List')]
param(
  [Parameter(ParameterSetName = 'List')][switch]$List,
  [Parameter(ParameterSetName = 'Detect')][switch]$Detect,
  [Parameter(ParameterSetName = 'Auto')][switch]$Auto,
  [Parameter(ParameterSetName = 'Enable', Mandatory = $true)][string[]]$Enable,
  [Parameter(ParameterSetName = 'Disable', Mandatory = $true)][string[]]$Disable,
  [string]$Path,
  [switch]$Global,
  [string[]]$Providers = @('Claude', 'Grok', 'Codex', 'Kimi', 'Hermes'),
  [string]$PackRoot,
  [int]$GrokMcpBudget = 6,
  [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'

if (-not $PackRoot) { $PackRoot = Split-Path -Parent $PSScriptRoot }
. (Join-Path $PSScriptRoot 'V7-Mcp-Write.ps1')

# Accept both -Providers Claude,Codex (one comma string, which is what
# powershell.exe -File produces) and -Providers @('Claude','Codex').
if ($Providers.Count -eq 1 -and $Providers[0] -match ',') { $Providers = $Providers[0] -split ',' }
$Providers = @($Providers | ForEach-Object { $_.Trim() } | Where-Object { $_ })

$profilesPath = Join-Path $PackRoot 'BUNDLED-TOOLS\PROFILES.json'
if (-not (Test-Path -LiteralPath $profilesPath -PathType Leaf)) {
  throw "PROFILES.json not found at $profilesPath. Pass -PackRoot <pack root>."
}

function Write-Head([string]$m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Write-Ok([string]$m)   { Write-Host "  OK  $m" -ForegroundColor Green }
function Write-Skip([string]$m) { Write-Host "  --  $m" -ForegroundColor Yellow }

function ConvertTo-V5Hashtable {
  <# Windows PowerShell 5.1 has no ConvertFrom-Json -AsHashtable, and the writer
     needs hashtables so it can ask .Contains() about optional keys. #>
  param($InputObject)
  if ($null -eq $InputObject) { return $null }
  if ($InputObject -is [System.Collections.IDictionary]) {
    $out = @{}
    foreach ($k in $InputObject.Keys) { $out[$k] = ConvertTo-V5Hashtable $InputObject[$k] }
    return $out
  }
  if ($InputObject -is [string] -or $InputObject.GetType().IsValueType) { return $InputObject }
  if ($InputObject -is [System.Collections.IEnumerable]) {
    return @(foreach ($item in $InputObject) { ConvertTo-V5Hashtable $item })
  }
  if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
    $out = @{}
    foreach ($p in $InputObject.PSObject.Properties) { $out[$p.Name] = ConvertTo-V5Hashtable $p.Value }
    return $out
  }
  return $InputObject
}

$catalog = ConvertTo-V5Hashtable ([IO.File]::ReadAllText($profilesPath) | ConvertFrom-Json)
$allProfiles = @($catalog['profiles'])

# Profiles that were renamed. The old id has to keep resolving, or every stored
# state, script and habit that names it breaks on upgrade.
$script:V5ProfileAliases = @{ 'code-deep' = 'code-intel' }

function Resolve-V5ProfileId([string]$Id) {
  if ($script:V5ProfileAliases.ContainsKey($Id)) { return $script:V5ProfileAliases[$Id] }
  return $Id
}

function Get-V5Profile([string]$Id) {
  $wanted = Resolve-V5ProfileId $Id
  $hit = @($allProfiles | Where-Object { $_['id'] -eq $wanted })
  if (-not $hit.Count) {
    throw ("Unknown profile '{0}'. Known: {1}" -f $Id, (($allProfiles | ForEach-Object { $_['id'] }) -join ', '))
  }
  return $hit[0]
}

function Get-V5ProfileScope($ProfileDef, $Server) {
  # A server may narrow its profile's scope but never widen it. The default is
  # 'project': a capability server that is useful everywhere belongs in the
  # always-on core, not here.
  if ($Server.Contains('scope') -and $Server['scope']) { return $Server['scope'] }
  if ($ProfileDef.Contains('scope') -and $ProfileDef['scope']) { return $ProfileDef['scope'] }
  return 'project'
}

function Test-V5ProfileDetected($ProfileDef, [string]$ProjectPath) {
  <# Top level only, deliberately: a recursive scan of a large tree would be
     slow and would match a marker in some vendored dependency. #>
  if ([string]::IsNullOrEmpty($ProjectPath)) { return $false }
  if (-not (Test-Path -LiteralPath $ProjectPath -PathType Container)) { return $false }
  $d = $null
  if ($ProfileDef.Contains('detect')) { $d = $ProfileDef['detect'] }
  if (-not $d) { return $false }
  if ($d.Contains('files')) {
    foreach ($f in @($d['files'])) {
      if (Test-Path -LiteralPath (Join-Path $ProjectPath $f)) { return $true }
    }
  }
  if ($d.Contains('globs')) {
    foreach ($g in @($d['globs'])) {
      if (Get-ChildItem -LiteralPath $ProjectPath -Filter $g -File -ErrorAction SilentlyContinue | Select-Object -First 1) { return $true }
    }
  }
  return $false
}

# ---- state -----------------------------------------------------------------
# v1 was a flat map of profile id -> { enabled_utc, servers, path }: one path per
# profile, because a profile could only be on once. A profile is per project now,
# so it can be on for several at the same time, and -Disable has to be able to
# reach every one of them. An orphaned entry is a server that keeps starting
# with nothing turning it off.

$statePath = Join-Path $env:LOCALAPPDATA 'Skyrim-AI-V5\mcp-profiles.json'

function New-V5ProfileState { @{ schema = 2; profiles = @{} } }

function Get-V5RawProfileState {
  if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { return @{} }
  try { return ConvertTo-V5Hashtable ([IO.File]::ReadAllText($statePath) | ConvertFrom-Json) } catch { return @{} }
}

function Convert-V5ProfileState {
  <# Returns @{ State = <v2>; Stale = @(<entries written machine-wide by v1>) }.

     Every v1 entry was written machine-wide, whatever it claimed, so each one is
     also a cleanup job: drop the global registration, then put it back for the
     project it was recorded against. Migrating the state file alone would leave
     Serena in every session with the state file saying it was project-scoped. #>
  param($Raw)
  if (-not $Raw -or -not $Raw.Count) { return @{ State = (New-V5ProfileState); Stale = @() } }
  if ($Raw.Contains('schema') -and [int]$Raw['schema'] -ge 2) {
    $s = New-V5ProfileState
    if ($Raw.Contains('profiles') -and $Raw['profiles']) { $s['profiles'] = $Raw['profiles'] }
    return @{ State = $s; Stale = @() }
  }

  $state = New-V5ProfileState
  $stale = @()
  foreach ($oldId in @($Raw.Keys)) {
    $entry = $Raw[$oldId]
    if ($entry -isnot [System.Collections.IDictionary]) { continue }
    $newId = Resolve-V5ProfileId $oldId
    $servers = @()
    if ($entry.Contains('servers')) { $servers = @($entry['servers']) }
    $projectPath = ''
    if ($entry.Contains('path') -and $entry['path']) { $projectPath = [string]$entry['path'] }
    $when = if ($entry.Contains('enabled_utc')) { $entry['enabled_utc'] } else { [DateTime]::UtcNow.ToString('o') }

    if (-not $state['profiles'].Contains($newId)) { $state['profiles'][$newId] = @{ projects = @{} } }
    if ($projectPath) {
      $state['profiles'][$newId]['projects'][$projectPath] = @{
        enabled_utc = $when; servers = $servers; providers = @()
      }
    }
    $stale += @{ old_id = $oldId; id = $newId; servers = $servers; path = $projectPath }
  }
  return @{ State = $state; Stale = $stale }
}

function Save-V5ProfileState($State) {
  if ($CheckOnly) { return }
  $dir = Split-Path -Parent $statePath
  if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  Set-Utf8NoBom -Path $statePath -Text (($State | ConvertTo-Json -Depth 10))
}

function Get-V5ProfileProjects($State, [string]$Id) {
  if (-not $State['profiles'].Contains($Id)) { return @() }
  $p = $State['profiles'][$Id]
  if (-not $p.Contains('projects') -or -not $p['projects']) { return @() }
  return @($p['projects'].Keys)
}

function Test-V5ProfileGlobal($State, [string]$Id) {
  if (-not $State['profiles'].Contains($Id)) { return $false }
  return ($State['profiles'][$Id].Contains('global') -and $State['profiles'][$Id]['global'])
}

# ---- writing ---------------------------------------------------------------

function Get-ClaudeDeclared {
  # Grok can also read ~/.claude.json -- but only while its Claude-compat MCP
  # cell is on, and this pack writes mcps = false. Read INSIDE the provider
  # loop, not before it: Claude is written earlier in the same pass, so a
  # snapshot taken up front would never see what was just added.
  $p = Join-Path $env:USERPROFILE '.claude.json'
  if (-not (Test-Path -LiteralPath $p)) { return @() }
  try {
    $cj = [IO.File]::ReadAllText($p) | ConvertFrom-Json
    if ($cj.mcpServers) { return @($cj.mcpServers.PSObject.Properties.Name) }
  } catch { }
  return @()
}

function Invoke-V5ProfileWrite {
  <# Writes (or removes) one group of servers and returns the providers that
     actually changed.

     Adding goes to the project target only, or to the machine target when
     -Machine. Removing sweeps BOTH, always: an entry left behind by an older
     version of this pack is in the global config, and a removal that only looks
     where the current version writes cannot reach it. #>
  param([object[]]$Servers, [string]$ProjectPath, [switch]$Remove, [switch]$Machine)

  $ids = @($Servers | ForEach-Object { $_['id'] })
  $machineTargets = Get-V5McpTargets
  $touched = @()

  foreach ($prov in $Providers) {

    # -- Hermes keeps its servers behind its own Python config API.
    if ($prov -eq 'Hermes') {
      $hpaths = Get-V5HermesPaths
      if (-not (Test-Path -LiteralPath $hpaths.Exe -PathType Leaf)) { Write-Skip 'Hermes  not installed'; continue }
      if ($Remove) {
        $done = @(Remove-V5McpHermes -Ids $ids -CheckOnly:$CheckOnly)
        if ($done.Count) { Write-Ok ("Hermes  removed {0}" -f ($done -join ', ')); $touched += 'Hermes' }
        continue
      }
      if (-not $Machine) {
        Write-Skip ("Hermes  not written: {0}" -f (Get-V5ProviderNoProjectScope -Provider 'Hermes'))
        continue
      }
      $done = @(Add-V5McpHermes -Servers $Servers -Refresh -CheckOnly:$CheckOnly -ProjectPath $ProjectPath -Scope 'global')
      if ($done.Count) { Write-Ok ("Hermes  {0}  (machine-wide)" -f ($done -join ', ')); $touched += 'Hermes' }
      elseif (@($Servers | Where-Object { -not (Test-V5HermesServerDeclared -Id $_['id']) }).Count -eq 0) {
        Write-Skip 'Hermes  already registered'; $touched += 'Hermes'
      } else { Write-Skip 'Hermes  no change' }
      continue
    }

    # Not $machine: variable names are case-insensitive and $Machine is this
    # function's typed switch parameter, so assigning a hashtable to it coerces
    # the hashtable into a SwitchParameter and every .Path after it fails.
    $machineTarget = $machineTargets[$prov]
    if (-not $machineTarget) { Write-Skip ("{0} unknown provider" -f $prov); continue }
    $project = Get-V5ProviderProjectTarget -Provider $prov -ProjectPath $ProjectPath

    # -- removal: sweep every place this pack has ever written the entry.
    if ($Remove) {
      $done = @()
      $sweep = @()
      if ($project) { $sweep += $project }
      $sweep += @{ Style = $machineTarget.Style; Path = $machineTarget.Path; Section = $machineTarget.Section; ProjectKey = '' }
      foreach ($tgt in $sweep) {
        if (-not (Test-Path -LiteralPath $tgt.Path -PathType Leaf)) { continue }
        if ($tgt.Style -eq 'json') {
          $keys = if ($tgt.ProjectKey) { @(Get-V5ClaudeProjectKeys -ProjectPath $tgt.ProjectKey -ConfigPath $tgt.Path) } else { @('') }
          foreach ($k in $keys) {
            $done += @(Remove-V5McpJson -Path $tgt.Path -Section $tgt.Section -Ids $ids -CheckOnly:$CheckOnly -ProjectKey $k)
          }
        } else {
          $done += @(Remove-V5McpToml -Path $tgt.Path -Section $tgt.Section -Ids $ids -CheckOnly:$CheckOnly)
        }
      }
      if ($machineTarget.Desktop) {
        $desktop = Get-ClaudeDesktopConfigPath
        if ($desktop) { $done += @(Remove-V5McpJson -Path $desktop -Section 'mcpServers' -Ids $ids -CheckOnly:$CheckOnly) }
      }
      $done = @($done | Select-Object -Unique)
      if ($done.Count) { Write-Ok ("{0,-7} removed {1}" -f $prov, ($done -join ', ')); $touched += $prov }
      else { Write-Skip ("{0,-7} nothing to remove" -f $prov) }
      continue
    }

    # -- addition.
    if (-not $Machine -and -not $project) {
      Write-Skip ("{0,-7} not written: {1}" -f $prov, (Get-V5ProviderNoProjectScope -Provider $prov))
      Write-Host  ("          -Global registers it machine-wide instead, at the cost of every session's context.") -ForegroundColor DarkGray
      continue
    }

    $target = if ($Machine) {
      @{ Style = $machineTarget.Style; Path = $machineTarget.Path; Section = $machineTarget.Section; ProjectKey = '' }
    } else { $project }
    $scope = if ($Machine) { 'global' } else { 'project' }

    $write = $Servers
    if ($prov -eq 'Grok') {
      # Grok's Claude-compat cell, when this pack has not switched it off.
      if (Test-V5GrokInheritsClaudeMcp) {
        $claudeHas = @(Get-ClaudeDeclared)
        if ($claudeHas.Count) {
          $write = @($write | Where-Object {
            if ($claudeHas -contains $_['id']) {
              Write-Skip ("Grok    inherits {0} from ~/.claude.json (not duplicated)" -f $_['id'])
              return $false
            }
            return $true
          })
        }
      }
      # grok-cli wedges at eight servers RUNNING, and it runs the union of the
      # user file and the project file -- so the ceiling is counted over both.
      if ($write.Count) {
        $write = @(Select-V5WithinGrokBudget -Servers $write -Budget $GrokMcpBudget -ProjectPath $ProjectPath)
      }
      if (-not $write.Count) { continue }
    }

    $parent = Split-Path -Parent $target.Path
    if ($target.Style -eq 'json' -and -not (Test-Path -LiteralPath $parent)) {
      Write-Skip ("{0,-7} not installed" -f $prov); continue
    }

    $done = @()
    if ($target.Style -eq 'json') {
      $keys = if ($target.ProjectKey) { @(Get-V5ClaudeProjectKeys -ProjectPath $target.ProjectKey -ConfigPath $target.Path) } else { @('') }
      foreach ($k in $keys) {
        $done += @(Add-V5McpJson -Path $target.Path -Section $target.Section -Servers $write -Provider $prov `
                     -Refresh -CheckOnly:$CheckOnly -ProjectPath $ProjectPath -ProjectKey $k -Scope $scope)
      }
      $done = @($done | Select-Object -Unique)
    } else {
      $done = @(Add-V5McpToml -Path $target.Path -Section $target.Section -Servers $write -Provider $prov `
                  -Refresh -CheckOnly:$CheckOnly -ProjectPath $ProjectPath -GrokTimeout:($prov -eq 'Grok') -Scope $scope)
    }
    if ($done.Count) {
      $where = if ($Machine) { 'machine-wide' } else { 'this project only' }
      Write-Ok ("{0,-7} {1} -> {2}  ({3})" -f $prov, ($done -join ', '), $target.Path, $where)
      $touched += $prov
      # Grok's only project mechanism puts a file inside the project. Better to
      # say so than to have it turn up in `git status` unexplained.
      if (-not $Machine -and $ProjectPath -and $target.Path.StartsWith($ProjectPath, [StringComparison]::OrdinalIgnoreCase)) {
        Write-Host  '          that file is inside your project; add .grok/ to .gitignore to keep it out of commits' -ForegroundColor DarkGray
      }
    } else {
      # An identical rewrite is not a change, but it IS a registration, and
      # that is what the state file has to record -- otherwise a second -Auto
      # run marks the profile off while the server is still wired, and -Disable
      # is then left with nothing to sweep.
      $missing = @($write | Where-Object {
        -not (Test-V5ServerDeclared -Path $target.Path -Style $target.Style -Section $target.Section -Id $_['id'] -ProjectKey $target.ProjectKey)
      })
      if ($write.Count -and -not $missing.Count) { Write-Skip ("{0,-7} already registered" -f $prov); $touched += $prov }
      else { Write-Skip ("{0,-7} no change" -f $prov) }
    }

    # Claude Desktop has no project, so a capability server there is machine-wide
    # by construction. Only -Global reaches it.
    if ($Machine -and $machineTarget.Desktop) {
      $desktop = Get-ClaudeDesktopConfigPath
      if ($desktop) {
        [void](Add-V5McpJson -Path $desktop -Section 'mcpServers' -Servers $write -Provider $prov `
                 -Refresh -CheckOnly:$CheckOnly -ProjectPath $ProjectPath -Scope 'global')
      }
    }
  }
  # No comma operator: every caller wraps this in @(), and ,@(...) would hand
  # them a one-element array containing the array.
  return @($touched | Select-Object -Unique)
}

function Invoke-V5AutoInstall {
  <# A printed command is a handoff, not an install. Where a requirement is a
     package this pack can fetch unattended, fetch it -- then re-check, because
     an install that reported success and produced nothing is still a failure.

     Installing is not enabling. This makes the tool exist on disk; whether an
     entry is written for a project is still decided per project. #>
  param($Server, [string]$ProjectPath)
  if (-not $Server.Contains('auto_install') -or -not $Server['auto_install']) { return $false }
  $spec = $Server['auto_install']
  if ($spec.Contains('requires_command') -and $spec['requires_command']) {
    if (-not (Test-V5CommandAvailable -Command $spec['requires_command'] -ProjectPath $ProjectPath)) {
      Write-Skip ("cannot auto-install {0}: {1} is not available" -f $Server['id'], $spec['requires_command'])
      return $false
    }
  }
  foreach ($step in @($spec['steps'])) {
    $exe = Expand-V5Template -Text $step['command'] -ProjectPath $ProjectPath
    $stepArgs = @(@($step['args']) | ForEach-Object { Expand-V5Template -Text ([string]$_) -ProjectPath $ProjectPath })
    Write-Host ("      installing: {0} {1}" -f $exe, ($stepArgs -join ' ')) -ForegroundColor DarkGray
    if ($CheckOnly) { continue }
    # Redirecting a native command's stderr into the pipeline turns each line
    # into an ErrorRecord, and this script runs with $ErrorActionPreference =
    # 'Stop'. `uv tool install serena-agent` prints "already installed" on
    # stderr and exits 0, so a second install run killed the whole script with
    # a NativeCommandError -- the success path, treated as fatal. Judge the exit
    # code, not the stream.
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
      & $exe @stepArgs 2>&1 | ForEach-Object { Write-Host ("        " + $_) -ForegroundColor DarkGray }
    } finally { $ErrorActionPreference = $prevEap }
    if ($LASTEXITCODE -ne 0) {
      Write-Skip ("auto-install step failed with exit code {0}: {1}" -f $LASTEXITCODE, $exe)
      return $false
    }
  }
  return $true
}

# ---- migration -------------------------------------------------------------

$raw = Get-V5RawProfileState
$converted = Convert-V5ProfileState -Raw $raw
$state = $converted.State
$stale = @($converted.Stale)

function Invoke-V5StaleGlobalMigration {
  <# 7.9.5 registered every enabled profile machine-wide. Upgrading has to move
     those entries, not just rename them in a state file: drop the machine-wide
     registration, then put it back for the project the state recorded.

     Only ids this pack recorded as enabled are touched. A server someone
     registered themselves is not in the state file and is left where it is. #>
  param([object[]]$Entries)
  if (-not @($Entries).Count) { return }
  Write-Head 'Migrating profiles written machine-wide by an earlier version'
  foreach ($e in $Entries) {
    $label = if ($e['old_id'] -ne $e['id']) { "{0} -> {1}" -f $e['old_id'], $e['id'] } else { $e['id'] }
    Write-Host ("  {0}: was machine-wide" -f $label)
    $p = $null
    try { $p = Get-V5Profile $e['id'] } catch { Write-Skip ("  {0} is no longer in the catalog; leaving its entries alone" -f $e['id']); continue }
    $known = @($p['servers'] | ForEach-Object { $_['id'] })
    $servers = @($p['servers'] | Where-Object { $e['servers'] -contains $_['id'] -or -not @($e['servers']).Count })
    if (-not $servers.Count) { continue }
    $unknown = @($e['servers'] | Where-Object { $known -notcontains $_ })
    if ($unknown.Count) { Write-Skip ("  not in the catalog any more, left alone: {0}" -f ($unknown -join ', ')) }

    [void](Invoke-V5ProfileWrite -Servers $servers -ProjectPath $e['path'] -Remove)

    if ($e['path'] -and (Test-Path -LiteralPath $e['path'] -PathType Container)) {
      $usable = @($servers | Where-Object { (Test-V5ServerRequirement -Server $_ -ProjectPath $e['path']).Ok })
      if ($usable.Count) {
        $provs = @(Invoke-V5ProfileWrite -Servers $usable -ProjectPath $e['path'])
        if ($state['profiles'].Contains($e['id']) -and $state['profiles'][$e['id']]['projects'].Contains($e['path'])) {
          $state['profiles'][$e['id']]['projects'][$e['path']]['providers'] = $provs
        }
      } else {
        Write-Skip ("  {0}: nothing registrable for {1} any more" -f $e['id'], $e['path'])
      }
    } elseif ($e['path']) {
      Write-Skip ("  {0}: recorded project is gone ({1}); left off" -f $e['id'], $e['path'])
      if ($state['profiles'].Contains($e['id'])) { [void]$state['profiles'][$e['id']]['projects'].Remove($e['path']) }
    }
  }
  Write-Host ''
}

# ---- list ------------------------------------------------------------------

if ($PSCmdlet.ParameterSetName -eq 'List') {
  Write-Host ''
  Write-Host 'MCP capability profiles' -ForegroundColor Cyan
  Write-Host '  INSTALLED means the tool is on disk. It costs no model context.'
  Write-Host '  ENABLED means an MCP entry is registered, so its tool schemas ride'
  Write-Host '  in context on every turn of every session that config covers.'
  Write-Host '  Profiles are enabled per project, never machine-wide by default.'
  Write-Host ''
  foreach ($p in $allProfiles) {
    $projects = @(Get-V5ProfileProjects $state $p['id'])
    $isGlobal = Test-V5ProfileGlobal $state $p['id']
    $on = ($projects.Count -gt 0) -or $isGlobal
    $mark = if ($on) { '[on ]' } else { '[off]' }
    Write-Host ("{0} {1,-14} {2}" -f $mark, $p['id'], $p['title']) -ForegroundColor $(if ($on) { 'Green' } else { 'Gray' })
    foreach ($proj in $projects) {
      $provs = @($state['profiles'][$p['id']]['projects'][$proj]['providers'])
      $suffix = if ($provs.Count) { '  -> ' + ($provs -join ', ') } else { '' }
      Write-Host ("       enabled for  {0}{1}" -f $proj, $suffix) -ForegroundColor Green
    }
    if ($isGlobal) { Write-Host '       enabled MACHINE-WIDE (-Global): every session pays for it' -ForegroundColor Yellow }
    foreach ($s in @($p['servers'])) {
      $req = Test-V5ServerRequirement -Server $s -ProjectPath $Path
      $status = if ($req.Ok) { 'installed and ready' } else { $req.Reason }
      Write-Host ("       {0,-16} {1}" -f $s['id'], $status) -ForegroundColor $(if ($req.Ok) { 'DarkGray' } else { 'Yellow' })
      if (-not $req.Ok -and $s.Contains('install_hint') -and $s['install_hint']) {
        Write-Host ("       {0,-16} install: {1}" -f '', $s['install_hint']) -ForegroundColor DarkGray
      }
    }
  }
  Write-Host ''
  foreach ($skipped in @($catalog['evaluated_not_shipped'])) {
    Write-Host ("  not shipped: {0} -- {1}" -f $skipped['id'], $skipped['reason']) -ForegroundColor DarkGray
  }
  Write-Host ''
  if ($stale.Count) {
    Write-Host '  An earlier version registered these machine-wide. Run -Auto or -Enable to move them:' -ForegroundColor Yellow
    foreach ($e in $stale) { Write-Host ("    {0}" -f $e['old_id']) -ForegroundColor Yellow }
    Write-Host ''
  }
  Write-Host ("State: {0}" -f $statePath) -ForegroundColor DarkGray
  Write-Host  'Enable:  Set-McpProfile.ps1 -Auto -Path <project>' -ForegroundColor DarkGray
  return
}

# ---- detect ----------------------------------------------------------------

# The current directory answers "which project am I setting up". It does not
# answer "turn this off": -Disable with no -Path means every project the profile
# was enabled for, and defaulting to the cwd there swept a directory nobody
# asked about while leaving the real registrations in place.
if (-not $Path -and -not $Global -and $PSCmdlet.ParameterSetName -ne 'Disable') {
  $Path = (Get-Location).Path
}
if ($Path) {
  if (-not (Test-Path -LiteralPath $Path)) { throw "-Path does not exist: $Path" }
  $Path = (Resolve-Path -LiteralPath $Path).Path.TrimEnd('\', '/')
}

if ($PSCmdlet.ParameterSetName -eq 'Detect') {
  Write-Head "Detecting capability profiles for $Path"
  $any = $false
  foreach ($p in $allProfiles) {
    if (-not (Test-V5ProfileDetected -ProfileDef $p -ProjectPath $Path)) { continue }
    $any = $true
    Write-Host ("  {0,-14} {1}" -f $p['id'], $p['title'])
    foreach ($s in @($p['servers'])) {
      $req = Test-V5ServerRequirement -Server $s -ProjectPath $Path
      if ($req.Ok) { Write-Ok $s['id'] } else { Write-Skip ("{0}: {1}" -f $s['id'], $req.Reason) }
    }
  }
  if (-not $any) { Write-Host '  no profile markers found; the always-on core is all this project needs' }
  return
}

# ---- disable ---------------------------------------------------------------

Invoke-V5StaleGlobalMigration -Entries $stale

if ($PSCmdlet.ParameterSetName -eq 'Disable') {
  foreach ($rawId in $Disable) {
    $p = Get-V5Profile $rawId
    $id = $p['id']
    Write-Head ("Disabling {0}" -f $id)

    # With -Path, only that project. Without, every project it was enabled for,
    # plus a machine-wide registration if one was ever made -- an entry nothing
    # turns off is a server that keeps starting.
    $targets = if ($Path) { @($Path) } else { @(Get-V5ProfileProjects $state $id) }
    if (-not $targets.Count) { $targets = @('') }
    foreach ($proj in $targets) {
      if ($proj) { Write-Host ("  project: {0}" -f $proj) -ForegroundColor DarkGray }
      [void](Invoke-V5ProfileWrite -Servers @($p['servers']) -ProjectPath $proj -Remove)
      if (-not $CheckOnly -and $state['profiles'].Contains($id) -and $proj) {
        [void]$state['profiles'][$id]['projects'].Remove($proj)
      }
    }
    if (-not $CheckOnly -and $state['profiles'].Contains($id)) {
      if (-not $Path) { [void]$state['profiles'][$id].Remove('global') }
      if (-not @($state['profiles'][$id]['projects'].Keys).Count -and -not $state['profiles'][$id].Contains('global')) {
        [void]$state['profiles'].Remove($id)
      }
    }
  }
  Save-V5ProfileState $state
  Write-Host ''
  Write-Host 'Restart each AI app for the change to take effect.' -ForegroundColor Yellow
  return
}

# ---- enable / auto ---------------------------------------------------------

$wanted = @()
if ($PSCmdlet.ParameterSetName -eq 'Enable') {
  $wanted = @($Enable | ForEach-Object { (Get-V5Profile $_)['id'] } | Select-Object -Unique)
} else {
  Write-Head ("Auto-detecting capability profiles for {0}" -f $Path)
  $wanted = @($allProfiles | Where-Object { Test-V5ProfileDetected -ProfileDef $_ -ProjectPath $Path } | ForEach-Object { $_['id'] })
  if (-not $wanted.Count) {
    Write-Host '  no profile markers found; nothing to wire beyond the always-on core'
    Save-V5ProfileState $state
    return
  }
}

if (-not $Path -and -not $Global) { throw 'Pass -Path <project directory>, or -Global to register machine-wide.' }

foreach ($id in $wanted) {
  $p = Get-V5Profile $id
  Write-Head ("Enabling {0} -- {1}" -f $id, $p['title'])
  if ($Global) {
    Write-Host '      -Global: machine-wide. Every session on this box carries these tool schemas.' -ForegroundColor Yellow
  }

  $usable = @()
  foreach ($s in @($p['servers'])) {
    $req = Test-V5ServerRequirement -Server $s -ProjectPath $Path
    if ($req.Ok) { $usable += $s; continue }
    Write-Skip ("{0}: {1}" -f $s['id'], $req.Reason)
    if (Invoke-V5AutoInstall -Server $s -ProjectPath $Path) {
      $req = Test-V5ServerRequirement -Server $s -ProjectPath $Path
      if ($req.Ok) { Write-Ok ("{0}: installed" -f $s['id']); $usable += $s; continue }
      Write-Skip ("{0}: still unsatisfied after install -- {1}" -f $s['id'], $req.Reason)
    }
    foreach ($hintKey in @('install_hint', 'editor_side')) {
      if ($s.Contains($hintKey) -and $s[$hintKey]) {
        $hint = Expand-V5Template -Text $s[$hintKey] -ProjectPath $Path
        if (-not $hint) { $hint = $s[$hintKey] }
        Write-Host ("      run: {0}" -f $hint) -ForegroundColor DarkGray
      }
    }
  }
  if (-not $usable.Count) {
    Write-Skip ("{0}: nothing registrable on this machine, profile left off" -f $id)
    continue
  }

  # Some servers cannot exist outside one project whatever the user asks for:
  # the Unity binary lives inside that project's Library folder, so a
  # machine-wide entry for it would be a path that is wrong everywhere else.
  $forcedGlobal = @($usable | Where-Object { (Get-V5ProfileScope $p $_) -eq 'global' })
  $group        = @($usable | Where-Object { (Get-V5ProfileScope $p $_) -ne 'global' })
  if ($Global -and $group.Count) {
    $bound = @($group | Where-Object { Test-V5ServerIsProjectBound -Server $_ })
    if ($bound.Count) {
      Write-Skip ("not registrable machine-wide, its command is resolved inside one project: {0}" -f (@($bound | ForEach-Object { $_['id'] }) -join ', '))
      $group = @($group | Where-Object { -not (Test-V5ServerIsProjectBound -Server $_) })
    }
  }
  $written = @()
  if ($forcedGlobal.Count) {
    $written += @(Invoke-V5ProfileWrite -Servers $forcedGlobal -ProjectPath $Path -Machine)
  }
  if ($group.Count) {
    $written += @(Invoke-V5ProfileWrite -Servers $group -ProjectPath $Path -Machine:($Global.IsPresent))
  }

  # An editor-side step is not a failure -- the server registers fine and simply
  # has nothing to talk to until the companion plugin is running. Saying so is
  # the difference between "configured" and "working".
  foreach ($s in $usable) {
    if ($s.Contains('editor_side') -and $s['editor_side']) {
      $hint = Expand-V5Template -Text $s['editor_side'] -ProjectPath $Path
      if (-not $hint) { $hint = $s['editor_side'] }
      Write-Host ("      editor side, not automatable from here: {0}" -f $hint) -ForegroundColor Yellow
    }
  }
  foreach ($s in $usable) {
    if ($s.Contains('side_effect_note') -and $s['side_effect_note']) {
      Write-Host ("      note: {0}" -f $s['side_effect_note']) -ForegroundColor DarkGray
    }
  }

  if ($CheckOnly) { continue }
  $written = @($written | Select-Object -Unique)
  if (-not $written.Count) {
    Write-Skip ("{0}: nothing was written, leaving the profile off" -f $id)
    continue
  }
  if (-not $state['profiles'].Contains($id)) { $state['profiles'][$id] = @{ projects = @{} } }
  $record = @{
    enabled_utc = [DateTime]::UtcNow.ToString('o')
    servers     = @($usable | ForEach-Object { $_['id'] })
    providers   = $written
  }
  if ($Global) { $state['profiles'][$id]['global'] = $record }
  if ($Path)   { $state['profiles'][$id]['projects'][$Path] = $record }
}

Save-V5ProfileState $state
Write-Host ''
Write-Host 'Restart each AI app for the change to take effect.' -ForegroundColor Yellow
Write-Host ("Turn one back off with: Set-McpProfile.ps1 -Disable <id>") -ForegroundColor DarkGray
