<#
.SYNOPSIS
  Remove what THIS pack left behind: retired skills and unbounded backups.

.DESCRIPTION
  Two problems, both created by the installer and never cleaned up by it.

  1. RETIRED SKILLS. The installer copies the canonical tree into every
     provider's skills directory but has never removed a skill the pack stopped
     shipping. A machine installed against v7 still carries the v7 names.
     Measured at v8.2.0 on the maintainer's machine: seven retired skills in
     three provider trees, twenty-one directories, each one loaded and offered
     to the agent NEXT TO the skill that replaced it. Two skills claiming KID
     syntax, and the retired one documents the older dialect.

  2. BACKUPS WITHOUT A CEILING. Every run writes config.toml.bak-*,
     AGENTS.md.before-soul-*.bak, settings.json.bak-gate-* and an install log.
     Nothing ever prunes them. Measured on the same machine: 217 files, 2.1 MB,
     86 of them Grok config backups. They are inert, but "inert and unbounded"
     is still a defect, and it buries the one backup someone might actually
     want to restore.

  It also REPORTS, without touching, boot-time autostarts for AI tooling whose
  target no longer exists -- the pack has never written an autostart, so those
  are not its to remove, but a launcher that fails at every boot is worth
  naming.

  DELETION IS LIMITED TO WHAT THIS PACK CREATED. A retired skill is removed
  only when its name is in BUNDLED-TOOLS/RETIRED-SKILLS.json AND the directory
  looks like a copy this pack made. Backups are matched on the pack's own
  naming patterns. Anything else -- plugin-provided skills, the optional
  Other-Games mega-pack, a user's own files -- is REPORTED, never touched.

.PARAMETER Apply
  Perform the deletions. Without this, print the plan and change nothing.

.PARAMETER KeepBackups
  How many backups to keep per family (newest first). Default 3.

.PARAMETER KeepLogs
  How many install logs to keep. Default 5.

.PARAMETER SkipSkills
  Leave retired skills alone; prune backups only.
#>
[CmdletBinding()]
param(
  [switch]$Apply,
  [ValidateRange(0, 100)][int]$KeepBackups = 3,
  [ValidateRange(1, 200)][int]$KeepLogs = 5,
  [switch]$SkipSkills,
  [string]$PackRoot
)

$ErrorActionPreference = 'Stop'
if (-not $PackRoot) { $PackRoot = Split-Path -Parent $PSScriptRoot }
. (Join-Path $PackRoot 'TOOLS\UABS-Common.ps1')

$script:Planned = New-Object System.Collections.Generic.List[object]
$script:Reported = New-Object System.Collections.Generic.List[string]
$script:FreedBytes = 0

function Add-CleanTarget {
  param([string]$Kind, [string]$Path, [string]$Why)
  $size = 0
  try {
    if (Test-Path -LiteralPath $Path -PathType Container) {
      $size = (Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue |
               Measure-Object -Property Length -Sum).Sum
    } elseif (Test-Path -LiteralPath $Path -PathType Leaf) {
      $size = (Get-Item -LiteralPath $Path).Length
    }
  } catch { }
  if (-not $size) { $size = 0 }
  $script:FreedBytes += $size
  [void]$script:Planned.Add([pscustomobject]@{ Kind = $Kind; Path = $Path; Why = $Why; Bytes = $size })
}

# ---------------------------------------------------------------- skills ----
$providerSkillDirs = [ordered]@{
  Claude = Join-Path $env:USERPROFILE '.claude\skills'
  Codex  = Join-Path $env:USERPROFILE '.agents\skills'
  Grok   = Join-Path $env:USERPROFILE '.grok\skills'
  Kimi   = Join-Path $env:USERPROFILE '.kimi-code\skills'
  Hermes = Join-Path $env:LOCALAPPDATA 'hermes\skills'
}

$retiredPath = Join-Path $PackRoot 'BUNDLED-TOOLS\RETIRED-SKILLS.json'
$retired = @()
if (Test-Path -LiteralPath $retiredPath -PathType Leaf) {
  $retired = @(([IO.File]::ReadAllText($retiredPath) | ConvertFrom-Json).retired)
} else {
  Write-UabsWarn "RETIRED-SKILLS.json not found - skipping retired-skill cleanup"
}

