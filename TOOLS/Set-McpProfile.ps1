<#
.SYNOPSIS
  Turn a named set of MCP servers on or off, per project, across all providers.

.DESCRIPTION
  Skills are lazy: a skill costs nothing until its description matches the task.
  MCP servers are not. Every connected server puts all of its tool schemas into
  the model's context on every turn of every session, related or not. Measured in
  this pack: 143 skill bodies are ~153,000 tokens against a ~5,500-token
  description index. There is no equivalent discount for MCP.

  So the capability servers in BUNDLED-TOOLS/PROFILES.json are not registered
  globally. This script wires a profile only when two things are true:

    the machine can run it     -- 'requires' in PROFILES.json is satisfied
    the project needs it       -- 'detect' markers are present under -Path

  A profile whose requirements are not met is skipped with the reason printed,
  never written as a config entry that fails on first call. A provider that
  cannot spawn a server just shows no tools and says nothing about why, which is
  the single most expensive failure mode this pack has.

.EXAMPLE
  Set-McpProfile.ps1 -List
  Set-McpProfile.ps1 -Detect -Path C:\code\my-app
  Set-McpProfile.ps1 -Auto   -Path C:\code\my-app
  Set-McpProfile.ps1 -Enable code-deep
  Set-McpProfile.ps1 -Disable web,cloud
