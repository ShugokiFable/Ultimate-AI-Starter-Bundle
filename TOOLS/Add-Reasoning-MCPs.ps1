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
#>
[CmdletBinding()]
param(
  [string[]]$Providers = @('Claude', 'Grok', 'Codex', 'Kimi'),
  [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'

# Windows PowerShell 5.1's `Set-Content -Encoding utf8` writes a UTF-8 BOM. A BOM
# in a JSON config is a real hazard: a strict reader rejects the file outright.
# This pack exists partly because a BOM once made seven skills invisible, so it
# does not get to reintroduce one. Write BOM-less UTF-8 explicitly.
function Set-Utf8NoBom {
  param([string]$Path, [string]$Text)
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Text, $enc)
}


if (-not (Get-Command npx -ErrorAction SilentlyContinue)) {
  Write-Host 'SKIP: Node/npx not found. Install Node 18+ and re-run.' -ForegroundColor Yellow
  exit 0
}

# Pinned majors, not "@latest": a server that silently changes its tool surface
# mid-session is worse than one that is a point release behind.
$servers = @(
  @{
    id   = 'context7'
    args = @('-y', '@upstash/context7-mcp@4')
    note = 'live library/API docs - stops invented signatures'
    env  = @{}
    key  = 'CONTEXT7_API_KEY'   # optional: higher rate limits
  },
  @{
    id   = 'sequential-thinking'
    args = @('-y', '@modelcontextprotocol/server-sequential-thinking')
    note = 'explicit problem decomposition'
    env  = @{}
    key  = $null
  },
  @{
    id   = 'github'
    args = @('-y', '@modelcontextprotocol/server-github')
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
    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
  } else { [pscustomobject]@{} }

  if ($json.PSObject.Properties.Name -notcontains $Section) {
    $json | Add-Member -NotePropertyName $Section -NotePropertyValue ([pscustomobject]@{})
  }
  $added = @()
  foreach ($s in $servers) {
    if ($json.$Section.PSObject.Properties.Name -contains $s.id) { continue }
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
  'Claude' = @{ Path = Join-Path $env:USERPROFILE '.claude.json'; Section = 'mcpServers'; Style = 'json' }
  'Kimi'   = @{ Path = Join-Path $env:USERPROFILE '.kimi-code\mcp.json'; Section = 'mcpServers'; Style = 'json' }
  'Grok'   = @{ Path = Join-Path $env:USERPROFILE '.grok\config.toml'; Section = 'mcp_servers'; Style = 'toml' }
  'Codex'  = @{ Path = Join-Path $env:USERPROFILE '.codex\config.toml'; Section = 'mcp_servers'; Style = 'toml' }
}

foreach ($p in $Providers) {
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
  } else {
    # TOML: append only the servers that are not already declared. Editing TOML
    # by hand is safer than a round-trip that would reorder the user's config.
    $text = if (Test-Path -LiteralPath $t.Path) { Get-Content -LiteralPath $t.Path -Raw } else { '' }
    $append = ''
    $added = @()
    foreach ($s in $servers) {
      if ($text -match [regex]::Escape("[$($t.Section).$($s.id)]")) { continue }
      $argList = ($s.args | ForEach-Object { '"' + $_ + '"' }) -join ', '
      $append += "`r`n# $($s.note)`r`n[$($t.Section).$($s.id)]`r`ncommand = `"npx`"`r`nargs = [$argList]`r`n"
      $added += $s.id
    }
    if ($added.Count -and -not $CheckOnly) {
      Copy-Item -LiteralPath $t.Path -Destination "$($t.Path).bak-mcp-$(Get-Date -Format yyyyMMdd-HHmmss)" -Force -ErrorAction SilentlyContinue
      Set-Utf8NoBom -Path $t.Path -Text ((Get-Content -LiteralPath $t.Path -Raw) + $append)
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
