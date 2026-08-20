<#
.SYNOPSIS
  Install the MCP servers that most directly raise one-shot success.

.DESCRIPTION
  These three were chosen against a single question: what actually makes the
  first attempt correct, rather than making the agent feel more capable?

  context7      Live, versioned library and API documentation with citations.
                The single biggest cause of a confidently wrong first attempt is
                an invented function signature or a call that was valid two
                releases ago. This replaces recall with the current doc.

  sequential-thinking
                Structured decomposition as a tool the model calls, so a hard
                problem is broken down explicitly instead of answered in one
                jump. Helps most on the multi-constraint tasks where a fast
                model skips a step.

  github        Official GitHub server: repos, PRs, issues, releases, CI status,
                Dependabot and security findings. Turns "push and hope" into
                something the agent can verify it actually did.

  All three are npx-based: no binaries are redistributed by this pack, and each
  update comes from upstream.

.PARAMETER Providers
  Which providers to wire. Default: every one detected.

.PARAMETER CheckOnly
  Report what would change and exit.

.PARAMETER Refresh
  Rewrite an existing entry so pins and timeouts stay current. Without this,
  a server that is already declared is left alone - which is how a broken
  unpinned npx cache survived an upgrade.
#>
[CmdletBinding()]
param(
  [string[]]$Providers = @('Claude', 'Grok', 'Codex', 'Kimi', 'Hermes'),
  [switch]$CheckOnly,
  [switch]$Refresh
)

$ErrorActionPreference = 'Stop'

# Accept both -Providers Claude,Codex (comma string, e.g. via -File) and
# -Providers @('Claude','Codex').
if ($Providers.Count -eq 1 -and $Providers[0] -match ',') {
  $Providers = $Providers[0] -split ','
}

# Windows PowerShell 5.1's `Set-Content -Encoding utf8` writes a UTF-8 BOM. A BOM
# in a JSON config is a real hazard: a strict reader rejects the file outright.
# This pack exists partly because a BOM once made seven skills invisible, so it
# does not get to reintroduce one. Write BOM-less UTF-8 explicitly.
function Set-Utf8NoBom {
  param([string]$Path, [string]$Text)
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Text, $enc)
}

