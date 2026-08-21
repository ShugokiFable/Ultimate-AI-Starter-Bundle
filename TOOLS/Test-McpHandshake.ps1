<#
.SYNOPSIS
  Prove a configured MCP server actually starts, speaks MCP, and lists tools.

.DESCRIPTION
  A provider that cannot spawn its server shows no tools and says nothing about
  why. Every silent-no-tools failure this pack has shipped looked identical from
  the outside: a command that does not exist, a package upstream withdrew, a
  backslash escaped twice too many. Writing the config is not the finish line.

  This reads a provider's own config, spawns each server exactly as that
  provider would, and runs the real handshake over stdio:

    initialize -> notifications/initialized -> tools/list

  It reports the server's protocol version and tool count, which is also the
  honest measure of what a server costs: every one of those tool schemas is in
  the model's context on every turn of every session.

  Nothing is written. This is a read-only check.

.PARAMETER Provider
  Claude (default), Codex, Grok, Kimi or Hermes.

.PARAMETER Name
  Check one server instead of all of them.

.PARAMETER Path
  A project directory. Capability profiles are registered per project, so
  without this the check sees only the machine-wide config -- and reports a
  cost that no session opened in that project would actually pay.

.PARAMETER TimeoutSeconds
  Per-server budget. Default 60: a cold `npx -y` has to download the package.
#>
[CmdletBinding()]
param(
  [ValidateSet('Claude', 'Codex', 'Grok', 'Kimi', 'Hermes')][string]$Provider = 'Claude',
  [string]$Name,
  [string]$Path,
  [int]$TimeoutSeconds = 60
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'V7-Mcp-Write.ps1')

function Get-HermesServers {
  <# Hermes writes one predictable shape: two-space nesting under mcp_servers,
     a scalar `command`, and `args` as either [] or a block list. This reads
     that shape, not YAML in general -- anything unrecognised is skipped with a
     note rather than guessed at. #>
  $paths = Get-V5HermesPaths
  if (-not (Test-Path -LiteralPath $paths.Config -PathType Leaf)) {
    throw "Hermes config not found at $($paths.Config)"
  }
  $lines = [IO.File]::ReadAllText($paths.Config) -split "`r?`n"
  $out = @()
  $inBlock = $false
  $cur = $null
  $inArgs = $false
  function Get-YamlScalar([string]$v) {
    $v = $v.Trim()
    if ($v.Length -ge 2 -and (($v[0] -eq "'" -and $v[-1] -eq "'") -or ($v[0] -eq '"' -and $v[-1] -eq '"'))) {
      return $v.Substring(1, $v.Length - 2)
    }
    return $v
  }
  foreach ($line in $lines) {
    if ($line -match '^mcp_servers:\s*$') { $inBlock = $true; continue }
    if (-not $inBlock) { continue }
    if ($line -match '^\S') { break }                      # back to top level
    if ($line -match '^\s*$' -or $line -match '^\s*#') { continue }

    if ($line -match '^  (?<name>[^\s:#][^:]*):\s*$') {
      if ($cur -and $cur.command) { $out += $cur }
      $cur = @{ id = (Get-YamlScalar $Matches['name']); command = ''; args = @(); enabled = $true }
      $inArgs = $false
      continue
    }
    if (-not $cur) { continue }
    if ($line -match '^    command:\s*(?<v>.+)$') { $cur.command = Get-YamlScalar $Matches['v']; $inArgs = $false; continue }
    if ($line -match '^    enabled:\s*(?<v>\S+)') { $cur.enabled = ((Get-YamlScalar $Matches['v']) -ine 'false'); $inArgs = $false; continue }
    if ($line -match '^    args:\s*\[\s*\]\s*$') { $cur.args = @(); $inArgs = $false; continue }
    if ($line -match '^    args:\s*$') { $inArgs = $true; continue }
    if ($inArgs -and $line -match '^      -\s*(?<v>.*)$') { $cur.args += (Get-YamlScalar $Matches['v']); continue }
    if ($line -match '^    \S') { $inArgs = $false }
  }
  if ($cur -and $cur.command) { $out += $cur }
  return @($out | Where-Object { $_.enabled })
}