if (-not $SkipSkills -and $retired.Count) {
  $canonical = @{}
  $canonRoot = Join-Path $PackRoot '_CANONICAL-SKILLS'
  if (Test-Path -LiteralPath $canonRoot -PathType Container) {
    foreach ($d in Get-ChildItem -LiteralPath $canonRoot -Directory) { $canonical[$d.Name] = $true }
  }
  foreach ($provider in $providerSkillDirs.Keys) {
    $dir = $providerSkillDirs[$provider]
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { continue }
    foreach ($entry in $retired) {
      $name = [string]$entry.name
      # Never delete a name the pack currently ships. A retired list that has
      # drifted must not be able to remove a live skill.
      if ($canonical.ContainsKey($name)) {
        [void]$script:Reported.Add("$provider/$name is in RETIRED-SKILLS.json but ALSO in the canonical tree - left alone, regenerate the list")
        continue
      }
      $target = Join-Path $dir $name
      if (-not (Test-Path -LiteralPath $target -PathType Container)) { continue }
      # It must look like a skill this pack copied, not a coincidence.
      if (-not (Test-Path -LiteralPath (Join-Path $target 'SKILL.md') -PathType Leaf)) {
        [void]$script:Reported.Add("$provider/$name has no SKILL.md - not recognizably ours, left alone")
        continue
      }
      $successor = if ($entry.superseded_by) { "superseded by $($entry.superseded_by)" } else { 'retired, no successor' }
      Add-CleanTarget -Kind "skill/$provider" -Path $target -Why $successor
    }
  }
}

# --------------------------------------------------------------- backups ----
# Families are (directory, glob). Everything here is written by this pack's own
# installers; a user's file does not match these names by accident.
$backupFamilies = @(
  @{ Dir = (Join-Path $env:USERPROFILE '.grok');      Glob = 'config.toml.*bak*' }
  @{ Dir = (Join-Path $env:USERPROFILE '.grok');      Glob = 'AGENTS.md.*bak*' }
  @{ Dir = (Join-Path $env:USERPROFILE '.codex');     Glob = 'config.toml.*bak*' }
  @{ Dir = (Join-Path $env:USERPROFILE '.codex');     Glob = 'AGENTS.md.*bak*' }
  @{ Dir = (Join-Path $env:USERPROFILE '.claude');    Glob = 'settings.json.bak*' }
  @{ Dir = (Join-Path $env:USERPROFILE '.claude');    Glob = 'CLAUDE.md.*bak*' }
  @{ Dir = (Join-Path $env:USERPROFILE '.kimi-code'); Glob = 'AGENTS.md.*bak*' }
  @{ Dir = (Join-Path $env:USERPROFILE '.kimi-code'); Glob = 'mcp.json.bak*' }
  @{ Dir = (Join-Path $env:LOCALAPPDATA 'hermes');    Glob = 'config.yaml.bak*' }
  @{ Dir = (Join-Path $env:LOCALAPPDATA 'hermes');    Glob = 'SOUL.md.*bak*' }
)

foreach ($family in $backupFamilies) {
  if (-not (Test-Path -LiteralPath $family.Dir -PathType Container)) { continue }
  $files = @(Get-ChildItem -LiteralPath $family.Dir -Filter $family.Glob -File -ErrorAction SilentlyContinue |
             Sort-Object LastWriteTimeUtc -Descending)
  if ($files.Count -le $KeepBackups) { continue }
  foreach ($old in $files[$KeepBackups..($files.Count - 1)]) {
    Add-CleanTarget -Kind 'backup' -Path $old.FullName -Why "older than the $KeepBackups most recent $($family.Glob)"
  }
}

# Install logs and profile-migration backups the pack writes under LOCALAPPDATA.
$uabsRoot = Join-Path $env:LOCALAPPDATA 'Ultimate-AI-Starter-Bundle'
$logDir = Join-Path $uabsRoot 'logs'
if (Test-Path -LiteralPath $logDir -PathType Container) {
  $logs = @(Get-ChildItem -LiteralPath $logDir -Filter 'install-*.log' -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTimeUtc -Descending)
  if ($logs.Count -gt $KeepLogs) {
    foreach ($old in $logs[$KeepLogs..($logs.Count - 1)]) {
      Add-CleanTarget -Kind 'log' -Path $old.FullName -Why "older than the $KeepLogs most recent install logs"
    }
  }
}
$profileBackups = Join-Path $uabsRoot 'backups\hermes-profiles'
if (Test-Path -LiteralPath $profileBackups -PathType Container) {
  $snaps = @(Get-ChildItem -LiteralPath $profileBackups -Directory -ErrorAction SilentlyContinue |
             Sort-Object Name -Descending)
  if ($snaps.Count -gt $KeepBackups) {
    foreach ($old in $snaps[$KeepBackups..($snaps.Count - 1)]) {
      Add-CleanTarget -Kind 'backup' -Path $old.FullName -Why "older than the $KeepBackups most recent Hermes profile snapshots"
    }
  }
}

