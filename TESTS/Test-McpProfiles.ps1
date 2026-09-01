<#
.SYNOPSIS
  Proves the shared MCP writer and the capability-profile catalog.

.DESCRIPTION
  Add-Reasoning-MCPs.ps1 and Set-McpProfile.ps1 both write provider configs
  through TOOLS\UABS-Mcp-Write.ps1. Every config-writing bug this pack has shipped
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

. (Join-Path $PackRoot 'TOOLS\UABS-Mcp-Write.ps1')

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
  # Read the core from the script that defines it. Hardcoding it here meant
  # this check kept comparing against a list that had moved on: 7.9.7 took
  # sequential-thinking out of always-on and into a profile, which this test
  # then reported as a collision with a core it was no longer part of.
  $reasoningSrc = [IO.File]::ReadAllText((Join-Path $PackRoot 'TOOLS\Add-Reasoning-MCPs.ps1'))
  $coreBlock = ($reasoningSrc -split [regex]::Escape('$servers = @('))[1]
  $core = @([regex]::Matches($coreBlock, "(?m)^\s*id\s*=\s*'(?<id>[^']+)'") | ForEach-Object { $_.Groups['id'].Value })
  if (-not $core.Count) { Bad 'could not read the always-on core from Add-Reasoning-MCPs.ps1' }
  else { Good ("always-on core read from source: {0}" -f ($core -join ', ')) }
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
$added = @(Add-UabsMcpJson -Path $jsonPath -Section 'mcpServers' -Servers @($oneArg) -Provider 'Claude')
Is $added.Count 1 'adds a server'

$read = [IO.File]::ReadAllText($jsonPath) | ConvertFrom-Json
Is $read.mcpServers.blender.command 'uvx' 'command round-trips'
# A one-element array that serializes as a bare string is a config the provider
# will reject or misread -- and blender-mcp takes exactly one argument.
if ($read.mcpServers.blender.args -is [array]) { Good 'single-element args stay an array' }
else { Bad ("single-element args collapsed to {0}" -f $read.mcpServers.blender.args.GetType().Name) }
Is $read.otherKey 123 'unrelated top-level keys survive'
Is $read.mcpServers.keepme.command 'x' 'unrelated servers survive'

$again = @(Add-UabsMcpJson -Path $jsonPath -Section 'mcpServers' -Servers @($oneArg) -Provider 'Claude')
Is $again.Count 0 'a declared server is left alone without -Refresh'

$dropped = @(Remove-UabsMcpJson -Path $jsonPath -Section 'mcpServers' -Ids @('blender'))
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
[void](Add-UabsMcpToml -Path $tomlPath -Section 'mcp_servers' -Servers @($winSrv) -Provider 'Codex')
$text = [IO.File]::ReadAllText($tomlPath)

# TOML escapes a backslash as exactly two. Four parses back to a doubled
# separator and a command that does not exist.
if ($text -match 'command = "C:\\\\Users\\\\x\\\\\.local\\\\bin\\\\serena\.exe"') { Good 'backslashes are escaped exactly once over' }
else { Bad ("backslash escaping is wrong: " + (($text -split "`r?`n" | Where-Object { $_ -like 'command = "C:*' }) -join ' | ')) }

# The bug this whole gate exists for: `args = ["-y", ...]` contains a '[', so a
# table matcher that ends at the next bracket never sees the package string.
$retired = @(Remove-UabsMcpToml -Path $tomlPath -Section 'mcp_servers' -MatchLiterals @('@modelcontextprotocol/server-github'))
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
$dropped = @(Remove-UabsMcpToml -Path $tomlPath -Section 'mcp_servers' -Ids @('withenv'))
$text = [IO.File]::ReadAllText($tomlPath)
if ($text -match 'withenv') { Bad 'sub-table orphaned by parent removal' } else { Good 'sub-table removed with its parent' }
if ($text -match '\[mcp_servers\.after\]') { Good 'the table after a removed family survived' } else { Bad 'removal ate the following table' }

# A user may comment a table out to disable it. It is documentation, not a
# registration: the doctor must report it off and a later explicit enable must
# be able to create one active table.
Set-Utf8NoBom -Path $tomlPath -Text @"
# [mcp_servers.serena]
# command = "old"
# args = []
"@
Is (Test-UabsServerDeclared -Path $tomlPath -Style 'toml' -Section 'mcp_servers' -Id 'serena') $false 'a commented TOML table is not registered'
$added = @(Add-UabsMcpToml -Path $tomlPath -Section 'mcp_servers' -Servers @($winSrv) -Provider 'Codex')
Is $added.Count 1 'a commented TOML table does not block re-enable'
Is ([regex]::Matches([IO.File]::ReadAllText($tomlPath), '(?m)^\[mcp_servers\.serena\]\r?$').Count) 1 're-enable writes exactly one active TOML table'

# An env block is only written for variables that are actually set.
$envVar = 'UABS_MCP_GATE_TOKEN'
[Environment]::SetEnvironmentVariable($envVar, 'secret-value')
try {
  $keyed = @{ id = 'keyed'; command = 'npx'; args = @('-y', 'k@1.0.0'); note = 'n'; key = $envVar }
  Set-Utf8NoBom -Path $tomlPath -Text ''
  [void](Add-UabsMcpToml -Path $tomlPath -Section 'mcp_servers' -Servers @($keyed) -Provider 'Codex')
  $text = [IO.File]::ReadAllText($tomlPath)
  if ($text -match '\[mcp_servers\.keyed\.env\]' -and $text -match 'secret-value') { Good 'a set key is written into an env sub-table' }
  else { Bad 'env sub-table missing for a set key' }
} finally { [Environment]::SetEnvironmentVariable($envVar, $null) }

Set-Utf8NoBom -Path $tomlPath -Text ''
[void](Add-UabsMcpToml -Path $tomlPath -Section 'mcp_servers' -Servers @($keyed) -Provider 'Codex')
$text = [IO.File]::ReadAllText($tomlPath)
if ($text -match '\.env\]') { Bad 'env sub-table written for an unset variable' } else { Good 'no env sub-table when the variable is unset' }

