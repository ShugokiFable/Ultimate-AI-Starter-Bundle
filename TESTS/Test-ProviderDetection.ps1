<#
.SYNOPSIS
  Prove Get-UabsInstalledProviders reports what is installed, not what is wanted.

.DESCRIPTION
  Through v8.0.4 INSTALL-AIO.ps1 defaulted -Providers to all five and the
  provider bootstrap then downloaded whichever were missing. Someone with only
  Claude finished a "one-click install" carrying four vendor CLIs they never
  asked for, and a provider they had deliberately uninstalled came back on the
  next run.

  The detector is the thing that decides that, so it is tested against a real
  filesystem rather than by reading the installer's source. Each case builds a
  throwaway USERPROFILE/LOCALAPPDATA, plants (or omits) the exact executables
  Resolve-UabsProviderExe looks for, empties PATH so a real installation on the
  build machine cannot leak into the answer, and compares the result.
#>
[CmdletBinding()]
param([string]$PackRoot)

$ErrorActionPreference = 'Stop'
if (-not $PackRoot) { $PackRoot = Split-Path -Parent $PSScriptRoot }
$fail = 0
function Good($m) { Write-Host "  OK   $m" -ForegroundColor Green }
function Bad($m) { Write-Host "  FAIL $m" -ForegroundColor Red; $script:fail++ }

. (Join-Path $PackRoot 'TOOLS\UABS-Common.ps1')

$sandboxRoot = Join-Path ([IO.Path]::GetTempPath()) ('uabs-provider-detect-' + [guid]::NewGuid().ToString('N'))

# Executable layouts Resolve-UabsProviderExe knows, keyed by provider. Relative
# to USERPROFILE unless the path starts with LOCALAPPDATA:.
$layout = @{
    Claude = '.local\bin\claude.exe'
    Codex  = '.local\bin\codex.exe'
    Grok   = '.grok\bin\grok.exe'
    Kimi   = '.kimi-code\bin\kimi.exe'
    Hermes = 'LOCALAPPDATA:hermes\hermes-agent\venv\Scripts\hermes.exe'
}

function Invoke-DetectionCase {
    param(
        [Parameter(Mandatory)][string]$Name,
        [string[]]$Present = @(),
        [string[]]$StaleHomes = @(),
        # Not Mandatory: PowerShell 5.1 refuses to bind an empty array to a
        # mandatory parameter, and "detects nothing" is the most important case.
        [string[]]$Expected = @()
    )
    $case = Join-Path $sandboxRoot ($Name -replace '[^A-Za-z0-9]', '-')
    $profileDir = Join-Path $case 'profile'
    $localDir = Join-Path $case 'local'
    New-Item -ItemType Directory -Force -Path $profileDir, $localDir | Out-Null

    foreach ($provider in $Present) {
        $rel = $layout[$provider]
        $full = if ($rel.StartsWith('LOCALAPPDATA:')) {
            Join-Path $localDir $rel.Substring('LOCALAPPDATA:'.Length)
        } else { Join-Path $profileDir $rel }
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $full) | Out-Null
        # Content is irrelevant; the detector tests for a file, and planting a
        # runnable stub would make this test depend on execution policy.
        [IO.File]::WriteAllText($full, 'stub')
    }
    # A config directory left behind by an uninstall must NOT read as installed.
    foreach ($provider in $StaleHomes) {
        # $homeDir, never $home: $HOME is read-only in Windows PowerShell 5.1
        # and assigning to it is a terminating error, not a shadowed local.
        $homeDir = switch ($provider) {
            'Claude' { '.claude' } 'Codex' { '.codex' } 'Grok' { '.grok' }
            'Kimi' { '.kimi-code' } 'Hermes' { '.hermes' }
        }
        New-Item -ItemType Directory -Force -Path (Join-Path $profileDir $homeDir) | Out-Null
    }

    $savedProfile = $env:USERPROFILE
    $savedLocal = $env:LOCALAPPDATA
    $savedPath = $env:PATH
    try {
        $env:USERPROFILE = $profileDir
        $env:LOCALAPPDATA = $localDir
        # Empty PATH: otherwise the build machine's own claude/codex/grok answer
        # for the sandbox and every case reports five.
        $env:PATH = Join-Path $case 'no-such-bin'
        $got = @(Get-UabsInstalledProviders)
    } finally {
        $env:USERPROFILE = $savedProfile
        $env:LOCALAPPDATA = $savedLocal
        $env:PATH = $savedPath
    }

    $gotText = if ($got.Count) { ($got -join ',') } else { '(none)' }
    $wantText = if ($Expected.Count) { ($Expected -join ',') } else { '(none)' }
    if ($gotText -eq $wantText) { Good "$Name -> $gotText" }
    else { Bad "$Name -> got $gotText, expected $wantText" }
}

