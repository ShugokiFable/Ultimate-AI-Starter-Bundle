<#
.SYNOPSIS
  Normalize Hermes into default, roblox, and skyrim MCP profiles.

.DESCRIPTION
  Default: context7, github, headroom
  Roblox:  default + Roblox Studio's official MCP
  Skyrim:  default + houseCARL

  Existing profile settings are preserved. Only UABS-owned MCP ids and their
  enabled/command/args fields are changed. Before the first write, exact config
  bytes are copied to a timestamped rollback directory. A failed verification
  restores those bytes and removes profiles created by the failed run.
  A game profile is created only when its local capability is installed.

.PARAMETER Apply
  Perform the migration. Without this switch, print the plan only.

.PARAMETER WithForgeCompatibility
  Explicitly add Skyrim Forge to the skyrim profile and RobloxForge to the
  roblox profile. The default migration keeps both installed but disconnected.
#>
[CmdletBinding()]
param(
  [switch]$Apply,
  [switch]$WithForgeCompatibility,
  # How much of houseCARL to register in the skyrim profile. Measured, 1.9.0:
  #   Full      45 tools  167,072 bytes  ~41,768 tok/turn
  #   Lean      42 tools  125,476 bytes  ~31,369 tok/turn   -25%  (default)
  #   ReadOnly  27 tools   70,418 bytes  ~17,604 tok/turn   -58%
  # Hermes enforces mcp_servers.<name>.tools.include/exclude at REGISTRATION,
  # so a filtered tool's schema never reaches the model. The sets live in
  # BUNDLED-TOOLS/CATALOG.json, not here.
  [ValidateSet('Full', 'Lean', 'ReadOnly')]
  [string]$SkyrimToolset = 'Lean',
  [string]$HermesHome,
  [string]$HermesExe
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'UABS-Mcp-Write.ps1')

if (-not $HermesHome) {
  $HermesHome = if ($env:HERMES_HOME) { $env:HERMES_HOME } else { Join-Path $env:LOCALAPPDATA 'hermes' }
}
$HermesHome = [IO.Path]::GetFullPath($HermesHome)

