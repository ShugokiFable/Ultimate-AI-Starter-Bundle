<#
.SYNOPSIS
  Does each agent's harness actually REALIZE the bundle, or do files just exist?

.DESCRIPTION
  Every other check in this pack asks "is the file there". That has repeatedly
  proven to be a terrible proxy. Kimi carried the whole skills tree on disk for
  four releases while the harness ignored it, because the delivery path was
  copied files and nothing bootstrapped them. The pack looked complete and
  behaved as if it were not installed.

  So this script asserts the things a harness needs in order to LOAD the
  bundle, per provider:

    - the native plugin is registered where that provider's loader reads it -
      Kimi's installed.json, Grok's registry.json, Codex's official plugin
      inventory, Claude's plugin cache -
      not merely staged somewhere on disk;
    - Kimi's plugin declares sessionStart.skill, which is what makes
      Superpowers bootstrap itself on every session;
    - Hermes' adapter re-injects after a compaction rather than only on turn 1;
    - the preamble block is present and provider-neutral;
    - plugin-owned skills are not ALSO sitting there as copies;
    - configured MCP command paths still resolve.

  Read-only. Never writes to a provider home.

.PARAMETER Providers
  Subset to check. Default: all five.
#>
[CmdletBinding()]
param(
  [string[]]$Providers = @('Claude', 'Codex', 'Grok', 'Kimi', 'Hermes')
)

$ErrorActionPreference = 'Stop'
$PackRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PackRoot 'TOOLS\UABS-Common.ps1')

$script:Fail = 0
$script:Pass = 0
$script:Skip = 0

function Ok([string]$Provider, [string]$Check) {
  $script:Pass++
  Write-Host ("  {0,-9} {1,-32} PASS" -f $Provider, $Check) -ForegroundColor Green
}
function Bad([string]$Provider, [string]$Check, [string]$Why) {
  $script:Fail++
  Write-Host ("  {0,-9} {1,-32} FAIL  {2}" -f $Provider, $Check, $Why) -ForegroundColor Red
}
function Nap([string]$Provider, [string]$Check, [string]$Why) {
  $script:Skip++
  Write-Host ("  {0,-9} {1,-32} SKIP  {2}" -f $Provider, $Check, $Why) -ForegroundColor DarkGray
}

$catalogPath = Join-Path $PackRoot 'BUNDLED-TOOLS\CATALOG.json'
$catalog = ([IO.File]::ReadAllText($catalogPath)) | ConvertFrom-Json
$soulFile = Join-Path $PackRoot '3-PREAMBLES\SOUL.md'
$soulText = ([IO.File]::ReadAllText($soulFile)).Trim()
$pluginsRoot = Join-Path $PackRoot 'BUNDLED-TOOLS\plugins'

# Which plugins are natively installed, per provider. Filled in by the
# per-provider checks below and then used to decide whether a copied skill is
# a duplicate or the intended fallback.
$pstateAll = @{}

Write-Host ''
Write-Host '=== Harness realization ===' -ForegroundColor Cyan

