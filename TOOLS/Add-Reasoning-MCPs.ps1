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

  These three are always on because they apply to every task. Everything else
  this pack can wire is a capability profile in BUNDLED-TOOLS/PROFILES.json,
  registered by TOOLS\Set-McpProfile.ps1 only when a project needs it -- MCP
  tool schemas are not lazy, and a server that is connected costs context on
  every turn whether or not the task is related.

  context7 and sequential-thinking are npx-based. GitHub's official MCP server
  ships Windows binaries rather than an npm package, so it is installed from the
  pack's SHA-pinned offline asset and registered by absolute path.

  All config writing lives in TOOLS\V7-Mcp-Write.ps1, shared with
  Set-McpProfile.ps1. Four providers keep MCP servers in three different shapes
  and every bug in this area has been a bug in one shape that the other three
  did not have; two scripts writing configs meant finding each one twice.

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

. (Join-Path $PSScriptRoot 'V7-Mcp-Write.ps1')

# Accept both -Providers Claude,Codex (comma string, e.g. via -File) and
# -Providers @('Claude','Codex').
if ($Providers.Count -eq 1 -and $Providers[0] -match ',') {
  $Providers = $Providers[0] -split ','
}

$hasNpx = [bool](Get-Command npx -ErrorAction SilentlyContinue)
if (-not $hasNpx) {
  Write-Host 'NOTE: Node/npx not found - skipping the two npx servers. Install Node 18+ and re-run for those.' -ForegroundColor Yellow
}

# Exact versions, not "@latest" and not a bare major. A major-only pin still
# lets npx reuse a broken cache (observed: context7@4 missing
# @modelcontextprotocol/core/dist/internal.mjs; sequential-thinking unpinned
# missing zod). A server that silently changes its tool surface mid-session is
# worse than one a point release behind.
# Resolve the official GitHub MCP server, installed from the pack's offline
# asset by the AIO's zip-extract path. Absent (component not installed, or a
# skills-only run) means the entry is skipped, not guessed at.
$ghExe = Join-Path $env:LOCALAPPDATA 'Skyrim-AI-V5\github-mcp-server\github-mcp-server.exe'

$servers = @(
  @{
    id      = 'context7'
    command = 'npx'
    args    = @('-y', '@upstash/context7-mcp@4.0.2')
    note    = 'live library/API docs - stops invented signatures'
    key     = 'CONTEXT7_API_KEY'   # optional: higher rate limits
  },
  @{
    id      = 'sequential-thinking'
    command = 'npx'
    args    = @('-y', '@modelcontextprotocol/server-sequential-thinking@2026.7.4')
    note    = 'explicit problem decomposition'
    key     = $null
  },
  @{
    # GitHub's official server. The previous entry here was
    # @modelcontextprotocol/server-github, from the MCP reference-server
    # collection; npm now reports it as 'Package no longer supported'. Note
    # that v7.7.11 already 'fixed' this line by pinning it -- the pin held and
    # the package died anyway, which is why CATALOG.json entries now carry a
    # version to check rather than only a pin to trust.
    #
    # --toolsets is scoped deliberately. The server groups its tools into 20
    # toolsets and 'all' puts every one of their schemas in the model's context
    # on every turn. These five are what this pack actually uses.
    id      = 'github'
    command = $ghExe
    args    = @('stdio', '--toolsets', 'context,repos,pull_requests,actions,issues')
    note    = 'repos, PRs, releases, CI status (official server, scoped toolsets)'
    key     = 'GITHUB_PERSONAL_ACCESS_TOKEN'
  }
)

# A server whose command cannot run is worse than an absent one: the provider
# shows no tools and says nothing about why. Drop those before writing configs.
$servers = @($servers | Where-Object {
  if ($_['command'] -eq 'npx') { return $hasNpx }
  if (Test-Path -LiteralPath $_['command'] -PathType Leaf) { return $true }
  Write-Host ("SKIP {0}: not installed at {1}" -f $_['id'], $_['command']) -ForegroundColor Yellow
  return $false
})
if (-not $servers) {
  Write-Host 'No reasoning MCP servers are available to register.' -ForegroundColor Yellow
  exit 0
}

# Dedupe keys on the server NAME, so an entry that already exists is left alone.
# That is right for user configuration and wrong for a package upstream has
# withdrawn: the name stays valid while the command behind it rots. List the
# exact literals here; anything matching is removed so the current definition is
# written in its place.
$retiredLiterals = @('@modelcontextprotocol/server-github')
$serverIds = @($servers | ForEach-Object { $_['id'] })

$targets = Get-V5McpTargets

