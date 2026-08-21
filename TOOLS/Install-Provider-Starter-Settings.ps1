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
. (Join-Path $PackRoot 'TOOLS\V7-Common.ps1')
$catalog = Get-V5Catalog
$tailored = Join-Path $PackRoot '1-TAILORED-PROVIDER-TREES'

function Test-V5PortableTemplate {
  param([string]$Path)
  $raw = [IO.File]::ReadAllText($Path)
  if ($raw -match '(?i)C:\\Users\\[^\\\s"]+' -or $raw -match '(?i)/Users/[^/\s"]+' -or $raw -match '(?i)S:\\Apps\\') {
    throw ("Refusing machine-local template (contains a user or Apps path): " + $Path)
  }

  # A starter template carries portable PREFERENCES. MCP registration belongs to
  # INSTALL-V7-AIO.ps1 and Set-McpProfile.ps1, which read what is actually
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
             " -- MCP is wired by INSTALL-V7-AIO.ps1 and Set-McpProfile.ps1 from what is installed, not copied from a template.")
    }
  }

  # An unpinned server can change its tool surface mid-session, and npx will
  # happily reuse a broken cache. The catalog pins every server it owns; a
  # template is not the place the policy gets an exemption.
  if ($code -match '@latest') {
    throw ("Refusing starter template with an unpinned @latest package: " + $Path)
  }
}

function Backup-V5File {
  param([string]$Path)
  if (Test-Path -LiteralPath $Path -PathType Leaf) {
    Copy-Item -LiteralPath $Path -Destination ($Path + '.before-starter-' + (Get-Date -Format 'yyyyMMdd-HHmmssfff') + '.bak') -Force
  }
}

function Merge-V5ClaudeSettings {
  param([string]$Src, [string]$Dest)
  Test-V5PortableTemplate -Path $Src
  $srcObj = [IO.File]::ReadAllText($Src) | ConvertFrom-Json
  $destDir = Split-Path -Parent $Dest
  if (-not (Test-Path -LiteralPath $destDir)) {
    Write-V5Warn 'Claude home not present; skipped settings.json'
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
    Backup-V5File -Path $Dest
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [IO.File]::WriteAllText($Dest, (($destObj | ConvertTo-Json -Depth 20) + [Environment]::NewLine), $utf8)
    Write-V5Ok ('Claude settings.json merged: ' + $Dest)
  } else {
    Write-V5Ok 'Claude settings.json already had starter keys'
  }
}

function Copy-V5StarterIfMissing {
  param([string]$Src, [string]$Dest, [string]$Label)
  Test-V5PortableTemplate -Path $Src
  $destDir = Split-Path -Parent $Dest
  if (-not (Test-Path -LiteralPath $destDir)) {
    Write-V5Warn ("{0} home not present; skipped {1}" -f $Label, (Split-Path -Leaf $Dest))
    return
  }
  if (Test-Path -LiteralPath $Dest -PathType Leaf) {
    Write-V5Ok ("{0} existing {1} preserved" -f $Label, (Split-Path -Leaf $Dest))
    return
  }
  New-Item -ItemType Directory -Force -Path $destDir | Out-Null
  Copy-Item -LiteralPath $Src -Destination $Dest -Force
  Write-V5Ok ("{0} starter {1} installed: {2}" -f $Label, (Split-Path -Leaf $Dest), $Dest)
}

function Ensure-V5GrokMcpSearchDisabled {
  param([string]$Dest)
  if (-not (Test-Path -LiteralPath $Dest -PathType Leaf)) { return }
  $raw = [IO.File]::ReadAllText($Dest)
  if ($raw -match '(?m)^disabled_mcp_servers\s*=.*mcp-search') {
    Write-V5Ok 'Grok mcp-search already disabled'
    return
  }
  Backup-V5File -Path $Dest
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
  Write-V5Ok 'Grok disabled mcp-search (plugin server occupies a running MCP slot)'
}

Write-V5Step 'Provider starter settings (portable; no live-machine dump)'

foreach ($prov in $Providers) {
  # NEVER assign the PowerShell HOME automatic variable. It is constant;
  # writing to it aborts the whole starter-settings pass
  # ("Cannot overwrite variable HOME because it is read-only or constant").
  $provHome = Get-V5ProviderHome -Provider $prov -Catalog $catalog
  $srcRoot = Join-Path $tailored "$prov\COPY-TO-PROVIDER-HOME"
  switch ($prov) {
    'Claude' {
      $src = Join-Path $srcRoot 'settings.json'
      if (Test-Path -LiteralPath $src) {
        Merge-V5ClaudeSettings -Src $src -Dest (Join-Path $provHome 'settings.json')
      }
    }
    'Codex' {
      $src = Join-Path $srcRoot 'config.toml'
      if (Test-Path -LiteralPath $src) {
        Copy-V5StarterIfMissing -Src $src -Dest (Join-Path $provHome 'config.toml') -Label Codex
      }
    }
    'Grok' {
      $src = Join-Path $srcRoot 'config.toml'
      $dest = Join-Path $provHome 'config.toml'
      if (Test-Path -LiteralPath $src) {
        Copy-V5StarterIfMissing -Src $src -Dest $dest -Label Grok
        Ensure-V5GrokMcpSearchDisabled -Dest $dest
      }
    }
    'Kimi' {
      $src = Join-Path $srcRoot 'config.toml'
      if (Test-Path -LiteralPath $src) {
        Copy-V5StarterIfMissing -Src $src -Dest (Join-Path $provHome 'config.toml') -Label Kimi
      }
    }
    'Hermes' {
      if ($SkipHermes) { Write-V5Ok 'Hermes starter config skipped'; continue }
      $src = Join-Path $srcRoot 'config.yaml'
      if (Test-Path -LiteralPath $src) {
        Copy-V5StarterIfMissing -Src $src -Dest (Join-Path $provHome 'config.yaml') -Label Hermes
      }
    }
  }
}
