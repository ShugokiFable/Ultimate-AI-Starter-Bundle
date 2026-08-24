<#
.SYNOPSIS
  Merge portable provider starter settings into each AI home.

.DESCRIPTION
  New users get a working settings.json / config.toml / config.yaml without
  copying anyone else's machine. Existing homes are never clobbered:

  - Claude JSON: fill missing keys. Never touch hooks (Install-Completeness-Gate)
    or CLAUDE.md (0-UNRESTRAINT-PACKS / SOUL preamble).
  - Codex / Kimi / Hermes: copy the template only when the dest file is absent.
  - Grok: copy if absent; if present, only ensure mcp-search is disabled.

  Templates live in 1-TAILORED-PROVIDER-TREES\<Provider>\COPY-TO-PROVIDER-HOME\.
  A template containing a user-profile path or S:\Apps is refused.
#>
[CmdletBinding()]
param(
  [string]$PackRoot,
  [string[]]$Providers = @('Claude', 'Codex', 'Grok', 'Kimi', 'Hermes'),
  [switch]$SkipHermes
)

$ErrorActionPreference = 'Stop'
if (-not $PackRoot) { $PackRoot = Split-Path -Parent $PSScriptRoot }
. (Join-Path $PackRoot 'TOOLS\UABS-Common.ps1')
$catalog = Get-UabsCatalog
$tailored = Join-Path $PackRoot '1-TAILORED-PROVIDER-TREES'

function Test-UabsPortableTemplate {
  param([string]$Path)
  $raw = [IO.File]::ReadAllText($Path)
  if ($raw -match '(?i)C:\\Users\\[^\\\s"]+' -or $raw -match '(?i)/Users/[^/\s"]+' -or $raw -match '(?i)S:\\Apps\\') {
    throw ("Refusing machine-local template (contains a user or Apps path): " + $Path)
  }

  # A starter template carries portable PREFERENCES. MCP registration belongs to
  # INSTALL-AIO.ps1 and Set-McpProfile.ps1, which read what is actually
  # installed on this machine and choose the scope each server belongs in.
  #
  # Through 7.9.7 the Hermes starter carried five live servers. Because the copy
  # is whole-file, each became a fresh-install default that outranked the
  # bundle's own decisions: sequential-thinking after 7.9.7 measured it out of
  # the always-on core, a GitHub package upstream had withdrawn, an unpinned
  # @latest server, and a 25-tool web server duplicating a native capability.
  # The file's own header said it must never contain a live MCP command. Only a
  # check can hold that line, so refuse the SHAPE rather than the four symptoms.
  $code = (($raw -split "`r?`n") | Where-Object { $_ -notmatch '^\s*(#|//)' }) -join "`n"
  $mcpShapes = [ordered]@{
    'YAML mcp_servers mapping' = '(?m)^[ \t]*mcp_servers:[ \t]*\r?\n[ \t]+\S'
    'TOML mcp_servers table'   = '(?m)^[ \t]*\[[ \t]*mcp[_.]servers\.'
    'JSON mcpServers object'   = '(?m)"mcpServers"[ \t]*:[ \t]*\{[ \t\r\n]*"'
  }
  foreach ($shape in $mcpShapes.Keys) {
    if ($code -match $mcpShapes[$shape]) {
      throw ("Refusing starter template with live MCP entries (" + $shape + "): " + $Path +
             " -- MCP is wired by INSTALL-AIO.ps1 and Set-McpProfile.ps1 from what is installed, not copied from a template.")
    }
  }

  # An unpinned server can change its tool surface mid-session, and npx will
  # happily reuse a broken cache. The catalog pins every server it owns; a
  # template is not the place the policy gets an exemption.
  if ($code -match '@latest') {
    throw ("Refusing starter template with an unpinned @latest package: " + $Path)
  }
}

function Backup-UabsFile {
  param([string]$Path)
  if (Test-Path -LiteralPath $Path -PathType Leaf) {
    Copy-Item -LiteralPath $Path -Destination ($Path + '.before-starter-' + (Get-Date -Format 'yyyyMMdd-HHmmssfff') + '.bak') -Force
  }
}

