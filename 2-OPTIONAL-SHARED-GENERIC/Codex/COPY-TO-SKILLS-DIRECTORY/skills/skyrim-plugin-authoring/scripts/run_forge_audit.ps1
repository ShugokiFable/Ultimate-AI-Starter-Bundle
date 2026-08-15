[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Path,
    [string]$Forge = "$HOME\Documents\Apps\skyrim-forge-bridge\.venv\Scripts\skyrim-forge.exe"
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $Forge)) { throw "Forge Bridge not found: $Forge" }
& $Forge health
if ($LASTEXITCODE -ne 0) { throw "Forge health failed: $LASTEXITCODE" }
& $Forge plugin-header $Path
if ($LASTEXITCODE -ne 0) { throw "Forge plugin-header failed: $LASTEXITCODE" }