function Get-TomlString($Match) {
  <# A basic string unescapes; a literal string is taken exactly as written. #>
  if ($Match.Groups['b'].Success) {
    return ($Match.Groups['b'].Value -replace '\\\\', '\')
  }
  return $Match.Groups['l'].Value
}

function Get-ServersFromFile {
  param([string]$ConfigPath, [string]$Style, [string]$Section, [string]$ProjectKey, [string]$Scope = 'machine')
  if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { return @() }
  $text = [IO.File]::ReadAllText($ConfigPath)
  $out = @()
  if ($Style -eq 'json') {
    $doc = $text | ConvertFrom-Json
    $json = Get-V5JsonScopeContainer -Json $doc -ProjectKey $ProjectKey
    if ($null -eq $json) { return @() }
    if (-not $json.PSObject.Properties[$Section]) { return @() }
    foreach ($p in $json.($Section).PSObject.Properties) {
      $out += @{ id = $p.Name; command = $p.Value.command; args = @($p.Value.args); scope = $Scope }
    }
    return $out
  }
  $t = @{ Section = $Section }
  # TOML: read only what this check needs -- the command and args of each
  # server table. A full TOML parser is not a dependency worth adding to a
  # read-only diagnostic.
  $pattern = '(?ms)^\[' + [regex]::Escape($t.Section) + '\.(?<name>[^\].]+)\](?<body>.*?)(?=^\[|\z)'
  foreach ($m in [regex]::Matches($text, $pattern)) {
    $body = $m.Groups['body'].Value
    # TOML has two string forms and Codex writes both: basic "..." (escapes
    # apply) and literal '...' (no escapes at all). Reading only the first
    # silently dropped two real servers from this report.
    $strPat = '"(?<b>(?:[^"\\]|\\.)*)"|''(?<l>[^'']*)'''
    $cmd = [regex]::Match($body, '(?m)^\s*command\s*=\s*(?:' + $strPat + ')')
    if (-not $cmd.Success) { continue }
    $argLine = [regex]::Match($body, '(?ms)^\s*args\s*=\s*\[(?<v>.*?)\]')
    $argv = @()
    if ($argLine.Success) {
      foreach ($a in [regex]::Matches($argLine.Groups['v'].Value, $strPat)) {
        $argv += (Get-TomlString $a)
      }
    }
    $out += @{
      id      = $m.Groups['name'].Value
      command = (Get-TomlString $cmd)
      args    = $argv
      scope   = $Scope
    }
  }
  return $out
}

function Get-ServersFromConfig {
  <# What a session opened in $ProjectPath would actually see: the machine-wide
     config, plus whatever that project adds. Reading only the first meant the
     one tool that can answer "is this server working" was blind to every
     capability profile, since those are registered per project. #>
  param([string]$Provider, [string]$ProjectPath)
  $t = (Get-V5McpTargets)[$Provider]
  if (-not (Test-Path -LiteralPath $t.Path -PathType Leaf)) {
    throw "$Provider config not found at $($t.Path)"
  }
  $out = @(Get-ServersFromFile -ConfigPath $t.Path -Style $t.Style -Section $t.Section -ProjectKey '' -Scope 'machine')
  if ($ProjectPath) {
    $proj = Get-V5ProviderProjectTarget -Provider $Provider -ProjectPath $ProjectPath
    if ($proj) {
      $names = @($out | ForEach-Object { $_.id })
      foreach ($s in @(Get-ServersFromFile -ConfigPath $proj.Path -Style $proj.Style -Section $proj.Section -ProjectKey $proj.ProjectKey -Scope 'project')) {
        # A project entry of the same name overrides, it does not duplicate:
        # one server runs, not two.
        $out = @($out | Where-Object { $_.id -ne $s.id })
        $out += $s
      }
    }
  }
  return $out
}

function Invoke-McpHandshake {
  param([string]$Command, [string[]]$Arguments, [int]$TimeoutSeconds)

  # npx ships as npx.ps1/npx.cmd on Windows; Start-Process cannot execute a
  # PowerShell script directly, and cmd.exe resolves the shim the same way the
  # provider's own launcher does.
  $exe = $Command
  $argv = @($Arguments)
  if ($Command -notmatch '[\\/]' -and $Command -notmatch '\.exe$') {
    $exe = "$env:ComSpec"
    $argv = @('/c', $Command) + @($Arguments)
  }

  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $exe
  # Not ArgumentList: that is a .NET Core API and Windows PowerShell 5.1 runs on
  # .NET Framework, where the property does not exist.
  $psi.Arguments = (@($argv | ForEach-Object {
    $a = [string]$_
    if ($a -match '[\s"]') { '"' + ($a -replace '(\\*)"', '$1$1\"') + '"' } else { $a }
  }) -join ' ')
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true

  $proc = [System.Diagnostics.Process]::Start($psi)
  # A redirected pipe that nobody reads fills at about 4KB and blocks the
  # writer. Serena logs ~20 startup lines to stderr and deadlocked there,
  # producing a false "no initialize response" from a tool whose entire job is
  # telling a real failure from a configuration mistake. Drain it, and keep the
  # tail so a genuine failure can quote what the server said.
  $errBuf = New-Object System.Text.StringBuilder
  $errSub = Register-ObjectEvent -InputObject $proc -EventName ErrorDataReceived -MessageData $errBuf -Action {
    if ($EventArgs.Data) { [void]$Event.MessageData.AppendLine($EventArgs.Data) }
  }
  $proc.BeginErrorReadLine()
  try {
    $send = {
      param($obj)
      $proc.StandardInput.WriteLine(($obj | ConvertTo-Json -Depth 10 -Compress))
      $proc.StandardInput.Flush()
    }
    & $send @{
      jsonrpc = '2.0'; id = 1; method = 'initialize'
      params  = @{
        protocolVersion = '2025-06-18'
        capabilities    = @{}
        clientInfo      = @{ name = 'uabs-handshake'; version = '1.0' }
      }
    }

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $initResult = $null
    $tools = $null
    $sentList = $false

    while ((Get-Date) -lt $deadline) {
      $remaining = [int](($deadline - (Get-Date)).TotalMilliseconds)
      if ($remaining -le 0) { break }
      $lineTask = $proc.StandardOutput.ReadLineAsync()
      if (-not $lineTask.Wait($remaining)) { break }
      $line = $lineTask.Result
      if ($null -eq $line) { break }
      if (-not $line.TrimStart().StartsWith('{')) { continue }
      try { $msg = $line | ConvertFrom-Json } catch { continue }
      if ($msg.PSObject.Properties['error']) {
        return @{ Ok = $false; Reason = ("server returned error: " + ($msg.error | ConvertTo-Json -Compress)) }
      }
      if ($msg.PSObject.Properties['id'] -and $msg.id -eq 1) {
        $initResult = $msg.result
        & $send @{ jsonrpc = '2.0'; method = 'notifications/initialized' }
        & $send @{ jsonrpc = '2.0'; id = 2; method = 'tools/list'; params = @{} }
        $sentList = $true
        continue
      }
      if ($sentList -and $msg.PSObject.Properties['id'] -and $msg.id -eq 2) {
        $tools = @($msg.result.tools)
        break
      }
    }

    if (-not $initResult) {
      $tail = ($errBuf.ToString() -split "`r?`n" | Where-Object { $_ } | Select-Object -Last 3) -join ' | '
      $why = "no initialize response within ${TimeoutSeconds}s"
      if ($tail) { $why += "  [stderr: $tail]" }
      return @{ Ok = $false; Reason = $why }
    }
    if ($null -eq $tools)  { return @{ Ok = $false; Reason = "initialized but never answered tools/list" } }
    return @{
      Ok        = $true
      Protocol  = $initResult.protocolVersion
      ServerName = $initResult.serverInfo.name
      ToolCount = $tools.Count
    }
  } finally {
    if ($errSub) { Unregister-Event -SourceIdentifier $errSub.Name -ErrorAction SilentlyContinue }
    # Kill the TREE, not the process. .NET Framework has no
    # Kill(entireProcessTree), and `cmd /c npx ...` means killing cmd leaves
    # node running -- one orphan per check, holding the ports and locks the
    # next check needs. This diagnostic reported ten healthy servers as broken
    # before that was fixed.
    if (-not $proc.HasExited) {
      try {
        & taskkill.exe /T /F /PID $proc.Id *> $null
      } catch { }
      try { if (-not $proc.WaitForExit(5000)) { $proc.Kill() } } catch { }
    }
    $proc.Dispose()
  }
}

if ($Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Container)) { throw "-Path does not exist: $Path" }
  $Path = (Resolve-Path -LiteralPath $Path).Path.TrimEnd('\', '/')
}
$servers = if ($Provider -eq 'Hermes') { @(Get-HermesServers) } else { @(Get-ServersFromConfig -Provider $Provider -ProjectPath $Path) }
if ($Name) { $servers = @($servers | Where-Object { $_.id -eq $Name }) }
if (-not $servers.Count) { Write-Host "No matching servers in the $Provider config."; exit 0 }