if (-not $HermesExe) {
  $HermesExe = @(
    (Join-Path $HermesHome 'bin\hermes.exe'),
    (Join-Path $env:LOCALAPPDATA 'hermes\bin\hermes.exe'),
    (Join-Path $HermesHome 'hermes-agent\venv\Scripts\hermes.exe')
  ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
}
if (-not $HermesExe -or -not (Test-Path -LiteralPath $HermesExe -PathType Leaf)) {
  throw "Hermes executable not found. Pass -HermesExe and -HermesHome explicitly."
}
if (-not (Test-Path -LiteralPath (Join-Path $HermesHome 'config.yaml') -PathType Leaf)) {
  throw "Hermes config not found at $HermesHome\config.yaml"
}

$savedHermesHome = $env:HERMES_HOME
$env:HERMES_HOME = $HermesHome
$script:Plan = New-Object System.Collections.Generic.List[object]
$script:Snapshots = New-Object System.Collections.Generic.List[object]
$script:CreatedProfiles = New-Object System.Collections.Generic.List[string]
$script:Ledger = [ordered]@{
  kept = New-Object System.Collections.Generic.List[string]
  migrated = New-Object System.Collections.Generic.List[string]
  removed = New-Object System.Collections.Generic.List[string]
  newly_created = New-Object System.Collections.Generic.List[string]
  untouched = New-Object System.Collections.Generic.List[string]
}

function Add-UabsLedger([string]$Kind, [string]$Text) {
  if (-not $script:Ledger.Contains($Kind)) { throw "Unknown ledger kind: $Kind" }
  if (-not $script:Ledger[$Kind].Contains($Text)) { [void]$script:Ledger[$Kind].Add($Text) }
}

function ConvertTo-UabsPlain($Value) {
  if ($null -eq $Value) { return $null }
  if ($Value -is [System.Collections.IDictionary]) {
    $out = @{}
    foreach ($key in $Value.Keys) { $out[[string]$key] = ConvertTo-UabsPlain $Value[$key] }
    return $out
  }
  if ($Value -is [System.Management.Automation.PSCustomObject]) {
    $out = @{}
    foreach ($property in $Value.PSObject.Properties) { $out[$property.Name] = ConvertTo-UabsPlain $property.Value }
    return $out
  }
  if ($Value -is [string] -or $Value.GetType().IsValueType) { return $Value }
  if ($Value -is [System.Collections.IEnumerable]) {
    $items = @(foreach ($item in $Value) { ConvertTo-UabsPlain $item })
    return ,$items
  }
  return $Value
}

function Copy-UabsValue($Value) {
  return ConvertTo-UabsPlain ((ConvertTo-Json -InputObject $Value -Depth 20 -Compress) | ConvertFrom-Json)
}

function Test-UabsValueEqual($Left, $Right) {
  return ((ConvertTo-Json -InputObject $Left -Depth 20 -Compress) -ceq
          (ConvertTo-Json -InputObject $Right -Depth 20 -Compress))
}

function Invoke-UabsHermes([string[]]$Arguments, [switch]$AllowMissing) {
  Write-Verbose ("hermes " + ($Arguments -join ' '))
  $output = @(& $HermesExe @Arguments 2>&1)
  $code = $LASTEXITCODE
  if ($code -ne 0 -and -not $AllowMissing) {
    throw "Hermes command failed ($code): hermes $($Arguments -join ' ')`n$($output -join [Environment]::NewLine)"
  }
  return @{ Code = $code; Output = $output }
}

function Get-UabsMcpMap([string]$Profile) {
  $result = Invoke-UabsHermes -Arguments @('-p', $Profile, 'config', 'get', 'mcp_servers', '--json') -AllowMissing
  if ($result.Code -ne 0) { return @{} }
  $json = @($result.Output | ForEach-Object { [string]$_ } | Where-Object { $_.Trim().StartsWith('{') }) | Select-Object -Last 1
  if (-not $json) { throw "Hermes returned no JSON for profile '$Profile'." }
  $map = ConvertTo-UabsPlain ($json | ConvertFrom-Json)
  Write-Verbose ("$Profile MCP ids: " + (@($map.Keys) -join ', '))
  return $map
}

function Add-UabsPlan([string]$Kind, [string]$Profile, [string]$Id, [string]$Key, $Value, [string]$Detail) {
  [void]$script:Plan.Add([pscustomobject]@{
    Kind = $Kind; Profile = $Profile; Id = $Id; Key = $Key; Value = $Value; Detail = $Detail
  })
}

function Test-UabsServerFamily($Entry, [string]$Family) {
  if (-not $Entry) { return $false }
  $text = (ConvertTo-Json -InputObject $Entry -Depth 20 -Compress).ToLowerInvariant()
  switch ($Family) {
    'context7' { return $text.Contains('context7-mcp') }
    'github' { return $text.Contains('github-mcp-server') }
    'headroom' { return $text.Contains('headroom') -and $text.Contains('mcp') }
    'roblox' { return $text.Contains('roblox') -and ($text.Contains('studiomcp') -or $text.Contains('mcp.bat')) }
    'housecarl' { return $text.Contains('housecarl-mcp') }
    'skyrim-forge' { return $text.Contains('skyrim-forge') -or $text.Contains('skyrim_forge') }
    'robloxforge' { return $text.Contains('robloxforge') -and $text.Contains('mcp_server') }
  }
  return $false
}

function Ensure-UabsServer([string]$Profile, [hashtable]$Map, [string]$Id, [hashtable]$Desired, [string]$Family) {
  if (-not $Map.ContainsKey($Id)) {
    Add-UabsPlan -Kind 'SetEntry' -Profile $Profile -Id $Id -Key "mcp_servers.$Id" -Value $Desired -Detail 'missing required server'
    $Map[$Id] = Copy-UabsValue $Desired
    Add-UabsLedger 'newly_created' "$Profile MCP '$Id'"
    return
  }

  $entry = $Map[$Id]
  if ($Family -and -not (Test-UabsServerFamily $entry $Family)) {
    Add-UabsLedger 'untouched' "$Profile MCP '$Id' (id is occupied by a user-specific implementation)"
    throw "Cannot normalize $profile MCP '$Id': that id is occupied by a user-specific implementation."
  }
  $changed = $false
  foreach ($field in $Desired.Keys) {
    # A deliberate user timeout remains valid; only fill it when absent.
    if ($field -eq 'connect_timeout' -and $entry.ContainsKey($field)) { continue }
    # A tool filter is the user's editing surface: `hermes mcp configure
    # <name>` writes tools.include, and re-normalizing it every install would
    # silently undo their choice on the next run. Fill it when absent, never
    # overwrite. -SkyrimToolset passed explicitly overrides (see $forceToolset).
    if ($field -eq 'tools' -and $entry.ContainsKey($field) -and -not $script:ForceToolset) { continue }
    if (-not $entry.ContainsKey($field) -or -not (Test-UabsValueEqual $entry[$field] $Desired[$field])) {
      Add-UabsPlan -Kind 'SetLeaf' -Profile $Profile -Id $Id -Key "mcp_servers.$Id.$field" -Value $Desired[$field] -Detail "normalize $field"
      $entry[$field] = Copy-UabsValue $Desired[$field]
      $changed = $true
    }
  }
  if ($changed) { Add-UabsLedger 'migrated' "$Profile MCP '$Id'" }
  else { Add-UabsLedger 'kept' "$Profile MCP '$Id'" }
}

function Remove-UabsServer([string]$Profile, [hashtable]$Map, [string]$Id, [string]$Family) {
  if (-not $Map.ContainsKey($Id)) { return }
  if (-not (Test-UabsServerFamily $Map[$Id] $Family)) {
    Add-UabsLedger 'untouched' "$Profile MCP '$Id' (name matched, implementation appeared user-specific)"
    return
  }
  Add-UabsPlan -Kind 'RemoveEntry' -Profile $Profile -Id $Id -Key "mcp_servers.$Id" -Value $null -Detail "remove $Family from this profile"
  [void]$Map.Remove($Id)
  Add-UabsLedger 'removed' "$Profile MCP '$Id'"
}

function Normalize-UabsAliases([string]$Profile, [hashtable]$Map, [string]$Canonical, [string[]]$Aliases, [string]$Family) {
  foreach ($alias in $Aliases) {
    if ($alias -eq $Canonical -or -not $Map.ContainsKey($alias)) { continue }
    Remove-UabsServer -Profile $Profile -Map $Map -Id $alias -Family $Family
  }
}

function Get-UabsCoreSpec([hashtable]$DefaultMap, [string]$Id, [string[]]$Aliases, [hashtable]$Fallback, [string]$Family) {
  foreach ($name in @($Id) + $Aliases) {
    if (-not $DefaultMap.ContainsKey($name)) { continue }
    $entry = $DefaultMap[$name]
    if ($name -ne $Id -and -not (Test-UabsServerFamily $entry $Family)) { continue }
    $spec = Copy-UabsValue $Fallback
    foreach ($field in @('command', 'args')) {
      if ($entry.ContainsKey($field)) { $spec[$field] = Copy-UabsValue $entry[$field] }
    }
    return $spec
  }
  return Copy-UabsValue $Fallback
}

function New-UabsBackup([string[]]$ExistingProfiles) {
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmssfff'
  $root = Join-Path $env:LOCALAPPDATA "Ultimate-AI-Starter-Bundle\backups\hermes-profiles\$stamp"
  New-Item -ItemType Directory -Force -Path $root | Out-Null
  foreach ($profile in $ExistingProfiles) {
    $sourceRoot = if ($profile -eq 'default') { $HermesHome } else { Join-Path $HermesHome "profiles\$profile" }
    foreach ($name in @('config.yaml', 'profile.yaml')) {
      $source = Join-Path $sourceRoot $name
      if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { continue }
      $destDir = Join-Path $root $profile
      New-Item -ItemType Directory -Force -Path $destDir | Out-Null
      $dest = Join-Path $destDir $name
      Copy-Item -LiteralPath $source -Destination $dest -Force
      $sourceHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
      $backupHash = (Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash
      if ($sourceHash -ne $backupHash) { throw "Backup verification failed: $source" }
      [void]$script:Snapshots.Add([pscustomobject]@{ Source = $source; Backup = $dest; Sha256 = $sourceHash })
    }
  }
  $manifest = [ordered]@{
    schema = 1
    created_utc = [DateTime]::UtcNow.ToString('o')
    files = @($script:Snapshots | ForEach-Object { [ordered]@{ source = $_.Source; backup = $_.Backup; sha256 = $_.Sha256 } })
  }
  [IO.File]::WriteAllText((Join-Path $root 'backup-manifest.json'), (($manifest | ConvertTo-Json -Depth 6) + "`n"), (New-Object Text.UTF8Encoding($false)))
  return $root
}

function Restore-UabsBackup {
  foreach ($snapshot in $script:Snapshots) {
    if ((Get-FileHash -LiteralPath $snapshot.Backup -Algorithm SHA256).Hash -ne $snapshot.Sha256) {
      throw "Rollback backup hash mismatch: $($snapshot.Backup)"
    }
    Copy-Item -LiteralPath $snapshot.Backup -Destination $snapshot.Source -Force
    if ((Get-FileHash -LiteralPath $snapshot.Source -Algorithm SHA256).Hash -ne $snapshot.Sha256) {
      throw "Rollback verification failed: $($snapshot.Source)"
    }
  }
  foreach ($profile in $script:CreatedProfiles) {
    try { [void](Invoke-UabsHermes -Arguments @('profile', 'delete', $profile, '--yes') -AllowMissing) } catch { }
  }
}

function Write-UabsLedger([string]$BackupPath, [string]$Status) {
  $out = [ordered]@{ schema = 1; migration = 'hermes-profile-topology-v1'; status = $Status; backup = $BackupPath }
  foreach ($kind in $script:Ledger.Keys) { $out[$kind] = @($script:Ledger[$kind]) }
  if ($BackupPath) {
    $path = Join-Path $BackupPath 'migration-ledger.json'
    [IO.File]::WriteAllText($path, (($out | ConvertTo-Json -Depth 8) + "`n"), (New-Object Text.UTF8Encoding($false)))
  }
  foreach ($kind in $script:Ledger.Keys) {
    Write-Host ("{0}:" -f $kind.ToUpperInvariant())
    if (-not $script:Ledger[$kind].Count) { Write-Host '  (none)'; continue }
    foreach ($item in $script:Ledger[$kind]) { Write-Host "  $item" }
  }
}

# ---------------------------------------------------------------------------
# Profile preferences (v8.5.0)
#
# `hermes profile create --clone-from default` copies default ONCE. Nothing
# re-converged the copies, so roblox and skyrim were still running the fallback
# chain from their creation day while default had moved on. A fallback chain is
# only consulted when the primary is already failing, so a stale one is invisible
# until the moment it has to work.
#
# Ordered best-first. All four are :free variants, so a failover costs nothing;
# the two 1M-context models sit above the 256K ones because a failover mid-task
# must not truncate the context that survived.
$script:UabsFallbackChain = @(
  @{ provider = 'openrouter'; model = 'poolside/laguna-s-2.1:free' }
  @{ provider = 'openrouter'; model = 'thinkingmachines/inkling:free' }
  @{ provider = 'openrouter'; model = 'thinkingmachines/inkling-small:free' }
  @{ provider = 'openrouter'; model = 'poolside/laguna-xs-2.1:free' }
)

# Chains THIS PACK shipped before. A profile still carrying one of these has
# never been touched by its owner, so migrating it forward is safe. Anything
# else is a deliberate choice and is left exactly as it is.
$script:UabsSupersededChains = @(
  'dots-studio/dots-3-note-preview:free|openrouter/free'
  'dots-studio/dots-3-note-preview:free'
  'openrouter/free'
)

# Aliases for the escalation ladder, so a model can be switched by name instead
# of by pasting a slug. Every id below was verified against the live
# openrouter.ai/api/v1/models list; none is written from memory.
$script:UabsModelAliases = [ordered]@{
  'flash'        = 'openrouter/deepseek/deepseek-v4-flash-0731'
  'flash-vision' = 'openrouter/deepseek/deepseek-v4-flash-vision-exp'
  'muse'         = 'openrouter/meta/muse-spark-1.2-contributor'
  'v4-pro'       = 'openrouter/deepseek/deepseek-v4-pro-0813'
  'ox'           = 'openrouter/stealth/ox-alpha'
  'gemini-flash' = 'openrouter/google/gemini-3.7-flash'
  'glm'          = 'openrouter/z-ai/glm-5.3'
  'grok'         = 'openrouter/x-ai/grok-4.6'
  'sol'          = 'openrouter/openai/gpt-5.6-sol'
  'opus'         = 'openrouter/anthropic/claude-opus-5'
}

$script:Prefs = @{}

function Get-UabsFallbackSignature($Chain) {
  if (-not $Chain) { return '' }
  $models = @()
  foreach ($entry in @($Chain)) {
    $plain = ConvertTo-UabsPlain $entry
    if ($plain -is [System.Collections.IDictionary] -and $plain.Contains('model')) {
      $models += [string]$plain['model']
    } elseif ($plain) {
      $models += [string]$plain
    }
  }
  return ($models -join '|')
}

function Get-UabsProfilePrefs([string]$Profile) {
  $out = @{ fallback = @(); aliases = @{}; plugins = @(); disabled_plugins = @() }
  $fb = Invoke-UabsHermes -Arguments @('-p', $Profile, 'config', 'get', 'fallback_providers', '--json') -AllowMissing
  if ($fb.Code -eq 0) {
    $json = @($fb.Output | ForEach-Object { [string]$_ } |
      Where-Object { $_.Trim().StartsWith('[') }) | Select-Object -Last 1
    # No @() wrapper: ConvertTo-UabsPlain returns `,$items` so an array survives
    # being returned intact. Re-wrapping it nests the whole chain one level deep,
    # and every entry then reads as Object[] instead of a server hashtable.
    if ($json) { $out.fallback = ConvertTo-UabsPlain ($json | ConvertFrom-Json) }
  }
  $pl = Invoke-UabsHermes -Arguments @('-p', $Profile, 'config', 'get', 'plugins.enabled', '--json') -AllowMissing
  if ($pl.Code -eq 0) {
    $json = @($pl.Output | ForEach-Object { [string]$_ } |
      Where-Object { $_.Trim().StartsWith('[') }) | Select-Object -Last 1
    # ConvertTo-UabsPlain deliberately returns an array as one pipeline object.
    # Casting that object to string joins every plugin with spaces, making
    # membership checks impossible. Let the parsed JSON array enumerate here.
    if ($json) {
      $parsedPlugins = $json | ConvertFrom-Json
      $out.plugins = @($parsedPlugins | ForEach-Object { [string]$_ })
    }
  }
  $dp = Invoke-UabsHermes -Arguments @('-p', $Profile, 'config', 'get', 'plugins.disabled', '--json') -AllowMissing
  if ($dp.Code -eq 0) {
    $json = @($dp.Output | ForEach-Object { [string]$_ } |
      Where-Object { $_.Trim().StartsWith('[') }) | Select-Object -Last 1
    if ($json) {
      $parsedDisabled = $json | ConvertFrom-Json
      $out.disabled_plugins = @($parsedDisabled | ForEach-Object { [string]$_ })
    }
  }
  $al = Invoke-UabsHermes -Arguments @('-p', $Profile, 'config', 'get', 'model.aliases', '--json') -AllowMissing
  if ($al.Code -eq 0) {
    $json = @($al.Output | ForEach-Object { [string]$_ } |
      Where-Object { $_.Trim().StartsWith('{') }) | Select-Object -Last 1
    if ($json) { $out.aliases = ConvertTo-UabsPlain ($json | ConvertFrom-Json) }
  }
  return $out
}

$script:UabsSharedPlugins = @()
$script:UabsDiscouragedPlugins = @()

function Get-UabsSharedPlugins([string]$HermesRoot) {
  # Exactly what the default profile already runs, minus anything whose payload
  # is absent. Never a hardcoded list: the point is to propagate what the user
  # actually installed, not what this pack imagines they installed.
  $root = Join-Path $HermesRoot 'plugins'
  if (-not (Test-Path $root)) { return @() }
  $out = @()
  foreach ($entry in (Get-UabsProfilePrefs 'default').plugins) {
    if ($script:UabsDiscouragedPlugins -contains [string]$entry) { continue }
    $top = ([string]$entry).Split(@('/', [char]92))[0]
    if ($top -and (Test-Path (Join-Path $root $top))) { $out += [string]$entry }
  }
  return $out
}

function Ensure-UabsProfilePluginPayload([string]$Profile, [string]$HermesRoot, [string]$ProfileDirs) {
  # Hermes resolves a user plugin under <HERMES_HOME>/plugins. For a named
  # profile that is profiles/<name>/plugins, which `profile create` never
  # creates -- so every plugin the cloned config enables silently resolves to
  # nothing. One junction back to the root keeps a single authoritative copy
  # instead of duplicating payloads that would then drift.
  if ($Profile -eq 'default') { return }
  $root = Join-Path $HermesRoot 'plugins'
  if (-not (Test-Path $root)) { return }
  $link = Join-Path (Join-Path $ProfileDirs $Profile) 'plugins'
  if (Test-Path $link) {
    Add-UabsLedger 'untouched' "$Profile already has a plugins directory"
    return
  }
  Add-UabsPlan -Kind 'LinkPlugins' -Profile $Profile -Id 'plugins' -Key 'plugins/' `
    -Value $root -Detail 'profile cannot see any installed plugin (no plugins directory)'
}

function Ensure-UabsProfilePrefs([string]$Profile) {
  $current = Get-UabsProfilePrefs $Profile
  $wanted = @{}

  $toDisable = @($current.plugins | Where-Object { $script:UabsDiscouragedPlugins -contains [string]$_ })
  Write-Verbose ("$Profile enabled plugins: {0}; catalog-rejected: {1}" -f ($current.plugins -join ', '), ($toDisable -join ', '))
  if ($toDisable.Count) {
    Add-UabsPlan -Kind 'SetPrefs' -Profile $Profile -Id 'plugins.disabled' `
      -Key 'plugins.disabled' -Value $toDisable `
      -Detail ('disable catalog-rejected plugin(s): ' + ($toDisable -join ', '))
    $wanted['disable_plugins'] = $toDisable
    foreach ($entry in $toDisable) { Add-UabsLedger 'removed' "$Profile enabled plugin '$entry'" }
  }

  $signature = Get-UabsFallbackSignature $current.fallback
  $target = Get-UabsFallbackSignature $script:UabsFallbackChain
  if ($signature -eq $target) {
    Add-UabsLedger 'untouched' "$Profile fallback chain already current"
  } elseif (-not $signature -or ($script:UabsSupersededChains -contains $signature)) {
    $why = if (-not $signature) { 'no fallback chain configured' }
           else { "superseded pack default ($signature)" }
    Add-UabsPlan -Kind 'SetPrefs' -Profile $Profile -Id 'fallback_providers' `
      -Key 'fallback_providers' -Value $script:UabsFallbackChain -Detail $why
    $wanted['fallback_providers'] = $script:UabsFallbackChain
  } else {
    # Not ours to overwrite. Say so rather than silently leaving it.
    Add-UabsLedger 'kept' "$Profile fallback chain is a user choice ($signature)"
  }

  $missing = [ordered]@{}
  foreach ($key in $script:UabsModelAliases.Keys) {
    if (-not ($current.aliases -and $current.aliases.Contains($key))) {
      $missing[$key] = $script:UabsModelAliases[$key]
    }
  }
  if ($missing.Count) {
    Add-UabsPlan -Kind 'SetPrefs' -Profile $Profile -Id 'model.aliases' `
      -Key 'model.aliases' -Value $missing `
      -Detail ("add " + $missing.Count + " missing alias(es): " + (@($missing.Keys) -join ', '))
    $wanted['aliases'] = $missing
  } else {
    Add-UabsLedger 'untouched' "$Profile model aliases already complete"
  }


  # Plugin payloads live in ONE place -- the root Hermes home's plugins dir --
  # but every profile keeps its own enabled list. `profile create --clone-from`
  # copies the list and not the payload, so a cloned profile ends up enabling
  # plugins it cannot see. Only ever enable a plugin whose directory is really
  # there; enabling a missing one is the bug this is fixing.
  $missingPlugins = @()
  foreach ($entry in $script:UabsSharedPlugins) {
    if ($current.plugins -notcontains $entry) { $missingPlugins += $entry }
  }
  if ($missingPlugins.Count) {
    Add-UabsPlan -Kind 'SetPrefs' -Profile $Profile -Id 'plugins.enabled' `
      -Key 'plugins.enabled' -Value $missingPlugins `
      -Detail ('enable ' + $missingPlugins.Count + ' installed plugin(s): ' + ($missingPlugins -join ', '))
    $wanted['plugins'] = $missingPlugins
  } else {
    Add-UabsLedger 'untouched' "$Profile plugin list already covers every installed plugin"
  }
  if ($wanted.Count) { $script:Prefs[$Profile] = $wanted }
}

$script:UabsHermesPrefsScript = @'
import json, os
from hermes_cli.config import load_config, save_config
cfg = load_config()
prefs = json.loads(os.environ["UABS_HERMES_PREFS_JSON"])
if "fallback_providers" in prefs:
    cfg["fallback_providers"] = prefs["fallback_providers"]
aliases = prefs.get("aliases") or {}
if aliases:
    model = dict(cfg.get("model") or {})
    merged = dict(model.get("aliases") or {})
    for key, value in aliases.items():
        merged.setdefault(key, value)   # never overwrite a user's own alias
    model["aliases"] = merged
    cfg["model"] = model
plugin_names = prefs.get("plugins") or []
disable_names = prefs.get("disable_plugins") or []
if plugin_names or disable_names:
    plugins = dict(cfg.get("plugins") or {})
    enabled = list(plugins.get("enabled") or [])
    for name in plugin_names:
        if name not in enabled:        # additive: never reorder or drop
            enabled.append(name)
    if disable_names:
        enabled = [name for name in enabled if name not in disable_names]
        disabled = list(plugins.get("disabled") or [])
        for name in disable_names:
            if name not in disabled:
                disabled.append(name)
        plugins["disabled"] = disabled
    plugins["enabled"] = enabled
    cfg["plugins"] = plugins
save_config(cfg)
'@

$script:UabsHermesMapScript = @'
import json, os
from hermes_cli.config import load_config, save_config
cfg = load_config()
cfg["mcp_servers"] = json.loads(os.environ["UABS_HERMES_MCP_MAP_JSON"])
save_config(cfg)
'@

try {
  $profileDirs = Join-Path $HermesHome 'profiles'
  $existingProfiles = @('default')
  $managedProfiles = @('default')
  $maps = @{}
  $maps['default'] = Get-UabsMcpMap 'default'

  $robloxBat = Join-Path $env:LOCALAPPDATA 'Roblox\mcp.bat'
  $robloxAvailable = Test-Path -LiteralPath $robloxBat -PathType Leaf
  $houseCarl = [Environment]::GetEnvironmentVariable('HOUSECARL_MCP', 'Process')
  if (-not $houseCarl) { $houseCarl = [Environment]::GetEnvironmentVariable('HOUSECARL_MCP', 'User') }
  $mo2 = [Environment]::GetEnvironmentVariable('SKYRIM_MO2_INSTANCE', 'Process')
  if (-not $mo2) { $mo2 = [Environment]::GetEnvironmentVariable('SKYRIM_MO2_INSTANCE', 'User') }
  $skyrimAvailable = $houseCarl -and $mo2 -and
    (Test-Path -LiteralPath $houseCarl -PathType Leaf) -and
    (Test-Path -LiteralPath $mo2 -PathType Container)
  $skyrimForgeRoot = [Environment]::GetEnvironmentVariable('SKYRIM_FORGE_ROOT', 'Process')
  if (-not $skyrimForgeRoot) { $skyrimForgeRoot = [Environment]::GetEnvironmentVariable('SKYRIM_FORGE_ROOT', 'User') }
  $spookyRoot = [Environment]::GetEnvironmentVariable('SPOOKY_AUTOMOD_ROOT', 'Process')
  if (-not $spookyRoot) { $spookyRoot = [Environment]::GetEnvironmentVariable('SPOOKY_AUTOMOD_ROOT', 'User') }
  if ($skyrimForgeRoot -and (Test-Path -LiteralPath (Join-Path $skyrimForgeRoot 'skyrim_forge\cli.py') -PathType Leaf)) {
    Add-UabsLedger 'kept' 'Skyrim Forge installed skill/CLI capability (not a default MCP member)'
  } else {
    Add-UabsLedger 'untouched' 'Skyrim Forge capability (not installed; no MCP entry created)'
  }
  if ($spookyRoot -and (Test-Path -LiteralPath (Join-Path $spookyRoot 'SpookysAutomod.sln') -PathType Leaf)) {
    Add-UabsLedger 'kept' "Spooky's AutoMod installed CLI capability (not an MCP member)"
  } else {
    Add-UabsLedger 'untouched' "Spooky's AutoMod capability (not installed; no MCP entry created)"
  }

  foreach ($profile in @('roblox', 'skyrim')) {
    $dir = Join-Path $profileDirs $profile
    $available = if ($profile -eq 'roblox') { $robloxAvailable } else { $skyrimAvailable }
    if (-not $available) {
      Add-UabsLedger 'untouched' "Hermes profile '$profile' (required local capability is not installed)"
      continue
    }
    $managedProfiles += $profile
    if (Test-Path -LiteralPath $dir -PathType Container) {
      $existingProfiles += $profile
      $maps[$profile] = Get-UabsMcpMap $profile
      Add-UabsLedger 'kept' "Hermes profile '$profile'"
    } else {
      Add-UabsPlan -Kind 'CreateProfile' -Profile $profile -Id '' -Key '' -Value $null -Detail 'clone config, credentials, SOUL, and skills from default'
      $maps[$profile] = Copy-UabsValue $maps['default']
      Add-UabsLedger 'newly_created' "Hermes profile '$profile' and native alias"
    }
  }

  $catalogPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'BUNDLED-TOOLS\CATALOG.json'
  $catalog = $null
  if (Test-Path -LiteralPath $catalogPath -PathType Leaf) {
    try { $catalog = [IO.File]::ReadAllText($catalogPath) | ConvertFrom-Json }
    catch { Write-Warning "CATALOG.json is unreadable at $catalogPath - using the previous known-good Context7 pin and no houseCARL tool budget." }
  }
  $context7Args = @('-y', '@upstash/context7-mcp@4.0.3')
  if ($catalog) {
    foreach ($comp in @($catalog.components | Where-Object { $_.hook_policy -eq 'off' -and $_.discouraged_provider_plugins })) {
      $providerBlock = $comp.discouraged_provider_plugins.PSObject.Properties['Hermes']
      if ($providerBlock) {
        $script:UabsDiscouragedPlugins += @($providerBlock.Value | ForEach-Object { [string]$_ })
      }
    }
    $script:UabsDiscouragedPlugins = @($script:UabsDiscouragedPlugins | Where-Object { $_ } | Select-Object -Unique)
    Write-Verbose ('Catalog-rejected Hermes plugins: ' + ($script:UabsDiscouragedPlugins -join ', '))
    $context7Comp = @($catalog.components | Where-Object { $_.id -eq 'context7' }) | Select-Object -First 1
    $fromCatalog = if ($context7Comp) { @($context7Comp.npx_args | ForEach-Object { [string]$_ }) } else { @() }
    if (@($fromCatalog | Where-Object { $_ -like '*context7-mcp@*' }).Count) { $context7Args = $fromCatalog }
  }
  $context7 = Get-UabsCoreSpec $maps['default'] 'context7' @('context-7') @{
    command = 'npx'; args = $context7Args; enabled = $true; connect_timeout = 30
  } 'context7'
  $github = Get-UabsCoreSpec $maps['default'] 'github' @('github-mcp-server') @{
    command = (Join-Path $env:LOCALAPPDATA 'Ultimate-AI-Starter-Bundle\github-mcp-server\github-mcp-server.exe')
    args = @('stdio', '--toolsets', 'context,repos,pull_requests,actions,issues'); enabled = $true; connect_timeout = 30
  } 'github'
  $headroomCommand = [Environment]::GetEnvironmentVariable('HEADROOM_CMD', 'Process')
  if (-not $headroomCommand) { $headroomCommand = [Environment]::GetEnvironmentVariable('HEADROOM_CMD', 'User') }
  if (-not $headroomCommand) { $headroomCommand = 'headroom' }
  $headroom = Get-UabsCoreSpec $maps['default'] 'headroom' @('headroom-mcp') @{
    command = $headroomCommand; args = @('mcp', 'serve'); enabled = $true; connect_timeout = 30
  } 'headroom'

  $robloxStudio = @{
    command = 'cmd.exe'; args = @('/c', $robloxBat); enabled = $true; connect_timeout = 30
  }

  # The tool budget is DATA. Reading it here rather than hardcoding names keeps
  # the measured numbers and the applied filter in one place, and makes the next
  # oversized server a catalog change.
  $script:ForceToolset = $PSBoundParameters.ContainsKey('SkyrimToolset')
  $toolsFilter = $null
  $toolsetNote = ''
  if (-not $catalog) {
    # Say so. Silently registering all 45 tools because a data file was not
    # found is a ~10,000 token/turn difference the user never asked for.
    Write-Warning "CATALOG.json not found at $catalogPath - no tool budget applied; every tool will be registered."
  }
  if ($catalog) {
    $carlComp = @($catalog.components | Where-Object { $_.id -eq 'housecarl' }) | Select-Object -First 1
    $budget = if ($carlComp) { $carlComp.mcp_tool_budget } else { $null }
    $chosen = if ($budget -and $budget.sets) { $budget.sets.$SkyrimToolset } else { $null }
    if ($chosen) {
      $inc = @($chosen.include | Where-Object { $_ })
      $exc = @($chosen.exclude | Where-Object { $_ })
      if ($inc.Count) { $toolsFilter = @{ include = $inc } }
      elseif ($exc.Count) { $toolsFilter = @{ exclude = $exc } }
      $toolsetNote = "$SkyrimToolset ($($chosen.tools)/$($budget.all_tools) tools, ~$($chosen.tokens_per_turn) tok/turn, -$($chosen.saving_pct)%)"
    } else {
      Write-Warning "CATALOG.json declares no mcp_tool_budget set '$SkyrimToolset' for housecarl; registering every tool."
    }
  }

  $houseCarlSpec = @{
    command = $houseCarl; args = @(); enabled = $true; connect_timeout = 30
    env = @{ SKYRIM_MO2_INSTANCE = $mo2; HouseCarl__Mo2InstanceDir = $mo2 }
  }

  $core = @(
    @{ Id = 'context7'; Spec = $context7; Aliases = @('context-7'); Family = 'context7' },
    @{ Id = 'github'; Spec = $github; Aliases = @('github-mcp-server'); Family = 'github' },
    @{ Id = 'headroom'; Spec = $headroom; Aliases = @('headroom-mcp'); Family = 'headroom' }
  )
  foreach ($profile in $managedProfiles) {
    foreach ($item in $core) {
      Ensure-UabsServer $profile $maps[$profile] $item.Id $item.Spec $item.Family
      Normalize-UabsAliases $profile $maps[$profile] $item.Id $item.Aliases $item.Family
    }
  }

  if ($robloxAvailable) {
    Ensure-UabsServer 'roblox' $maps['roblox'] 'Roblox_Studio' $robloxStudio 'roblox'
    Normalize-UabsAliases 'roblox' $maps['roblox'] 'Roblox_Studio' @('roblox-studio', 'roblox_studio') 'roblox'
  }
  if ($skyrimAvailable) {
    if ($toolsFilter) {
      # Do not re-apply a budget the user deliberately deleted. The provider
      # auto-detection in v8.1.0 exists because "the installer keeps putting
      # back what I removed" is the worst kind of helpful.
      $stateFile = Join-Path $env:LOCALAPPDATA 'Ultimate-AI-Starter-Bundle\hermes-profile-migration.json'
      $priorToolset = $null
      if (Test-Path -LiteralPath $stateFile -PathType Leaf) {
        try { $priorToolset = ([IO.File]::ReadAllText($stateFile) | ConvertFrom-Json).skyrim_toolset } catch { }
      }
      $entryHasFilter = $maps['skyrim'].ContainsKey('housecarl') -and
        (ConvertTo-UabsPlain $maps['skyrim']['housecarl']).ContainsKey('tools')
      if ($priorToolset -and -not $entryHasFilter -and -not $script:ForceToolset) {
        Add-UabsLedger 'untouched' "skyrim MCP 'housecarl' tool budget (previously applied and since removed by hand)"
      } else {
        $houseCarlSpec['tools'] = $toolsFilter
        Add-UabsLedger 'migrated' "skyrim MCP 'housecarl' tool budget: $toolsetNote"
      }
    } elseif ($script:ForceToolset -and $maps['skyrim'].ContainsKey('housecarl') -and
              (ConvertTo-UabsPlain $maps['skyrim']['housecarl']).ContainsKey('tools')) {
      # -SkyrimToolset Full means "register every tool", which requires REMOVING
      # the filter. Ensure-UabsServer only writes fields present in the desired
      # spec, so leaving `tools` out of the spec keeps the old filter installed
      # and the run reports "already matches" while Full is not in effect.
      Add-UabsPlan -Kind 'RemoveLeaf' -Profile 'skyrim' -Id 'housecarl' -Key 'mcp_servers.housecarl.tools' -Value $null -Detail 'remove the tool budget (-SkyrimToolset Full)'
      [void]$maps['skyrim']['housecarl'].Remove('tools')
      Add-UabsLedger 'removed' "skyrim MCP 'housecarl' tool budget (Full: all $(if ($budget) { $budget.all_tools } else { '' }) tools registered)"
    }
    Ensure-UabsServer 'skyrim' $maps['skyrim'] 'housecarl' $houseCarlSpec 'housecarl'
    Normalize-UabsAliases 'skyrim' $maps['skyrim'] 'housecarl' @('houseCARL', 'house-carl') 'housecarl'
  }

  if ($robloxAvailable) {
    foreach ($profile in @('default', 'skyrim') | Where-Object { $managedProfiles -contains $_ }) {
      foreach ($id in @('Roblox_Studio', 'roblox-studio', 'roblox_studio')) {
        Remove-UabsServer $profile $maps[$profile] $id 'roblox'
      }
    }
  }
  if ($skyrimAvailable) {
    foreach ($profile in @('default', 'roblox') | Where-Object { $managedProfiles -contains $_ }) {
      foreach ($id in @('housecarl', 'houseCARL', 'house-carl')) {
        Remove-UabsServer $profile $maps[$profile] $id 'housecarl'
      }
    }
  }

  $forgeIds = @{
    'skyrim-forge' = 'skyrim-forge'; 'skyrim_forge' = 'skyrim-forge'
    'robloxforge' = 'robloxforge'; 'roblox-forge' = 'robloxforge'
  }
  $forgeCompatRoblox = $false
  $forgeCompatSkyrim = $false
  if ($WithForgeCompatibility) {
    $skyrimForgePython = if ($skyrimForgeRoot) { [IO.Path]::Combine($skyrimForgeRoot, '.venv\Scripts\python.exe') } else { '' }
    $robloxForgeRoot = [Environment]::GetEnvironmentVariable('ROBLOX_FORGE_ROOT', 'Process')
    if (-not $robloxForgeRoot) { $robloxForgeRoot = [Environment]::GetEnvironmentVariable('ROBLOX_FORGE_ROOT', 'User') }
    $robloxForgeServer = if ($robloxForgeRoot) { [IO.Path]::Combine($robloxForgeRoot, 'mcp_server\server.py') } else { '' }
    $hermesPython = [IO.Path]::Combine($env:LOCALAPPDATA, 'hermes\hermes-agent\venv\Scripts\python.exe')
    if ($skyrimAvailable) {
      if (-not (Test-Path -LiteralPath $skyrimForgePython -PathType Leaf)) { throw 'Skyrim Forge compatibility requested but its Python is missing.' }
      Ensure-UabsServer 'skyrim' $maps['skyrim'] 'skyrim-forge' @{
        command = $skyrimForgePython; args = @('-m', 'skyrim_forge', 'mcp'); enabled = $true; connect_timeout = 30
      } 'skyrim-forge'
      $forgeCompatSkyrim = $true
    }
    if ($robloxAvailable) {
      if (-not (Test-Path -LiteralPath $robloxForgeServer -PathType Leaf)) { throw 'RobloxForge compatibility requested but its MCP server is missing.' }
      if (-not (Test-Path -LiteralPath $hermesPython -PathType Leaf)) { throw 'RobloxForge compatibility requested but Hermes Python is missing.' }
      Ensure-UabsServer 'roblox' $maps['roblox'] 'robloxforge' @{
        command = $hermesPython; args = @($robloxForgeServer); enabled = $true; connect_timeout = 30
      } 'robloxforge'
      $forgeCompatRoblox = $true
    }
  }
  foreach ($profile in $managedProfiles) {
    foreach ($id in $forgeIds.Keys) {
      $allowed = ($forgeCompatSkyrim -and $id -eq 'skyrim-forge' -and $profile -eq 'skyrim') -or
        ($forgeCompatRoblox -and $id -eq 'robloxforge' -and $profile -eq 'roblox')
      if (-not $allowed) { Remove-UabsServer $profile $maps[$profile] $id $forgeIds[$id] }
    }
  }

  $expected = @{
    default = @('context7', 'github', 'headroom')
    roblox = @('context7', 'github', 'headroom', 'Roblox_Studio')
    skyrim = @('context7', 'github', 'headroom', 'housecarl')
  }
  if ($forgeCompatRoblox) { $expected.roblox += 'robloxforge' }
  if ($forgeCompatSkyrim) { $expected.skyrim += 'skyrim-forge' }
  $expectedFamilies = @{
    context7 = 'context7'; github = 'github'; headroom = 'headroom'
    Roblox_Studio = 'roblox'; housecarl = 'housecarl'
    robloxforge = 'robloxforge'; 'skyrim-forge' = 'skyrim-forge'
  }
  foreach ($profile in $managedProfiles) {
    foreach ($id in $maps[$profile].Keys) {
      if ($expected[$profile] -notcontains $id) { Add-UabsLedger 'untouched' "$profile MCP '$id' (unowned/user-specific)" }
    }
  }

  # Must be planned BEFORE the no-op check: MCP topology can already be correct
  # while fallbacks and aliases have drifted, and that combination is exactly
  # what a cloned profile looks like months later.
  $script:UabsSharedPlugins = Get-UabsSharedPlugins $HermesHome
  foreach ($profile in $managedProfiles) {
    Ensure-UabsProfilePluginPayload $profile $HermesHome $profileDirs
    Ensure-UabsProfilePrefs $profile
  }

  if (-not $script:Plan.Count) {
    Write-Host 'Hermes profiles already match the target architecture; no files changed.' -ForegroundColor Green
    Write-UabsLedger -BackupPath '' -Status 'no-op'
    return
  }

  Write-Host ($(if ($Apply) { 'Applying Hermes profile migration:' } else { 'Hermes profile migration plan:' })) -ForegroundColor Cyan
  foreach ($item in $script:Plan) { Write-Host ("  {0,-13} {1,-7} {2}" -f $item.Kind, $item.Profile, $item.Detail) }
  if (-not $Apply) {
    Write-Host 'No files changed. Re-run with -Apply.' -ForegroundColor Yellow
    Write-UabsLedger -BackupPath '' -Status 'planned'
    return
  }

  if (Get-Process -Name 'Hermes' -ErrorAction SilentlyContinue) {
    throw 'Hermes is running. Close the desktop app before applying this migration so it cannot save stale config over the changes.'
  }

  $backup = New-UabsBackup $existingProfiles
  try {
    foreach ($item in $script:Plan | Where-Object { $_.Kind -eq 'CreateProfile' }) {
      $description = if ($item.Profile -eq 'roblox') { 'Roblox development with the official Studio MCP.' } else { 'Skyrim development with houseCARL load-order evidence.' }
      [void](Invoke-UabsHermes -Arguments @('profile', 'create', $item.Profile, '--clone-from', 'default', '--description', $description))
      [void]$script:CreatedProfiles.Add($item.Profile)
    }
    foreach ($item in $script:Plan | Where-Object { $_.Kind -eq 'LinkPlugins' }) {
      $link = Join-Path (Join-Path $profileDirs $item.Profile) 'plugins'
      [void](New-Item -ItemType Junction -Path $link -Target $item.Value -ErrorAction Stop)
    }
    $affectedProfiles = @($script:Plan | Where-Object { $_.Kind -ne 'CreateProfile' } | ForEach-Object { $_.Profile } | Select-Object -Unique)
    foreach ($profile in $affectedProfiles) {
      $profileHome = if ($profile -eq 'default') { $HermesHome } else { Join-Path $profileDirs $profile }
      $env:HERMES_HOME = $profileHome
      Invoke-UabsHermesConfig -Script $script:UabsHermesMapScript -EnvVars @{
        UABS_HERMES_MCP_MAP_JSON = (ConvertTo-Json -InputObject $maps[$profile] -Depth 20 -Compress)
      }
      if ($script:Prefs.ContainsKey($profile)) {
        Invoke-UabsHermesConfig -Script $script:UabsHermesPrefsScript -EnvVars @{
          UABS_HERMES_PREFS_JSON = (ConvertTo-Json -InputObject $script:Prefs[$profile] -Depth 20 -Compress)
        }
      }
    }
    $env:HERMES_HOME = $HermesHome

    foreach ($profile in $managedProfiles) {
      $actual = Get-UabsMcpMap $profile
      foreach ($id in $expected[$profile]) {
        $entry = if ($actual.ContainsKey($id)) { $actual[$id] } else { $null }
        $enabled = $entry -and $entry.ContainsKey('enabled') -and ($entry['enabled'] -eq $true) -and
          (Test-UabsServerFamily $entry $expectedFamilies[$id])
        Write-Verbose ("verify $profile/${id}: present={0} enabled={1} type={2}" -f ($null -ne $entry), $entry['enabled'], $(if ($null -ne $entry['enabled']) { $entry['enabled'].GetType().FullName } else { 'null' }))
        if (-not $enabled) {
          throw "Verification failed: $profile is missing enabled MCP '$id'."
        }
      }
      foreach ($id in $forgeIds.Keys) {
        $allowedHere = ($forgeCompatSkyrim -and $profile -eq 'skyrim' -and $id -eq 'skyrim-forge') -or
          ($forgeCompatRoblox -and $profile -eq 'roblox' -and $id -eq 'robloxforge')
        if (-not $allowedHere -and $actual.ContainsKey($id) -and (Test-UabsServerFamily $actual[$id] $forgeIds[$id])) {
          throw "Verification failed: legacy Forge MCP '$id' remains in $profile."
        }
      }
    }
    if ($robloxAvailable) {
      $robloxActual = Get-UabsMcpMap 'roblox'
      if ($robloxActual['Roblox_Studio']['command'] -ne 'cmd.exe' -or @($robloxActual['Roblox_Studio']['args'])[1] -ne $robloxBat) {
        throw 'Verification failed: Roblox profile does not use the official stable mcp.bat launcher.'
      }
    }
    foreach ($profile in $script:Prefs.Keys) {
      $after = Get-UabsProfilePrefs $profile
      if ($script:Prefs[$profile].ContainsKey('fallback_providers')) {
        $want = Get-UabsFallbackSignature $script:UabsFallbackChain
        $got = Get-UabsFallbackSignature $after.fallback
        if ($got -ne $want) {
          throw "Verification failed: $profile fallback chain is '$got', expected '$want'."
        }
      }
      foreach ($key in $script:Prefs[$profile]['aliases'].Keys) {
        if (-not ($after.aliases -and $after.aliases.Contains($key))) {
          throw "Verification failed: $profile is missing alias '$key'."
        }
      }
      foreach ($entry in @($script:Prefs[$profile]['plugins'])) {
        if (-not $entry) { continue }
        if ($after.plugins -notcontains $entry) {
          throw "Verification failed: $profile did not enable plugin '$entry'."
        }
        # Enabled is worthless if the payload is unreachable -- that is the
        # original bug, and writing the list without checking would recreate it.
        $home2 = if ($profile -eq 'default') { $HermesHome } else { Join-Path $profileDirs $profile }
        $top = ([string]$entry).Split(@('/', [char]92))[0]
        if (-not (Test-Path (Join-Path (Join-Path $home2 'plugins') $top))) {
          throw "Verification failed: $profile enables plugin '$entry' but cannot resolve its payload."
        }
      }
      foreach ($entry in @($script:Prefs[$profile]['disable_plugins'])) {
        if (-not $entry) { continue }
        if ($after.plugins -contains $entry -or $after.disabled_plugins -notcontains $entry) {
          throw "Verification failed: $profile did not disable catalog-rejected plugin '$entry'."
        }
      }
    }
    $defaultActual = Get-UabsMcpMap 'default'
    if (($robloxAvailable -and $defaultActual.ContainsKey('Roblox_Studio') -and (Test-UabsServerFamily $defaultActual['Roblox_Studio'] 'roblox')) -or
        ($skyrimAvailable -and $defaultActual.ContainsKey('housecarl') -and (Test-UabsServerFamily $defaultActual['housecarl'] 'housecarl'))) {
      throw 'Verification failed: a game MCP remains in the default profile.'
    }

    $stateDir = Join-Path $env:LOCALAPPDATA 'Ultimate-AI-Starter-Bundle'
    New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
    $state = [ordered]@{
      schema = 1; migration = 'hermes-profile-topology-v1'; applied_utc = [DateTime]::UtcNow.ToString('o')
      hermes_home = $HermesHome; backup = $backup; forge_compatibility = [bool]$WithForgeCompatibility
      skyrim_toolset = $(if ($toolsFilter) { $SkyrimToolset } else { $null })
    }
    [IO.File]::WriteAllText((Join-Path $stateDir 'hermes-profile-migration.json'), (($state | ConvertTo-Json -Depth 5) + "`n"), (New-Object Text.UTF8Encoding($false)))
    Write-UabsLedger -BackupPath $backup -Status 'applied'
    Write-Host "Backup: $backup" -ForegroundColor Green
  } catch {
    $env:HERMES_HOME = $HermesHome
    Restore-UabsBackup
    Write-UabsLedger -BackupPath $backup -Status 'failed-rolled-back'
    throw "Hermes profile migration failed and was rolled back: $($_.Exception.Message)"
  }
} finally {
  $env:HERMES_HOME = $savedHermesHome
}