# Non-secret policy values (for example a telemetry opt-out) are not user
# credentials and must be present even when no process variable was set.
$staticEnv = @{ id = 'static'; command = 'uvx'; args = @('thing@1.0.0'); note = 'n'; env_static = @{ DISABLE_TELEMETRY = 'true' } }
$resolvedStatic = Resolve-UabsServerEnv -Server $staticEnv
Is $resolvedStatic['DISABLE_TELEMETRY'] 'true' 'a static server environment policy is resolved without a process variable'
Set-Utf8NoBom -Path $tomlPath -Text ''
[void](Add-UabsMcpToml -Path $tomlPath -Section 'mcp_servers' -Servers @($staticEnv) -Provider 'Codex')
$text = [IO.File]::ReadAllText($tomlPath)
if ($text -match '\[mcp_servers\.static\.env\]' -and $text -match 'DISABLE_TELEMETRY = "true"') { Good 'a static environment policy reaches TOML provider config' }
else { Bad 'static environment policy was dropped from TOML provider config' }

# ------------------------------------------------------------ requirements ----
Section 'requirement gating'

Is (Expand-UabsTemplate -Text '{project}\Library\x.exe' -ProjectPath 'C:\proj') 'C:\proj\Library\x.exe' '{project} expands'
Is (Expand-UabsTemplate -Text '{project}\x' -ProjectPath '') '' '{project} with no project resolves to empty'

$script:fakeProfilePython = Join-Path $sandbox 'python.exe'
[IO.File]::WriteAllBytes($script:fakeProfilePython, [byte[]]@(0))
function Get-UabsPythonExecutable { return $script:fakeProfilePython }
Is (Expand-UabsTemplate -Text 'python' -ProjectPath '') $script:fakeProfilePython 'bare python resolves through the shared runtime helper'
Is (Test-UabsCommandAvailable -Command 'python' -ProjectPath '') $true 'resolved Python satisfies a profile command requirement'

$noCmd = @{ id = 'x'; command = 'q'; args = @(); note = 'n'; requires = @{ command = 'definitely-not-a-real-command-9f3a' } }
$r = Test-UabsServerRequirement -Server $noCmd -ProjectPath ''
Is $r.Ok $false 'a missing command fails the gate'
if ($r.Reason -match 'definitely-not-a-real-command') { Good 'the reason names the missing command' } else { Bad "reason is not specific: $($r.Reason)" }

$noEnv = @{ id = 'x'; command = 'q'; args = @(); note = 'n'; requires = @{ env = 'UABS_DEFINITELY_UNSET_9F3A' } }
Is (Test-UabsServerRequirement -Server $noEnv -ProjectPath '').Ok $false 'an unset key variable fails the gate'

$noProj = @{ id = 'x'; command = 'q'; args = @(); note = 'n'; requires = @{ project_rel = 'Library\nope.exe' } }
Is (Test-UabsServerRequirement -Server $noProj -ProjectPath $sandbox).Ok $false 'a missing project file fails the gate'

$ok = @{ id = 'x'; command = 'q'; args = @(); note = 'n' }
Is (Test-UabsServerRequirement -Server $ok -ProjectPath '').Ok $true 'no requirements means ready'

# ----------------------------------------------------------------- Hermes ----
Section 'Hermes'
Is (ConvertTo-UabsJsonArray @('one')) '["one"]' 'one Hermes id stays a JSON array'
Is (ConvertTo-UabsJsonArray @('one','two')) '["one","two"]' 'multiple Hermes ids stay a JSON array'
$oneArgServer = @{ args=@('only'); key=$null }
Is (ConvertTo-Json -InputObject (Resolve-UabsServerArgs -Server $oneArgServer -Provider 'Hermes') -Compress) '["only"]' 'one Hermes argument stays a flat JSON array'
$twoArgServer = @{ args=@('one','two'); key=$null }
Is (ConvertTo-Json -InputObject (Resolve-UabsServerArgs -Server $twoArgServer -Provider 'Hermes') -Compress) '["one","two"]' 'multiple Hermes arguments stay a flat JSON array'

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
  Is (Test-UabsHermesRetired -Literals @('@modelcontextprotocol/server-github')) $true 'detects a retired package in the stored config'
  Is (Test-UabsHermesRetired -Literals @('something-else-entirely')) $false 'does not fire on an unrelated literal'

  $targets = @(Remove-UabsMcpHermes -Ids @('github', 'context7') -CheckOnly)
  Is ($targets -join ',') 'github' 'names only the ids actually declared'
} finally {
  if ($null -eq $savedHome) { Remove-Item Env:HERMES_HOME -ErrorAction SilentlyContinue } else { $env:HERMES_HOME = $savedHome }
}

# ------------------------------------------------------- same server, name ----
Section 'the same server under a different name'

# Dedupe keys on the server NAME everywhere in this pack. That is right for user
# configuration and blind to one case: the same package already declared under
# another name. Adding by catalog id gave Hermes both `playwright` and
# `playwright-mcp` -- two entries, two handshakes, one server each.
Is (Get-UabsNpxPackageBase -Arguments @('-y', '@playwright/mcp@0.0.79')) '@playwright/mcp' 'scoped package base, version dropped'
Is (Get-UabsNpxPackageBase -Arguments @('-y', 'firecrawl-mcp@3.24.0')) 'firecrawl-mcp' 'unscoped package base'
Is (Get-UabsNpxPackageBase -Arguments @('-y', 'shadcn@4.19.0', 'mcp')) 'shadcn' 'the first non-flag argument wins'
Is (Get-UabsNpxPackageBase -Arguments @()) '' 'no arguments means no package'

$yaml = @"
mcp_servers:
  playwright:
    command: npx
    args:
      - -y
      - '@playwright/mcp@latest'
  housecarl:
    command: x
    args: []
"@
Is (Find-UabsServerByPackage -ConfigText $yaml -PackageBase '@playwright/mcp') 'playwright' 'finds a YAML entry by package, whatever it is named'
Is (Find-UabsServerByPackage -ConfigText $yaml -PackageBase 'firecrawl-mcp') '' 'does not invent a match'

# A pin change must still count as the same server, or every bump adds a copy.
Is (Find-UabsServerByPackage -ConfigText $yaml -PackageBase (Get-UabsNpxPackageBase -Arguments @('-y','@playwright/mcp@0.0.79'))) 'playwright' 'a different pin is still the same server'

$json = '{"mcpServers":{"web":{"command":"npx","args":["-y","@playwright/mcp@0.0.79"]},"other":{"command":"z","args":[]}}}'
Is (Find-UabsServerByPackage -ConfigText $json -PackageBase '@playwright/mcp') 'web' 'finds a JSON entry by package'

# ------------------------------------------------------------ Grok budget ----
Section 'Grok inheritance and budget'

