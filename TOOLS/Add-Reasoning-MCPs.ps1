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

  Not here any more: sequential-thinking. It held the third slot until 7.9.7
  and lost it on measurement. Speaking real MCP to it gives one tool and a
  4,587-byte schema -- ~1,146 tokens on every turn of every session, as much as
  context7's two tools -- for a structured scratchpad rather than a capability:
  it fetches nothing and reaches nothing the model could not write in its own
  reasoning. It is the 'reasoning' profile now, off unless asked for:

      TOOLS\Set-McpProfile.ps1 -Enable reasoning -Global

  github        Official GitHub server: repos, PRs, issues, releases, CI status,
                Dependabot and security findings. Turns "push and hope" into
                something the agent can verify it actually did.

  headroom      Context inspection/compression tools. Registered for every
                provider when the installed command is available.

  These two are always on because they apply to every task. Everything else
  this pack can wire is a capability profile in BUNDLED-TOOLS/PROFILES.json,
  registered by TOOLS\Set-McpProfile.ps1 only when a project needs it -- MCP
  tool schemas are not lazy, and a server that is connected costs context on
  every turn whether or not the task is related.

  context7 is npx-based. GitHub's official MCP server
  ships Windows binaries rather than an npm package, so it is installed from the
  pack's SHA-pinned offline asset and registered by absolute path.

  All config writing lives in TOOLS\UABS-Mcp-Write.ps1, shared with
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

. (Join-Path $PSScriptRoot 'UABS-Mcp-Write.ps1')

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
$ghExe = Join-Path $env:LOCALAPPDATA 'Ultimate-AI-Starter-Bundle\github-mcp-server\github-mcp-server.exe'

# The context7 pin lives in CATALOG.json, not here. It was hardcoded until
# 8.6.12, and that made the catalog decorative for the one server registered on
# ALL FIVE providers: 8.6.12 bumped context7 4.0.2 -> 4.0.3, re-measured its
# capability record, shipped it -- and a full installer re-run left every
# provider still pinned to 4.0.2, because this file had its own copy. A version
# in two places is a version in the wrong place.
#
# Falls back to the previous literal if the catalog cannot be read, so a
# damaged catalog degrades to "one release behind" rather than "unpinned".
$context7Args = @('-y', '@upstash/context7-mcp@4.0.3')
try {
  $catalogPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'BUNDLED-TOOLS\CATALOG.json'
  if (Test-Path -LiteralPath $catalogPath -PathType Leaf) {
    $cat = [IO.File]::ReadAllText($catalogPath) | ConvertFrom-Json
    $c7 = $cat.components | Where-Object { $_.id -eq 'context7' } | Select-Object -First 1
    if ($c7 -and $c7.npx_args) {
      $fromCatalog = @($c7.npx_args | ForEach-Object { [string]$_ })
      if (@($fromCatalog | Where-Object { $_ -like '*context7-mcp@*' }).Count) {
        $context7Args = $fromCatalog
      }
    }
  }
} catch { }

# A machine installed before 7.9.7 still has sequential-thinking registered.
# Say so, with the number and the command -- do not silently remove a server the
# user may be relying on, and do not silently keep charging them for it either.
function Show-UabsSequentialThinkingNotice {
  $found = @()
  foreach ($t in (Get-UabsMcpTargets).GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $t.Value.Path -PathType Leaf)) { continue }
    $text = [IO.File]::ReadAllText($t.Value.Path)
    if ($text -match 'server-sequential-thinking') { $found += $t.Key }
  }
  $hp = Get-UabsHermesPaths
  if ((Test-Path -LiteralPath $hp.Config -PathType Leaf) -and
      ([IO.File]::ReadAllText($hp.Config) -match 'server-sequential-thinking')) { $found += 'Hermes' }
  if (-not $found.Count) { return }
  Write-Host ''
  Write-Host ("sequential-thinking is still registered for: {0}" -f (($found | Sort-Object -Unique) -join ', ')) -ForegroundColor Yellow
  Write-Host  '  It left the always-on core in 7.9.7 on measurement: 1 tool, 4,587-byte schema,' -ForegroundColor DarkGray
  Write-Host  '  ~1,146 tokens on every turn of every session. Nothing here removed it for you.' -ForegroundColor DarkGray
  Write-Host  '  Keep it:   TOOLS\Set-McpProfile.ps1 -Enable reasoning -Global' -ForegroundColor DarkGray
  Write-Host  '  Drop it:   TOOLS\Set-McpProfile.ps1 -Disable reasoning' -ForegroundColor DarkGray
}

