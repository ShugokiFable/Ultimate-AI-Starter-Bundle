[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$Python = Join-Path $Root '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $Python)) { throw 'Install Forge first.' }
$Tools = @(
    @{Name='xedit';Label='SSEEdit64.exe'},
    @{Name='mo2';Label='ModOrganizer.exe'},
    @{Name='loot';Label='LOOT.exe'},
    @{Name='wrye_bash';Label='Wrye Bash.exe'},
    @{Name='creation_kit';Label='CreationKit.exe'},
    @{Name='ckpe_loader';Label='ckpe_loader.exe'},
    @{Name='papyrus_compiler';Label='PapyrusCompiler.exe'},
    @{Name='archive';Label='Archive.exe / BSArch.exe / 7z.exe'},
    @{Name='cmake';Label='cmake.exe'},
    @{Name='vcpkg';Label='vcpkg.exe'},
    @{Name='ninja';Label='ninja.exe (optional)'},
    @{Name='asset_worker';Label='Forge-compatible asset worker executable (optional)'},
    @{Name='animation_worker';Label='Forge-compatible animation worker executable (optional)'},
    @{Name='bodyslide_worker';Label='Forge-compatible BodySlide worker executable (optional)'},
    @{Name='lod_worker';Label='Forge-compatible LOD worker executable (optional)'},
    @{Name='grass_worker';Label='Forge-compatible grass-cache worker executable (optional)'},
    @{Name='synthesis_worker';Label='Forge-compatible Synthesis worker executable (optional)'},
    @{Name='audio_worker';Label='Forge-compatible audio/voice worker executable (optional)'}
)
Write-Host 'Configure only tools installed on this machine. Blank entries are preserved.' -ForegroundColor Cyan
foreach ($Tool in $Tools) {
    $Path = Read-Host "$($Tool.Label) path"
    if ($Path) {
        & $Python -m skyrim_forge config-set "tools.$($Tool.Name).executable" $Path
        if ($LASTEXITCODE) { throw "$($Tool.Name) configuration failed." }
        $Hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
        & $Python -m skyrim_forge config-set "tools.$($Tool.Name).sha256" $Hash
        if ($LASTEXITCODE) { throw "$($Tool.Name) SHA-256 pin failed." }
    }
}
$UI = Read-Host 'Configure coordinate-free Windows UI Automation fallback? [y/N]'
if ($UI -match '^(?i:y|yes)$') {
    $PowerShellExe = Join-Path $PSHOME 'powershell.exe'
    & $Python -m skyrim_forge config-set tools.ui_worker.executable $PowerShellExe
    $WorkerScript = Join-Path $Root 'workers\SkyrimForge.UIWorker.ps1'
    & $Python -m skyrim_forge config-set tools.ui_worker.worker $WorkerScript
    $WorkerHash = (Get-FileHash -LiteralPath $WorkerScript -Algorithm SHA256).Hash.ToLowerInvariant()
    & $Python -m skyrim_forge config-set tools.ui_worker.worker_sha256 $WorkerHash
    & $Python -m skyrim_forge config-set allow_ui_automation true
}
& $Python -m skyrim_forge doctor
