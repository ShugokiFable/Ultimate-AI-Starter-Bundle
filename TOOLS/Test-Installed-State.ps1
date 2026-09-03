<#
.SYNOPSIS
  Final fail-closed installed-state doctor for Ultimate AI Starter Bundle.
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
. (Join-Path $PackRoot 'TOOLS\UABS-Common.ps1')
# Join-Path, not Join-UabsPath: the helper lives inside the file being sourced.
# Needed for Test-UabsServerDeclared in the capability-state section -- without it
# every component reports "registered: none", which is a wrong answer rather
# than a visible failure.
. (Join-Path $PackRoot 'TOOLS\UABS-Mcp-Write.ps1')
$Providers = @($Providers | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$catalog = Get-UabsCatalog
$state = $null
$rtkRuntime = $null
$errors = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
function Err([string]$m){ [void]$errors.Add($m); Write-UabsBad $m }
function Warn([string]$m){ [void]$warnings.Add($m); Write-UabsWarn $m }
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
Write-UabsStep 'Final installed-state doctor'
# VERSION.txt is the one source. The doctor used to restate 7.8.0 in four
# places, so a release bump could leave the doctor failing a correct install.
$packVersion = [IO.File]::ReadAllText((Join-Path $PackRoot 'VERSION.txt')).Trim()
$packBare = $packVersion.TrimStart('v','V')
# Three or more parts. v7.9.8.5 was the pack's first four-part version, and it
# widened check_versions.py and test_version_sources but not this gate -- so the
# doctor failed the release that shipped it, on a correct tree. A version format
# is agreed by every check that reads it or by none of them.
if ($packBare -notmatch '^\d+(\.\d+){2,}$') { Err "Pack VERSION.txt is not a dotted version of three or more parts: $packVersion" }
$statePath=Join-Path $env:LOCALAPPDATA 'Ultimate-AI-Starter-Bundle\install-state.json'
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

# A path can be exactly where the installer recorded it and still contain the
# wrong release. This happened when GitHub reused RTK's asset filename: an old
# cache archive was accepted by size alone and copied over the newer offline
# payload. Bind the executable that actually wins on PATH to CATALOG's version.
$rtkComponent = @($catalog.components | Where-Object { $_.id -eq 'rtk' }) | Select-Object -First 1
$rtkInstalled = $null
if ($state -and $state.components) {
  $rtkProperty = $state.components.PSObject.Properties['rtk']
  if ($rtkProperty) { $rtkInstalled = $rtkProperty.Value }
}
if ($rtkComponent -and $rtkInstalled) {
  $rtkCommand = Get-Command rtk -ErrorAction SilentlyContinue
  if (-not $rtkCommand -or -not $rtkCommand.Source) {
    Err 'rtk is recorded as installed but does not resolve on PATH.'
  } else {
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
      $rtkVersionText = (& $rtkCommand.Source --version 2>&1 | Out-String).Trim()
      $rtkVersionExit = $LASTEXITCODE
    } finally { $ErrorActionPreference = $prevEap }
    $rtkVersionMatch = [regex]::Match($rtkVersionText, '(?im)^rtk\s+([0-9]+(?:\.[0-9]+){2,})\s*$')
    $rtkActual = if ($rtkVersionMatch.Success) { $rtkVersionMatch.Groups[1].Value } else { $null }
    $rtkRuntime = [ordered]@{ path = $rtkCommand.Source; version = $rtkActual; expected = [string]$rtkComponent.version }
    if ($rtkVersionExit -ne 0 -or -not $rtkActual) {
      Err "rtk failed its active --version check: $rtkVersionText"
    } elseif ($rtkActual -ne [string]$rtkComponent.version) {
      Err "active rtk version is $rtkActual, expected $($rtkComponent.version): $($rtkCommand.Source)"
    } else {
      Write-UabsOk "RTK active version $rtkActual matches CATALOG: $($rtkCommand.Source)"
    }
  }
}
if(-not $SkipSkills){
  foreach($provider in $Providers){
    $exe=Resolve-Exe $provider
    if(-not $exe){Err "$provider executable missing after provider bootstrap.";continue}
    # Hermes 0.21's --version performs an upstream git fetch. A local doctor
    # must not become a network health check (or wait minutes when GitHub is
    # slow), so use its local argparse help path as the executable probe.
    # Provider launchers can emit harmless warnings on stderr (Codex does when
    # CODEX_HOME is under TEMP). Under Stop that becomes a terminating
    # NativeCommandError before the exit code can be checked.
    $prevEap=$ErrorActionPreference; $ErrorActionPreference='Continue'
    if ($provider -eq 'Hermes') {
      & $exe --help 2>&1 | Out-Null
    } else {
      & $exe --version 2>&1 | Out-Null
    }
    $versionExit=$LASTEXITCODE
    $ErrorActionPreference=$prevEap
    if($versionExit -ne 0){Err "$provider executable failed its local startup probe."}

    # PowerShell variable names are case-insensitive; $HOME is a read-only
    # automatic variable on Windows PowerShell 5.1. Never use $home as a local.
    $providerHome=Get-UabsProviderHome -Provider $provider -Catalog $catalog
    if (-not $providerHome) { Err "$provider provider home could not be resolved."; continue }
    $destSkills=Get-UabsProviderSkillsDir -Provider $provider -Catalog $catalog
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

    # Codex additionally owns skills under <CodexHome>\skills\.system. Discover
    # the live set instead of trusting old install state: if Codex removes a
    # built-in later, the matching pack copy is installed again on the next run.
    $builtinDeduped=New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)
    if($provider -eq 'Codex'){
      foreach($name in @(Get-UabsCodexBuiltinSkillNames -CodexHome $providerHome)){
        if($name){[void]$builtinDeduped.Add([string]$name)}
      }
    }

    $expectedSkills=@(Get-ChildItem -LiteralPath $sourceSkills -Directory -ErrorAction Stop | Where-Object {
      Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') -PathType Leaf
    })
    if($expectedSkills.Count -eq 0){Err "$provider bundled skill source contains zero skills.";continue}

    $verified=0
    $nativeOwned=0
    $builtinOwned=0
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
      if($builtinDeduped.Contains($skill)){
        $builtinOwned++
        continue
      }
      Err "$provider missing bundled skill with no native-plugin ownership record: $skill"
    }
    $ownedNote=''
    if($builtinOwned){ $ownedNote=", $builtinOwned owned by Codex itself" }
    Write-UabsOk ("$provider bundled skills accounted: $verified exact file(s), $nativeOwned native-plugin-owned$ownedNote, $($expectedSkills.Count) expected.")

    # Codex renders its skills index into a FIXED block of roughly 22.3 KB and
    # splits it across every entry. Each entry costs its name plus its file path
    # BEFORE it describes anything, so at high entry counts almost the whole
    # budget is paths and the descriptions collapse.
    #
    # Measured with `codex debug prompt-input` against throwaway CODEX_HOMEs,
    # one variable changed per run:
    #
    #   entries   median visible description
    #   151       80 chars
    #   166       68
    #   181       56
    #   196       40
    #   223       32
    #   255       16
    #
    # At 16 chars every description reads like "Use when buildin" and Codex is
    # routing on skill NAMES alone. Shortening descriptions does NOT help: the
    # allowance follows entry COUNT, and cutting every description to 60 chars
    # measurably gave no entry more room.
    #
    # DO NOT re-derive the index by walking plugins\cache. Codex indexes only
    # the plugins ENABLED in config.toml, and the cache also holds marketplaces
    # that were never enabled, backup copies of upgraded plugins, and payload
    # directories meant for other tools (ponytail ships an .openclaw\skills).
    # Counting the whole cache reported 319 entries on this machine when Codex
    # was actually indexing 197 -- a warning that told the user their
    # descriptions had collapsed to 16 chars while they were really at 42.
    #
    # So ask Codex. `codex debug prompt-input` emits the exact block the model
    # receives; the entry count and the visible description width are then
    # measured rather than estimated.
    if($provider -eq 'Codex'){
      $indexCount=0; $packCount=0; $medianWidth=0; $dupes=@(); $measured=$false
      $codexExe=Resolve-Exe 'Codex'
      if($codexExe){
        $prompt=''
        try{
          $prevEap=$ErrorActionPreference; $ErrorActionPreference='Continue'
          try{ $prompt=(& $codexExe 'debug' 'prompt-input' 2>&1 | Out-String) } finally { $ErrorActionPreference=$prevEap }
        }catch{ $prompt='' }
        # The block is JSON-encoded inside the developer message, so its line
        # breaks are the two characters \n rather than real newlines.
        $block=''
        $m=[regex]::Match($prompt,'### Available skills(?<body>.*?)</skills_instructions>',[Text.RegularExpressions.RegexOptions]::Singleline)
        if($m.Success){ $block=$m.Groups['body'].Value }
        if($block){
          $rootMap=@{}
          foreach($rm in [regex]::Matches($prompt,'- `(?<r>r\d+)` = `(?<p>[^`]+)`')){
            $rootMap[$rm.Groups['r'].Value]=$rm.Groups['p'].Value
          }
          $packRootIds=@($rootMap.Keys | Where-Object {
            $rootMap[$_].Replace('/','\').TrimEnd('\') -ieq $destSkills.TrimEnd('\')
          })
          $widths=New-Object System.Collections.Generic.List[int]
          $packNames=New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)
          $entries=@()
          # The name pattern must exclude spaces and parens. A loose one lets
          # the optional `plugin:` half swallow "imagegen: Generate ... (file",
          # after which the description runs on into the NEXT entry -- measured
          # 113 entries of 97 chars where the truth was 197 of 42. The (?!\\n)
          # guard makes spanning structurally impossible even if a future name
          # character sneaks past the class.
          foreach($em in [regex]::Matches($block,'\\n- (?<name>[A-Za-z0-9][A-Za-z0-9._-]*(?::[A-Za-z0-9][A-Za-z0-9._-]*)?): (?:(?<desc>(?:(?!\\n).)*?) )?\(file: (?<root>r\d+)/')){
            $entries += ,@($em.Groups['name'].Value, $em.Groups['desc'].Value, $em.Groups['root'].Value)
          }
          if($entries.Count){
            $measured=$true
            $indexCount=$entries.Count
            foreach($e in $entries){
              [void]$widths.Add($e[1].Length)
              if($packRootIds -contains $e[2]){ $packCount++; [void]$packNames.Add($e[0]) }
            }
            foreach($e in $entries){
              if($packRootIds -contains $e[2]){ continue }
              $leaf=$e[0].Substring($e[0].LastIndexOf(':')+1)
              if($packNames.Contains($leaf)){ $dupes+=$e[0] }
            }
            $sorted=@($widths | Sort-Object)
            $medianWidth=$sorted[[int][math]::Floor($sorted.Count/2)]
          }
        }
      }
      if(-not $measured){
        # Fallback only: Codex could not be asked. Count the pack tree plus the
        # system root plus the cached payload of the plugins config.toml
        # actually enables, and say plainly that the width is an estimate.
        $roots=@($destSkills,(Join-Path $destSkills '.system'))
        $cacheRoot=Join-Path $providerHome 'plugins\cache'
        foreach($id in @(Get-UabsCodexEnabledPluginIds -CodexHome $providerHome)){
          $parts=$id.Split('@'); if($parts.Count -ne 2){continue}
          $pluginDir=Join-Path $cacheRoot ($parts[1]+'\'+$parts[0])
          if(-not(Test-Path -LiteralPath $pluginDir -PathType Container)){continue}
          foreach($ver in @(Get-ChildItem -LiteralPath $pluginDir -Directory -EA SilentlyContinue)){
            $sk=Join-Path $ver.FullName 'skills'
            if(Test-Path -LiteralPath $sk -PathType Container){$roots+=$sk}
          }
        }
        foreach($root in $roots){
          if(-not(Test-Path -LiteralPath $root -PathType Container)){continue}
          foreach($d in @(Get-ChildItem -LiteralPath $root -Directory -EA SilentlyContinue)){
            $file=Join-Path $d.FullName 'SKILL.md'
            if(-not(Test-Path -LiteralPath $file -PathType Leaf)){continue}
            $head=''
            try{ $head=([IO.File]::ReadAllText($file)) }catch{ continue }
            if(-not [regex]::IsMatch($head,'(?ms)^description:[ \t]*(?<d>.*?)(?=^[A-Za-z_-]+:|^---)')){continue}
            $indexCount++
            if($root -eq $destSkills){$packCount++}
          }
        }
        $curve=@(
          @{ n=151; d=80 }, @{ n=166; d=68 }, @{ n=181; d=56 },
          @{ n=196; d=40 }, @{ n=223; d=32 }, @{ n=255; d=16 }
        )
        $near=$curve[0]
        foreach($p in $curve){ if([math]::Abs($p.n-$indexCount) -lt [math]::Abs($near.n-$indexCount)){$near=$p} }
        $medianWidth=$near.d
      }
      $foreign=$indexCount-$packCount
      $how='measured'
      if(-not $measured){ $how='estimated from the nearest measured point (codex CLI could not be asked)' }
      $detail="Codex skills index: $indexCount entries ($packCount from this pack, $foreign from Codex itself and enabled plugins); $medianWidth visible description chars, $how."
      $script:codexSkillIndex=[ordered]@{entries=$indexCount;from_pack=$packCount;from_elsewhere=$foreign;visible_description_chars=$medianWidth;measured=$measured;duplicates=@($dupes)}

      if($dupes.Count){
        $shown=[string]::Join(', ',@($dupes|Select-Object -First 6))
        if($dupes.Count -gt 6){ $shown=$shown+' ...' }
        Warn "Codex indexes $($dupes.Count) skill(s) twice -- this pack copied them and an enabled plugin, or Codex's own .system set, also serves its own: $shown"
        Warn "  Each duplicate costs an index entry and narrows every other description. Re-run the installer; it dedupes copies a native plugin OR Codex itself owns."
        Warn "  If duplicates survive that, Codex's plugin inventory is unreadable. Repair it with: codex plugin marketplace upgrade <name>"
      }
      # Only two things here are actionable, and only those two warn: the
      # duplicates above (the pack's own fault, fixed by the installer) and a
      # genuinely collapsed width. Between 32 and 56 chars the index is merely
      # narrow, and the only remaining lever is the user's own plugin choices.
      # Warning about a state the user cannot clear teaches them to skip
      # warnings, so that band is reported as a note instead.
      if($medianWidth -lt 32){
        Warn $detail
        Warn "  At this width descriptions read like 'Use when buildin' and Codex routes on skill NAMES alone."
        Warn "  Shortening descriptions does NOT help -- the allowance follows entry COUNT. What does:"
        Warn "    - run the installer; TOOLS\Clean-StaleState.ps1 removes retired and absorbed skills automatically"
        Warn "    - remove Codex plugins you do not use; each contributes its whole skill set"
        Warn "  Reproduce with: codex debug prompt-input"
      } else {
        Write-UabsOk $detail
        if($medianWidth -lt 56){
          Write-Host '     Descriptions are short but still carry their leading clause. Each enabled Codex plugin adds its whole skill set; removing one you do not use is the only lever that costs no skill.' -ForegroundColor DarkGray
          Write-Host '     Reproduce with: codex debug prompt-input' -ForegroundColor DarkGray
        }
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
try { $capCatalog = Get-UabsCatalog } catch { $capCatalog = $null }
try { $mcpTargets = Get-UabsMcpTargets } catch { $mcpTargets = @{} }
$projectScopedMcp = @{}
$profileStatePath = Join-Path (Split-Path -Parent $statePath) 'mcp-profiles.json'
if (Test-Path -LiteralPath $profileStatePath -PathType Leaf) {
  try {
    $profileState = [IO.File]::ReadAllText($profileStatePath) | ConvertFrom-Json
    foreach ($profileProp in $profileState.profiles.PSObject.Properties) {
      $profileId = [string]$profileProp.Name
      foreach ($projectProp in $profileProp.Value.projects.PSObject.Properties) {
        $record = $projectProp.Value
        foreach ($serverId in @($record.servers | Where-Object { $_ })) {
          $serverId = [string]$serverId
          if (-not $projectScopedMcp.ContainsKey($serverId)) { $projectScopedMcp[$serverId] = @() }
          foreach ($provider in @($record.providers | Where-Object { $_ })) {
            $projectScopedMcp[$serverId] += ('{0}/{1}' -f $provider, $profileId)
          }
        }
      }
    }
  } catch { }
}
$hermesHomeRoot = if ($env:HERMES_HOME) { $env:HERMES_HOME } else { Join-Path $env:LOCALAPPDATA 'hermes' }
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
      scoped_for = @()
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

    # REGISTERED: which provider configs actually name it. Test-UabsServerDeclared
    # takes a resolved config target, not a provider name -- calling it with
    # -Provider throws, and a swallowed throw here reports "registered: none"
    # for a machine where everything is registered. Resolve the target first,
    # and let Hermes use its own YAML-shaped check.
    foreach ($prov in @('Claude','Codex','Grok','Kimi','Hermes')) {
      try {
        if ($prov -eq 'Hermes') {
          if (Test-UabsHermesServerDeclared -Id $sid) { $capState.registered_for += $prov }
          continue
        }
        $tgt = $mcpTargets[$prov]
        if (-not $tgt) { continue }
        if (Test-UabsServerDeclared -Path $tgt.Path -Style $tgt.Style -Section $tgt.Section -Id $sid) {
          $capState.registered_for += $prov
        }
      } catch { }
    }
    if ($projectScopedMcp.ContainsKey($sid)) {
      $capState.scoped_for += @($projectScopedMcp[$sid])
    }
    $hermesProfilesRoot = Join-Path $hermesHomeRoot 'profiles'
    if (Test-Path -LiteralPath $hermesProfilesRoot -PathType Container) {
      foreach ($profileDir in @(Get-ChildItem -LiteralPath $hermesProfilesRoot -Directory -ErrorAction SilentlyContinue)) {
        $profileCfg = Join-Path $profileDir.FullName 'config.yaml'
        if (-not (Test-Path -LiteralPath $profileCfg -PathType Leaf)) { continue }
        try {
          $yaml = [IO.File]::ReadAllText($profileCfg)
          $mcpBlock = [regex]::Match($yaml, '(?ms)^mcp_servers:\s*\r?\n(?<body>(?:^[ \t].*(?:\r?\n|$))*)')
          $serverLine = '(?m)^  ["'']?' + [regex]::Escape($sid) + '["'']?:\s*$'
          if ($mcpBlock.Success -and $mcpBlock.Groups['body'].Value -match $serverLine) {
            $capState.scoped_for += ('Hermes/' + $profileDir.Name)
          }
        } catch { }
      }
    }
    $capState.scoped_for = @($capState.scoped_for | Where-Object { $_ } | Select-Object -Unique)
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
  Write-Host '     registered = machine-wide; scoped = project or Hermes named profile' -ForegroundColor DarkGray
  foreach ($s in $capabilityStates) {
    $reg = if ($s.registered_for.Count) { ($s.registered_for -join ',') } else { 'none' }
    $scoped = if ($s.scoped_for.Count) { '; scoped: ' + ($s.scoped_for -join ',') } else { '' }
    $kl  = if ($s.keyless_tools.Count) { "$($s.keyless_tools.Count) keyless" } else { 'keyless unmeasured' }
    $cost = if ($s.schema_bytes) { "$([math]::Round($s.schema_bytes/4)) tok/turn" } else { 'cost unmeasured' }
    $cred = if ($s.credentialled) { 'key set' } else { 'no key' }
    Write-UabsOk ("{0,-16} registered: {1,-22} {2}, {3}, {4}{5}" -f $s.component, $reg, $kl, $cred, $cost, $scoped)
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

# ---- Hermes profile tool budgets -------------------------------------------
# Hermes filters MCP servers at the individual-TOOL level (tools.include /
# tools.exclude, enforced at registration), which no other provider here can do.
# It is also completely invisible: `hermes mcp test` reports what the SERVER
# advertises, not what Hermes registers. Show what each profile actually costs.
$hermesBudgets = @()
if ($Providers -contains 'Hermes' -and (Test-Path -LiteralPath (Join-Path $hermesHomeRoot 'config.yaml') -PathType Leaf)) {
  $budgetCatalog = @{}
  if ($capCatalog) {
    foreach ($comp in @($capCatalog.components | Where-Object { $_.mcp_tool_budget })) {
      $budgetCatalog[[string]$comp.id] = $comp.mcp_tool_budget
    }
  }
  foreach ($profileName in @('default', 'code', 'roblox', 'skyrim')) {
    $profileCfg = if ($profileName -eq 'default') {
      Join-Path $hermesHomeRoot 'config.yaml'
    } else {
      Join-Path $hermesHomeRoot ('profiles\' + $profileName + '\config.yaml')
    }
    if (-not (Test-Path -LiteralPath $profileCfg -PathType Leaf)) { continue }
    $yaml = [IO.File]::ReadAllText($profileCfg)
    foreach ($sid in $budgetCatalog.Keys) {
      # Cheap YAML slice rather than a parser: take the server's block and look
      # for a tools: filter inside it. PS 5.1 has no YAML reader and adding one
      # to a doctor that must never fail on a malformed config is not worth it.
      $blockMatch = [regex]::Match($yaml, "(?ms)^  " + [regex]::Escape($sid) + ":\r?\n(.*?)(?=^  \S|^\S|\Z)")
      if (-not $blockMatch.Success) { continue }
      $block = $blockMatch.Groups[1].Value
      $budget = $budgetCatalog[$sid]
      $allTools = [int]$budget.all_tools
      $names = @([regex]::Matches($block, "(?m)^\s+-\s+(" + [regex]::Escape($sid) + "_\S+)\s*$") |
                 ForEach-Object { $_.Groups[1].Value })
      $mode = 'Full'
      if ($block -match '(?m)^\s+include:\s*$') { $mode = 'include' }
      elseif ($block -match '(?m)^\s+exclude:\s*$') { $mode = 'exclude' }

      # Match the live filter against the DECLARED sets and report that set's
      # recorded measurement. Never compute one from a per-tool average: the
      # sets exist precisely because schema size is wildly uneven (three of
      # houseCARL's 45 tools are a quarter of its bytes), so an average is not
      # an approximation, it is a wrong answer with a confident format.
      $setName = $null; $tokens = $null; $activeTools = $null
      if ($mode -eq 'Full') {
        $setName = 'Full'; $tokens = [int]$budget.all_tokens_per_turn; $activeTools = $allTools
      } else {
        $sorted = @($names | Sort-Object)
        foreach ($candidate in $budget.sets.PSObject.Properties) {
          $set = $candidate.Value
          $declared = @(if ($mode -eq 'include') { $set.include } else { $set.exclude }) | Where-Object { $_ }
          if (-not $declared.Count) { continue }
          if ((@($declared | Sort-Object) -join '|') -eq ($sorted -join '|')) {
            $setName = $candidate.Name
            $tokens = [int]$set.tokens_per_turn
            $activeTools = [int]$set.tools
            break
          }
        }
        if (-not $setName) {
          # A hand-picked selection. Report the shape, refuse to price it.
          $setName = 'custom'
          $activeTools = if ($mode -eq 'include') { $names.Count } else { $allTools - $names.Count }
        }
      }
      $hermesBudgets += [ordered]@{
        profile = $profileName; server = $sid; filter = $mode; set = $setName
        tools_active = $activeTools; tools_total = $allTools
        approx_tokens_per_turn = $tokens
        full_tokens_per_turn = [int]$budget.all_tokens_per_turn
      }
    }
  }
}
if ($hermesBudgets.Count) {
  Write-Host ''
  Write-UabsStep 'Hermes profile tool budgets'
  foreach ($b in $hermesBudgets) {
    $cost = if ($null -ne $b.approx_tokens_per_turn) { "~$($b.approx_tokens_per_turn) tok/turn" } else { 'cost unmeasured' }
    $line = "{0,-8} {1,-12} {2}/{3} tools  {4}" -f $b.profile, $b.server, $b.tools_active, $b.tools_total, $cost
    if ($b.set -eq 'Full') {
      Write-UabsWarn ($line + '  (no filter)')
      Write-Host ('     Every tool registered. Cheaper: TOOLS\Migrate-HermesProfiles.ps1 -SkyrimToolset ReadOnly -Apply') -ForegroundColor DarkGray
    } elseif ($b.set -eq 'custom') {
      Write-UabsOk ($line + '  (hand-picked selection)')
      Write-Host ('     This combination has not been measured, so no token figure is shown. Measure it: TOOLS\Measure-McpSchemaCost.ps1') -ForegroundColor DarkGray
    } else {
      Write-UabsOk ($line + ("  [{0}] full is ~{1}, saving ~{2}" -f $b.set, $b.full_tokens_per_turn, ($b.full_tokens_per_turn - $b.approx_tokens_per_turn)))
    }
  }
  Write-Host '     Figures are the recorded per-set measurement, not a per-tool average: schema size is very uneven.' -ForegroundColor DarkGray
  Write-Host '     Change the set: hermes -p skyrim mcp configure housecarl  (interactive, survives re-installs)' -ForegroundColor DarkGray
}

# ---- Hermes plugin payloads and shell hooks --------------------------------
# Two failures that are invisible from inside Hermes: a profile enabling a
# plugin whose payload it cannot reach, and a configured shell hook that was
# never consented to. Both report success everywhere and simply do nothing.
$hermesPluginIssues = @()
$hermesDiscouragedPluginIssues = @()
$discouragedHermesPlugins = @()
if ($capCatalog) {
  foreach ($comp in @($capCatalog.components | Where-Object { $_.hook_policy -eq 'off' -and $_.discouraged_provider_plugins })) {
    $providerBlock = $comp.discouraged_provider_plugins.PSObject.Properties['Hermes']
    if ($providerBlock) { $discouragedHermesPlugins += @($providerBlock.Value | ForEach-Object { [string]$_ }) }
  }
  $discouragedHermesPlugins = @($discouragedHermesPlugins | Where-Object { $_ } | Select-Object -Unique)
}
if ($Providers -contains 'Hermes' -and (Test-Path -LiteralPath (Join-Path $hermesHomeRoot 'config.yaml') -PathType Leaf)) {
  foreach ($profileName in @('default', 'code', 'roblox', 'skyrim')) {
    $pHome = if ($profileName -eq 'default') { $hermesHomeRoot } else { Join-Path $hermesHomeRoot (Join-Path 'profiles' $profileName) }
    $pCfg = Join-Path $pHome 'config.yaml'
    if (-not (Test-Path -LiteralPath $pCfg -PathType Leaf)) { continue }
    $inPlugins = $false; $inEnabled = $false; $names = @()
    foreach ($line in [IO.File]::ReadAllLines($pCfg)) {
      if ($line -match '^plugins:\s*$') { $inPlugins = $true; continue }
      if ($inPlugins -and $line -match '^\S') { $inPlugins = $false; $inEnabled = $false }
      if (-not $inPlugins) { continue }
      if ($line -match '^  enabled:\s*$') { $inEnabled = $true; continue }
      if ($inEnabled -and $line -match '^  \S') { $inEnabled = $false }
      if ($inEnabled -and $line -match '^\s+-\s+(.+?)\s*$') { $names += $Matches[1].Trim("'" + '"') }
    }
    foreach ($name in @($names | Where-Object { $discouragedHermesPlugins -contains $_ })) {
      $hermesDiscouragedPluginIssues += ('{0}: plugin ''{1}'' is enabled but its catalog hook_policy is off' -f $profileName, $name)
    }
    foreach ($name in $names) {
      $top = ([string]$name).Split(@('/', [char]92))[0]
      $userPath = Join-Path (Join-Path $pHome 'plugins') $top
      $repoPath = Join-Path $hermesHomeRoot (Join-Path 'hermes-agent' (Join-Path 'plugins' $top))
      if ((Test-Path -LiteralPath $userPath) -or (Test-Path -LiteralPath $repoPath)) { continue }
      $hermesPluginIssues += ('{0}: plugin ''{1}'' is enabled but its payload is not reachable' -f $profileName, $name)
    }
  }
}
$hermesHookIssues = @()
$hookAllowlist = Join-Path $hermesHomeRoot 'shell-hooks-allowlist.json'
$hermesCfgPath = Join-Path $hermesHomeRoot 'config.yaml'
if ($Providers -contains 'Hermes' -and (Test-Path -LiteralPath $hermesCfgPath -PathType Leaf)) {
  $approved = @()
  if (Test-Path -LiteralPath $hookAllowlist -PathType Leaf) {
    # ReadAllText, not Get-Content: on PS 5.1 Get-Content decodes as ANSI and
    # mangles any non-ASCII byte in a path. The pack gate enforces this.
    try { $approved = @(([IO.File]::ReadAllText($hookAllowlist) | ConvertFrom-Json).approvals | ForEach-Object { [string]$_.command }) } catch { $approved = @() }
  }
  # Match on the script path, not the whole command: Hermes' YAML writer wraps
  # long command strings across lines, so a literal comparison misses them.
  $cfgText = [IO.File]::ReadAllText($hermesCfgPath)
  $scripts = @([regex]::Matches($cfgText, '[A-Za-z]:/[^\s"'']+?\.py') | ForEach-Object { $_.Value } | Select-Object -Unique)
  foreach ($s in $scripts) {
    if ($cfgText.IndexOf('hooks:') -lt 0) { break }
    $isApproved = $false
    foreach ($cmd in $approved) { if ($cmd -and $cmd.Replace([char]92, '/').Contains($s)) { $isApproved = $true; break } }
    if (-not $isApproved) { $hermesHookIssues += ('shell hook will NOT fire (never consented): {0}' -f (Split-Path -Leaf $s)) }
  }
}
if ($hermesPluginIssues.Count -or $hermesDiscouragedPluginIssues.Count -or $hermesHookIssues.Count) {
  Write-Host ''
  Write-UabsStep 'Hermes plugins and shell hooks'
  foreach ($m in $hermesPluginIssues) {
    Write-UabsWarn $m
    $warnings += $m
  }
  if ($hermesPluginIssues.Count) {
    Write-Host '     A cloned profile copies the enabled list, never the payload. Fix: TOOLS\Migrate-HermesProfiles.ps1 -Apply' -ForegroundColor DarkGray
  }
  foreach ($m in $hermesDiscouragedPluginIssues) {
    Write-UabsWarn $m
    $warnings += $m
  }
  if ($hermesDiscouragedPluginIssues.Count) {
    Write-Host '     Fix with backup and verification: TOOLS\Migrate-HermesProfiles.ps1 -Apply' -ForegroundColor DarkGray
  }
  foreach ($m in $hermesHookIssues) {
    Write-UabsWarn $m
    $warnings += $m
  }
  if ($hermesHookIssues.Count) {
    Write-Host '     Consent is deliberately interactive. Grant once: hermes --accept-hooks   then re-run: hermes hooks doctor' -ForegroundColor DarkGray
  }
}

# ------------------------------------ hooks that steer toward absent MCPs ---
# A session hook that TELLS an agent to use an MCP server is only correct while
# that server is registered. This pack deliberately profile-gates most of its
# MCPs, so the two conditions drift apart silently and the cost is invisible:
# the instructions are injected, the tools are not there, and the agent spends
# the turn reaching for something it cannot call.
#
# Measured on the maintainer's machine 2026-08-27: codebase-memory-mcp's own
# SessionStart hook was emitting 695 bytes of "ALWAYS use codebase-memory-mcp
# tools FIRST", naming six tools, on every startup / resume / clear / compact,
# while codebase-memory was registered on no provider at all.
#
# Reported, never rewritten. These hooks belong to the tools that installed
# them, exactly as with autostarts above.
$unregisteredMcp = @()
foreach ($cs in $capabilityStates) {
  $regCount = 0
  if ($cs.registered_for) { $regCount = @($cs.registered_for).Count }
  if ($regCount -eq 0) { $unregisteredMcp += [string]$cs.component }
}

$hookMisdirection = @()
if ($unregisteredMcp.Count) {
  $claudeSettingsPath = Join-Path $env:USERPROFILE '.claude\settings.json'
  if (Test-Path -LiteralPath $claudeSettingsPath -PathType Leaf) {
    try {
      $sj = [IO.File]::ReadAllText($claudeSettingsPath) | ConvertFrom-Json
      $hookCmds = New-Object System.Collections.Generic.List[string]
      foreach ($evt in @('SessionStart', 'SubagentStart', 'UserPromptSubmit', 'PreToolUse')) {
        $group = $null
        try { $group = $sj.hooks.$evt } catch { $group = $null }
        if (-not $group) { continue }
        foreach ($matcher in @($group)) {
          foreach ($h in @($matcher.hooks)) {
            if ($h -and $h.command) { [void]$hookCmds.Add([string]$h.command) }
          }
        }
      }
      foreach ($cmd in $hookCmds) {
        $p = $cmd.Trim()
        if ($p.StartsWith('"')) { $p = $p.Split('"')[1] }
        else { $p = $p.Split(' ')[0] }
        if ($p.StartsWith('~')) { $p = $env:USERPROFILE + $p.Substring(1) }
        $p = $p.Replace('/', '\')
        if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { continue }
        $body = ''
        try { $body = [IO.File]::ReadAllText($p) } catch { continue }
        # Only a hook that PRODUCES text can misdirect. One that merely shells
        # out to a binary and exits (like cbm's own augmenter, which its
        # comments describe as never blocking) injects nothing.
        $emitAt = -1
        $m = [regex]::Match($body, 'cat\s*<<|echo\s|printf\s|Write-Output|Write-Host')
        if ($m.Success) { $emitAt = $m.Index }
        if ($emitAt -lt 0) { continue }
        # A hook that gates itself -- a conditional early exit, so it stays
        # quiet when the server is absent -- is correct as written, and
        # flagging it would punish the fix. Only ungated emitters are reported.
        #
        # Checked across the whole body rather than the text before the first
        # print: a gate is normally invoked by piping the payload into it
        # (printf ... | gate || exit 0), and that printf is not the hook
        # speaking, it is the hook asking. Anchoring on the first print
        # construct therefore reads the guard as arriving too late.
        if ($body -match '\|\|\s*(exit\s+0|return)\b') { continue }
        foreach ($id in $unregisteredMcp) {
          if ([string]::IsNullOrWhiteSpace($id)) { continue }
          if ($body -match [regex]::Escape($id)) {
            $hookMisdirection += ('{0} injects text naming MCP ''{1}'', which is registered on no provider' -f (Split-Path -Leaf $p), $id)
          }
        }
      }
    } catch { }
  }
}

if ($hookMisdirection.Count) {
  Write-Host ''
  Write-UabsStep 'Session hooks pointing at unregistered MCP servers'
  foreach ($m in ($hookMisdirection | Select-Object -Unique)) {
    Write-UabsWarn $m
    $warnings += $m
  }
  Write-Host '     Those instructions reach the model on every session; the tools do not.' -ForegroundColor DarkGray
  Write-Host '     Either register the server for the projects that need it' -ForegroundColor DarkGray
  Write-Host '       (TOOLS\Set-McpProfile.ps1 -Auto -Path <project>)' -ForegroundColor DarkGray
  Write-Host '     or gate the hook so it stays quiet when the server is absent.' -ForegroundColor DarkGray
  Write-Host '     This pack does not rewrite hooks it did not install.' -ForegroundColor DarkGray
}

# --------------------------------- pack tools shadowed by older copies ---
# The installer records where it put each tool. Nothing checked that the
# recorded copy is the one that actually RUNS, and on a machine with more than
# one install location it usually is not: PATH order decides, and an older copy
# earlier on PATH wins silently, forever.
#
# Measured 2026-08-27: codebase-memory-mcp had been updated to 0.10.8 under
# %LOCALAPPDATA%\Programs, while %USERPROFILE%\.local\bin held a 0.9.0 binary
# from six weeks earlier -- and .local\bin came first on PATH, so every caller,
# including codebase-memory's own discovery hook (which hardcodes that path),
# got 0.9.0. The update had "succeeded" every time it ran.
#
# Reported with both paths, never repaired: which copy should win is a PATH
# decision, and this pack does not reorder anyone's PATH.
$shadowed = @()
try {
  $stateFile = Join-Path $env:LOCALAPPDATA 'Ultimate-AI-Starter-Bundle\install-state.json'
  if (Test-Path -LiteralPath $stateFile -PathType Leaf) {
    $st = [IO.File]::ReadAllText($stateFile) | ConvertFrom-Json
    if ($st.components) {
      foreach ($prop in $st.components.PSObject.Properties) {
        $entry = $prop.Value
        if (-not $entry) { continue }
        $recorded = $null
        foreach ($k in @('exe', 'path', 'headroom', 'binary')) {
          $v = $null
          try { $v = $entry.$k } catch { $v = $null }
          if ($v -and ([string]$v).EndsWith('.exe')) { $recorded = [string]$v; break }
        }
        if (-not $recorded) { continue }
        if (-not (Test-Path -LiteralPath $recorded -PathType Leaf)) { continue }
        $leaf = [IO.Path]::GetFileNameWithoutExtension($recorded)
        $onPath = Get-Command $leaf -ErrorAction SilentlyContinue
        if (-not $onPath -or -not $onPath.Source) { continue }
        $a = [IO.Path]::GetFullPath($recorded)
        $b = [IO.Path]::GetFullPath([string]$onPath.Source)
        if ([string]::Equals($a, $b, [StringComparison]::OrdinalIgnoreCase)) { continue }
        # Two copies is normal -- some tools install their own launcher as well
        # as the pack's. Two copies that DIFFER is the hazard, because then an
        # update to one silently leaves every caller on the other. Compared by
        # length: cheap, and these are single-file builds, so a version change
        # always moves it. Hashing a 274 MB binary on every doctor run is not
        # worth the certainty.
        $sizeA = (Get-Item -LiteralPath $a).Length
        $sizeB = (Get-Item -LiteralPath $b -EA SilentlyContinue).Length
        if ($sizeB -and $sizeA -eq $sizeB) { continue }
        $shadowed += [pscustomobject]@{
          component = $prop.Name; installed = $a; wins = $b
        }
      }
    }
  }
} catch { }

if ($shadowed.Count) {
  Write-Host ''
  Write-UabsStep 'Pack-installed tools shadowed by another copy on PATH'
  foreach ($s in $shadowed) {
    $m = ('{0}: this pack installed {1}, but PATH resolves {2} first' -f $s.component, $s.installed, $s.wins)
    Write-UabsWarn $m
    $warnings += $m
  }
  Write-Host '     Whichever comes first on PATH is what every caller gets, including' -ForegroundColor DarkGray
  Write-Host '     hooks that hardcode a path. An update can succeed and change nothing.' -ForegroundColor DarkGray
  Write-Host '     Compare them:  <path> --version   for each of the two above.' -ForegroundColor DarkGray
  Write-Host '     This pack does not reorder your PATH.' -ForegroundColor DarkGray
}
$shadowReport = @($shadowed | ForEach-Object {
  [ordered]@{ component = $_.component; installed = $_.installed; wins = $_.wins }
})

# ------------------------------------------------------------- autostarts ---
# Boot-time launchers for AI tooling. This pack has never written one, so
# NOTHING here is deleted: they are reported, and a dead one - an entry whose
# target is no longer on disk - is warned about, because it costs a failed
# process launch at every boot and is invisible outside Task Manager's Startup
# tab. Measured on the maintainer's machine 2026-08-26: three entries written
# by past agent sessions, one pointing into a tree that had been deleted
# entirely.
$autostarts = @()
try { $autostarts = @(Get-UabsAiAutostartEntries) } catch {
  Write-UabsWarn ('could not read autostart entries: ' + $_.Exception.Message)
}
$deadAutostarts = @($autostarts | Where-Object { $_.Dead })
if ($autostarts.Count) {
  Write-Host ''
  Write-UabsStep 'Boot-time autostarts for AI tooling'
  foreach ($a in $autostarts) {
    if ($a.Dead) {
      $m = ('autostart ''{0}'' runs at every boot but its target is missing: {1}' -f $a.Name, ($a.MissingTargets -join '; '))
      Write-UabsWarn $m
      $warnings += $m
    } else {
      Write-Host ('  {0,-34} {1}' -f $a.Name, $a.Source) -ForegroundColor DarkGray
    }
  }
  if ($deadAutostarts.Count) {
    Write-Host '     This pack never creates autostarts, so it will not remove one either.' -ForegroundColor DarkGray
    Write-Host '     Review them yourself:  explorer shell:startup    (and Task Manager > Startup apps)' -ForegroundColor DarkGray
  }
}
$autostartReport = @($autostarts | ForEach-Object {
  [ordered]@{ name = $_.Name; source = $_.Source; dead = $_.Dead; missing_targets = @($_.MissingTargets) }
})

$doctorResult = if ($errors.Count) { 'FAIL' } else { 'PASS' }
$report=[ordered]@{version=$packBare;checked_utc=[DateTime]::UtcNow.ToString('o');errors=@($errors);warnings=@($warnings);rtk_runtime=$rtkRuntime;capability_states=@($capabilityStates);hermes_tool_budgets=@($hermesBudgets);hermes_plugin_issues=@($hermesPluginIssues);hermes_discouraged_plugin_issues=@($hermesDiscouragedPluginIssues);hermes_hook_issues=@($hermesHookIssues);codex_skill_index=$script:codexSkillIndex;ai_autostarts=@($autostartReport);hook_misdirection=@($hookMisdirection);shadowed_tools=@($shadowReport);result=$doctorResult}
$reportPath=Join-Path $env:LOCALAPPDATA 'Ultimate-AI-Starter-Bundle\installed-state-doctor.json'
$enc=New-Object System.Text.UTF8Encoding($false); [IO.File]::WriteAllText($reportPath,($report|ConvertTo-Json -Depth 8),$enc)
if($errors.Count){Write-UabsBad ("Installed-state doctor FAIL ($($errors.Count) error(s)). Report: $reportPath");exit 1}
Write-UabsOk ("Installed-state doctor PASS. Report: $reportPath")
exit 0
