[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Compiler,
    [Parameter(Mandatory=$true)][string]$Source,
    [Parameter(Mandatory=$true)][string]$Output,
    [Parameter(Mandatory=$true)][string[]]$Imports,
    [string]$Flags,
    [string]$Log = "$PWD\papyrus-compile.log"
)
$ErrorActionPreference = 'Stop'
foreach ($p in @($Compiler,$Source) + $Imports) {
    if (-not (Test-Path -LiteralPath $p)) { throw "Missing required path: $p" }
}
New-Item -ItemType Directory -Force -Path $Output | Out-Null
$importArg = ($Imports -join ';')
$args = @($Source, "-i=$importArg", "-o=$Output")
if ($Flags) { $args += "-f=$Flags" }
& $Compiler @args *>&1 | Tee-Object -FilePath $Log
if ($LASTEXITCODE -ne 0) { throw "Papyrus compiler failed with exit code $LASTEXITCODE. See $Log" }