function Merge-UabsClaudeSettings {
  param([string]$Src, [string]$Dest)
  Test-UabsPortableTemplate -Path $Src
  $srcObj = [IO.File]::ReadAllText($Src) | ConvertFrom-Json
  $destDir = Split-Path -Parent $Dest
  if (-not (Test-Path -LiteralPath $destDir)) {
    Write-UabsWarn 'Claude home not present; skipped settings.json'
    return
  }
  $destObj = if (Test-Path -LiteralPath $Dest) {
    [IO.File]::ReadAllText($Dest) | ConvertFrom-Json
  } else {
    [pscustomobject]@{}
  }
  $changed = $false
  foreach ($p in $srcObj.PSObject.Properties) {
    if ($p.Name -eq 'hooks' -or $p.Name -eq 'enabledPlugins') { continue }
    if ($destObj.PSObject.Properties.Name -notcontains $p.Name) {
      $destObj | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value
      $changed = $true
    } elseif ($p.Name -eq 'extraKnownMarketplaces') {
      if ($destObj.PSObject.Properties.Name -notcontains 'extraKnownMarketplaces') {
        $destObj | Add-Member -NotePropertyName extraKnownMarketplaces -NotePropertyValue $p.Value
        $changed = $true
      } else {
        foreach ($m in $p.Value.PSObject.Properties) {
          if ($destObj.extraKnownMarketplaces.PSObject.Properties.Name -notcontains $m.Name) {
            $destObj.extraKnownMarketplaces | Add-Member -NotePropertyName $m.Name -NotePropertyValue $m.Value
            $changed = $true
          }
        }
      }
    }
  }
  if ($changed) {
    Backup-UabsFile -Path $Dest
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [IO.File]::WriteAllText($Dest, (($destObj | ConvertTo-Json -Depth 20) + [Environment]::NewLine), $utf8)
    Write-UabsOk ('Claude settings.json merged: ' + $Dest)
  } else {
    Write-UabsOk 'Claude settings.json already had starter keys'
  }
}

function Copy-UabsStarterIfMissing {
  param([string]$Src, [string]$Dest, [string]$Label)
  Test-UabsPortableTemplate -Path $Src
  $destDir = Split-Path -Parent $Dest
  if (-not (Test-Path -LiteralPath $destDir)) {
    Write-UabsWarn ("{0} home not present; skipped {1}" -f $Label, (Split-Path -Leaf $Dest))
    return
  }
  if (Test-Path -LiteralPath $Dest -PathType Leaf) {
    Write-UabsOk ("{0} existing {1} preserved" -f $Label, (Split-Path -Leaf $Dest))
    return
  }
  New-Item -ItemType Directory -Force -Path $destDir | Out-Null
  Copy-Item -LiteralPath $Src -Destination $Dest -Force
  Write-UabsOk ("{0} starter {1} installed: {2}" -f $Label, (Split-Path -Leaf $Dest), $Dest)
}

function Merge-UabsHermesEfficiencyDefaults {
  param([string]$Dest)
  if (-not (Test-Path -LiteralPath $Dest -PathType Leaf)) { return }
  $exe = Join-Path $env:LOCALAPPDATA 'hermes\hermes-agent\venv\Scripts\hermes.exe'
  if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
    Write-UabsWarn 'Hermes config exists but the official CLI is unavailable; efficiency defaults were not merged'
    return
  }

  # Fill only absent keys through Hermes' own config API. This repairs an
  # upstream reset without replacing the user's model, credentials, plugins,
  # MCP entries, or deliberate values.
  $defaults = [ordered]@{
    'agent.verbose'                           = 'false'
    'compression.enabled'                     = 'true'
    'compression.threshold_tokens'            = '220000'
    'compression.target_ratio'                = '0.30'
    'compression.protect_last_n'              = '20'
    'compression.min_tail_user_messages'      = '3'
    'compression.proactive_prune_tokens'      = '80000'
    'compression.proactive_prune_min_reclaim_tokens' = '32768'
    'compression.micro_compact'               = 'false'
    'compression.abort_on_summary_failure'    = 'true'
    'compression.idle_compact_after_seconds'  = '0'
    'prompt_caching.cache_ttl'                 = '1h'
    'mcp.auto_reload_on_config_change'         = 'false'
    'openrouter.response_cache'                = 'true'
    'openrouter.response_cache_ttl'            = '300'
    'auxiliary.transient_retries'              = '1'
  }

  $missing = @()
  foreach ($key in $defaults.Keys) {
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $probe = (& $exe config get $key --json 2>&1 | Out-String); $code = $LASTEXITCODE }
    finally { $ErrorActionPreference = $prevEap }
    if ($code -eq 0) { continue }
    if ($probe -notmatch 'Config key not set') {
      Write-UabsWarn ("Hermes config read failed for {0}; preserved as-is" -f $key)
      continue
    }
    $missing += $key
  }
  if (-not $missing.Count) { Write-UabsOk 'Hermes efficiency/cache defaults already present'; return }

  Backup-UabsFile -Path $Dest
  foreach ($key in $missing) {
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & $exe config set $key $defaults[$key] 2>&1 | ForEach-Object { Write-Host ('     ' + $_) }; $code = $LASTEXITCODE }
    finally { $ErrorActionPreference = $prevEap }
    if ($code -ne 0) { throw "Hermes rejected efficiency default ${key}." }
  }
  Write-UabsOk ("Hermes filled {0} missing efficiency/cache setting(s); existing values preserved" -f $missing.Count)
}

