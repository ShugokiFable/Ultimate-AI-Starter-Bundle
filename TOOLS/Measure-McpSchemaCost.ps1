<#
.SYNOPSIS
  Measure advertised MCP schema bytes, not prompt usage or billed tokens.
.DESCRIPTION
  Reuses mcp_handshake.py: initialize must succeed before tools/list; all pages
  are collected. Reports compact UTF-8 JSON array bytes and a bytes/4 estimate.
  Provider filtering, deferred discovery, prompt caching and billing are NOT
  measured. Even one tool is measured as an array. Compare like serializations.

  Python sends UTF-8 without a BOM. The retired .NET implementation's
  StandardInput AutoFlush emitted a BOM before a BaseStream wrapper could fix
  it; do not reintroduce a second transport implementation here.
.EXAMPLE
  TOOLS\Measure-McpSchemaCost.ps1 -Command 'npx -y @upstash/context7-mcp@4.0.4' -Name context7
.EXAMPLE
  TOOLS\Measure-McpSchemaCost.ps1 -Executable 'C:\Program Files\Tool\server.exe' -Arguments @('serve')
#>
[CmdletBinding(DefaultParameterSetName = 'CommandLine')]
param(
  [Parameter(Mandatory = $true, ParameterSetName = 'CommandLine')][string]$Command,
  [Parameter(Mandatory = $true, ParameterSetName = 'Argv')][string]$Executable,
  [Parameter(ParameterSetName = 'Argv')][string[]]$Arguments = @(),
  [string]$Name,
  [ValidateRange(1, 600)][int]$TimeoutSeconds = 120
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'UABS-Common.ps1')
$python = Get-UabsPythonExecutable
if (-not $python) { throw 'No working Python interpreter found.' }
if ($PSCmdlet.ParameterSetName -eq 'CommandLine') {
  # Legacy -Command explicitly accepts a Windows shell command. Prefer argv
  # for executable paths with spaces; never interpolate untrusted input here.
  $Executable = $env:ComSpec
  $Arguments = @('/d', '/s', '/c', $Command)
}
if (-not $Name) { $Name = if ($Command) { $Command } else { $Executable } }
$spec = @{ command = $Executable; args = @($Arguments); timeout = $TimeoutSeconds }
if ($PSCmdlet.ParameterSetName -eq 'CommandLine') { $spec.shell_command = $Command }
$spec = $spec | ConvertTo-Json -Depth 4 -Compress
$encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($spec))
$raw = @(& $python (Join-Path $PSScriptRoot 'mcp_handshake.py') --spec $encoded)
$rc = $LASTEXITCODE
$result = ($raw -join [Environment]::NewLine) | ConvertFrom-Json
if ($rc -ne 0 -or -not $result.ok) { throw ("{0}: {1}" -f $Name, $result.reason) }
Write-Host $Name -ForegroundColor Cyan
Write-Host ("  {0} advertised tools; {1:N0} schema bytes; ~{2:N0} schema-token estimate (bytes/4)" -f $result.tool_count, $result.schema_bytes, $result.schema_tokens_estimate) -ForegroundColor Yellow
foreach ($row in ($result.per_tool | Sort-Object bytes -Descending)) {
  Write-Host ("  {0,-38} {1,7:N0} bytes" -f $row.name, $row.bytes) -ForegroundColor DarkGray
}
Write-Host '  Loaded, cached and billed tokens: unmeasured. Provider filtering and deferred discovery change the active surface.'