# The plugin-owned-skill dedupe writes backups\dedupe-<Provider>-<stamp>\ on
# EVERY install and nothing ever pruned them. This is by far the largest family:
# measured at 160 directories and 52 MB on the maintainer's machine, against
# 2.1 MB for every .bak file combined. Keep the newest per provider, because a
# rollback is only ever wanted for the install that just ran.
$backupsRoot = Join-Path $uabsRoot 'backups'
if (Test-Path -LiteralPath $backupsRoot -PathType Container) {
  $dedupe = @(Get-ChildItem -LiteralPath $backupsRoot -Directory -Filter 'dedupe-*' -ErrorAction SilentlyContinue)
  foreach ($group in ($dedupe | Group-Object { ($_.Name -split '-')[1] })) {
    $ordered = @($group.Group | Sort-Object Name -Descending)
    if ($ordered.Count -le $KeepBackups) { continue }
    foreach ($old in $ordered[$KeepBackups..($ordered.Count - 1)]) {
      Add-CleanTarget -Kind 'backup' -Path $old.FullName -Why "older than the $KeepBackups most recent $($group.Name) dedupe snapshots"
    }
  }
}

# ------------------------------------------------------------ autostarts ----
# Boot-time launchers for AI tooling are REPORTED, never planned for deletion.
# The rule at the top of this file is that deletion is limited to what this
# pack created, and this pack has never written an autostart -- these come from
# agent sessions, other tools' installers, and the user. A dead one still gets
# named, because it costs a failed process launch at every boot.
$autostarts = @()
try { $autostarts = @(Get-UabsAiAutostartEntries) } catch { }
foreach ($a in $autostarts) {
  if ($a.Dead) {
    [void]$script:Reported.Add(
      ("autostart '{0}' ({1}) runs at every boot but its target is gone: {2} -- not ours to delete; remove it yourself via  explorer shell:startup" -f `
        $a.Name, $a.Source, ($a.MissingTargets -join '; ')))
  }
}

# ------------------------------------------------------- report / execute ---
Write-Host ''
Write-UabsStep $(if ($Apply) { 'Cleaning pack-created leftovers' } else { 'Leftover plan (nothing removed)' })

if (-not $script:Planned.Count) {
  Write-UabsOk 'Nothing to clean; no retired skills and no backups past the retention limit.'
} else {
  foreach ($group in ($script:Planned | Group-Object Kind | Sort-Object Name)) {
    $bytes = ($group.Group | Measure-Object -Property Bytes -Sum).Sum
    Write-Host ("  {0,-16} {1,3} item(s)  {2,8:N1} KB" -f $group.Name, $group.Count, ($bytes / 1KB))
    foreach ($item in $group.Group | Select-Object -First 6) {
      Write-Host ("      " + (Split-Path -Leaf $item.Path) + "  -- " + $item.Why) -ForegroundColor DarkGray
    }
    if ($group.Count -gt 6) { Write-Host ("      ... and " + ($group.Count - 6) + " more") -ForegroundColor DarkGray }
  }
  Write-Host ("  TOTAL            {0,3} item(s)  {1,8:N1} KB" -f $script:Planned.Count, ($script:FreedBytes / 1KB))
}

foreach ($note in $script:Reported) { Write-UabsWarn $note }

if (-not $Apply) {
  if ($script:Planned.Count) {
    Write-Host ''
    Write-Host '  Nothing was removed. Re-run with -Apply to delete the items above.' -ForegroundColor Yellow
  }
  exit 0
}

$removed = 0
$failed = 0
foreach ($item in $script:Planned) {
  try {
    Remove-Item -LiteralPath $item.Path -Recurse -Force -ErrorAction Stop
    $removed++
  } catch {
    $failed++
    Write-UabsWarn ("could not remove " + $item.Path + ": " + $_.Exception.Message)
  }
}
Write-UabsOk ("removed $removed item(s), freed ~{0:N1} KB" -f ($script:FreedBytes / 1KB))
if ($failed) {
  Write-UabsWarn "$failed item(s) could not be removed (in use, or permission denied). Re-run after closing the AI apps."
}
exit 0
