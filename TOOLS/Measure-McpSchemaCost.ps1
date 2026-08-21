<#
.SYNOPSIS
  Measure what an MCP server actually costs per turn: bytes of tool schema.

.DESCRIPTION
  Tools is the wrong unit. Every connected server's tool schemas are serialized
  into context on every turn, and a single tool with a large parameter schema
  can outweigh a dozen small ones. 7.9.7 demoted sequential-thinking on this
  measurement (1 tool, 4,590 bytes) and 7.9.8 kept firecrawl-mcp out of the
  Hermes starter on it (25 tools, 36,337 bytes, ~9,084 tokens every turn).

  Both numbers were produced by hand. Shipping the measurement means the next
  person can check them instead of trusting a changelog.

  This speaks real MCP over stdio -- initialize, notifications/initialized,
  tools/list -- exactly as a provider does, and reports the serialized size of
  the tools array, per tool, largest first.

  Token figures are bytes/4, the usual English-text approximation. They are an
  estimate; the byte count is the measurement.

.PARAMETER Command
  The full server command line, e.g. 'npx -y firecrawl-mcp@3.24.0'.

.PARAMETER Name
  Label for the output. Defaults to the command.

.PARAMETER TimeoutSeconds
  How long to wait for tools/list. npx may need to download the package first.

.EXAMPLE
  TOOLS\Measure-McpSchemaCost.ps1 -Command 'npx -y firecrawl-mcp@3.24.0'

.EXAMPLE
  TOOLS\Measure-McpSchemaCost.ps1 -Command 'npx -y @upstash/context7-mcp@4.0.2' -Name context7
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$Command,
  [string]$Name,
  [int]$TimeoutSeconds = 120
)

$ErrorActionPreference = 'Stop'
if (-not $Name) { $Name = $Command }

# Split the command line the way a provider does: first token is the exe.
$parts = @($Command -split '\s+' | Where-Object { $_ })
if (-not $parts.Count) { throw 'Empty -Command' }
$exe = $parts[0]
$rest = @($parts | Select-Object -Skip 1)

# npx/npm/uvx are shims on Windows, and `Get-Command npx` can hand back the
# extensionless Unix script, which CreateProcess refuses with "not a valid
# application for this OS platform". Anything that is not already a real
# executable goes through cmd.exe, which is how the providers launch these
# servers in the first place.
if ($exe -notmatch '(?i)\.exe$') {
  $psiArgs = '/c ' + $Command
  $exe = "$env:SystemRoot\System32\cmd.exe"
} else {
  $psiArgs = ($rest -join ' ')
}

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $exe
$psi.Arguments = $psiArgs
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
# stderr is deliberately NOT redirected. A redirected pipe nobody drains fills
# up and blocks the child forever -- npx writes install progress there, so the
# server never reaches the point of answering initialize and the measurement
# hangs with no output at all. Letting it through to the console costs some
# npx noise and buys a tool that terminates.
$psi.RedirectStandardError = $false
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$psi.StandardOutputEncoding = New-Object System.Text.UTF8Encoding $false

$proc = [System.Diagnostics.Process]::Start($psi)
try {
  $send = {
    param($obj)
    $proc.StandardInput.WriteLine(($obj | ConvertTo-Json -Depth 12 -Compress))
    $proc.StandardInput.Flush()
  }

  & $send @{
    jsonrpc = '2.0'; id = 1; method = 'initialize'
    params  = @{
      protocolVersion = '2024-11-05'
      capabilities    = @{}
      clientInfo      = @{ name = 'uabs-measure'; version = '1' }
    }
  }

  # Announce and ask for tools WITHOUT waiting for the initialize reply first.
  # Gating on that reply deadlocks against real servers: context7 4.0.2 answers
  # tools/list but emits nothing readable for initialize, so a loop that waits
  # for id 1 before sending id 2 waits forever against a server that is running
  # perfectly. Ordering is preserved on the pipe either way.
  Start-Sleep -Milliseconds 1500
  & $send @{ jsonrpc = '2.0'; method = 'notifications/initialized'; params = @{} }
  & $send @{ jsonrpc = '2.0'; id = 2; method = 'tools/list'; params = @{} }

  # StandardOutput.ReadLine() blocks, so a plain `while (Get-Date) -lt $deadline`
  # around it never times out -- a server that says nothing hangs the caller
  # forever instead of reporting that it said nothing. Read asynchronously and
  # let the wait carry the deadline. One pending read is carried across
  # iterations: starting a second ReadLineAsync while the first is outstanding
  # throws "The stream is currently in use by a previous operation".
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  $tools = $null
  $pending = $null
  while ((Get-Date) -lt $deadline -and -not $proc.HasExited) {
    if ($null -eq $pending) { $pending = $proc.StandardOutput.ReadLineAsync() }
    $budget = [int][math]::Max(1, ($deadline - (Get-Date)).TotalMilliseconds)
    if (-not $pending.Wait([math]::Min($budget, 2000))) { continue }
    $line = $pending.Result
    $pending = $null
    if ($null -eq $line) { break }
    if (-not $line.Trim().StartsWith('{')) { continue }
    try { $msg = $line | ConvertFrom-Json } catch { continue }
    if ($msg.PSObject.Properties.Name -contains 'result' -and
        $msg.result.PSObject.Properties.Name -contains 'tools') {
      $tools = @($msg.result.tools)
      break
    }
  }

  if ($null -eq $tools) {
    Write-Host ("{0}: no tools/list response within {1}s" -f $Name, $TimeoutSeconds) -ForegroundColor Red
    Write-Host '  (server stderr, if any, is above)' -ForegroundColor DarkGray
    exit 1
  }

  $rows = foreach ($t in $tools) {
    $bytes = ([Text.Encoding]::UTF8.GetByteCount(($t | ConvertTo-Json -Depth 25 -Compress)))
    [pscustomobject]@{ Tool = [string]$t.name; Bytes = $bytes }
  }
  $total = ([Text.Encoding]::UTF8.GetByteCount(($tools | ConvertTo-Json -Depth 25 -Compress)))

  Write-Host ''
  Write-Host ("{0}" -f $Name) -ForegroundColor Cyan
  $unit = if ($tools.Count -eq 1) { 'tool ' } else { 'tools' }
  Write-Host ("  {0} {1}   {2:N0} bytes   ~{3:N0} tokens on every turn" -f $tools.Count, $unit, $total, [math]::Round($total / 4)) -ForegroundColor Yellow
  Write-Host ''
  foreach ($r in ($rows | Sort-Object Bytes -Descending)) {
    Write-Host ("  {0,-38} {1,7:N0} bytes" -f $r.Tool, $r.Bytes) -ForegroundColor DarkGray
  }
  Write-Host ''
  Write-Host '  Measured with this tool for comparison:' -ForegroundColor DarkGray
  Write-Host '    context7             2 tools    5,124 bytes   current docs -- kept always-on' -ForegroundColor DarkGray
  Write-Host '    sequential-thinking  1 tool     4,590 bytes   a scratchpad -- lost its slot in 7.9.7' -ForegroundColor DarkGray
  Write-Host '    firecrawl-mcp       25 tools   36,337 bytes   keyless: search+scrape only -- not registered in 7.9.8' -ForegroundColor DarkGray
} finally {
  if (-not $proc.HasExited) { $proc.Kill() }
  $proc.Dispose()
}
