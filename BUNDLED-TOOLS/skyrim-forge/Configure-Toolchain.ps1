[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$Root=$PSScriptRoot
$Python=Join-Path $Root '.venv\Scripts\python.exe'
if(-not(Test-Path -LiteralPath $Python)){throw 'Install Forge first.'}
Write-Host 'Verified Toolchain Broker' -ForegroundColor Cyan
Write-Host 'Forge scans recursively, including executables nested inside another tool folder or ZIP.'
$Source=Read-Host 'Tool directory or ZIP to scan'
if(-not $Source){exit 0}
$Resolved = (Resolve-Path -LiteralPath $Source).Path
$ReadRoot = if(Test-Path -LiteralPath $Resolved -PathType Container){$Resolved}else{Split-Path -Parent $Resolved}
& $Python -m skyrim_forge config-set tools_root $ReadRoot
if($LASTEXITCODE){throw 'Could not configure the tool scan root.'}
& $Python -m skyrim_forge tool-scan $Resolved
if($LASTEXITCODE){throw 'Tool scan failed.'}
Write-Host ''
Write-Host 'Importable local tools include bsarch, champollion, deadmesh_cli and other catalog entries.'
$All=Read-Host 'Import all recognized automation-capable tools? [y/N]'
if($All -match '^(?i:y|yes)$'){
  & $Python -m skyrim_forge tool-import-all $Resolved --approve
  if($LASTEXITCODE){Write-Warning 'One or more tools were incomplete; review the report.'}
}
$Identifier=Read-Host 'Catalog tool ID to import individually (blank to stop)'
if($Identifier){
  $Confirm=Read-Host "Import $Identifier into the local Forge tool vault and SHA-256 pin it? [y/N]"
  if($Confirm -match '^(?i:y|yes)$'){
    & $Python -m skyrim_forge tool-import $Resolved $Identifier --approve
    if($LASTEXITCODE){throw 'Tool import failed.'}
  }
}
& $Python -m skyrim_forge toolchain-status
