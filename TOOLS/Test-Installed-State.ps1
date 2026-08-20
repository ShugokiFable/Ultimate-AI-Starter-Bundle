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
if ($packBare -notmatch '^\d+\.\d+\.\d+$') { Err "Pack VERSION.txt is not a semantic version: $packVersion" }
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
      $forgeDoctorRaw = (& $py -m skyrim_forge doctor 2>&1 | Out-String)
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
$doctorResult = if ($errors.Count) { 'FAIL' } else { 'PASS' }
$report=[ordered]@{version=$packBare;checked_utc=[DateTime]::UtcNow.ToString('o');errors=@($errors);warnings=@($warnings);result=$doctorResult}
$reportPath=Join-Path $env:LOCALAPPDATA 'Skyrim-AI-V5\installed-state-doctor.json'
$enc=New-Object System.Text.UTF8Encoding($false); [IO.File]::WriteAllText($reportPath,($report|ConvertTo-Json -Depth 8),$enc)
if($errors.Count){Write-V5Bad ("Installed-state doctor FAIL ($($errors.Count) error(s)). Report: $reportPath");exit 1}
Write-V5Ok ("Installed-state doctor PASS. Report: $reportPath")
exit 0