function Remove-UabsHermesLegacyOpenRouterExtra {
  param([string]$Dest)
  if (-not (Test-Path -LiteralPath $Dest -PathType Leaf)) { return }
  $exe = Join-Path $env:LOCALAPPDATA 'hermes\hermes-agent\venv\Scripts\hermes.exe'
  $python = Join-Path $env:LOCALAPPDATA 'hermes\hermes-agent\venv\Scripts\python.exe'
  if (-not (Test-Path -LiteralPath $exe -PathType Leaf) -or
      -not (Test-Path -LiteralPath $python -PathType Leaf)) {
    Write-UabsWarn 'Hermes CLI unavailable; legacy openrouter-extra migration skipped'
    return
  }
  $legacyFound = $false
  foreach ($key in @('providers', 'custom_providers')) {
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $raw = (& $exe config get $key --json 2>&1 | Out-String); $code = $LASTEXITCODE }
    finally { $ErrorActionPreference = $prevEap }
    if ($code -ne 0) {
      if ($raw -notmatch 'Config key not set') {
        Write-UabsWarn ("Hermes {0} inventory could not be read; preserved as-is" -f $key)
        return
      }
      continue
    }
    try { [void]($raw | ConvertFrom-Json) } catch {
      Write-UabsWarn ("Hermes {0} inventory was not valid JSON; preserved as-is" -f $key)
      return
    }
    if ($raw -match '"name"\s*:\s*"openrouter-extra"' -or
        $raw -match '"openrouter-extra"\s*:') { $legacyFound = $true }
  }
  if (-not $legacyFound) { return }

  Backup-UabsFile -Path $Dest
  $tmp = Join-Path ([IO.Path]::GetTempPath()) ('uabs-hermes-provider-' + [guid]::NewGuid().ToString('N') + '.py')
  $script = @'
import copy
import os
import sys
from pathlib import Path
from ruamel.yaml import YAML

path = Path(sys.argv[1])
yaml = YAML()
yaml.preserve_quotes = True
with path.open("r", encoding="utf-8") as stream:
    cfg = yaml.load(stream) or {}
for section in ("providers", "custom_providers"):
    providers = cfg.get(section)
    if isinstance(providers, list):
        providers = [p for p in providers if not (isinstance(p, dict) and p.get("name") == "openrouter-extra")]
        if providers:
            cfg[section] = providers
        else:
            cfg.pop(section, None)
    elif isinstance(providers, dict):
        providers.pop("openrouter-extra", None)
        if not providers:
            cfg.pop(section, None)
expected = copy.deepcopy(cfg)
tmp = path.with_name(path.name + ".uabs-provider.tmp")
with tmp.open("w", encoding="utf-8", newline="") as stream:
    yaml.dump(cfg, stream)
with tmp.open("r", encoding="utf-8") as stream:
    saved = yaml.load(stream) or {}
if saved != expected:
    tmp.unlink(missing_ok=True)
    raise SystemExit(3)
for section in ("providers", "custom_providers"):
    check = saved.get(section) or []
    if isinstance(check, list) and any(isinstance(p, dict) and p.get("name") == "openrouter-extra" for p in check):
        raise SystemExit(2)
    if isinstance(check, dict) and "openrouter-extra" in check:
        raise SystemExit(2)