foreach ($p in $Providers) {
  $p = $p.Trim()
  if (-not $p) { continue }

  if ($p -eq 'Hermes') {
    $hpaths = Get-V5HermesPaths
    if (-not (Test-Path -LiteralPath $hpaths.Exe -PathType Leaf)) { Write-Host 'Hermes  not installed, skipped'; continue }
    if (-not (Test-Path -LiteralPath $hpaths.Python -PathType Leaf)) { Write-Host 'Hermes  Python runtime missing, skipped'; continue }
    if (Test-V5HermesRetired -Literals $retiredLiterals) {
      $retired = @(Remove-V5McpHermes -Ids $serverIds -CheckOnly:$CheckOnly)
      if ($retired.Count) {
        Write-Host ("{0,-7} retired {1} (upstream package withdrawn, rewriting all three)" -f $p, ($retired -join ', ')) -ForegroundColor Yellow
      }
    }
    $addedH = @(Add-V5McpHermes -Servers $servers -Refresh:$Refresh -CheckOnly:$CheckOnly)
    if ($addedH.Count) { Write-Host ("{0,-7} {1} -> Hermes config (noninteractive)" -f $p, ($addedH -join ', ')) }
    else { Write-Host ("{0,-7} already has all three" -f $p) }
    continue
  }

  $t = $targets[$p]
  if (-not $t) { Write-Host ("{0,-7} unknown provider" -f $p); continue }
  $providerHome = Split-Path -Parent $t.Path
  if (-not (Test-Path -LiteralPath $providerHome)) { Write-Host ("{0,-7} not installed, skipped" -f $p); continue }

  if ($t.Style -eq 'json') {
    $retired = @(Remove-V5McpJson -Path $t.Path -Section $t.Section -MatchLiterals $retiredLiterals -CheckOnly:$CheckOnly)
    if ($retired.Count) { Write-Host ("{0,-7} retired {1} (upstream package withdrawn)" -f $p, ($retired -join ', ')) -ForegroundColor Yellow }
    $added = @(Add-V5McpJson -Path $t.Path -Section $t.Section -Servers $servers -Provider $p -Refresh:$Refresh -CheckOnly:$CheckOnly)
    if ($added.Count) { Write-Host ("{0,-7} {1} -> {2}" -f $p, ($added -join ', '), $t.Path) }
    else { Write-Host ("{0,-7} already has all three" -f $p) }

    if ($t.Desktop) {
      # Claude Desktop app reads claude_desktop_config.json, not ~/.claude.json.
      # Merge the same entries there so desktop-only users get the servers.
      $desktopCfg = Get-ClaudeDesktopConfigPath
      if ($desktopCfg) {
        [void](Remove-V5McpJson -Path $desktopCfg -Section 'mcpServers' -MatchLiterals $retiredLiterals -CheckOnly:$CheckOnly)
        $addedD = @(Add-V5McpJson -Path $desktopCfg -Section 'mcpServers' -Servers $servers -Provider $p -Refresh:$Refresh -CheckOnly:$CheckOnly)
        if ($addedD.Count) { Write-Host ("{0,-7} {1} -> {2} (Claude Desktop app)" -f $p, ($addedD -join ', '), $desktopCfg) }
      }
    }
    continue
  }

  $retired = @(Remove-V5McpToml -Path $t.Path -Section $t.Section -MatchLiterals $retiredLiterals -CheckOnly:$CheckOnly)
  if ($retired.Count) { Write-Host ("{0,-7} retired {1} (upstream package withdrawn)" -f $p, ($retired -join ', ')) -ForegroundColor Yellow }

  # Grok also reads ~/.claude.json. A second copy of the same server is two
  # handshakes for one name, which is how "MCP is slow to start" starts.
  $tomlServers = $servers
  if ($p -eq 'Grok') {
    $claudeJson = Join-Path $env:USERPROFILE '.claude.json'
    $claudeHas = @()
    if (Test-Path -LiteralPath $claudeJson) {
      try {
        $cj = [IO.File]::ReadAllText($claudeJson) | ConvertFrom-Json
        if ($cj.mcpServers) { $claudeHas = @($cj.mcpServers.PSObject.Properties.Name) }
      } catch { }
    }
    $tomlServers = @($servers | Where-Object {
      if ($claudeHas -contains $_['id']) {
        Write-Host ("{0,-7} inherits {1} from ~/.claude.json (not duplicated)" -f $p, $_['id'])
        return $false
      }
      return $true
    })
  }

  $added = @()
  if ($tomlServers.Count) {
    $added = @(Add-V5McpToml -Path $t.Path -Section $t.Section -Servers $tomlServers -Provider $p -Refresh:$Refresh -CheckOnly:$CheckOnly -GrokTimeout:($p -eq 'Grok'))
  }
  if ($added.Count) { Write-Host ("{0,-7} {1} -> {2}" -f $p, ($added -join ', '), $t.Path) }
  else { Write-Host ("{0,-7} already has all three" -f $p) }
}

Write-Host ''
Write-Host 'Optional keys (both servers work without one, with lower limits):'
Write-Host '  setx CONTEXT7_API_KEY "<key>"                 https://context7.com'
Write-Host '  setx GITHUB_PERSONAL_ACCESS_TOKEN "<token>"   github.com/settings/tokens'
Write-Host 'Restart each AI app, then check /mcp.'
Write-Host ''
Write-Host 'Capability profiles (browser, Serena, Blender, Godot, Unity, Supabase) are'
Write-Host 'off by default. See what applies to a project:'
Write-Host '  TOOLS\Set-McpProfile.ps1 -List'
Write-Host '  TOOLS\Set-McpProfile.ps1 -Auto -Path <your project>'
