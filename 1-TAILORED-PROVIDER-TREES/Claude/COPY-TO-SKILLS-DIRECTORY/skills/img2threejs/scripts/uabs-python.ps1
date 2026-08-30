[CmdletBinding()]
param(
  [Parameter(Mandatory = $true, Position = 0)][string]$Script,
  [Parameter(ValueFromRemainingArguments = $true)][string[]]$ScriptArgs
)

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$target = if ([IO.Path]::IsPathRooted($Script)) { [IO.Path]::GetFullPath($Script) } else { [IO.Path]::GetFullPath((Join-Path $root $Script)) }
if (-not $target.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'The Python script must be inside the img2threejs skill.' }
if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw "Python script not found: $Script" }

$env:PYTHONUTF8 = '1'
$env:PYTHONDONTWRITEBYTECODE = '1'
$py = Get-Command py.exe -ErrorAction SilentlyContinue
if ($py) { & $py.Source -3 -X utf8 $target @ScriptArgs; exit $LASTEXITCODE }
foreach ($name in @('python.exe', 'python3.exe')) {
  $py = Get-Command $name -ErrorAction SilentlyContinue
  if ($py) { & $py.Source -X utf8 $target @ScriptArgs; exit $LASTEXITCODE }
}
$uv = Get-Command uv.exe -ErrorAction SilentlyContinue
if ($uv) {
  $defaultUvCache = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'uv\cache' } else { '' }
  if (-not $env:UV_CACHE_DIR -and $defaultUvCache -and (Test-Path -LiteralPath $defaultUvCache -PathType Leaf)) {
    $env:UV_CACHE_DIR = Join-Path ([IO.Path]::GetTempPath()) 'uabs-uv-cache'
  }
  & $uv.Source run --python 3.12 python -X utf8 $target @ScriptArgs
  exit $LASTEXITCODE
}
throw 'Python 3.10+ was not found. Re-run START-HERE.bat to repair bundle runtimes.'