os.replace(tmp, path)
'@
  try {
    $enc = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($tmp, $script, $enc)
    & $python $tmp $Dest
    if ($LASTEXITCODE -ne 0) { throw 'Hermes rejected the legacy provider migration' }
    Write-UabsOk 'Hermes: removed legacy openrouter-extra; native OpenRouter model discovery remains enabled'
  } finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath ($Dest + '.uabs-provider.tmp') -Force -ErrorAction SilentlyContinue
  }
}

function Ensure-UabsGrokMcpSearchDisabled {
  param([string]$Dest)
  if (-not (Test-Path -LiteralPath $Dest -PathType Leaf)) { return }
  $raw = [IO.File]::ReadAllText($Dest)
  if ($raw -match '(?m)^disabled_mcp_servers\s*=.*mcp-search') {
    Write-UabsOk 'Grok mcp-search already disabled'
    return
  }
  Backup-UabsFile -Path $Dest
  if ($raw -match '(?m)^disabled_mcp_servers\s*=') {
    $raw = [regex]::Replace($raw, '(?m)^(disabled_mcp_servers\s*=\s*\[)([^\]]*)\]', {
      param($m)
      $inner = $m.Groups[2].Value.Trim()
      if ($inner -match 'mcp-search') { return $m.Value }
      if (-not $inner) { return 'disabled_mcp_servers = ["mcp-search"]' }
      return ('disabled_mcp_servers = [' + $inner.TrimEnd(',') + ', "mcp-search"]')
    })
  } else {
    $raw = 'disabled_mcp_servers = ["mcp-search"]' + [Environment]::NewLine + $raw
  }
  $utf8 = New-Object System.Text.UTF8Encoding $false
  [IO.File]::WriteAllText($Dest, $raw, $utf8)
  Write-UabsOk 'Grok disabled mcp-search (plugin server occupies a running MCP slot)'
}

Write-UabsStep 'Provider starter settings (portable; no live-machine dump)'

foreach ($prov in $Providers) {
  # NEVER assign the PowerShell HOME automatic variable. It is constant;
  # writing to it aborts the whole starter-settings pass
  # ("Cannot overwrite variable HOME because it is read-only or constant").
  $provHome = Get-UabsProviderHome -Provider $prov -Catalog $catalog
  $srcRoot = Join-Path $tailored "$prov\COPY-TO-PROVIDER-HOME"
  switch ($prov) {
    'Claude' {
      $src = Join-Path $srcRoot 'settings.json'
      if (Test-Path -LiteralPath $src) {
        Merge-UabsClaudeSettings -Src $src -Dest (Join-Path $provHome 'settings.json')
      }
    }
    'Codex' {
      $src = Join-Path $srcRoot 'config.toml'
      if (Test-Path -LiteralPath $src) {
        Copy-UabsStarterIfMissing -Src $src -Dest (Join-Path $provHome 'config.toml') -Label Codex
      }
    }
    'Grok' {
      $src = Join-Path $srcRoot 'config.toml'
      $dest = Join-Path $provHome 'config.toml'
      if (Test-Path -LiteralPath $src) {
        Copy-UabsStarterIfMissing -Src $src -Dest $dest -Label Grok
        Ensure-UabsGrokMcpSearchDisabled -Dest $dest
      }
    }
    'Kimi' {
      $src = Join-Path $srcRoot 'config.toml'
      if (Test-Path -LiteralPath $src) {
        Copy-UabsStarterIfMissing -Src $src -Dest (Join-Path $provHome 'config.toml') -Label Kimi
      }
    }
    'Hermes' {
      if ($SkipHermes) { Write-UabsOk 'Hermes starter config skipped'; continue }
      $src = Join-Path $srcRoot 'config.yaml'
      if (Test-Path -LiteralPath $src) {
        $dest = Join-Path $provHome 'config.yaml'
        Copy-UabsStarterIfMissing -Src $src -Dest $dest -Label Hermes
        Remove-UabsHermesLegacyOpenRouterExtra -Dest $dest
        Merge-UabsHermesEfficiencyDefaults -Dest $dest
      }
    }
  }
}
