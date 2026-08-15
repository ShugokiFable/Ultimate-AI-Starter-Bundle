[CmdletBinding()]
param(
    [string]$Source = $PWD,
    [Alias('Preset')][string]$ConfigurePreset,
    [string]$BuildPreset,
    [string]$BuildDir,
    [string]$Config = 'Release',
    [switch]$CleanFirst
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath (Join-Path $Source 'CMakeLists.txt'))) { throw 'CMakeLists.txt not found' }
if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) { throw 'cmake was not found on PATH' }
Push-Location $Source
try {
    if ($ConfigurePreset) {
        & cmake --preset $ConfigurePreset
    } elseif ($BuildDir) {
        & cmake -S . -B $BuildDir
    } else {
        throw 'Specify -ConfigurePreset (alias -Preset) or -BuildDir'
    }
    if ($LASTEXITCODE -ne 0) { throw "CMake configure failed: $LASTEXITCODE" }

    $buildArgs=@('--build')
    if ($BuildPreset) {
        $buildArgs += @('--preset',$BuildPreset)
    } elseif ($BuildDir) {
        $buildArgs += $BuildDir
    } else {
        throw 'A configure preset does not imply a same-named build preset. Specify -BuildPreset or the preset binary directory with -BuildDir.'
    }
    $buildArgs += @('--config',$Config)
    if ($CleanFirst) { $buildArgs += '--clean-first' }
    & cmake @buildArgs
    if ($LASTEXITCODE -ne 0) { throw "CMake build failed: $LASTEXITCODE" }
} finally { Pop-Location }
