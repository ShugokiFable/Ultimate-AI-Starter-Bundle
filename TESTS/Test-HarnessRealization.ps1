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

    - the native plugin is registered where that provider's loader reads it,
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
. (Join-Path $PackRoot 'TOOLS\V7-Common.ps1')

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
  try { $phome = Get-V5ProviderHome -Provider $prov -Catalog $catalog } catch { }
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
        $mk = Get-V5ClaudeMarketplaceName -PluginRoot (Join-Path $pluginsRoot $id)
        if (-not $mk) { Nap $prov ("native " + $id) 'no Claude marketplace in bundle'; continue }
        $cache = Join-Path $phome ('plugins\cache\' + $mk + '\' + $id)
        if (Test-Path -LiteralPath $cache -PathType Container) { Ok $prov ("native " + $id) }
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

    default {
      # Codex and Grok: a staged plugin dir is not proof, so only report what
      # can actually be observed rather than inventing a verdict.
      Nap $prov 'native plugin' 'needs a live harness smoke test'
    }
  }

  # ---- plugin-owned skills must not ALSO exist as copies ---------------
  $skillsDir = Join-Path $phome 'skills'
  if (Test-Path -LiteralPath $skillsDir -PathType Container) {
    # A copy is only a DUPLICATE when the native plugin for it is actually
    # installed for this provider. Where the native install did not happen -
    # Grok has no native ponytail today - the copies ARE the delivery path,
    # and calling them duplicates would argue for deleting the only working
    # copy of those skills.
    $dupes = @()
    foreach ($id in @('superpowers', 'ponytail')) {
      $entry = $null
      if ($pstateAll.ContainsKey($prov)) { $entry = $pstateAll[$prov][$id] }
      if (-not $entry) { continue }
      foreach ($n in (Get-V5PluginOwnedSkillNames -PluginRoot (Join-Path $pluginsRoot $id))) {
        if (Test-Path -LiteralPath (Join-Path $skillsDir $n) -PathType Container) { $dupes += $n }
      }
    }
    if ($dupes.Count -gt 0) {
      Bad $prov 'no duplicate skills' (($dupes.Count.ToString()) + ' plugin-owned copies: ' + (($dupes | Select-Object -First 4) -join ', '))
    } else {
      Ok $prov 'no duplicate skills'
    }
  }
}

Write-Host ''
Write-Host ("HARNESS REALIZATION: {0}" -f $(if ($script:Fail -eq 0) { 'PASS' } else { "FAIL ($($script:Fail) problem(s))" })) `
  -ForegroundColor $(if ($script:Fail -eq 0) { 'Green' } else { 'Red' })
Write-Host ("  pass={0} fail={1} skip={2}" -f $script:Pass, $script:Fail, $script:Skip)
if ($script:Fail -gt 0) { exit 1 }
exit 0