function Get-ClaudeDesktopConfigPath {
  # Claude Desktop app ships as either a normal install (%APPDATA%\Claude)
  # or a Microsoft Store package (LocalCache\Roaming\Claude). Return the
  # live claude_desktop_config.json, or $null when the app is absent. The
  # app's own MCP surface is this file; ~/.claude.json only feeds Claude
  # Code CLI sessions, so a desktop-only user would otherwise get no servers.
  $Normal = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'Claude\claude_desktop_config.json'
  if (Test-Path -LiteralPath $Normal -PathType Leaf) { return $Normal }
  $Store = Get-ChildItem -LiteralPath (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Packages') -Directory -Filter 'Claude_*' -ErrorAction SilentlyContinue |
    ForEach-Object { Join-Path $_.FullName 'LocalCache\Roaming\Claude\claude_desktop_config.json' } |
    Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
    Select-Object -First 1
  return $Store
}


if (-not (Get-Command npx -ErrorAction SilentlyContinue)) {
  Write-Host 'SKIP: Node/npx not found. Install Node 18+ and re-run.' -ForegroundColor Yellow
  exit 0
}

# Exact versions, not "@latest" and not a bare major. A major-only pin still
# lets npx reuse a broken cache (observed: context7@4 missing
# @modelcontextprotocol/core/dist/internal.mjs; sequential-thinking unpinned
# missing zod). A server that silently changes its tool surface mid-session is
# worse than one a point release behind.
$servers = @(
  @{
    id   = 'context7'
    args = @('-y', '@upstash/context7-mcp@4.0.2')
    note = 'live library/API docs - stops invented signatures'
    env  = @{}
    key  = 'CONTEXT7_API_KEY'   # optional: higher rate limits
  },
  @{
    id   = 'sequential-thinking'
    args = @('-y', '@modelcontextprotocol/server-sequential-thinking@2026.7.4')
    note = 'explicit problem decomposition'
    env  = @{}
    key  = $null
  },
  @{
    id   = 'github'
    args = @('-y', '@modelcontextprotocol/server-github@2025.4.8')
    note = 'repos, PRs, releases, CI status'
    env  = @{}
    key  = 'GITHUB_PERSONAL_ACCESS_TOKEN'
  }
)

function Write-JsonFile {
  param([string]$Path, $Object)
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  if (Test-Path -LiteralPath $Path) {
    Copy-Item -LiteralPath $Path -Destination "$Path.bak-mcp-$(Get-Date -Format yyyyMMdd-HHmmss)" -Force
  }
  Set-Utf8NoBom -Path $Path -Text ($Object | ConvertTo-Json -Depth 20)
}

function Add-ToJsonMcp {
  param([string]$Path, [string]$Section)
  $json = if (Test-Path -LiteralPath $Path) {
    [IO.File]::ReadAllText($Path) | ConvertFrom-Json
  } else { [pscustomobject]@{} }

  if ($json.PSObject.Properties.Name -notcontains $Section) {
    $json | Add-Member -NotePropertyName $Section -NotePropertyValue ([pscustomobject]@{})
  }
  $added = @()
  foreach ($s in $servers) {
    if ($json.$Section.PSObject.Properties.Name -contains $s.id) {
      if (-not $Refresh) { continue }
      $json.$Section.PSObject.Properties.Remove($s.id)
    }
    $entry = [ordered]@{ command = 'npx'; args = $s.args }
    # $env:$name is not valid PowerShell; resolve the name dynamically.
    $keyValue = if ($s.key) { [Environment]::GetEnvironmentVariable($s.key) } else { $null }
    if ($keyValue) { $entry['env'] = @{ $s.key = $keyValue } }
    $json.$Section | Add-Member -NotePropertyName $s.id -NotePropertyValue ([pscustomobject]$entry)
    $added += $s.id
  }
  if ($added.Count -and -not $CheckOnly) { Write-JsonFile -Path $Path -Object $json }
  return $added
}

$targets = @{
  'Claude' = @{ Path = Join-Path $env:USERPROFILE '.claude.json'; Section = 'mcpServers'; Style = 'json'; Desktop = $true }
  'Kimi'   = @{ Path = Join-Path $env:USERPROFILE '.kimi-code\mcp.json'; Section = 'mcpServers'; Style = 'json' }
  'Grok'   = @{ Path = Join-Path $env:USERPROFILE '.grok\config.toml'; Section = 'mcp_servers'; Style = 'toml' }
  'Codex'  = @{ Path = Join-Path $env:USERPROFILE '.codex\config.toml'; Section = 'mcp_servers'; Style = 'toml' }
}

foreach ($p in $Providers) {
  if ($p -eq 'Hermes') {
    # Hermes' `mcp add` is interactive after discovery. Hidden stdin piping can
    # block on Windows PowerShell 5.1, so use Hermes' own config API instead.
    $hx = Join-Path $env:LOCALAPPDATA 'hermes\hermes-agent\venv\Scripts\hermes.exe'
    if (-not (Test-Path -LiteralPath $hx)) { Write-Host 'Hermes  not installed, skipped'; continue }
    $hpy = Join-Path (Split-Path -Parent $hx) 'python.exe'
    if (-not (Test-Path -LiteralPath $hpy -PathType Leaf)) { Write-Host 'Hermes  Python runtime missing, skipped'; continue }
    $existing = & $hx mcp list 2>&1 | Out-String
    $addedH = @()
    foreach ($s in $servers) {
      if ($existing -match [regex]::Escape($s.id)) { continue }
      if ($CheckOnly) { $addedH += $s.id; continue }
      $tmp = Join-Path ([IO.Path]::GetTempPath()) ('uabs-hermes-reasoning-' + [guid]::NewGuid().ToString('N') + '.py')
      $oldId = $env:UABS_HERMES_MCP_ID; $oldArgs = $env:UABS_HERMES_MCP_ARGS_JSON
      try {
        $env:UABS_HERMES_MCP_ID = $s.id
        $env:UABS_HERMES_MCP_ARGS_JSON = ($s.args | ConvertTo-Json -Compress)
        $helper = @'
import json, os
from hermes_cli.config import load_config, save_config
cfg = load_config()
servers = cfg.setdefault("mcp_servers", {})
servers[os.environ["UABS_HERMES_MCP_ID"]] = {
    "command": "npx",
    "args": json.loads(os.environ["UABS_HERMES_MCP_ARGS_JSON"]),
    "enabled": True,
    "connect_timeout": 30,
}
save_config(cfg)
'@
        $enc = New-Object System.Text.UTF8Encoding($false)
        [IO.File]::WriteAllText($tmp, $helper, $enc)
        & $hpy $tmp
        if ($LASTEXITCODE -ne 0) { throw "Hermes MCP config update failed for $($s.id) with exit code $LASTEXITCODE" }
        $addedH += $s.id
      } finally {
        if ($null -eq $oldId) { Remove-Item Env:UABS_HERMES_MCP_ID -ErrorAction SilentlyContinue } else { $env:UABS_HERMES_MCP_ID = $oldId }
        if ($null -eq $oldArgs) { Remove-Item Env:UABS_HERMES_MCP_ARGS_JSON -ErrorAction SilentlyContinue } else { $env:UABS_HERMES_MCP_ARGS_JSON = $oldArgs }
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
      }
    }
    if ($addedH.Count) { Write-Host ("{0,-7} {1} -> Hermes config (noninteractive)" -f $p, ($addedH -join ', ')) }
    else { Write-Host ("{0,-7} already has all three" -f $p) }
    continue
  }
  $t = $targets[$p]
  if (-not $t) { Write-Host ("{0,-7} unknown provider" -f $p); continue }
  $providerHome = Split-Path -Parent $t.Path
  if (-not (Test-Path -LiteralPath $providerHome)) { Write-Host ("{0,-7} not installed, skipped" -f $p); continue }

  if ($t.Style -eq 'json') {
    $added = Add-ToJsonMcp -Path $t.Path -Section $t.Section
    if ($added.Count) {
      Write-Host ("{0,-7} {1} -> {2}" -f $p, ($added -join ', '), $t.Path)
    } else {
      Write-Host ("{0,-7} already has all three" -f $p)
    }
    if ($t.Desktop) {
      # Claude Desktop app reads claude_desktop_config.json, not ~/.claude.json.
      # Merge the same entries there so desktop-only users get the servers.
      $desktopCfg = Get-ClaudeDesktopConfigPath
      if ($desktopCfg) {
        $addedD = Add-ToJsonMcp -Path $desktopCfg -Section 'mcpServers'
        if ($addedD.Count) {
          Write-Host ("{0,-7} {1} -> {2} (Claude Desktop app)" -f $p, ($addedD -join ', '), $desktopCfg)
        }
      }
    }
  } else {
    # TOML: append only the servers that are not already declared. Editing TOML
    # by hand is safer than a round-trip that would reorder the user's config.
    $text = if (Test-Path -LiteralPath $t.Path) { [IO.File]::ReadAllText($t.Path) } else { '' }
    $append = ''
    $added = @()
    # Grok also reads ~/.claude.json. A second copy of the same server is two
    # handshakes for one name, which is how "MCP is slow to start" starts.
    $claudeJson = Join-Path $env:USERPROFILE '.claude.json'
    $claudeHas = @()
    if ($p -eq 'Grok' -and (Test-Path -LiteralPath $claudeJson)) {
      try {
        $cj = [IO.File]::ReadAllText($claudeJson) | ConvertFrom-Json
        if ($cj.mcpServers) { $claudeHas = @($cj.mcpServers.PSObject.Properties.Name) }
      } catch { }
    }

    foreach ($s in $servers) {
      if ($p -eq 'Grok' -and $claudeHas -contains $s.id) {
        Write-Host ("{0,-7} inherits {1} from ~/.claude.json (not duplicated)" -f $p, $s.id)
        continue
      }
      $already = $text -match [regex]::Escape("[$($t.Section).$($s.id)]")
      if ($already) {
        Write-Host ("{0,-7} {1} already in {2} (not duplicated)" -f $p, $s.id, $t.Path)
        continue
      }
      $argList = ($s.args | ForEach-Object { '"' + $_ + '"' }) -join ', '
      $timeout = if ($p -eq 'Grok') { "startup_timeout_sec = 90`r`n" } else { '' }
      $append += "`r`n# $($s.note)`r`n[$($t.Section).$($s.id)]`r`ncommand = `"npx`"`r`nargs = [$argList]`r`n$timeout"
      $added += $s.id
    }
    if ($added.Count -and -not $CheckOnly) {
      Copy-Item -LiteralPath $t.Path -Destination "$($t.Path).bak-mcp-$(Get-Date -Format yyyyMMdd-HHmmss)" -Force -ErrorAction SilentlyContinue
      Set-Utf8NoBom -Path $t.Path -Text (([IO.File]::ReadAllText($t.Path)) + $append)
    }
    if ($added.Count) {
      Write-Host ("{0,-7} {1} -> {2}" -f $p, ($added -join ', '), $t.Path)
    } else {
      Write-Host ("{0,-7} already has all three" -f $p)
    }
  }
}

Write-Host ''
Write-Host 'Optional keys (both servers work without one, with lower limits):'
Write-Host '  setx CONTEXT7_API_KEY "<key>"                 https://context7.com'
Write-Host '  setx GITHUB_PERSONAL_ACCESS_TOKEN "<token>"   github.com/settings/tokens'
Write-Host 'Restart each AI app, then check /mcp.'
