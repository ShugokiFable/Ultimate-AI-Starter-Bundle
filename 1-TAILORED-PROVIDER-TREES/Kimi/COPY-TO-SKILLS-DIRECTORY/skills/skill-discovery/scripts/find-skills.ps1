[CmdletBinding()]
param(
  [Parameter(Mandatory = $true, Position = 0)][ValidateNotNullOrEmpty()][string]$Query,
  [string]$Owner
)

$ErrorActionPreference = 'Stop'
$npx = Get-Command npx -ErrorAction SilentlyContinue
if (-not $npx) { throw 'npx was not found. Re-run START-HERE.bat to repair the Node runtime.' }
$env:DISABLE_TELEMETRY = '1'
$env:DO_NOT_TRACK = '1'
$invoke = @('-y', 'skills@1.5.23', 'find', $Query)
if ($Owner) { $invoke += @('--owner', $Owner) }
& $npx.Source @invoke
exit $LASTEXITCODE
