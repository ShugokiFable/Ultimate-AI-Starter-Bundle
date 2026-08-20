[CmdletBinding()]
param(
    [ValidateSet('All', 'Codex', 'Claude', 'Grok', 'Kimi', 'Hermes')]
    [string]$Provider = 'All'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$Source = Join-Path $Root 'integrations\skyrim-forge'
$InstallationDescriptorPath = Join-Path $Root 'INSTALLATION.json'

if (-not (Test-Path -LiteralPath $InstallationDescriptorPath -PathType Leaf)) {
    throw 'Forge is not installed. Run Install-or-Update.ps1 before installing provider skills.'
}
# ReadAllText, not Get-Content -Raw: on PS 5.1 Get-Content without -Encoding
# decodes with the ANSI codepage, corrupting any non-ASCII in the descriptor.
$InstallationDescriptor = [IO.File]::ReadAllText($InstallationDescriptorPath) | ConvertFrom-Json
if (-not (Test-Path -LiteralPath $InstallationDescriptor.python -PathType Leaf)) {
    throw "Installed Forge Python is missing: $($InstallationDescriptor.python)"
}

function Test-ReparsePoint {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    return [bool]((Get-Item -LiteralPath $Path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)
}

function Get-ProviderHome {
    param([Parameter(Mandatory = $true)][string]$Name)
    $UserProfile = [Environment]::GetFolderPath('UserProfile')
    switch ($Name) {
        'Codex'  { if ($env:CODEX_HOME) { return $env:CODEX_HOME }; return (Join-Path $UserProfile '.codex') }
        'Claude' { if ($env:CLAUDE_CONFIG_DIR) { return $env:CLAUDE_CONFIG_DIR }; return (Join-Path $UserProfile '.claude') }
        'Grok'   { if ($env:GROK_HOME) { return $env:GROK_HOME }; return (Join-Path $UserProfile '.grok') }
        'Kimi'   { if ($env:KIMI_CODE_HOME) { return $env:KIMI_CODE_HOME }; return (Join-Path $UserProfile '.kimi-code') }
        'Hermes' {
            if ($env:HERMES_HOME) { return $env:HERMES_HOME }
            $LocalAppData = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { [Environment]::GetFolderPath('LocalApplicationData') }
            return (Join-Path $LocalAppData 'hermes')
        }
        default  { throw "Unknown AI provider: $Name" }
    }
}

if (-not (Test-Path -LiteralPath (Join-Path $Source 'SKILL.md') -PathType Leaf)) {
    throw "Bundled Forge skill is missing: $Source"
}
$SourceReparsePoints = @(Get-ChildItem -LiteralPath $Source -Recurse -Force | Where-Object {
    $_.Attributes -band [IO.FileAttributes]::ReparsePoint
})
if ($SourceReparsePoints.Count -ne 0) {
    throw 'Bundled Forge skill contains a reparse point and cannot be installed safely.'
}

$Selected = if ($Provider -eq 'All') {
    @('Codex', 'Claude', 'Grok', 'Kimi', 'Hermes')
} else {
    @($Provider)
}

foreach ($Name in $Selected) {
    $ProviderHome = [IO.Path]::GetFullPath((Get-ProviderHome -Name $Name))
    $Skills = Join-Path $ProviderHome 'skills'
    $Target = Join-Path $Skills 'skyrim-forge'
    $Stage = Join-Path $Skills ('.skyrim-forge.stage-' + [Guid]::NewGuid().ToString('N'))
    $Backup = Join-Path $Skills ('.skyrim-forge.backup-' + [Guid]::NewGuid().ToString('N'))

    New-Item -ItemType Directory -Force -Path $Skills | Out-Null
    if (Test-ReparsePoint -Path $Skills) {
        throw "Refusing provider skills directory that is a reparse point: $Skills"
    }
    if ((Test-Path -LiteralPath $Target) -and (Test-ReparsePoint -Path $Target)) {
        throw "Refusing existing Forge skill target that is a reparse point: $Target"
    }

    $MovedExisting = $false
    try {
        Copy-Item -LiteralPath $Source -Destination $Stage -Recurse
        if (-not (Test-Path -LiteralPath (Join-Path $Stage 'SKILL.md') -PathType Leaf)) {
            throw "Staged Forge skill validation failed for $Name."
        }
        Copy-Item -LiteralPath $InstallationDescriptorPath -Destination (Join-Path $Stage 'INSTALLATION.json')
        if (Test-Path -LiteralPath $Target) {
            Move-Item -LiteralPath $Target -Destination $Backup
            $MovedExisting = $true
        }
        try {
            Move-Item -LiteralPath $Stage -Destination $Target
        } catch {
            if ($MovedExisting -and -not (Test-Path -LiteralPath $Target) -and (Test-Path -LiteralPath $Backup)) {
                Move-Item -LiteralPath $Backup -Destination $Target
                $MovedExisting = $false
            }
            throw
        }
        if (Test-Path -LiteralPath $Backup) {
            Remove-Item -LiteralPath $Backup -Recurse -Force
            $MovedExisting = $false
        }
    } finally {
        Remove-Item -LiteralPath $Stage -Recurse -Force -ErrorAction SilentlyContinue
        if ($MovedExisting -and -not (Test-Path -LiteralPath $Target) -and (Test-Path -LiteralPath $Backup)) {
            Move-Item -LiteralPath $Backup -Destination $Target -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $Backup -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host ('{0}: {1}' -f $Name, $Target) -ForegroundColor Green
    Write-Host ('  Forge root: {0}' -f $InstallationDescriptor.root)
}
