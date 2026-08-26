<#
.SYNOPSIS
  Copy this pack's LM Studio sampling presets into LM Studio's preset folder.

.DESCRIPTION
  Deliberately NOT called by START-HERE.ps1 / INSTALL-AIO.ps1. LM Studio is a
  desktop app that owns its own configuration, and this pack does not rewrite
  another application's settings without being asked -- the same rule that
  keeps it from deleting autostarts it did not create.

  Only the presets are copied. `settings.json` is never touched: the real one
  carries an absolute downloads path, two Hugging Face credential fields and an
  account billing context, none of which should move between machines. The
  handful of values worth changing are listed in README.md, and the one that
  actually breaks things -- context length 65,536 -- has to be set in the UI
  anyway.

  Existing presets are left alone unless -Force is given.

.PARAMETER Force
  Overwrite a preset of the same name. Without it, an existing file is reported
  and skipped.

.PARAMETER LmStudioHome
  Override the LM Studio home. Defaults to %USERPROFILE%\.lmstudio.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [switch]$Force,
  [string]$LmStudioHome
)

$ErrorActionPreference = 'Stop'

$source = Join-Path $PSScriptRoot 'config-presets'
if (-not (Test-Path -LiteralPath $source -PathType Container)) {
  Write-Error "No config-presets folder next to this script ($source)."
  exit 1
}

if (-not $LmStudioHome) { $LmStudioHome = Join-Path $env:USERPROFILE '.lmstudio' }
$target = Join-Path $LmStudioHome 'config-presets'

Write-Host '== LM Studio presets =='
Write-Host "source: $source"
Write-Host "target: $target"
Write-Host ''

if (-not (Test-Path -LiteralPath $LmStudioHome -PathType Container)) {
  # Creating .lmstudio ourselves would leave a half-made home for an app that
  # is not installed. Say so instead.
  Write-Warning "LM Studio home not found at $LmStudioHome -- is LM Studio installed and has it been run once?"
  Write-Host 'Nothing was copied. Pass -LmStudioHome <path> if yours lives elsewhere.'
  exit 1
}

if (-not (Test-Path -LiteralPath $target -PathType Container)) {
  if ($PSCmdlet.ShouldProcess($target, 'create preset folder')) {
    New-Item -ItemType Directory -Force -Path $target | Out-Null
  }
}

$copied = 0
$skipped = 0
foreach ($file in Get-ChildItem -LiteralPath $source -Filter '*.preset.json' -File) {
  $dest = Join-Path $target $file.Name
  $exists = Test-Path -LiteralPath $dest -PathType Leaf

  if ($exists -and -not $Force) {
    Write-Host ("  skip     {0}  (already present -- use -Force to overwrite)" -f $file.Name) -ForegroundColor DarkGray
    $skipped++
    continue
  }

  $verb = if ($exists) { 'overwrite preset' } else { 'copy preset' }
  if ($PSCmdlet.ShouldProcess($dest, $verb)) {
    Copy-Item -LiteralPath $file.FullName -Destination $dest -Force
    Write-Host ("  {0,-8} {1}" -f $(if ($exists) { 'replaced' } else { 'copied' }), $file.Name) -ForegroundColor Green
    $copied++
  }
}

Write-Host ''
Write-Host ("$copied copied, $skipped left alone.")
if ($copied) {
  Write-Host 'Restart LM Studio for them to appear in the preset dropdown.' -ForegroundColor Yellow
}
Write-Host ''
Write-Host 'Still to do by hand, and it is the one that matters:' -ForegroundColor Yellow
Write-Host '  set the context length to 65,536. Under 64,000 Hermes will not start.'
exit 0