$servers = @(
  @{
    id      = 'context7'
    command = 'npx'
    args    = $context7Args
    note    = 'live library/API docs - stops invented signatures'
    key     = 'CONTEXT7_API_KEY'   # optional: higher rate limits
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

$headroom = $null
try { $headroom = (Get-Command headroom -ErrorAction SilentlyContinue).Source } catch { }
if (-not $headroom) { $headroom = [Environment]::GetEnvironmentVariable('HEADROOM_CMD', 'User') }
if ($headroom -and (Test-Path -LiteralPath $headroom -PathType Leaf)) {
  $servers += @{
    id      = 'headroom'
    command = $headroom
    args    = @('mcp','serve')
    note    = 'context inspection and compression'
    key     = $null
  }
}

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

$targets = Get-UabsMcpTargets

foreach ($p in $Providers) {
  $p = $p.Trim()
  if (-not $p) { continue }

  if ($p -eq 'Hermes') {
    $hpaths = Get-UabsHermesPaths
    if (-not (Test-Path -LiteralPath $hpaths.Exe -PathType Leaf)) { Write-Host 'Hermes  not installed, skipped'; continue }
    if (-not (Test-Path -LiteralPath $hpaths.Python -PathType Leaf)) { Write-Host 'Hermes  Python runtime missing, skipped'; continue }
    if (Test-UabsHermesRetired -Literals $retiredLiterals) {
      $retired = @(Remove-UabsMcpHermes -Ids $serverIds -CheckOnly:$CheckOnly)
      if ($retired.Count) {
        Write-Host ("{0,-7} retired {1} (upstream package withdrawn, rewriting the core)" -f $p, ($retired -join ', ')) -ForegroundColor Yellow
      }
    }
    $addedH = @(Add-UabsMcpHermes -Servers $servers -Refresh:$Refresh -CheckOnly:$CheckOnly)
    if ($addedH.Count) { Write-Host ("{0,-7} {1} -> Hermes config (noninteractive)" -f $p, ($addedH -join ', ')) }
    else { Write-Host ("{0,-7} nothing to add" -f $p) }
    continue
  }

  $t = $targets[$p]
  if (-not $t) { Write-Host ("{0,-7} unknown provider" -f $p); continue }
  $providerHome = Split-Path -Parent $t.Path
  if (-not (Test-Path -LiteralPath $providerHome)) { Write-Host ("{0,-7} not installed, skipped" -f $p); continue }

  if ($t.Style -eq 'json') {
    $retired = @(Remove-UabsMcpJson -Path $t.Path -Section $t.Section -MatchLiterals $retiredLiterals -CheckOnly:$CheckOnly)
    if ($retired.Count) { Write-Host ("{0,-7} retired {1} (upstream package withdrawn)" -f $p, ($retired -join ', ')) -ForegroundColor Yellow }
    $added = @(Add-UabsMcpJson -Path $t.Path -Section $t.Section -Servers $servers -Provider $p -Refresh:$Refresh -CheckOnly:$CheckOnly)
    if ($added.Count) { Write-Host ("{0,-7} {1} -> {2}" -f $p, ($added -join ', '), $t.Path) }
    else { Write-Host ("{0,-7} nothing to add" -f $p) }

    if ($t.Desktop) {
      # Claude Desktop app reads claude_desktop_config.json, not ~/.claude.json.
      # Merge the same entries there so desktop-only users get the servers.
      $desktopCfg = Get-ClaudeDesktopConfigPath
      if ($desktopCfg) {
        [void](Remove-UabsMcpJson -Path $desktopCfg -Section 'mcpServers' -MatchLiterals $retiredLiterals -CheckOnly:$CheckOnly)
        $addedD = @(Add-UabsMcpJson -Path $desktopCfg -Section 'mcpServers' -Servers $servers -Provider $p -Refresh:$Refresh -CheckOnly:$CheckOnly)
        if ($addedD.Count) { Write-Host ("{0,-7} {1} -> {2} (Claude Desktop app)" -f $p, ($addedD -join ', '), $desktopCfg) }
      }
    }
    continue
  }

  $retired = @(Remove-UabsMcpToml -Path $t.Path -Section $t.Section -MatchLiterals $retiredLiterals -CheckOnly:$CheckOnly)
  if ($retired.Count) { Write-Host ("{0,-7} retired {1} (upstream package withdrawn)" -f $p, ($retired -join ', ')) -ForegroundColor Yellow }

  # Grok can read ~/.claude.json, but only while its Claude-compat MCP cell is
  # on -- and this same installer writes [compat.claude] mcps = false. Assuming
  # inheritance after switching it off is not a dedupe, it is a silent omission:
  # Grok ended up with no github and no sequential-thinking.
  $tomlServers = $servers
  if ($p -eq 'Grok') {
    if (Test-UabsGrokInheritsClaudeMcp) {
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
    # Only the ones not already declared count against the budget.
    $grokText = if (Test-Path -LiteralPath $t.Path) { [IO.File]::ReadAllText($t.Path) } else { '' }
    $newOnes = @($tomlServers | Where-Object { $grokText -notmatch [regex]::Escape("[$($t.Section).$($_['id'])]") })
    if ($newOnes.Count) {
      $allowed = @(Select-UabsWithinGrokBudget -Servers $newOnes)
      $allowedIds = @($allowed | ForEach-Object { $_['id'] })
      $tomlServers = @($tomlServers | Where-Object {
        ($grokText -match [regex]::Escape("[$($t.Section).$($_['id'])]")) -or ($allowedIds -contains $_['id'])
      })
    }
  }

  $added = @()
  if ($tomlServers.Count) {
    $added = @(Add-UabsMcpToml -Path $t.Path -Section $t.Section -Servers $tomlServers -Provider $p -Refresh:$Refresh -CheckOnly:$CheckOnly -GrokTimeout:($p -eq 'Grok'))
  }
  if ($added.Count) { Write-Host ("{0,-7} {1} -> {2}" -f $p, ($added -join ', '), $t.Path) }
  else { Write-Host ("{0,-7} nothing to add" -f $p) }
}

Write-Host ''
Write-Host 'Optional credentials:'
Write-Host '  setx CONTEXT7_API_KEY "<key>"                 https://context7.com'
Write-Host '  GitHub needs no PAT: its official binary opens browser OAuth on the first authenticated tool call.'
Write-Host '  A PAT is an optional alternative only; configure credentials yourself, never through an AI prompt.'
Write-Host 'Restart each AI app, then check /mcp.'
Write-Host ''
Show-UabsSequentialThinkingNotice
Write-Host ''
Write-Host 'Capability profiles (browser, Serena, Blender, Godot, Unity, reasoning) are'
Write-Host 'off by default and wired for one project. See what applies to a project:'
Write-Host '  TOOLS\Set-McpProfile.ps1 -List'
Write-Host '  TOOLS\Set-McpProfile.ps1 -Auto -Path <your project>'
