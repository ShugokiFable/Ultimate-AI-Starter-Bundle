[CmdletBinding()]
param(
    [string]$Root = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$CandidateRoot = if ([string]::IsNullOrWhiteSpace($Root)) {
    $PSScriptRoot
} else {
    $Root.Trim().Trim([char]34)
}
if ([string]::IsNullOrWhiteSpace($CandidateRoot)) {
    throw 'PowerShell parser gate could not determine the Forge root directory.'
}
$ResolvedRoot = (Resolve-Path -LiteralPath $CandidateRoot -ErrorAction Stop).Path

$Scripts = @(
    Get-ChildItem -LiteralPath $ResolvedRoot -File -Filter '*.ps1' -Force
    $Workers = Join-Path $ResolvedRoot 'workers'
    if (Test-Path -LiteralPath $Workers -PathType Container) {
        Get-ChildItem -LiteralPath $Workers -File -Filter '*.ps1' -Force
    }
) | Sort-Object FullName -Unique
$Scripts = @($Scripts)
if ($Scripts.Count -eq 0) {
    throw "No PowerShell scripts were found under: $ResolvedRoot"
}

$Failed = $false
foreach ($Script in $Scripts) {
    $Tokens = $null
    $ParseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $Script.FullName,
        [ref]$Tokens,
        [ref]$ParseErrors
    ) | Out-Null
    foreach ($ParseError in @($ParseErrors)) {
        $Failed = $true
        Write-Error ('{0}:{1}:{2}: {3}' -f $Script.FullName, $ParseError.Extent.StartLineNumber, $ParseError.Extent.StartColumnNumber, $ParseError.Message)
    }
}
if ($Failed) { exit 1 }
Write-Host ('PowerShell parser gate: PASS ({0} scripts)' -f $Scripts.Count) -ForegroundColor Green
