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
  Claude (default), Codex, Grok or Kimi. Hermes stores servers in YAML and is
  not read here.

.PARAMETER Name
  Check one server instead of all of them.

.PARAMETER TimeoutSeconds
  Per-server budget. Default 60: a cold `npx -y` has to download the package.
#>
[CmdletBinding()]
param(
  [ValidateSet('Claude', 'Codex', 'Grok', 'Kimi')][string]$Provider = 'Claude',
  [string]$Name,
  [int]$TimeoutSeconds = 60
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'V7-Mcp-Write.ps1')

function Get-TomlString($Match) {
  <# A basic string unescapes; a literal string is taken exactly as written. #>
  if ($Match.Groups['b'].Success) {
    return ($Match.Groups['b'].Value -replace '\\\\', '\')
  }
  return $Match.Groups['l'].Value
}

function Get-ServersFromConfig([string]$Provider) {
  $t = (Get-V5McpTargets)[$Provider]
  if (-not (Test-Path -LiteralPath $t.Path -PathType Leaf)) {
    throw "$Provider config not found at $($t.Path)"
  }
  $text = [IO.File]::ReadAllText($t.Path)
  $out = @()
  if ($t.Style -eq 'json') {
    $json = $text | ConvertFrom-Json
    if (-not $json.PSObject.Properties[$t.Section]) { return @() }
    foreach ($p in $json.($t.Section).PSObject.Properties) {
      $out += @{ id = $p.Name; command = $p.Value.command; args = @($p.Value.args) }
    }
    return $out
  }
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

    if (-not $initResult) { return @{ Ok = $false; Reason = "no initialize response within ${TimeoutSeconds}s" } }
    if ($null -eq $tools)  { return @{ Ok = $false; Reason = "initialized but never answered tools/list" } }
    return @{
      Ok        = $true
      Protocol  = $initResult.protocolVersion
      ServerName = $initResult.serverInfo.name
      ToolCount = $tools.Count
    }
  } finally {
    if (-not $proc.HasExited) { try { $proc.Kill() } catch { } }
    $proc.Dispose()
  }
}

$servers = @(Get-ServersFromConfig $Provider)
if ($Name) { $servers = @($servers | Where-Object { $_.id -eq $Name }) }
if (-not $servers.Count) { Write-Host "No matching servers in the $Provider config."; exit 0 }

Write-Host ("MCP handshake: {0} ({1} server(s))" -f $Provider, $servers.Count) -ForegroundColor Cyan
Write-Host ''
$failed = 0
$totalTools = 0
foreach ($s in $servers) {
  Write-Host ("  {0,-24} " -f $s.id) -NoNewline
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