#>
[CmdletBinding(DefaultParameterSetName = 'List')]
param(
  [Parameter(ParameterSetName = 'List')][switch]$List,
  [Parameter(ParameterSetName = 'Detect')][switch]$Detect,
  [Parameter(ParameterSetName = 'Auto')][switch]$Auto,
  [Parameter(ParameterSetName = 'Enable', Mandatory = $true)][string[]]$Enable,
  [Parameter(ParameterSetName = 'Disable', Mandatory = $true)][string[]]$Disable,
  [string]$Path,
  [string[]]$Providers = @('Claude', 'Grok', 'Codex', 'Kimi', 'Hermes'),
  [string]$PackRoot,
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

function Get-V5Profile([string]$Id) {
  $hit = @($allProfiles | Where-Object { $_['id'] -eq $Id })
  if (-not $hit.Count) {
    throw ("Unknown profile '{0}'. Known: {1}" -f $Id, (($allProfiles | ForEach-Object { $_['id'] }) -join ', '))
  }
  return $hit[0]
}

function Get-V5ProfileScope($ProfileDef, $Server) {
  # A server may narrow its profile's scope but never widen it.
  if ($Server.Contains('scope') -and $Server['scope']) { return $Server['scope'] }
  if ($ProfileDef.Contains('scope') -and $ProfileDef['scope']) { return $ProfileDef['scope'] }
  return 'global'
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

$statePath = Join-Path $env:LOCALAPPDATA 'Skyrim-AI-V5\mcp-profiles.json'
function Get-V5ProfileState {
  if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { return @{} }
  try { return ConvertTo-V5Hashtable ([IO.File]::ReadAllText($statePath) | ConvertFrom-Json) } catch { return @{} }
}
function Save-V5ProfileState($State) {
  if ($CheckOnly) { return }
  $dir = Split-Path -Parent $statePath
  if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  Set-Utf8NoBom -Path $statePath -Text (($State | ConvertTo-Json -Depth 10))
}

function Invoke-V5AutoInstall {
  <# A printed command is a handoff, not an install. Where a requirement is a
     package this pack can fetch unattended, fetch it -- then re-check, because
     an install that reported success and produced nothing is still a failure. #>
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
    & $exe @stepArgs 2>&1 | ForEach-Object { Write-Host ("        " + $_) -ForegroundColor DarkGray }
    if ($LASTEXITCODE -ne 0) {
      Write-Skip ("auto-install step failed with exit code {0}: {1}" -f $LASTEXITCODE, $exe)
      return $false
    }
  }
  return $true
}

function Write-Head([string]$m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Write-Ok([string]$m)   { Write-Host "  OK  $m" -ForegroundColor Green }
function Write-Skip([string]$m) { Write-Host "  --  $m" -ForegroundColor Yellow }

# ---- list ------------------------------------------------------------------

if ($PSCmdlet.ParameterSetName -eq 'List') {
  $state = Get-V5ProfileState
  Write-Host ''
  Write-Host 'MCP capability profiles' -ForegroundColor Cyan
  Write-Host '  Off by default. A connected server costs context on every turn;'
  Write-Host '  a skill costs nothing until its description matches.'
  Write-Host ''
  foreach ($p in $allProfiles) {
    $on = $state.Contains($p['id'])
    $mark = if ($on) { '[on ]' } else { '[off]' }
    Write-Host ("{0} {1,-14} {2}" -f $mark, $p['id'], $p['title']) -ForegroundColor $(if ($on) { 'Green' } else { 'Gray' })
    foreach ($s in @($p['servers'])) {
      $req = Test-V5ServerRequirement -Server $s -ProjectPath $Path
      $status = if ($req.Ok) { 'ready' } else { $req.Reason }
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
  Write-Host ("State: {0}" -f $statePath) -ForegroundColor DarkGray
  return
}

# ---- detect ----------------------------------------------------------------

if (-not $Path -and ($PSCmdlet.ParameterSetName -in @('Detect', 'Auto'))) { $Path = (Get-Location).Path }
if ($Path) { $Path = (Resolve-Path -LiteralPath $Path).Path }

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

# ---- enable / disable ------------------------------------------------------

function Invoke-V5ProfileWrite {
  param([object[]]$Servers, [string]$Scope, [string]$ProjectPath, [switch]$Remove)

  $ids = @($Servers | ForEach-Object { $_['id'] })
  $targets = Get-V5McpTargets

  # Grok also reads ~/.claude.json. A second copy of the same server under one
  # name is two handshakes for one entry, and Grok wedges at eight running.
  # Read this INSIDE the loop, not before it: Claude is written earlier in the
  # same pass, so a snapshot taken up front would never see what was just added.
  function Get-ClaudeDeclared {
    $p = Join-Path $env:USERPROFILE '.claude.json'
    if (-not (Test-Path -LiteralPath $p)) { return @() }
    try {
      $cj = [IO.File]::ReadAllText($p) | ConvertFrom-Json
      if ($cj.mcpServers) { return @($cj.mcpServers.PSObject.Properties.Name) }
    } catch { }
    return @()
  }

  foreach ($prov in $Providers) {
    if ($prov -eq 'Hermes') {
      $hpaths = Get-V5HermesPaths
      if (-not (Test-Path -LiteralPath $hpaths.Exe -PathType Leaf)) { Write-Skip 'Hermes  not installed'; continue }
      if ($Remove) {
        $done = @(Remove-V5McpHermes -Ids $ids -CheckOnly:$CheckOnly)

      } else {
        $done = @(Add-V5McpHermes -Servers $Servers -Refresh -CheckOnly:$CheckOnly -ProjectPath $ProjectPath)
      }
      if ($done.Count) { Write-Ok ("Hermes  {0}" -f ($done -join ', ')) } else { Write-Skip 'Hermes  no change' }
      continue
    }

    $t = $targets[$prov]
    if (-not $t) { Write-Skip ("{0} unknown provider" -f $prov); continue }

    $write = $Servers
    $claudeHas = if ($prov -eq 'Grok') { @(Get-ClaudeDeclared) } else { @() }
    if (-not $Remove -and $prov -eq 'Grok' -and $claudeHas.Count) {
      # Only on add. Removal must reach the entry wherever it actually is.
      $write = @($Servers | Where-Object {
        if ($claudeHas -contains $_['id']) {
          Write-Skip ("Grok    inherits {0} from ~/.claude.json (not duplicated)" -f $_['id'])
          return $false
        }
        return $true
      })
      if (-not $write.Count) { continue }
    }

    # Claude Code is the only provider here with a project-scoped MCP file.
    # For the rest, a project-scoped server still has to live in the global
    # config -- with the project's absolute path baked into the command, which
    # is what makes it project-scoped in practice.
    $cfgPath = $t.Path
    if ($Scope -eq 'project' -and $prov -eq 'Claude' -and $ProjectPath) {
      $cfgPath = Join-Path $ProjectPath '.mcp.json'
    }
    if (-not (Test-Path -LiteralPath (Split-Path -Parent $cfgPath))) {
      Write-Skip ("{0,-7} not installed" -f $prov); continue
    }

    if ($t.Style -eq 'json') {
      if ($Remove) {
        $done = @(Remove-V5McpJson -Path $cfgPath -Section $t.Section -Ids $ids -CheckOnly:$CheckOnly)
      } else {
        $done = @(Add-V5McpJson -Path $cfgPath -Section $t.Section -Servers $write -Provider $prov -Refresh -CheckOnly:$CheckOnly -ProjectPath $ProjectPath)
      }
    } else {
      if ($Remove) {
        $done = @(Remove-V5McpToml -Path $cfgPath -Section $t.Section -Ids $ids -CheckOnly:$CheckOnly)
      } else {
        $done = @(Add-V5McpToml -Path $cfgPath -Section $t.Section -Servers $write -Provider $prov -Refresh -CheckOnly:$CheckOnly -ProjectPath $ProjectPath -GrokTimeout:($prov -eq 'Grok'))
      }
    }
    if ($done.Count) { Write-Ok ("{0,-7} {1} -> {2}" -f $prov, ($done -join ', '), $cfgPath) }
    else { Write-Skip ("{0,-7} no change" -f $prov) }

    if ($t.Desktop -and $Scope -ne 'project') {
      $desktop = Get-ClaudeDesktopConfigPath
      if ($desktop) {
        if ($Remove) { [void](Remove-V5McpJson -Path $desktop -Section 'mcpServers' -Ids $ids -CheckOnly:$CheckOnly) }
        else { [void](Add-V5McpJson -Path $desktop -Section 'mcpServers' -Servers $Servers -Provider $prov -Refresh -CheckOnly:$CheckOnly -ProjectPath $ProjectPath) }
      }
    }
  }
}

$state = Get-V5ProfileState

if ($PSCmdlet.ParameterSetName -eq 'Disable') {
  foreach ($id in $Disable) {
    $p = Get-V5Profile $id
    Write-Head ("Disabling {0}" -f $id)
    foreach ($scope in @('global', 'project')) {
      $group = @($p['servers'] | Where-Object { (Get-V5ProfileScope $p $_) -eq $scope })
      if (-not $group.Count) { continue }
      $projectPath = if ($state.Contains($id) -and $state[$id].Contains('path')) { $state[$id]['path'] } else { $Path }
      Invoke-V5ProfileWrite -Servers $group -Scope $scope -ProjectPath $projectPath -Remove
    }
    if (-not $CheckOnly) { $state.Remove($id) }
  }
  Save-V5ProfileState $state
  Write-Host ''
  Write-Host 'Restart each AI app for the change to take effect.' -ForegroundColor Yellow
  return
}

$wanted = @()
if ($PSCmdlet.ParameterSetName -eq 'Enable') {
  $wanted = @($Enable | ForEach-Object { (Get-V5Profile $_)['id'] })
} else {
  Write-Head ("Auto-detecting capability profiles for {0}" -f $Path)
  $wanted = @($allProfiles | Where-Object { Test-V5ProfileDetected -ProfileDef $_ -ProjectPath $Path } | ForEach-Object { $_['id'] })
  if (-not $wanted.Count) {
    Write-Host '  no profile markers found; nothing to wire beyond the always-on core'
    return
  }
}

foreach ($id in $wanted) {
  $p = Get-V5Profile $id
  Write-Head ("Enabling {0} -- {1}" -f $id, $p['title'])

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

  foreach ($scope in @('global', 'project')) {
    $group = @($usable | Where-Object { (Get-V5ProfileScope $p $_) -eq $scope })
    if (-not $group.Count) { continue }
    Invoke-V5ProfileWrite -Servers $group -Scope $scope -ProjectPath $Path
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

  if (-not $CheckOnly) {
    $state[$id] = @{
      enabled_utc = [DateTime]::UtcNow.ToString('o')
      servers     = @($usable | ForEach-Object { $_['id'] })
      path        = $Path
    }
  }
}

Save-V5ProfileState $state
Write-Host ''
Write-Host 'Restart each AI app for the change to take effect.' -ForegroundColor Yellow
Write-Host ("Turn one back off with: Set-McpProfile.ps1 -Disable <id>") -ForegroundColor DarkGray