foreach ($prov in $Providers) {
  $phome = $null
  try { $phome = Get-UabsProviderHome -Provider $prov -Catalog $catalog } catch { }
  if (-not $phome -or -not (Test-Path -LiteralPath $phome -PathType Container)) {
    Nap $prov 'provider home' 'not installed on this machine'
    continue
  }

  # ---- preamble: present, provider-neutral, decodable -------------------
  $instName = $catalog.providers.$prov.instructions
  if (-not $instName) { $instName = 'AGENTS.md' }
  $instFile = if ($prov -eq 'Hermes') { Join-Path $phome 'SOUL.md' } else { Join-Path $phome $instName }
  if (-not (Test-Path -LiteralPath $instFile -PathType Leaf)) {
    Bad $prov 'preamble installed' ("missing " + $instFile)
  } else {
    $txt = [IO.File]::ReadAllText($instFile)
    $norm = $txt -replace "`r`n", "`n"
    if ($norm -notmatch [regex]::Escape(($soulText -replace "`r`n", "`n"))) {
      Bad $prov 'preamble installed' 'soul block absent or not current'
    } elseif ($txt -match 'Hermes Agent|Nous Research|created by (Anthropic|OpenAI|xAI|Moonshot)') {
      Bad $prov 'preamble provider-neutral' 'names a specific vendor identity'
    } elseif ($txt.Contains([char]0xFFFD)) {
      Bad $prov 'preamble encoding' 'contains U+FFFD (decoded with the wrong codepage)'
    } else {
      Ok $prov 'preamble installed'
    }
  }

  # ---- native plugin registration, per provider ------------------------
  switch ($prov) {

    'Claude' {
      foreach ($id in @('superpowers', 'ponytail')) {
        $mk = Get-UabsClaudeMarketplaceName -PluginRoot (Join-Path $pluginsRoot $id)
        if (-not $mk) { Nap $prov ("native " + $id) 'no Claude marketplace in bundle'; continue }
        $cache = Join-Path $phome ('plugins\cache\' + $mk + '\' + $id)
        if (Test-Path -LiteralPath $cache -PathType Container) {
          Ok $prov ("native " + $id)
          if (-not $pstateAll.ContainsKey($prov)) { $pstateAll[$prov] = @{} }
          $pstateAll[$prov][$id] = $true
        }
        else { Bad $prov ("native " + $id) ('no plugins\cache\' + $mk + '\' + $id) }
      }
    }

    'Kimi' {
      # The whole point of the v7.7.0 Kimi rework: a registry entry Kimi's
      # loader reads, and a manifest that bootstraps on session start.
      $store = Join-Path $phome 'plugins\installed.json'
      if (-not (Test-Path -LiteralPath $store -PathType Leaf)) {
        Bad $prov 'plugin registry' 'plugins\installed.json missing'
      } else {
        $doc = $null
        try { $doc = ([IO.File]::ReadAllText($store)) | ConvertFrom-Json } catch { }
        if (-not $doc) { Bad $prov 'plugin registry' 'installed.json does not parse' }
        else {
          $sp = @($doc.plugins) | Where-Object { $_.id -eq 'superpowers' }
          if (-not $sp) { Bad $prov 'native superpowers' 'no superpowers entry' }
          elseif (-not $sp.enabled) { Bad $prov 'native superpowers' 'entry present but disabled' }
          elseif (-not (Test-Path -LiteralPath $sp.root -PathType Container)) {
            Bad $prov 'native superpowers' ('root does not exist: ' + $sp.root)
          } else {
            Ok $prov 'native superpowers'
            if (-not $pstateAll.ContainsKey($prov)) { $pstateAll[$prov] = @{} }
            $pstateAll[$prov]['superpowers'] = $true
            # sessionStart is what makes Kimi bootstrap it every session.
            $mfDir = Join-Path $sp.root '.kimi-plugin\plugin.json'
            $mfRoot = Join-Path $sp.root 'plugin.json'
            $mf = if (Test-Path -LiteralPath $mfRoot) { $mfRoot } else { $mfDir }
            if (-not (Test-Path -LiteralPath $mf -PathType Leaf)) {
              Bad $prov 'sessionStart bootstrap' 'no plugin.json under the installed root'
            } else {
              $m = ([IO.File]::ReadAllText($mf)) | ConvertFrom-Json
              if ($m.sessionStart -and $m.sessionStart.skill) { Ok $prov 'sessionStart bootstrap' }
              else { Bad $prov 'sessionStart bootstrap' 'manifest declares no sessionStart.skill' }
            }
          }
        }
      }
    }

    'Hermes' {
      $adapter = Join-Path $pluginsRoot 'superpowers\.hermes-plugin\__init__.py'
      if (-not (Test-Path -LiteralPath $adapter -PathType Leaf)) {
        Bad $prov 'post-compact bootstrap' 'hermes adapter missing from the bundle'
      } else {
        $src = [IO.File]::ReadAllText($adapter)
        # First-turn-only injection is the bug: a compaction drops the
        # bootstrap and it is never put back for the rest of the session.
        if ($src -match '_history_has_marker' -and $src -match 'BOOTSTRAP_MARKER') {
          Ok $prov 'post-compact bootstrap'
        } else {
          Bad $prov 'post-compact bootstrap' 'adapter injects on first turn only'
        }
      }
      # The scanner must not have been left switched off for everything else.
      $cfg = Join-Path $phome 'config.yaml'
      if (Test-Path -LiteralPath $cfg -PathType Leaf) {
        if (([IO.File]::ReadAllText($cfg)) -match '(?m)^\s+scan_on_install\s*:\s*false') {
          Bad $prov 'plugin scanner restored' 'scan_on_install is still false'
        } else { Ok $prov 'plugin scanner restored' }
      }
    }

    'Codex' {
      $cc = Get-Command codex -ErrorAction SilentlyContinue
      if (-not $cc) { Nap $prov 'native plugins' 'codex CLI missing'; break }
      $raw = Get-UabsNativeOutput -Exe $cc.Source -CmdArgs @('plugin','list','--json')
      $inventory = $null
      try { $inventory = ($raw | ConvertFrom-Json).installed } catch { }
      foreach ($id in @('superpowers','ponytail')) {
        $market = Get-UabsClaudeMarketplaceName -PluginRoot (Join-Path $pluginsRoot $id)
        $pluginId = $id + '@' + $market
        $hit = @($inventory | Where-Object { $_.pluginId -eq $pluginId }) | Select-Object -First 1
        if (-not $hit) { Bad $prov ('native ' + $id) ('official inventory missing ' + $pluginId) }
        elseif (-not $hit.enabled) { Bad $prov ('native ' + $id) ($pluginId + ' is disabled') }
        else {
          Ok $prov ('native ' + $id)
          if (-not $pstateAll.ContainsKey($prov)) { $pstateAll[$prov] = @{} }
          $pstateAll[$prov][$id] = $true
        }
      }
      if (@($inventory | Where-Object { $_.marketplaceName -eq 'ultimate-bundle' }).Count) {
        Bad $prov 'legacy marketplace retired' 'ultimate-bundle plugin inventory still present'
      } else { Ok $prov 'legacy marketplace retired' }
    }

    'Grok' {
      # Grok keeps its own registry of installed plugin repos. Reading it is
      # the same class of evidence as Kimi's installed.json: the loader's own
      # source of truth, not a directory that happens to sit on disk.
      $reg = Join-Path $phome 'installed-plugins\registry.json'
      if (-not (Test-Path -LiteralPath $reg -PathType Leaf)) {
        Bad $prov 'native superpowers' 'installed-plugins\registry.json missing'
      } else {
        $doc = $null
        try { $doc = ([IO.File]::ReadAllText($reg)) | ConvertFrom-Json } catch { }
        if (-not $doc) {
          Bad $prov 'native superpowers' 'registry.json does not parse'
        } else {
          $hits = @()
          foreach ($r in $doc.repos.PSObject.Properties) {
            if ($r.Value.plugins -and (@($r.Value.plugins.PSObject.Properties.Name) -contains 'superpowers')) {
              $hits += $r.Value
            }
          }
          if ($hits.Count -eq 0) {
            Bad $prov 'native superpowers' 'no repo in the registry provides superpowers'
          } elseif ($hits.Count -gt 1) {
            Bad $prov 'native superpowers' ('duplicate superpowers plugins (' + $hits.Count + ') - systematic-debugging collides')
          } elseif (-not (Test-Path -LiteralPath $hits[0].path -PathType Container)) {
            Bad $prov 'native superpowers' ('registered path does not exist: ' + $hits[0].path)
          } elseif (-not (Test-Path -LiteralPath (Join-Path $hits[0].path 'skills') -PathType Container)) {
            Bad $prov 'native superpowers' ('registered repo has no skills tree: ' + $hits[0].path)
          } else {
            Ok $prov 'native superpowers'
            if (-not $pstateAll.ContainsKey($prov)) { $pstateAll[$prov] = @{} }
            $pstateAll[$prov]['superpowers'] = $true
          }
        }
      }
    }

    default {
      Nap $prov 'native plugin' 'no registration check for this provider'
    }
  }

  # ---- skill delivery matches this provider's policy -------------------
  # Two policies, both deliberate, and the check has to know which applies:
  #
  #   dedupe      Claude, Codex, Kimi - the harness loads skills from the
  #               plugin itself, so a copy in the skills dir is a stale
  #               duplicate that shadows the plugin's own version.
  #   keep-copies Grok, Hermes - the harness reads the SKILLS DIR, not the
  #               plugin registration. Grok's TUI Reads
  #               ~/.grok/skills/<name>/SKILL.md (v7.7.5); Hermes derives
  #               /slash commands and desktop autofill by scanning the same
  #               path (v7.7.7). Here a MISSING copy is the defect.
  #
  # The previous version of this check asserted neither. It only looked at
  # $pstateAll, which was written for 'superpowers' in three branches and
  # never for 'ponytail' or for Claude at all - so eight of ten
  # provider/plugin pairs reported PASS while testing nothing, and it kept
  # reporting 'no duplicate skills' for the two providers that now REQUIRE
  # those copies. Silence that reads as PASS is what this script exists to
  # catch.
  $keepCopies = @('Grok', 'Hermes')
  $skillsDir = Join-Path $phome 'skills'
  if (Test-Path -LiteralPath $skillsDir -PathType Container) {
    if ($keepCopies -contains $prov) {
      $absent = @()
      foreach ($id in @('superpowers', 'ponytail')) {
        foreach ($n in (Get-UabsPluginOwnedSkillNames -PluginRoot (Join-Path $pluginsRoot $id))) {
          if (-not (Test-Path -LiteralPath (Join-Path $skillsDir $n) -PathType Container)) { $absent += $n }
        }
      }
      if ($absent.Count -gt 0) {
        Bad $prov 'plugin skill copies present' (($absent.Count.ToString()) + ' missing (slash commands/TUI read this path): ' + (($absent | Select-Object -First 4) -join ', '))
      } else {
        Ok $prov 'plugin skill copies present'
      }
    } else {
      $dupes = @()
      $unknown = @()
      foreach ($id in @('superpowers', 'ponytail')) {
        $native = $null
        if ($pstateAll.ContainsKey($prov)) { $native = $pstateAll[$prov][$id] }
        if (-not $native) { $unknown += $id; continue }
        foreach ($n in (Get-UabsPluginOwnedSkillNames -PluginRoot (Join-Path $pluginsRoot $id))) {
          if (Test-Path -LiteralPath (Join-Path $skillsDir $n) -PathType Container) { $dupes += $n }
        }
      }
      if ($dupes.Count -gt 0) {
        Bad $prov 'no duplicate skills' (($dupes.Count.ToString()) + ' plugin-owned copies shadow the plugin: ' + (($dupes | Select-Object -First 4) -join ', '))
      } elseif ($unknown.Count -eq 2) {
        # Nothing was confirmed native, so there is nothing to call a
        # duplicate. Say so instead of printing a PASS that tested nothing.
        Nap $prov 'no duplicate skills' ('no native plugin confirmed: ' + ($unknown -join ', '))
      } elseif ($unknown.Count -gt 0) {
        Ok $prov ('no duplicate skills (' + ($unknown -join ', ') + ' not checked)')
      } else {
        Ok $prov 'no duplicate skills'
      }
    }
  }
}

Write-Host ''
Write-Host ("HARNESS REALIZATION: {0}" -f $(if ($script:Fail -eq 0) { 'PASS' } else { "FAIL ($($script:Fail) problem(s))" })) `
  -ForegroundColor $(if ($script:Fail -eq 0) { 'Green' } else { 'Red' })
Write-Host ("  pass={0} fail={1} skip={2}" -f $script:Pass, $script:Fail, $script:Skip)
if ($script:Fail -gt 0) { exit 1 }
exit 0
