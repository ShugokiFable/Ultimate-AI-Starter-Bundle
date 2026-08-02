$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path $PSScriptRoot -Parent
$scriptPath = Join-Path $repoRoot 'TOOLS\Ensure-Headroom-Grok.ps1'
if (-not (Test-Path -LiteralPath $scriptPath)) {
  throw "Missing production script: $scriptPath"
}

$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
  $scriptPath,
  [ref]$tokens,
  [ref]$parseErrors
)
if ($parseErrors.Count -gt 0) {
  throw ('PowerShell parse errors: ' + (($parseErrors | ForEach-Object Message) -join '; '))
}

function Get-FunctionText([string]$Name) {
  $node = $ast.Find({
    param($candidate)
    $candidate -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
      $candidate.Name -eq $Name
  }, $true)
  if (-not $node) {
    throw "Required function is missing: $Name"
  }
  return $node.Extent.Text
}

foreach ($name in @(
  'Get-HeadroomTaskActionTargetPaths',
  'Test-HeadroomTaskOrphaned'
)) {
  Invoke-Expression (Get-FunctionText $name)
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('headroom-task-test-' + [guid]::NewGuid())
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
try {
  $existingScript = Join-Path $tempRoot 'ensure-headroom.cmd'
  Set-Content -LiteralPath $existingScript -Value '@exit /b 0' -Encoding Ascii
  $missingScript = Join-Path $tempRoot 'missing-ensure-headroom.cmd'
  $manifest = Join-Path $tempRoot 'manifest.json'
  $script:TestManifestPath = $manifest

  function Get-HeadroomManifestPath { return $script:TestManifestPath }

  $shellExe = if ($env:ComSpec) { $env:ComSpec } else { '/bin/sh' }

  $missingTargetTask = [pscustomobject]@{
    TaskName = 'headroom-health'
    TaskPath = '\'
    Actions = @([pscustomobject]@{
      Execute = $shellExe
      Arguments = '/d /c "' + $missingScript + '"'
    })
  }

  if (-not (Test-HeadroomTaskOrphaned $missingTargetTask)) {
    throw 'A task whose shell argument points to a missing Headroom script was not detected as orphaned.'
  }

  Set-Content -LiteralPath $manifest -Value '{"targets":["grok_build"]}' -Encoding UTF8
  $liveTask = [pscustomobject]@{
    TaskName = 'headroom-health'
    TaskPath = '\'
    Actions = @([pscustomobject]@{
      Execute = $shellExe
      Arguments = '/d /c "' + $existingScript + '"'
    })
  }

  if (Test-HeadroomTaskOrphaned $liveTask) {
    throw 'A task with an existing target and deployment manifest was incorrectly marked orphaned.'
  }

  Remove-Item -LiteralPath $manifest -Force
  $deployDir = Join-Path $tempRoot '.headroom\deploy\default'
  New-Item -ItemType Directory -Force -Path $deployDir | Out-Null
  $deployScript = Join-Path $deployDir 'ensure-headroom.cmd'
  Set-Content -LiteralPath $deployScript -Value '@exit /b 0' -Encoding Ascii

  $manifestlessDeployTask = [pscustomobject]@{
    TaskName = 'headroom-ensure'
    TaskPath = '\'
    Actions = @([pscustomobject]@{
      Execute = $shellExe
      Arguments = '/d /c "' + $deployScript + '"'
    })
  }

  if (-not (Test-HeadroomTaskOrphaned $manifestlessDeployTask)) {
    throw 'A Headroom deploy task without its deployment manifest was not detected as orphaned.'
  }

  $source = Get-Content -LiteralPath $scriptPath -Raw
  $mainMarker = "Step 'Headroom + Grok (auth aware)'"
  $cleanupMarker = 'Remove-OrphanHeadroomTasks'
  $headroomLookupMarker = '$hr = Find-HeadroomExe'
  $mainIndex = $source.IndexOf($mainMarker, [StringComparison]::Ordinal)
  $cleanupIndex = $source.IndexOf($cleanupMarker, $mainIndex, [StringComparison]::Ordinal)
  $lookupIndex = $source.IndexOf($headroomLookupMarker, $mainIndex, [StringComparison]::Ordinal)
  if ($mainIndex -lt 0 -or $cleanupIndex -lt 0 -or $lookupIndex -lt 0 -or $cleanupIndex -gt $lookupIndex) {
    throw 'Orphan-task cleanup must run during normal startup before Find-HeadroomExe can exit early.'
  }

  Write-Host 'PASS: Headroom scheduled-task cleanup regression tests.' -ForegroundColor Green
}
finally {
  Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
