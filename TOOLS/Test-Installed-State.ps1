<#
.SYNOPSIS
  Final fail-closed installed-state doctor for Ultimate AI Starter Bundle 7.9.x.
#>
[CmdletBinding()]
param(
  [string]$PackRoot,
  [string[]]$Providers = @('Claude','Codex','Grok','Kimi','Hermes'),
  [switch]$SkipSkills,
  [switch]$SkipForge
)
$ErrorActionPreference='Stop'
if (-not $PackRoot) { $PackRoot = Split-Path -Parent $PSScriptRoot }
. (Join-Path $PackRoot 'TOOLS\V7-Common.ps1')
# Join-Path, not Join-V5Path: the helper lives inside the file being sourced.
# Needed for Test-V5ServerDeclared in the capability-state section -- without it
# every component reports "registered: none", which is a wrong answer rather
# than a visible failure.
. (Join-Path $PackRoot 'TOOLS\V7-Mcp-Write.ps1')
$Providers = @($Providers | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$catalog = Get-V5Catalog
$state = $null
$errors = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
function Err([string]$m){ [void]$errors.Add($m); Write-V5Bad $m }
function Warn([string]$m){ [void]$warnings.Add($m); Write-V5Warn $m }
function Resolve-Exe([string]$Provider) {
  $cmd=Get-Command $Provider.ToLowerInvariant() -EA SilentlyContinue
  if($cmd){return $cmd.Source}
  $cands=switch($Provider){
    'Claude'{@((Join-Path $env:USERPROFILE '.local\bin\claude.exe'))}
    'Codex'{@((Join-Path $env:USERPROFILE '.local\bin\codex.exe'),(Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\bin\codex.exe'))}
    'Grok'{@((Join-Path $env:USERPROFILE '.grok\bin\grok.exe'))}
    'Kimi'{@((Join-Path $env:USERPROFILE '.local\bin\kimi.exe'),(Join-Path $env:USERPROFILE '.kimi-code\bin\kimi.exe'))}
    'Hermes'{@((Join-Path $env:LOCALAPPDATA 'hermes\hermes-agent\venv\Scripts\hermes.exe'))}
  }
  foreach($c in $cands){if($c -and (Test-Path -LiteralPath $c -PathType Leaf)){return $c}}
  return $null
}
Write-V5Step 'Final installed-state doctor'
# VERSION.txt is the one source. The doctor used to restate 7.8.0 in four
# places, so a release bump could leave the doctor failing a correct install.
$packVersion = [IO.File]::ReadAllText((Join-Path $PackRoot 'VERSION.txt')).Trim()
$packBare = $packVersion.TrimStart('v','V')
# Three or more parts. v7.9.8.5 was the pack's first four-part version, and it
# widened check_versions.py and test_version_sources but not this gate -- so the
# doctor failed the release that shipped it, on a correct tree. A version format
# is agreed by every check that reads it or by none of them.
if ($packBare -notmatch '^\d+(\.\d+){2,}$') { Err "Pack VERSION.txt is not a dotted version of three or more parts: $packVersion" }
$statePath=Join-Path $env:LOCALAPPDATA 'Skyrim-AI-V5\install-state.json'
if(-not(Test-Path -LiteralPath $statePath -PathType Leaf)){Err 'install-state.json is missing.'}
else{
  try{
    $state=[IO.File]::ReadAllText($statePath)|ConvertFrom-Json
    if($state.version -ne $packBare){Err "install-state version is $($state.version), expected $packBare."}
    foreach($prop in $state.components.PSObject.Properties){
      if($prop.Value.status -in @('error','failed')){Err "component $($prop.Name) status=$($prop.Value.status)"}
    }
  }catch{Err ('install-state unreadable: '+$_.Exception.Message)}
}
if(-not $SkipSkills){
  foreach($provider in $Providers){
    $exe=Resolve-Exe $provider
    if(-not $exe){Err "$provider executable missing after provider bootstrap.";continue}
    & $exe --version *> $null
    if($LASTEXITCODE -ne 0){Err "$provider executable failed --version."}

    # PowerShell variable names are case-insensitive; $HOME is a read-only
    # automatic variable on Windows PowerShell 5.1. Never use $home as a local.
    $providerHome=Get-V5ProviderHome -Provider $provider -Catalog $catalog
    if (-not $providerHome) { Err "$provider provider home could not be resolved."; continue }
    $destSkills=Join-Path $providerHome 'skills'
    $sourceSkills=Join-Path $PackRoot ("1-TAILORED-PROVIDER-TREES\$provider\COPY-TO-SKILLS-DIRECTORY\skills")
    if(-not(Test-Path -LiteralPath $sourceSkills -PathType Container)){
      Err "$provider bundled skill source is missing: $sourceSkills"
      continue
    }

    # Native-plugin installs intentionally remove exact duplicate skill copies
    # from a provider's ~/skills tree. Account for only the names the installer
    # itself recorded as deduped after a successful native plugin install. This
    # keeps duplicate definitions out while making unexplained omissions fatal.
    $nativeDeduped=New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)
    if($state -and $state.native_plugins){
      $providerState=$state.native_plugins.PSObject.Properties[$provider]
      if($providerState -and $providerState.Value.plugins){
        foreach($pluginProp in $providerState.Value.plugins.PSObject.Properties){
          $pluginState=$pluginProp.Value
          if($pluginState.native -eq $true){
            foreach($name in @($pluginState.deduped)){
              if($name){[void]$nativeDeduped.Add([string]$name)}
            }
          }
        }
      }
    }

    $expectedSkills=@(Get-ChildItem -LiteralPath $sourceSkills -Directory -ErrorAction Stop | Where-Object {
      Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') -PathType Leaf
    })
    if($expectedSkills.Count -eq 0){Err "$provider bundled skill source contains zero skills.";continue}

    $verified=0
    $nativeOwned=0
    foreach($skillDir in $expectedSkills){
      $skill=$skillDir.Name
      $src=Join-Path $skillDir.FullName 'SKILL.md'
      $dst=Join-Path $destSkills ("$skill\SKILL.md")
      if(Test-Path -LiteralPath $dst -PathType Leaf){
        $srcHash=(Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash
        $dstHash=(Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash
        if($srcHash -ne $dstHash){Err "$provider bundled skill is stale/modified: $skill";continue}
        $verified++
        continue
      }
      if($nativeDeduped.Contains($skill)){
        $nativeOwned++
        continue
      }
      Err "$provider missing bundled skill with no native-plugin ownership record: $skill"
    }
    Write-V5Ok ("$provider bundled skills accounted: $verified exact file(s), $nativeOwned native-plugin-owned, $($expectedSkills.Count) expected.")

    # Codex budgets its skills index in CHARACTERS, scaled to the model's
    # context window, and degrades in two stages -- the first one silent:
    #
    #   over budget      every description is truncated to a per-entry
    #                    allowance. The list still looks complete.
    #   far over budget  descriptions removed and entries dropped outright
    #                    ("Exceeded skills context budget..."), the message
    #                    7.9.7 caught.
    #
    # Measured with `codex debug prompt-input` against throwaway CODEX_HOMEs:
    # 146 bundle skills alone render at ~88 visible chars per description (142
    # of the 146 are written longer than that); 60 skills render at ~183 with
    # nothing truncated. Cutting every raw description to 60 chars did NOT give
    # anyone more room -- the rendered total just shrank. The allowance follows
    # entry COUNT, so shortening descriptions is not the lever, and this pack
    # routes by description.
    #
    # The doctor cannot raise the budget. It can stop the silent stage being
    # invisible and name the levers that actually move it.
    if($provider -eq 'Codex'){
      $indexCount=0
      foreach($d in @(Get-ChildItem -LiteralPath $destSkills -Directory -ErrorAction SilentlyContinue)){
        $file=Join-Path $d.FullName 'SKILL.md'
        if(-not(Test-Path -LiteralPath $file -PathType Leaf)){continue}
        $head=''
        try{ $head=(Get-Content -LiteralPath $file -TotalCount 40 -ErrorAction Stop) -join "`n" }catch{ continue }
        $m=[regex]::Match($head,'(?ms)^description:[ 	]*(?<d>.*?)(?=^[A-Za-z_-]+:|^---)')
        if(-not $m.Success){continue}
        $indexCount++
      }
      # ~100 entries is roughly where descriptions stop being truncated. Past
      # that the per-entry allowance shrinks in proportion to the count.
      # Whether to WARN depends on whether anything is removable, not on the
      # raw count. This pack ships 146 skills, so a bare "> 100" fired on every
      # correct install and then advised deleting an optional mega-pack, stale
      # duplicates and unused plugins -- none of which exist on a clean one.
      # Telling a user to remove things that are not there is noise, and noise
      # is how a real warning gets ignored.
      $extraEntries = $indexCount - $expectedSkills.Count
      if($extraEntries -gt 10){
        Warn ("Codex skills index is $indexCount entries, $extraEntries of them not from this pack. Codex splits a character budget evenly across entries, so every description is truncated -- and this pack routes by description.")
        Warn ("  Shortening descriptions does NOT help: the allowance follows entry COUNT. Measured -- cutting every description to 60 chars gave no entry more room.")
        Warn ("  Fewer entries does: 146 skills render at ~88 chars each, 60 skills at ~183 untruncated. Candidates in ${destSkills}:")
        Warn ("    - the OPTIONAL Other-Games mega-pack (70 skills). A manual extra; INSTALL-V7-AIO.ps1 never deploys it.")
        Warn ("    - superseded duplicates such as skyrim-kid-distribution / skyrim-spid-distribution (now kid-authoring / spid-authoring)")
        Warn ("    - skills from Codex plugins you do not use; each costs a full entry")
        Warn ("  Reproduce any of this with: codex debug prompt-input")
      } elseif($indexCount -gt 100){
        Write-V5Ok ("Codex skills index: $indexCount entries, essentially all from this pack. Descriptions are truncated to roughly 88 chars each -- structural at this skill count, and nothing here is removable without losing a skill.")
      } else {
        Write-V5Ok ("Codex skills index: $indexCount entries -- inside the range where descriptions survive intact.")
      }
    }
  }
}
if(-not $SkipForge){
  $forge=[Environment]::GetEnvironmentVariable('SKYRIM_FORGE_ROOT','User'); if(-not $forge){$forge=$env:SKYRIM_FORGE_ROOT}
  if(-not $forge -or -not(Test-Path -LiteralPath $forge -PathType Container)){Err 'SKYRIM_FORGE_ROOT missing after bundled Forge install.'}
  else{
    $py=Join-Path $forge '.venv\Scripts\python.exe'
    if(-not(Test-Path -LiteralPath $py -PathType Leaf)){Err 'Forge venv Python missing.'}
    else{
      # Forge 6 is developed in this repository and intentionally removed the
      # old cross-repository version-handshake command. Prove the installed copy
      # is runnable and read-only ready with the same health contract used by
      # Install-SkyrimForge.ps1.
      $prevEap=$ErrorActionPreference; $ErrorActionPreference='Continue'
      $forgeDoctorRaw = (& $py -m skyrim_forge doctor 2>&1 | Out-String)
      $ErrorActionPreference=$prevEap
      $forgeDoctorExit = $LASTEXITCODE
      if($forgeDoctorExit -ne 0){
        Err "Forge doctor failed with exit code $forgeDoctorExit. $($forgeDoctorRaw.Trim())"
      } else {
        try {
          $forgeDoctor = $forgeDoctorRaw | ConvertFrom-Json
          if($forgeDoctor.result -ne 'PASS'){Err "Forge doctor result=$($forgeDoctor.result), expected PASS."}
          if(-not $forgeDoctor.read_only_ready){Err 'Forge doctor reports read_only_ready=false.'}
        } catch {
          Err ('Forge doctor output is unreadable JSON: '+$_.Exception.Message)
        }
      }
    }
  }
}
# ---------------------------------------------------------------------------
# Capability states. "Installed" is the least informative thing the doctor can
# say about an MCP server, and until 7.9.9 it was the only thing it said.
# Registered-but-useless and installed-but-deliberately-unregistered look
# identical from the outside; they are opposite situations.
$capabilityStates = @()
$capRecordDir = Join-Path $PackRoot 'BUNDLED-TOOLS\capability-records'
try { $capCatalog = Get-V5Catalog } catch { $capCatalog = $null }
try { $mcpTargets = Get-V5McpTargets } catch { $mcpTargets = @{} }
if ($capCatalog) {
  foreach ($comp in @($capCatalog.components | Where-Object { $_.mcp })) {
    # $capState, not $state: $state holds the parsed install-state.json that
    # earlier checks read. Reusing the name worked only because this block runs
    # last, and PowerShell's case-insensitive variables leave no $State escape.
    $cid = [string]$comp.id
    # The MCP entry is not always named after the catalog component:
    # codebase-memory registers as codebase-memory-mcp, github-mcp-server as
    # github. Declared in the catalog, because a guessed alias reports a
    # capability absent on a machine that has it.
    $sid = if ($comp.server_id) { [string]$comp.server_id } else { $cid }
    $capState = [ordered]@{
      component = $cid
      key_env = [string]$comp.api_key_env
      # What the installer RECORDED, not a guess derived from registration.
      # This field used to be (registered -or credentialled), which is the
      # conflation this release exists to remove -- and for an mcp-npx
      # component nothing is installed at all until npx resolves it on first
      # launch, so a boolean here would be false either way.
      install_state = 'unknown'
      registered_for = @()
      keyless_tools = @()
      credentialled = $false
      schema_bytes = $null
      tools_total = $null
      not_registered_because = $null
    }

    # CREDENTIALLED: presence only. The doctor never reads a key's value.
    if ($comp.api_key_env) {
      $kv = [Environment]::GetEnvironmentVariable([string]$comp.api_key_env, 'User')
      if (-not $kv) { $kv = [Environment]::GetEnvironmentVariable([string]$comp.api_key_env, 'Process') }
      $capState.credentialled = [bool]$kv
    }

    # KEYLESS-CAPABLE + SCHEMA COST: from the generated record, never by hand.
    $rec = Join-Path $capRecordDir ($cid + '.json')
    if (Test-Path -LiteralPath $rec -PathType Leaf) {
      try {
        $r = [IO.File]::ReadAllText($rec) | ConvertFrom-Json
        # @($r.keyless) on a record with no keyless field is Count=1 holding
        # $null, which prints as "1 keyless" -- a confident false capability
        # count from a truncated or older-format record.
        $capState.keyless_tools = @($r.keyless_capable | Where-Object { $_ })
        if (-not $capState.keyless_tools.Count) {
          $capState.keyless_tools = @($r.keyless | Where-Object { $_ })
        }
        $capState.schema_bytes = $r.schema_bytes
        $capState.tools_total = $r.tools
      } catch { }
    }
    # Only explain a skip that actually happened. Without the registered_for
    # guard a machine carrying a pre-7.9.9 registration printed "registered:
    # Claude,Codex,Grok,Kimi" and "registered only with a key" three lines apart.

    # REGISTERED: which provider configs actually name it. Test-V5ServerDeclared
    # takes a resolved config target, not a provider name -- calling it with
    # -Provider throws, and a swallowed throw here reports "registered: none"
    # for a machine where everything is registered. Resolve the target first,
    # and let Hermes use its own YAML-shaped check.
    foreach ($prov in @('Claude','Codex','Grok','Kimi','Hermes')) {
      try {
        if ($prov -eq 'Hermes') {
          if (Test-V5HermesServerDeclared -Id $sid) { $capState.registered_for += $prov }
          continue
        }
        $tgt = $mcpTargets[$prov]
        if (-not $tgt) { continue }
        if (Test-V5ServerDeclared -Path $tgt.Path -Style $tgt.Style -Section $tgt.Section -Id $sid) {
          $capState.registered_for += $prov
        }
      } catch { }
    }
    if ($state -and $state.components) {
      $rec = $state.components.PSObject.Properties[$cid]
      if ($rec -and $rec.Value.status) { $capState.install_state = [string]$rec.Value.status }
    }

    if ($comp.keyless_registration -eq 'skip' -and -not $capState.credentialled -and
        -not $capState.registered_for.Count) {
      $capState.not_registered_because = [string]$comp.keyless_skip_reason
    }

    $capabilityStates += $capState
  }
}

if ($capabilityStates.Count) {
  # "registered" here means the MACHINE-WIDE config names it. Capability
  # profiles are project-scoped by design (7.9.6), so a profile enabled for one
  # project correctly shows as not registered machine-wide. Say so, rather than
  # let the column read as "this capability is absent".
  Write-Host '     registered = machine-wide config only; project-scoped profiles: Set-McpProfile.ps1 -List' -ForegroundColor DarkGray
  foreach ($s in $capabilityStates) {
    $reg = if ($s.registered_for.Count) { ($s.registered_for -join ',') } else { 'none' }
    $kl  = if ($s.keyless_tools.Count) { "$($s.keyless_tools.Count) keyless" } else { 'keyless unmeasured' }
    $cost = if ($s.schema_bytes) { "$([math]::Round($s.schema_bytes/4)) tok/turn" } else { 'cost unmeasured' }
    $cred = if ($s.credentialled) { 'key set' } else { 'no key' }
    Write-V5Ok ("{0,-16} registered: {1,-22} {2}, {3}, {4}" -f $s.component, $reg, $kl, $cred, $cost)
    if ($s.not_registered_because) {
      Write-Host ("     " + $s.not_registered_because) -ForegroundColor DarkGray
    }
    # Registered, no key, and only a sliver of it works keyless: the machine is
    # paying full schema price on every turn for a fraction of the server. An
    # earlier -WithExtras run could have done this before 7.9.9 stopped it.
    # Tell, do not edit -- the same rule sequential-thinking got in 7.9.7. A
    # server someone chose does not vanish because a measurement went the other
    # way, but they should be able to see what it costs.
    if ($s.registered_for.Count -and -not $s.credentialled -and
        $s.keyless_tools.Count -and $s.schema_bytes -and $s.tools_total -and
        ($s.keyless_tools.Count * 4) -lt $s.tools_total) {
      $perTurn = [math]::Round($s.schema_bytes / 4)
      Write-Host ("     $($s.component) is registered on $($s.registered_for.Count) provider(s) with no key: ~$perTurn tokens every turn for $($s.keyless_tools.Count) of its $($s.tools_total) tools.") -ForegroundColor DarkGray
      Write-Host ("     Nothing here removed it. Keep it, set $($s.key_env) to unlock the rest, or drop the entry from those configs.") -ForegroundColor DarkGray
    }
  }
}

$doctorResult = if ($errors.Count) { 'FAIL' } else { 'PASS' }
$report=[ordered]@{version=$packBare;checked_utc=[DateTime]::UtcNow.ToString('o');errors=@($errors);warnings=@($warnings);capability_states=@($capabilityStates);result=$doctorResult}
$reportPath=Join-Path $env:LOCALAPPDATA 'Skyrim-AI-V5\installed-state-doctor.json'
$enc=New-Object System.Text.UTF8Encoding($false); [IO.File]::WriteAllText($reportPath,($report|ConvertTo-Json -Depth 8),$enc)
if($errors.Count){Write-V5Bad ("Installed-state doctor FAIL ($($errors.Count) error(s)). Report: $reportPath");exit 1}
Write-V5Ok ("Installed-state doctor PASS. Report: $reportPath")
exit 0
