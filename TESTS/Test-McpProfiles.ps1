<#
.SYNOPSIS
  Proves the shared MCP writer and the capability-profile catalog.

.DESCRIPTION
  Add-Reasoning-MCPs.ps1 and Set-McpProfile.ps1 both write provider configs
  through TOOLS\V7-Mcp-Write.ps1. Every config-writing bug this pack has shipped
  was a bug in one of the three config shapes that the other two did not have,
  and each was found on a user's machine rather than in a test:

    * a TOML table matcher that ended at the '[' inside `args = ["-y", ...]`,
      so the block it matched stopped before the string it was hunting
    * a Hermes check that read `mcp list` output -- which prints names, never
      the commands behind them -- for a package literal
    * a backslash escaped four times instead of two, producing a command that
      does not exist: the silent-no-tools failure, inside its own fix

  Everything below runs against temp files. No test in this file may read or
  write a real provider config.
#>
[CmdletBinding()]
param([string]$PackRoot)

$ErrorActionPreference = 'Stop'
if (-not $PackRoot) { $PackRoot = Split-Path -Parent $PSScriptRoot }

. (Join-Path $PackRoot 'TOOLS\V7-Mcp-Write.ps1')

$script:fail = 0
function Good($m) { Write-Host "  ok   $m" -ForegroundColor Green }
function Bad($m)  { Write-Host "  FAIL $m" -ForegroundColor Red; $script:fail++ }
function Is($actual, $expected, $what) {
  if ($actual -eq $expected) { Good $what } else { Bad ("{0}: expected [{1}], got [{2}]" -f $what, $expected, $actual) }
}
function Section($t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }

$sandbox = Join-Path ([IO.Path]::GetTempPath()) ('uabs-mcp-gate-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $sandbox | Out-Null

try {

# ---------------------------------------------------------------- catalog ----
Section 'PROFILES.json'

$profilesPath = Join-Path $PackRoot 'BUNDLED-TOOLS\PROFILES.json'
if (-not (Test-Path -LiteralPath $profilesPath -PathType Leaf)) {
  Bad 'BUNDLED-TOOLS\PROFILES.json missing'
} else {
  $cat = [IO.File]::ReadAllText($profilesPath) | ConvertFrom-Json
  Good 'parses as JSON'

  $ids = @($cat.profiles | ForEach-Object { $_.id })
  Is @($ids | Select-Object -Unique).Count $ids.Count 'profile ids are unique'

  $serverIds = @($cat.profiles | ForEach-Object { $_.servers } | ForEach-Object { $_.id })
  Is @($serverIds | Select-Object -Unique).Count $serverIds.Count 'server ids are unique across profiles'

  # A profile server that collides with an always-on server would be written
  # twice under one name: two handshakes, one entry, and whichever the provider
  # read last wins.
  $core = @('context7', 'sequential-thinking', 'github')
  $collide = @($serverIds | Where-Object { $core -contains $_ })
  if ($collide.Count) { Bad ("profile server collides with the always-on core: {0}" -f ($collide -join ', ')) }
  else { Good 'no profile server shadows an always-on server' }

  foreach ($p in $cat.profiles) {
    foreach ($field in 'id', 'title', 'why', 'servers') {
      if (-not $p.$field) { Bad ("profile {0} has no {1}" -f $p.id, $field) }
    }
    foreach ($s in $p.servers) {
      foreach ($field in 'id', 'command', 'args', 'note') {
        if ($null -eq $s.$field) { Bad ("{0}/{1} has no {2}" -f $p.id, $s.id, $field) }
      }
      # An unpinned npx server can change its tool surface mid-session, and npx
      # will happily reuse a broken cache. This pack pins, everywhere.
      foreach ($a in @($s.args)) {
        if ($a -match '@latest$') { Bad ("{0}/{1} pins @latest: {2}" -f $p.id, $s.id, $a) }
      }
      if ($s.command -eq 'npx') {
        $pkg = @($s.args | Where-Object { $_ -notmatch '^-' } | Select-Object -First 1)
        if ($pkg -and $pkg -notmatch '@[0-9]') { Bad ("{0}/{1} npx package is not version-pinned: {2}" -f $p.id, $s.id, $pkg) }
      }
    }
  }
  Good 'every profile and server declares its required fields'
}

# ------------------------------------------------------------------- JSON ----
Section 'JSON providers'

$jsonPath = Join-Path $sandbox 'claude.json'
Set-Utf8NoBom -Path $jsonPath -Text '{"mcpServers":{"keepme":{"command":"x","args":[]}},"otherKey":123}'

$oneArg = @{ id = 'blender'; command = 'uvx'; args = @('blender-mcp'); note = 'n'; key = $null }
$added = @(Add-V5McpJson -Path $jsonPath -Section 'mcpServers' -Servers @($oneArg) -Provider 'Claude')
Is $added.Count 1 'adds a server'

$read = [IO.File]::ReadAllText($jsonPath) | ConvertFrom-Json
Is $read.mcpServers.blender.command 'uvx' 'command round-trips'
# A one-element array that serializes as a bare string is a config the provider
# will reject or misread -- and blender-mcp takes exactly one argument.
if ($read.mcpServers.blender.args -is [array]) { Good 'single-element args stay an array' }
else { Bad ("single-element args collapsed to {0}" -f $read.mcpServers.blender.args.GetType().Name) }
Is $read.otherKey 123 'unrelated top-level keys survive'
Is $read.mcpServers.keepme.command 'x' 'unrelated servers survive'

$again = @(Add-V5McpJson -Path $jsonPath -Section 'mcpServers' -Servers @($oneArg) -Provider 'Claude')
Is $again.Count 0 'a declared server is left alone without -Refresh'

$dropped = @(Remove-V5McpJson -Path $jsonPath -Section 'mcpServers' -Ids @('blender'))
Is $dropped.Count 1 'removes by id'
$read = [IO.File]::ReadAllText($jsonPath) | ConvertFrom-Json
if ($read.mcpServers.PSObject.Properties.Name -contains 'blender') { Bad 'removed server is still declared' } else { Good 'removed server is gone' }
Is $read.mcpServers.keepme.command 'x' 'removal leaves siblings alone'

# ------------------------------------------------------------------- TOML ----
Section 'TOML providers'

$tomlPath = Join-Path $sandbox 'config.toml'
Set-Utf8NoBom -Path $tomlPath -Text @"
[general]
theme = "dark"

[mcp_servers.keepme]
command = "keep"
args = ["-y", "keep-me@1.0.0"]

[mcp_servers.dead]
command = "npx"
args = ["-y", "@modelcontextprotocol/server-github"]
"@

$winSrv = @{ id = 'serena'; command = 'C:\Users\x\.local\bin\serena.exe'; args = @('start-mcp-server', '--context', 'codex'); note = 'lsp'; key = $null }
[void](Add-V5McpToml -Path $tomlPath -Section 'mcp_servers' -Servers @($winSrv) -Provider 'Codex')
$text = [IO.File]::ReadAllText($tomlPath)

# TOML escapes a backslash as exactly two. Four parses back to a doubled
# separator and a command that does not exist.
if ($text -match 'command = "C:\\\\Users\\\\x\\\\\.local\\\\bin\\\\serena\.exe"') { Good 'backslashes are escaped exactly once over' }
else { Bad ("backslash escaping is wrong: " + (($text -split "`r?`n" | Where-Object { $_ -like 'command = "C:*' }) -join ' | ')) }

# The bug this whole gate exists for: `args = ["-y", ...]` contains a '[', so a
# table matcher that ends at the next bracket never sees the package string.
$retired = @(Remove-V5McpToml -Path $tomlPath -Section 'mcp_servers' -MatchLiterals @('@modelcontextprotocol/server-github'))
Is $retired.Count 1 'finds a retired literal past the bracket inside args'
Is $retired[0] 'dead' 'names the right table'

$text = [IO.File]::ReadAllText($tomlPath)
if ($text -match '\[mcp_servers\.dead\]') { Bad 'retired table survived' } else { Good 'retired table removed' }
if ($text -match '\[mcp_servers\.keepme\]') { Good 'sibling table survived' } else { Bad 'sibling table was removed too' }
if ($text -match '\[general\]') { Good 'unrelated section survived' } else { Bad 'unrelated section removed' }

# Sub-tables belong to their parent: dropping [x.a] but keeping [x.a.env]
# orphans a table the TOML parser will reject or attach to the wrong entry.
Set-Utf8NoBom -Path $tomlPath -Text @"
[mcp_servers.withenv]
command = "npx"
args = ["-y", "thing@1.0.0"]

[mcp_servers.withenv.env]
TOKEN = "abc"

[mcp_servers.after]
command = "after"
args = []
"@
$dropped = @(Remove-V5McpToml -Path $tomlPath -Section 'mcp_servers' -Ids @('withenv'))
$text = [IO.File]::ReadAllText($tomlPath)
if ($text -match 'withenv') { Bad 'sub-table orphaned by parent removal' } else { Good 'sub-table removed with its parent' }
if ($text -match '\[mcp_servers\.after\]') { Good 'the table after a removed family survived' } else { Bad 'removal ate the following table' }

# An env block is only written for variables that are actually set.
$envVar = 'UABS_MCP_GATE_TOKEN'
[Environment]::SetEnvironmentVariable($envVar, 'secret-value')
try {
  $keyed = @{ id = 'keyed'; command = 'npx'; args = @('-y', 'k@1.0.0'); note = 'n'; key = $envVar }
  Set-Utf8NoBom -Path $tomlPath -Text ''
  [void](Add-V5McpToml -Path $tomlPath -Section 'mcp_servers' -Servers @($keyed) -Provider 'Codex')
  $text = [IO.File]::ReadAllText($tomlPath)
  if ($text -match '\[mcp_servers\.keyed\.env\]' -and $text -match 'secret-value') { Good 'a set key is written into an env sub-table' }
  else { Bad 'env sub-table missing for a set key' }
} finally { [Environment]::SetEnvironmentVariable($envVar, $null) }

Set-Utf8NoBom -Path $tomlPath -Text ''
[void](Add-V5McpToml -Path $tomlPath -Section 'mcp_servers' -Servers @($keyed) -Provider 'Codex')
$text = [IO.File]::ReadAllText($tomlPath)
if ($text -match '\.env\]') { Bad 'env sub-table written for an unset variable' } else { Good 'no env sub-table when the variable is unset' }

# ------------------------------------------------------------ requirements ----
Section 'requirement gating'

Is (Expand-V5Template -Text '{project}\Library\x.exe' -ProjectPath 'C:\proj') 'C:\proj\Library\x.exe' '{project} expands'
Is (Expand-V5Template -Text '{project}\x' -ProjectPath '') '' '{project} with no project resolves to empty'

$noCmd = @{ id = 'x'; command = 'q'; args = @(); note = 'n'; requires = @{ command = 'definitely-not-a-real-command-9f3a' } }
$r = Test-V5ServerRequirement -Server $noCmd -ProjectPath ''
Is $r.Ok $false 'a missing command fails the gate'
if ($r.Reason -match 'definitely-not-a-real-command') { Good 'the reason names the missing command' } else { Bad "reason is not specific: $($r.Reason)" }

$noEnv = @{ id = 'x'; command = 'q'; args = @(); note = 'n'; requires = @{ env = 'UABS_DEFINITELY_UNSET_9F3A' } }
Is (Test-V5ServerRequirement -Server $noEnv -ProjectPath '').Ok $false 'an unset key variable fails the gate'

$noProj = @{ id = 'x'; command = 'q'; args = @(); note = 'n'; requires = @{ project_rel = 'Library\nope.exe' } }
Is (Test-V5ServerRequirement -Server $noProj -ProjectPath $sandbox).Ok $false 'a missing project file fails the gate'

$ok = @{ id = 'x'; command = 'q'; args = @(); note = 'n' }
Is (Test-V5ServerRequirement -Server $ok -ProjectPath '').Ok $true 'no requirements means ready'

# ----------------------------------------------------------------- Hermes ----
Section 'Hermes'

$fakeHermes = Join-Path $sandbox 'hermes'
New-Item -ItemType Directory -Force -Path $fakeHermes | Out-Null
$savedHome = $env:HERMES_HOME
try {
  $env:HERMES_HOME = $fakeHermes
  Set-Utf8NoBom -Path (Join-Path $fakeHermes 'config.yaml') -Text @"
mcp_servers:
  github:
    command: npx
    args:
      - -y
      - '@modelcontextprotocol/server-github'
  other:
    command: x
"@
  # `mcp list` prints names, never commands, so it can never reveal a withdrawn
  # package. Reading the stored config can.
  Is (Test-V5HermesRetired -Literals @('@modelcontextprotocol/server-github')) $true 'detects a retired package in the stored config'
  Is (Test-V5HermesRetired -Literals @('something-else-entirely')) $false 'does not fire on an unrelated literal'

  $targets = @(Remove-V5McpHermes -Ids @('github', 'context7') -CheckOnly)
  Is ($targets -join ',') 'github' 'names only the ids actually declared'
} finally {
  if ($null -eq $savedHome) { Remove-Item Env:HERMES_HOME -ErrorAction SilentlyContinue } else { $env:HERMES_HOME = $savedHome }
}

# ------------------------------------------------------- dead-path repair ----
Section 'dead MCP command paths'

# Repair-McpPaths knew one shape: a version-stamped sibling (Name-1.2.3), which
# is this pack's own convention. Codex keys its runtime directories by content
# hash, so an update leaves every config pointing at a directory that no longer
# exists -- same silent failure, unmatched by that rule. The generalisation is
# "exactly one sibling under which the tail exists", and the uniqueness half is
# what has to be tested: picking wrong writes a config aimed at another binary.
function New-FakeExe([string]$Path) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  Set-Utf8NoBom -Path $Path -Text 'x'
}

function Invoke-RepairInSandbox([string]$Root, [string]$DeadPath) {
  $codexDir = Join-Path $Root '.codex'
  New-Item -ItemType Directory -Force -Path $codexDir | Out-Null
  Set-Utf8NoBom -Path (Join-Path $codexDir 'config.toml') -Text (
    "[mcp_servers.node_repl]`r`ncommand = '" + $DeadPath + "'`r`nargs = []`r`n")
  $saved = @{ U = $env:USERPROFILE; L = $env:LOCALAPPDATA }
  try {
    $env:USERPROFILE = $Root
    $env:LOCALAPPDATA = Join-Path $Root 'LocalAppData'
    New-Item -ItemType Directory -Force -Path $env:LOCALAPPDATA | Out-Null
    & (Join-Path $PackRoot 'TOOLS\Repair-McpPaths.ps1') -Apply -Quiet *> $null
  } finally {
    $env:USERPROFILE = $saved.U
    $env:LOCALAPPDATA = $saved.L
  }
  return [IO.File]::ReadAllText((Join-Path $codexDir 'config.toml'))
}

$repairRoot = Join-Path $sandbox 'repair-unique'
$runtimes = Join-Path $repairRoot 'runtimes\cua_node'
New-FakeExe (Join-Path $runtimes '84464046935436b8\bin\node_repl.exe')
$dead = Join-Path $runtimes '2fb562745e6d66f0\bin\node_repl.exe'
$after = Invoke-RepairInSandbox -Root $repairRoot -DeadPath $dead
if ($after -match '84464046935436b8') { Good 'repoints a hash-named directory to its only live sibling' }
else { Bad ('hash-named directory was not repaired: ' + ($after -replace "`r?`n", ' ')) }
if ($after -notmatch '2fb562745e6d66f0') { Good 'the dead path is gone' } else { Bad 'the dead path survived the repair' }

$ambigRoot = Join-Path $sandbox 'repair-ambiguous'
$ambigRuntimes = Join-Path $ambigRoot 'runtimes\cua_node'
New-FakeExe (Join-Path $ambigRuntimes 'aaaaaaaaaaaaaaaa\bin\node_repl.exe')
New-FakeExe (Join-Path $ambigRuntimes 'bbbbbbbbbbbbbbbb\bin\node_repl.exe')
$deadAmbig = Join-Path $ambigRuntimes 'cccccccccccccccc\bin\node_repl.exe'
$afterAmbig = Invoke-RepairInSandbox -Root $ambigRoot -DeadPath $deadAmbig
# Two candidates is not a resolution. Reporting it beats picking one.
if ($afterAmbig -match 'cccccccccccccccc') { Good 'two candidates are reported, not guessed between' }
else { Bad 'an ambiguous dead path was rewritten anyway' }

# ------------------------------------------------------------ script shape ----
Section 'front-end script'

$setProfile = Join-Path $PackRoot 'TOOLS\Set-McpProfile.ps1'
if (-not (Test-Path -LiteralPath $setProfile -PathType Leaf)) {
  Bad 'TOOLS\Set-McpProfile.ps1 missing'
} else {
  $out = & (Join-Path $PSHOME 'powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $setProfile -List -PackRoot $PackRoot 2>&1 | Out-String
  if ($LASTEXITCODE -eq 0) { Good '-List exits 0' } else { Bad "-List exited $LASTEXITCODE" }
  foreach ($needle in 'code-deep', 'engine-blender', 'not shipped') {
    if ($out -match [regex]::Escape($needle)) { Good "-List reports $needle" } else { Bad "-List output has no $needle" }
  }
}

# Both writers must share one implementation. Two copies means every bug in
# this file has to be found twice.
$reasoning = [IO.File]::ReadAllText((Join-Path $PackRoot 'TOOLS\Add-Reasoning-MCPs.ps1'))
foreach ($needle in 'V7-Mcp-Write.ps1', 'Add-V5McpJson', 'Add-V5McpToml') {
  if ($reasoning -match [regex]::Escape($needle)) { Good "Add-Reasoning-MCPs uses $needle" } else { Bad "Add-Reasoning-MCPs does not use $needle" }
}
if ($reasoning -match "'y'\s*\|\s*&\s*\`$hx mcp add") { Bad 'reasoning-MCP wiring still hides a Hermes interactive prompt' }
else { Good 'no hidden interactive Hermes prompt' }

} finally {
  Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($script:fail) {
  Write-Host ("MCP PROFILE GATE: {0} failure(s)" -f $script:fail) -ForegroundColor Red
  exit 1
}
Write-Host 'MCP PROFILE GATE: PASS' -ForegroundColor Green
exit 0