# grok-cli adopts ~/.claude.json by default, but this pack writes
# [compat.claude] mcps = false because inherited MCP startup cost 65s on the
# first turn of every session and attached zero tools. Skipping a server on the
# assumption it is inherited, after switching inheritance off, is not a dedupe --
# it is a silent omission, and it left Grok with no github and no
# sequential-thinking.
$grokRoot = Join-Path $sandbox 'grokhome'
New-Item -ItemType Directory -Force -Path (Join-Path $grokRoot '.grok') | Out-Null
$grokCfg = Join-Path $grokRoot '.grok\config.toml'
$savedProfile = $env:USERPROFILE
try {
  $env:USERPROFILE = $grokRoot

  Set-Utf8NoBom -Path $grokCfg -Text "[compat.claude]`r`nmcps = false`r`n"
  Is (Test-UabsGrokInheritsClaudeMcp) $false 'mcps = false means Grok inherits nothing'

  Set-Utf8NoBom -Path $grokCfg -Text "[compat.claude]`r`nmcps = true`r`n"
  Is (Test-UabsGrokInheritsClaudeMcp) $true 'mcps = true means Grok does inherit'

  # No flag at all is grok-cli's own default, which is inheritance on.
  Set-Utf8NoBom -Path $grokCfg -Text "[general]`r`ntheme = `"dark`"`r`n"
  Is (Test-UabsGrokInheritsClaudeMcp) $true 'no compat cell falls back to the CLI default'

  $body = "[mcp_servers.a]`r`ncommand = `"a`"`r`nargs = []`r`n[mcp_servers.b]`r`ncommand = `"b`"`r`nargs = []`r`n"
  Set-Utf8NoBom -Path $grokCfg -Text $body
  Is (Get-UabsGrokMcpCount) 2 'counts declared servers'

  # The budget used to be enforced for exactly one server by name while every
  # other path added freely. grok-cli wedges at eight running.
  $three = @(
    @{ id = 'x'; command = 'c'; args = @(); note = 'n' },
    @{ id = 'y'; command = 'c'; args = @(); note = 'n' },
    @{ id = 'z'; command = 'c'; args = @(); note = 'n' }
  )
  Is (@(Select-UabsWithinGrokBudget -Servers $three -Budget 6)).Count 3 'all three fit under a budget of 6'
  Is (@(Select-UabsWithinGrokBudget -Servers $three -Budget 4)).Count 2 'only the ones that fit are added'
  Is (@(Select-UabsWithinGrokBudget -Servers $three -Budget 2)).Count 0 'nothing is added once the budget is spent'
} finally {
  $env:USERPROFILE = $savedProfile
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
  $out = & (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File $setProfile -List -PackRoot $PackRoot 2>&1 | Out-String
  if ($LASTEXITCODE -eq 0) { Good '-List exits 0' } else { Bad "-List exited $LASTEXITCODE" }
  foreach ($needle in 'code-intel', 'engine-blender', 'not shipped', 'INSTALLED', 'ENABLED') {
    if ($out -match [regex]::Escape($needle)) { Good "-List reports $needle" } else { Bad "-List output has no $needle" }
  }

  $robloxProject = Join-Path $sandbox 'detect-roblox'
  New-Item -ItemType Directory -Force -Path $robloxProject | Out-Null
  Set-Utf8NoBom -Path (Join-Path $robloxProject 'default.project.json') -Text '{"name":"test"}'
  $detected = & (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File $setProfile -Detect -Path $robloxProject -PackRoot $PackRoot 2>&1 | Out-String
  if ($detected -match 'game-roblox') { Good 'Roblox marker selects only its game profile' } else { Bad 'Roblox marker did not select game-roblox' }

  $saintsProject = Join-Path $sandbox 'detect-saints-row'
  New-Item -ItemType Directory -Force -Path $saintsProject | Out-Null
  Set-Utf8NoBom -Path (Join-Path $saintsProject 'project.json') -Text '{"game":"sriv"}'
  $detected = & (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File $setProfile -Detect -Path $saintsProject -PackRoot $PackRoot 2>&1 | Out-String
  if ($detected -match 'game-saints-row') { Good 'Saints Row JSON marker selects its game profile' } else { Bad 'Saints Row JSON marker did not select game-saints-row' }

  Set-Utf8NoBom -Path (Join-Path $saintsProject 'project.json') -Text '{"game":"unrelated"}'
  $detected = & (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File $setProfile -Detect -Path $saintsProject -PackRoot $PackRoot 2>&1 | Out-String
  if ($detected -notmatch 'game-saints-row') { Good 'generic project.json does not enable Saints Row tools' } else { Bad 'generic project.json falsely selected game-saints-row' }

  $nodeBackend = Join-Path $sandbox 'detect-node-backend'
  New-Item -ItemType Directory -Force -Path $nodeBackend | Out-Null
  Set-Utf8NoBom -Path (Join-Path $nodeBackend 'package.json') -Text '{"dependencies":{"express":"5.0.0"}}'
  $detected = & (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File $setProfile -Detect -Path $nodeBackend -PackRoot $PackRoot 2>&1 | Out-String
  if ($detected -match 'code-intel' -and $detected -notmatch '(?m)^\s*web\s') { Good 'a backend-only package.json does not enable the browser profile' }
  else { Bad 'a backend-only Node project was mistaken for a frontend' }

  $nodeFrontend = Join-Path $sandbox 'detect-node-frontend'
  New-Item -ItemType Directory -Force -Path $nodeFrontend | Out-Null
  Set-Utf8NoBom -Path (Join-Path $nodeFrontend 'package.json') -Text '{"devDependencies":{"vite":"7.0.0"}}'
  $detected = & (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File $setProfile -Detect -Path $nodeFrontend -PackRoot $PackRoot 2>&1 | Out-String
  if ($detected -match '(?m)^\s*web\s') { Good 'a frontend dependency enables the browser profile' }
  else { Bad 'a frontend package.json did not select the web profile' }
}

# Both writers must share one implementation. Two copies means every bug in
# this file has to be found twice.
$reasoning = [IO.File]::ReadAllText((Join-Path $PackRoot 'TOOLS\Add-Reasoning-MCPs.ps1'))
foreach ($needle in 'UABS-Mcp-Write.ps1', 'Add-UabsMcpJson', 'Add-UabsMcpToml') {
  if ($reasoning -match [regex]::Escape($needle)) { Good "Add-Reasoning-MCPs uses $needle" } else { Bad "Add-Reasoning-MCPs does not use $needle" }
}
if ($reasoning -match "'y'\s*\|\s*&\s*\`$hx mcp add") { Bad 'reasoning-MCP wiring still hides a Hermes interactive prompt' }
else { Good 'no hidden interactive Hermes prompt' }


function ConvertTo-UabsTestHashtable($InputObject) {
  <# The writer takes hashtables so it can ask .Contains() about optional keys;
     ConvertFrom-Json on 5.1 produces PSCustomObjects. #>
  if ($null -eq $InputObject) { return $null }
  if ($InputObject -is [string] -or $InputObject.GetType().IsValueType) { return $InputObject }
  if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [System.Collections.IDictionary]) {
    return @(foreach ($i in $InputObject) { ConvertTo-UabsTestHashtable $i })
  }
  $out = @{}
  foreach ($p in $InputObject.PSObject.Properties) { $out[$p.Name] = ConvertTo-UabsTestHashtable $p.Value }
  return $out
}

# --------------------------------------------------------- project scope ----
Section 'profiles are wired for one project, not for the machine'

# Everything above tests a config-writing primitive. 7.9.5's actual defect was
# in the caller: PROFILES.json said scope "global", so enabling a profile for
# one project registered its servers machine-wide and every unrelated session
# carried the schemas until someone ran -Disable by hand. No primitive test can
# see that. This section drives the real front-end script against a fake
# USERPROFILE and LOCALAPPDATA and reads the configs it produced.

$psExe = (Get-Command powershell.exe -ErrorAction Stop).Source
$setProfileScript = Join-Path $PackRoot 'TOOLS\Set-McpProfile.ps1'

function New-UabsTestBox {
  <# A machine: a home, a local-appdata, a code project and an unrelated one. #>
  $box = @{
    Root  = Join-Path $sandbox ('box-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
  }
  $box.Home  = Join-Path $box.Root 'home'
  $box.Local = Join-Path $box.Root 'local'
  $box.Proj  = Join-Path $box.Root 'code-project'
  $box.Other = Join-Path $box.Root 'unrelated'
  New-Item -ItemType Directory -Force -Path @(
    $box.Home, $box.Local, $box.Proj, $box.Other,
    (Join-Path $box.Home '.codex'), (Join-Path $box.Home '.grok'),
    (Join-Path $box.Home '.kimi-code'), (Join-Path $box.Home '.local\bin')
  ) | Out-Null
  # A marker only code-intel detects, so one profile is under test at a time.
  Set-Utf8NoBom -Path (Join-Path $box.Proj 'pyproject.toml') -Text "[project]`r`nname = 'x'`r`n"
  Set-Utf8NoBom -Path (Join-Path $box.Other 'notes.txt') -Text 'nothing to detect here'
  # Serena is INSTALLED. Whether it is ENABLED anywhere is the whole question.
  Set-Utf8NoBom -Path (Join-Path $box.Home '.local\bin\serena.exe') -Text 'stub'
  Set-Utf8NoBom -Path (Join-Path $box.Home '.claude.json') -Text '{"mcpServers":{"context7":{"command":"npx","args":["-y","c@1.0.0"]}},"projects":{}}'
  Set-Utf8NoBom -Path (Join-Path $box.Home '.codex\config.toml') -Text "[mcp_servers.keepme]`r`ncommand = `"keep`"`r`nargs = []`r`n"
  Set-Utf8NoBom -Path (Join-Path $box.Home '.grok\config.toml') -Text "[compat.claude]`r`nmcps = false`r`n"
  Set-Utf8NoBom -Path (Join-Path $box.Home '.kimi-code\mcp.json') -Text '{"mcpServers":{}}'
  return $box
}

function Invoke-UabsProfile {
  param($Box, [string[]]$Arguments, [string]$ProviderList = 'Claude,Grok,Codex,Kimi,Hermes')
  $saved = @{ U = $env:USERPROFILE; L = $env:LOCALAPPDATA; H = $env:HERMES_HOME; A = $env:APPDATA; C = $env:CODEBASE_MEMORY_MCP }
  try {
    $env:USERPROFILE  = $Box.Home
    $env:LOCALAPPDATA = $Box.Local
    # Claude Desktop's config lives under %APPDATA%. Without this the sandbox
    # would reach the real one -- a test that edits the machine it runs on.
    $env:APPDATA      = Join-Path $Box.Home 'AppData\Roaming'
    # Point Hermes at a directory that does not exist, so it reports itself
    # absent instead of touching the real one.
    $env:HERMES_HOME  = Join-Path $Box.Root 'no-hermes'
    $cbm = Join-Path $Box.Home '.local\bin\codebase-memory-mcp.exe'
    if (Test-Path -LiteralPath $cbm -PathType Leaf) { $env:CODEBASE_MEMORY_MCP = $cbm }
    else { Remove-Item Env:CODEBASE_MEMORY_MCP -ErrorAction SilentlyContinue }
    $all = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $setProfileScript) + $Arguments +
           @('-PackRoot', $PackRoot, '-Providers', $ProviderList)
    return (& $psExe @all 2>&1 | Out-String)
  } finally {
    $env:USERPROFILE = $saved.U
    $env:LOCALAPPDATA = $saved.L
    $env:APPDATA = $saved.A
    if ($null -eq $saved.C) { Remove-Item Env:CODEBASE_MEMORY_MCP -ErrorAction SilentlyContinue } else { $env:CODEBASE_MEMORY_MCP = $saved.C }
    if ($null -eq $saved.H) { Remove-Item Env:HERMES_HOME -ErrorAction SilentlyContinue } else { $env:HERMES_HOME = $saved.H }
  }
}

function Get-UabsBoxClaude($Box) { [IO.File]::ReadAllText((Join-Path $Box.Home '.claude.json')) | ConvertFrom-Json }
function Get-UabsBoxText([string]$Path) { if (Test-Path -LiteralPath $Path -PathType Leaf) { [IO.File]::ReadAllText($Path) } else { '' } }
function Test-UabsBoxProjectServer($Box, [string]$Key, [string]$Id) {
  $j = Get-UabsBoxClaude $Box
  if (-not $j.projects -or ($j.projects.PSObject.Properties.Name -notcontains $Key)) { return $null }
  $p = $j.projects.$Key
  if (-not $p.mcpServers -or ($p.mcpServers.PSObject.Properties.Name -notcontains $Id)) { return $null }
  return $p.mcpServers.$Id
}

# ---- a clean install enables nothing ---------------------------------------
$box = New-UabsTestBox
$out = Invoke-UabsProfile -Box $box -Arguments @('-List')
if ($out -match 'code-intel') { Good '-List names the renamed profile' } else { Bad "-List does not name code-intel: $out" }
if ($out -notmatch 'code-deep') { Good '-List does not name the old id' } else { Bad '-List still names code-deep' }
$claude = Get-UabsBoxClaude $box
if ($claude.mcpServers.PSObject.Properties.Name -notcontains 'serena') { Good 'a clean install leaves Serena unregistered machine-wide' }
else { Bad 'Serena is registered machine-wide on a clean install' }

# ---- -CheckOnly writes nothing ---------------------------------------------
$before = @{}
foreach ($f in @((Join-Path $box.Home '.claude.json'), (Join-Path $box.Home '.codex\config.toml'), (Join-Path $box.Home '.grok\config.toml'), (Join-Path $box.Home '.kimi-code\mcp.json'))) {
  $before[$f] = (Get-FileHash -LiteralPath $f -Algorithm MD5).Hash
}
[void](Invoke-UabsProfile -Box $box -Arguments @('-Auto', '-Path', $box.Proj, '-CheckOnly'))
$changed = @($before.Keys | Where-Object { (Get-FileHash -LiteralPath $_ -Algorithm MD5).Hash -ne $before[$_] })
if (-not $changed.Count) { Good '-CheckOnly changes no provider config' }
else { Bad ("-CheckOnly wrote to: {0}" -f ($changed -join ', ')) }
if (-not (Test-Path -LiteralPath (Join-Path $box.Proj '.grok\config.toml'))) { Good '-CheckOnly creates no project config' }
else { Bad '-CheckOnly created the project grok config' }

# ---- -Auto on a detected project -------------------------------------------
$out = Invoke-UabsProfile -Box $box -Arguments @('-Auto', '-Path', $box.Proj)

$entry = Test-UabsBoxProjectServer $box $box.Proj 'serena'
if ($entry) { Good 'Serena is registered for the detected project (Claude)' } else { Bad "Serena missing from projects['$($box.Proj)'] -- $out" }
if ($entry -and (@($entry.args) -contains '--project') -and (@($entry.args) -contains $box.Proj)) { Good 'Serena is told which project' }
else { Bad ("Serena did not get --project <path>: {0}" -f (@($entry.args) -join ' ')) }
if ($entry -and (@($entry.args) -contains 'claude-code')) { Good 'Claude gets the claude-code context' }
else { Bad 'Claude did not get its own Serena context' }
if ($entry -and (@($entry.args) -notcontains '--project-from-cwd')) { Good 'a project registration does not also guess from the cwd' }
else { Bad 'both --project and --project-from-cwd were written' }

$claude = Get-UabsBoxClaude $box
if ($claude.mcpServers.PSObject.Properties.Name -notcontains 'serena') { Good 'enabling for a project does not register Serena machine-wide' }
else { Bad 'enabling for a project registered Serena machine-wide -- the 7.9.5 defect' }
if ($claude.mcpServers.PSObject.Properties.Name -contains 'context7') { Good 'the always-on core is left alone' }
else { Bad 'writing a profile removed an always-on server' }

$grokProject = Get-UabsBoxText (Join-Path $box.Proj '.grok\config.toml')
if ($grokProject -match '\[mcp_servers\.serena\]') { Good 'Grok gets the project config file it actually supports' }
else { Bad 'Grok project config has no serena entry' }
if ($grokProject -match '"grok"') { Good 'Grok gets the grok context' } else { Bad 'Grok did not get its own Serena context' }
if ((Get-UabsBoxText (Join-Path $box.Home '.grok\config.toml')) -notmatch 'serena') { Good 'nothing went into the machine-wide Grok config' }
else { Bad 'Serena reached the machine-wide Grok config' }

# Codex, Kimi and Hermes have no project-scoped MCP config. Skipping them with
# the reason printed is the point; writing them machine-wide behind a
# "project-scoped" comment is the bug.
if ((Get-UabsBoxText (Join-Path $box.Home '.codex\config.toml')) -notmatch 'serena') { Good 'Codex is not written machine-wide by a project enable' }
else { Bad 'Serena reached the machine-wide Codex config' }
if ((Get-UabsBoxText (Join-Path $box.Home '.kimi-code\mcp.json')) -notmatch 'serena') { Good 'Kimi is not written machine-wide by a project enable' }
else { Bad 'Serena reached the machine-wide Kimi config' }
if ($out -match 'no project-scoped MCP config') { Good 'the providers that cannot be scoped say so' }
else { Bad "a provider was skipped without a reason: $out" }
if ((Get-UabsBoxText (Join-Path $box.Home '.codex\config.toml')) -match 'keepme') { Good 'an unrelated Codex server is untouched' }
else { Bad 'writing a profile removed an unrelated Codex server' }

# ---- an unrelated project sees nothing --------------------------------------
if (-not (Test-UabsBoxProjectServer $box $box.Other 'serena')) { Good 'an unrelated project has no Serena entry' }
else { Bad 'Serena leaked into an unrelated project' }
if (-not (Test-Path -LiteralPath (Join-Path $box.Other '.grok\config.toml'))) { Good 'an unrelated project gets no grok config' }
else { Bad 'a grok config appeared in an unrelated project' }
$out = Invoke-UabsProfile -Box $box -Arguments @('-Auto', '-Path', $box.Other)
if ($out -match 'no profile markers found') { Good 'a project with no markers wires nothing' }
else { Bad "an unmarked project matched a profile: $out" }

# ---- repeated runs -----------------------------------------------------------
$grokBefore = (Get-FileHash -LiteralPath (Join-Path $box.Proj '.grok\config.toml') -Algorithm MD5).Hash
$out = Invoke-UabsProfile -Box $box -Arguments @('-Auto', '-Path', $box.Proj)
$grokText = Get-UabsBoxText (Join-Path $box.Proj '.grok\config.toml')
Is (@([regex]::Matches($grokText, '\[mcp_servers\.serena\]')).Count) 1 'a second run does not duplicate the TOML entry'
if ((Get-FileHash -LiteralPath (Join-Path $box.Proj '.grok\config.toml') -Algorithm MD5).Hash -eq $grokBefore) { Good 'an identical re-run rewrites nothing' }
else { Bad 'an identical re-run rewrote the project config' }
# A backup file per install run, inside the user's repository, is litter.
$baks = @(Get-ChildItem -LiteralPath (Join-Path $box.Proj '.grok') -Filter '*.bak-mcp-*' -ErrorAction SilentlyContinue)
if (-not $baks.Count) { Good 'no backup litter in the project directory' } else { Bad ("{0} .bak file(s) left in the project" -f $baks.Count) }
if ($out -match 'already registered') { Good 'a re-run reports the profile as still registered' }
else { Bad "a re-run lost track of the registration: $out" }
$claudeServers = @((Get-UabsBoxClaude $box).projects.$($box.Proj).mcpServers.PSObject.Properties.Name)
Is (@($claudeServers | Where-Object { $_ -eq 'serena' }).Count) 1 'a second run does not duplicate the JSON entry'

# ---- repair an already-enabled partial profile ------------------------------
$rbox = New-UabsTestBox
[void](Invoke-UabsProfile -Box $rbox -Arguments @('-Auto', '-Path', $rbox.Proj) -ProviderList 'Claude')
if (-not (Test-UabsBoxProjectServer $rbox $rbox.Proj 'codebase-memory-mcp')) { Good 'the fixture starts with a partial code-intel profile' }
else { Bad 'the partial-profile fixture unexpectedly registered codebase-memory' }
Set-Utf8NoBom -Path (Join-Path $rbox.Home '.local\bin\codebase-memory-mcp.exe') -Text 'stub'
$out = Invoke-UabsProfile -Box $rbox -Arguments @('-Repair')
if (Test-UabsBoxProjectServer $rbox $rbox.Proj 'codebase-memory-mcp') { Good '-Repair adds a newly available server to an already-enabled profile' }
else { Bad "-Repair left codebase-memory missing from the recorded project: $out" }
$rstate = Get-UabsBoxText (Join-Path $rbox.Local 'Ultimate-AI-Starter-Bundle\mcp-profiles.json') | ConvertFrom-Json
if (@($rstate.profiles.'code-intel'.projects.$($rbox.Proj).servers) -contains 'codebase-memory-mcp') { Good '-Repair records the complete server set' }
else { Bad '-Repair rewired the server but left stale partial state' }
if (((@($rstate.profiles.'code-intel'.projects.$($rbox.Proj).providers) -join ',') -eq 'Claude') -and
    -not (Test-Path -LiteralPath (Join-Path $rbox.Proj '.grok\config.toml') -PathType Leaf)) {
  Good '-Repair does not widen a Claude-only scope into other selected providers'
} else { Bad '-Repair widened the recorded provider scope' }
$out = Invoke-UabsProfile -Box $rbox -Arguments @('-List', '-Path', $rbox.Proj)
if ($out -match '(?m)^\s*codebase-memory-mcp\s+REGISTERED' -and $out -match '(?m)^\s*serena\s+REGISTERED') {
  Good '-List handles a multi-server state array'
} else { Bad "-List lost registered ids from a multi-server array: $out" }

# ---- -Disable ----------------------------------------------------------------
# No -Path: every project the profile was enabled for. The cwd is not a default
# for turning something off -- that swept a directory nobody asked about and
# left the real registration in place.
$out = Invoke-UabsProfile -Box $box -Arguments @('-Disable', 'code-intel')
if (-not (Test-UabsBoxProjectServer $box $box.Proj 'serena')) { Good '-Disable with no -Path reaches the project it was enabled for' }
else { Bad '-Disable left the Claude project entry behind' }
if ((Get-UabsBoxText (Join-Path $box.Proj '.grok\config.toml')) -notmatch '\[mcp_servers\.serena\]') { Good '-Disable reaches the Grok project file' }
else { Bad '-Disable left the Grok project entry behind' }
if ((Get-UabsBoxClaude $box).mcpServers.PSObject.Properties.Name -contains 'context7') { Good '-Disable leaves unrelated servers alone' }
else { Bad '-Disable removed an unrelated server' }
# The old id has to keep working, or every habit and script that names it breaks.
$out = Invoke-UabsProfile -Box $box -Arguments @('-Disable', 'code-deep')
if ($out -match 'Disabling code-intel') { Good 'the old profile id still resolves' }
else { Bad "the old profile id no longer resolves: $out" }

# ---- -Global is an opt-in, and says what it costs ---------------------------
$gbox = New-UabsTestBox
$out = Invoke-UabsProfile -Box $gbox -Arguments @('-Enable', 'code-intel', '-Global')
$g = (Get-UabsBoxClaude $gbox).mcpServers
if ($g.PSObject.Properties.Name -contains 'serena') { Good '-Global does register machine-wide' } else { Bad "-Global registered nothing: $out" }
# A baked absolute path in a machine-wide entry activates that one project in
# every unrelated session. Serena's own flag for this is --project-from-cwd.
if (@($g.serena.args) -contains '--project-from-cwd') { Good '-Global follows the session instead of baking one project' }
else { Bad ("machine-wide Serena did not get --project-from-cwd: {0}" -f (@($g.serena.args) -join ' ')) }
if (@($g.serena.args) -notcontains '--project') { Good '-Global does not bake an absolute project path' }
else { Bad 'a machine-wide entry baked one project path' }
if ((Get-UabsBoxText (Join-Path $gbox.Home '.codex\config.toml')) -match 'serena') { Good '-Global reaches the providers that have no project scope' }
else { Bad '-Global did not reach Codex' }
if ($out -match 'machine-wide') { Good '-Global says what it costs' } else { Bad '-Global did not warn' }

# A server whose command is resolved inside one project cannot be machine-wide:
# the Unity binary lives in that project's Library folder.
$cat = [IO.File]::ReadAllText((Join-Path $PackRoot 'BUNDLED-TOOLS\PROFILES.json')) | ConvertFrom-Json
$unity = @($cat.profiles | Where-Object { $_.id -eq 'engine-unity' }).servers[0]
$serenaDef = @($cat.profiles | Where-Object { $_.id -eq 'code-intel' }).servers[0]
Is (Test-UabsServerIsProjectBound -Server (ConvertTo-UabsTestHashtable $unity)) $true 'a {project} command is project-bound'
Is (Test-UabsServerIsProjectBound -Server (ConvertTo-UabsTestHashtable $serenaDef)) $false 'Serena is not project-bound by its command'

# ---- migrating a 7.9.5 machine ----------------------------------------------
# The upgrade has to MOVE those entries, not just rename them in a state file.
$mbox = New-UabsTestBox
$cj = Get-UabsBoxClaude $mbox
$cj.mcpServers | Add-Member -NotePropertyName 'serena' -NotePropertyValue ([pscustomobject]@{ command = 'serena.exe'; args = @('start-mcp-server') })
Set-Utf8NoBom -Path (Join-Path $mbox.Home '.claude.json') -Text ($cj | ConvertTo-Json -Depth 20)
Set-Utf8NoBom -Path (Join-Path $mbox.Home '.codex\config.toml') -Text (
  "[mcp_servers.keepme]`r`ncommand = `"keep`"`r`nargs = []`r`n`r`n[mcp_servers.serena]`r`ncommand = `"serena.exe`"`r`nargs = []`r`n")
New-Item -ItemType Directory -Force -Path (Join-Path $mbox.Local 'Ultimate-AI-Starter-Bundle') | Out-Null
Set-Utf8NoBom -Path (Join-Path $mbox.Local 'Ultimate-AI-Starter-Bundle\mcp-profiles.json') -Text (
  '{"code-deep":{"enabled_utc":"2026-08-21T00:00:00Z","servers":["serena"],"path":' + ($mbox.Proj | ConvertTo-Json) + '}}')

$out = Invoke-UabsProfile -Box $mbox -Arguments @('-Auto', '-Path', $mbox.Proj)
$claude = Get-UabsBoxClaude $mbox
if ($claude.mcpServers.PSObject.Properties.Name -notcontains 'serena') { Good 'the upgrade drops the machine-wide Claude registration' }
else { Bad 'Serena is still registered machine-wide after upgrading' }
if ((Get-UabsBoxText (Join-Path $mbox.Home '.codex\config.toml')) -notmatch 'serena') { Good 'the upgrade drops the machine-wide Codex registration' }
else { Bad 'Serena is still in the machine-wide Codex config after upgrading' }
if ((Get-UabsBoxText (Join-Path $mbox.Home '.codex\config.toml')) -match 'keepme') { Good 'the upgrade leaves unrelated Codex servers alone' }
else { Bad 'the upgrade removed an unrelated Codex server' }
if (Test-UabsBoxProjectServer $mbox $mbox.Proj 'serena') { Good 'the upgrade re-enables it for the project it was recorded against' }
else { Bad "the upgrade lost the registration entirely: $out" }
$stateText = Get-UabsBoxText (Join-Path $mbox.Local 'Ultimate-AI-Starter-Bundle\mcp-profiles.json')
if ($stateText -match 'code-intel') { Good 'state carries the new profile id' } else { Bad 'state has no code-intel entry' }
if ($stateText -notmatch 'code-deep') { Good 'state no longer carries the old id' } else { Bad 'state still carries code-deep' }
if ($stateText -match '"schema"') { Good 'state is written in the new shape' } else { Bad 'state was not migrated' }

# A machine whose recorded project no longer exists must not re-register blind.
$dbox = New-UabsTestBox
New-Item -ItemType Directory -Force -Path (Join-Path $dbox.Local 'Ultimate-AI-Starter-Bundle') | Out-Null
# Not a hardcoded drive letter: this pack's own rule, and CI proved why -- a
# path on Z:\ made Test-Path raise "Cannot find drive" on a runner that has no
# Z:, and $ErrorActionPreference = 'Stop' turned that into a dead gate.
$goneProject = Join-Path $dbox.Root 'was-a-project'
Set-Utf8NoBom -Path (Join-Path $dbox.Local 'Ultimate-AI-Starter-Bundle\mcp-profiles.json') -Text (
  '{"code-deep":{"enabled_utc":"2026-08-21T00:00:00Z","servers":["serena"],"path":' + ($goneProject | ConvertTo-Json) + '}}')
$out = Invoke-UabsProfile -Box $dbox -Arguments @('-Auto', '-Path', $dbox.Other)
if ($out -match 'recorded project is gone') { Good 'a vanished project is reported, not re-registered' }
else { Bad "a vanished recorded project was handled silently: $out" }
if ((Get-UabsBoxClaude $dbox).mcpServers.PSObject.Properties.Name -notcontains 'serena') { Good 'a vanished project does not fall back to machine-wide' }
else { Bad 'a vanished project fell back to a machine-wide registration' }

# The drive itself being gone is the harder case: Test-Path raises "Cannot find
# drive" rather than answering $false, and under $ErrorActionPreference = 'Stop'
# that kills the run. The tools on this pack's development machine live on S:
# and its projects on Z:; neither is guaranteed to be mounted.
# Pick a letter that is verifiably absent right now. Hardcoding Z: is what
# broke CI; hardcoding a less popular letter is the same mistake with better
# odds. This pack's rule is that a drive letter is never assumed.
$taken = @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue | ForEach-Object { $_.Name.ToUpper() })
$freeLetter = @([char[]]'QVWXY' | Where-Object { $taken -notcontains ([string]$_) } | Select-Object -First 1)[0]
if (-not $freeLetter) { Bad 'no free drive letter to test the unmounted case with'; $freeLetter = 'Q' }
$unmounted = ('{0}:\definitely-not-mounted\project' -f $freeLetter)
Is (Test-UabsPath -LiteralPath $unmounted -PathType Container) $false 'an unmounted drive answers no instead of throwing'
Is (Test-UabsPath -LiteralPath '' -PathType Leaf) $false 'an empty path answers no instead of throwing'
$ubox = New-UabsTestBox
New-Item -ItemType Directory -Force -Path (Join-Path $ubox.Local 'Ultimate-AI-Starter-Bundle') | Out-Null
Set-Utf8NoBom -Path (Join-Path $ubox.Local 'Ultimate-AI-Starter-Bundle\mcp-profiles.json') -Text (
  '{"code-deep":{"enabled_utc":"2026-08-21T00:00:00Z","servers":["serena"],"path":' + ($unmounted | ConvertTo-Json) + '}}')
# -Auto is the path that reaches it: migration asks whether the recorded
# project still exists before deciding to re-register it there.
$out = Invoke-UabsProfile -Box $ubox -Arguments @('-Auto', '-Path', $ubox.Other)
if ($out -match 'recorded project is gone') { Good 'a state entry on an unmounted drive is reported, not fatal' }
else { Bad ("a project on an unmounted drive broke the run: " + $out) }

# ---- the Grok budget counts the project file too -----------------------------
# grok-cli runs the union of ~/.grok/config.toml and <project>/.grok/config.toml,
# so a ceiling counted over only the user file is a ceiling that does not hold.
$bbox = New-UabsTestBox
$savedU = $env:USERPROFILE
try {
  $env:USERPROFILE = $bbox.Home
  Set-Utf8NoBom -Path (Join-Path $bbox.Home '.grok\config.toml') -Text (
    "[mcp_servers.a]`r`ncommand = `"a`"`r`nargs = []`r`n[mcp_servers.b]`r`ncommand = `"b`"`r`nargs = []`r`n")
  New-Item -ItemType Directory -Force -Path (Join-Path $bbox.Proj '.grok') | Out-Null
  Set-Utf8NoBom -Path (Join-Path $bbox.Proj '.grok\config.toml') -Text "[mcp_servers.c]`r`ncommand = `"c`"`r`nargs = []`r`n"
  Is (Get-UabsGrokMcpCount) 2 'the user config alone counts two'
  Is (Get-UabsGrokMcpCount -ProjectPath $bbox.Proj) 3 'the project config counts toward the ceiling'
  # The same server declared in both files is one server running, not two.
  Set-Utf8NoBom -Path (Join-Path $bbox.Proj '.grok\config.toml') -Text "[mcp_servers.b]`r`ncommand = `"b`"`r`nargs = []`r`n"
  Is (Get-UabsGrokMcpCount -ProjectPath $bbox.Proj) 2 'a server declared in both files is counted once'
} finally { $env:USERPROFILE = $savedU }


# ----------------------------------------------- withdrawn and opt-in ----
Section 'a withdrawn profile, and the one that is deliberately machine-wide'

# Deleting a profile from the catalog does not un-register its servers from the
# machines that enabled it: the entry keeps starting and keeps costing its tool
# schemas, with nothing left in the catalog able to turn it off. Supabase was
# withdrawn in 7.9.7, so this is that path.
$wbox = New-UabsTestBox
$cj = Get-UabsBoxClaude $wbox
$cj.mcpServers | Add-Member -NotePropertyName 'supabase' -NotePropertyValue ([pscustomobject]@{ command = 'npx'; args = @('-y', '@supabase/mcp-server-supabase@0.11.0') })
# ...and one the USER configured, under a different name, which must survive.
$cj.mcpServers | Add-Member -NotePropertyName 'my-own-supabase' -NotePropertyValue ([pscustomobject]@{ command = 'npx'; args = @('-y', '@supabase/mcp-server-supabase@0.11.0') })
Set-Utf8NoBom -Path (Join-Path $wbox.Home '.claude.json') -Text ($cj | ConvertTo-Json -Depth 20)
New-Item -ItemType Directory -Force -Path (Join-Path $wbox.Local 'Ultimate-AI-Starter-Bundle') | Out-Null
Set-Utf8NoBom -Path (Join-Path $wbox.Local 'Ultimate-AI-Starter-Bundle\mcp-profiles.json') -Text (
  '{"schema":2,"profiles":{"cloud":{"global":{"enabled_utc":"2026-08-21T00:00:00Z","servers":["supabase"],"providers":["Claude"]}}}}')

$out = Invoke-UabsProfile -Box $wbox -Arguments @('-Auto', '-Path', $wbox.Proj)
$after = (Get-UabsBoxClaude $wbox).mcpServers.PSObject.Properties.Name
if ($after -notcontains 'supabase') { Good 'a withdrawn profile is un-registered, not just forgotten' }
else { Bad ("the withdrawn Supabase entry survived: " + $out) }
if ($after -contains 'my-own-supabase') { Good 'a server the user configured themselves is untouched' }
else { Bad 'the migration removed a server this pack never created' }
$stateAfter = Get-UabsBoxText (Join-Path $wbox.Local 'Ultimate-AI-Starter-Bundle\mcp-profiles.json')
if ($stateAfter -notmatch '"cloud"') { Good 'the withdrawn profile leaves the state file' }
else { Bad 'the withdrawn profile is still in state' }

# The `reasoning` profile is the single deliberate machine-wide one. It has no
# detection markers precisely so that -Auto can never turn it on: a thinking aid
# is not a property of a project, and ~1,146 tokens a turn is not something to
# acquire by accident.
$rbox = New-UabsTestBox
$out = Invoke-UabsProfile -Box $rbox -Arguments @('-Auto', '-Path', $rbox.Proj)
$rClaude = Get-UabsBoxClaude $rbox
if ($rClaude.mcpServers.PSObject.Properties.Name -notcontains 'sequential-thinking') { Good '-Auto never enables the reasoning profile' }
else { Bad '-Auto enabled a machine-wide profile from a project marker' }
if (-not (Test-UabsBoxProjectServer $rbox $rbox.Proj 'sequential-thinking')) { Good 'and it does not arrive project-scoped either' }
else { Bad 'the reasoning profile was written into a project scope' }

$out = Invoke-UabsProfile -Box $rbox -Arguments @('-Enable', 'reasoning', '-Global')
$rClaude = Get-UabsBoxClaude $rbox
if ($rClaude.mcpServers.PSObject.Properties.Name -contains 'sequential-thinking') { Good 'an explicit -Enable reasoning -Global does register it' }
else { Bad ("-Enable reasoning -Global registered nothing: " + $out) }
$out = Invoke-UabsProfile -Box $rbox -Arguments @('-Disable', 'reasoning')
$rClaude = Get-UabsBoxClaude $rbox
if ($rClaude.mcpServers.PSObject.Properties.Name -notcontains 'sequential-thinking') { Good '-Disable reasoning gives the context back' }
else { Bad '-Disable left the machine-wide reasoning server behind' }

# ------------------------------------------------------- vision canary ----
Section 'the vision canary is falsifiable'

# "Look at the screenshot" cannot be checked by reading a skill file: the honest
# report and the fabricated one are the same sentence. The canary is the part
# that can be checked.
$canaryImg = Join-Path $PackRoot 'TOOLS\vision-canary\vision-canary.png'
$canaryMeta = Join-Path $PackRoot 'TOOLS\vision-canary\canary.json'
$canaryChk = Join-Path $PackRoot 'TOOLS\Test-VisionCanary.ps1'
foreach ($p in @($canaryImg, $canaryMeta, $canaryChk)) {
  if (Test-UabsPath -LiteralPath $p -PathType Leaf) { Good ("ships " + (Split-Path -Leaf $p)) } else { Bad ("missing " + $p) }
}
if (Test-UabsPath -LiteralPath $canaryChk -PathType Leaf) {
  # A wrong answer must fail, or the check proves nothing.
  $wrong = & (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File $canaryChk `
             -Word 'definitely' -Shape 'not' -Color 'right' -CanaryRoot (Split-Path -Parent $canaryImg) 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0 -and $wrong -match 'FAIL') { Good 'a wrong answer fails the canary' }
  else { Bad 'the canary passes an answer that cannot have come from the image' }
  if ($wrong -match 'visual verification unavailable') { Good 'and it says what to do instead' }
  else { Bad 'a canary failure does not tell the agent how to report honestly' }
}

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