Write-Host ("MCP handshake: {0} ({1} server(s))" -f $Provider, $servers.Count) -ForegroundColor Cyan
if ($Path) { Write-Host ("  as a session opened in {0}" -f $Path) -ForegroundColor DarkGray }
else { Write-Host '  machine-wide config only -- pass -Path <project> to include that project''s own servers' -ForegroundColor DarkGray }
Write-Host ''
$failed = 0
$totalTools = 0
foreach ($s in $servers) {
  $tag = if ($s.scope -eq 'project') { ' [project]' } else { '' }
  Write-Host ("  {0,-24} " -f ($s.id + $tag)) -NoNewline
  try {
    $r = Invoke-McpHandshake -Command $s.command -Arguments $s.args -TimeoutSeconds $TimeoutSeconds
  } catch {
    $r = @{ Ok = $false; Reason = $_.Exception.Message }
  }
  if ($r.Ok) {
    $totalTools += $r.ToolCount
    Write-Host ("OK   {0,3} tools   proto {1}" -f $r.ToolCount, $r.Protocol) -ForegroundColor Green
  } else {
    $failed++
    Write-Host ("FAIL {0}" -f $r.Reason) -ForegroundColor Red
  }
}
Write-Host ''
# The number that matters for cost: this many tool schemas ride along on every
# turn of every session with this provider, whatever the task is.
Write-Host ("  {0} tool schemas in context on every turn" -f $totalTools) -ForegroundColor DarkGray
if ($failed) {
  Write-Host ("  {0} server(s) did not complete a handshake" -f $failed) -ForegroundColor Red
  exit 1
}
Write-Host '  all servers completed an MCP handshake' -ForegroundColor Green
exit 0