Write-Host '=== provider detection ===' -ForegroundColor Cyan
try {
    Invoke-DetectionCase -Name 'empty profile detects nothing' -Expected @()

    Invoke-DetectionCase -Name 'only Claude installed' -Present @('Claude') -Expected @('Claude')

    Invoke-DetectionCase -Name 'Claude plus Hermes under LOCALAPPDATA' `
        -Present @('Claude', 'Hermes') -Expected @('Claude', 'Hermes')

    # The case the maintainer hit: Kimi is gone but ~/.kimi-code survives with
    # AGENTS.md backups in it. Treating that folder as an install would keep
    # re-wiring a provider that was deliberately removed.
    Invoke-DetectionCase -Name 'uninstalled provider leaves a config folder' `
        -Present @('Claude') -StaleHomes @('Kimi', 'Codex') -Expected @('Claude')

    Invoke-DetectionCase -Name 'all five installed' `
        -Present @('Claude', 'Codex', 'Grok', 'Kimi', 'Hermes') `
        -Expected @('Claude', 'Codex', 'Grok', 'Kimi', 'Hermes')

    # Order must follow the canonical list, not the filesystem, so the banner
    # and install-state.json read the same on every machine.
    Invoke-DetectionCase -Name 'result order is canonical, not filesystem order' `
        -Present @('Kimi', 'Claude', 'Grok') -Expected @('Claude', 'Grok', 'Kimi')

    Write-Host '=== installer honours the detector ===' -ForegroundColor Cyan
    $aio = [IO.File]::ReadAllText((Join-Path $PackRoot 'INSTALL-AIO.ps1'))
    # Single quotes: in a double-quoted PowerShell string `\$Providers` is not
    # an escape -- backtick is -- so $Providers interpolates to empty and the
    # pattern silently stops matching what it names.
    if ($aio -match '(?m)^\s*\[string\[\]\]\$Providers\s*=\s*@\(\s*\)\s*,') {
        Good '-Providers defaults to empty (auto-detect), not a hardcoded five'
    } else {
        Bad '-Providers no longer defaults to empty; a default list re-enables install-everything'
    }
    if ($aio -match 'Get-UabsInstalledProviders') { Good 'the installer calls the detector' }
    else { Bad 'the installer does not call Get-UabsInstalledProviders' }
    if ($aio -match '\$AllProviders') { Good '-AllProviders remains the explicit install-everything opt-in' }
    else { Bad '-AllProviders opt-in is gone; a fresh-machine user has no way back' }
    # A fresh machine detects nothing; falling through with an empty list would
    # install nothing at all and report success.
    if ($aio -match "none detected - bootstrapping all") {
        Good 'an empty detection falls back to all five rather than installing nothing'
    } else {
        Bad 'no fallback when nothing is detected: a fresh machine would get an empty install'
    }
} finally {
    if (Test-Path -LiteralPath $sandboxRoot) {
        Remove-Item -LiteralPath $sandboxRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ''
if ($fail -eq 0) {
    Write-Host 'PROVIDER DETECTION GATE: PASS' -ForegroundColor Green
    exit 0
} else {
    Write-Host "PROVIDER DETECTION GATE: FAIL ($fail problem(s))" -ForegroundColor Red
    exit 1
}
