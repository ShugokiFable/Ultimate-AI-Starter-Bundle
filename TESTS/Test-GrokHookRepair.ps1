<# Regression for config-reset hook duplication. Uses temp fixtures only. #>
[CmdletBinding()]
param([string]$PackRoot)
$ErrorActionPreference = 'Stop'
if (-not $PackRoot) { $PackRoot = Split-Path -Parent $PSScriptRoot }
. (Join-Path $PackRoot 'TOOLS\UABS-Common.ps1')
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('uabs-grok-hooks-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixtureRoot | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
try {
  foreach ($newline in @("`n", "`r`n")) {
    $config = Join-Path $fixtureRoot ('config-' + $newline.Length + '.toml')
    $original = @('[ui]', 'compact_mode = true', '[compat.claude]', 'hooks = true # keep comment', 'mcps = true', 'skills = true', 'rules = false', 'future_setting = "keep"', '[mcp_servers.personal]', 'command = "personal-server"', '') -join $newline
    [IO.File]::WriteAllText($config, $original, $utf8)
    Set-UabsGrokCompatCells -ConfigPath $config -HooksOnly
    $actual = [IO.File]::ReadAllText($config)
    Assert ($actual -ceq $original.Replace('hooks = true', 'hooks = false')) 'Hook-only repair changed an unrelated byte.'
    $backups = @(Get-ChildItem -LiteralPath $fixtureRoot -Filter ([IO.Path]::GetFileName($config) + '.before-compat-*.bak'))
    Assert ($backups.Count -eq 1) 'Original config was not backed up.'
    Assert ([IO.File]::ReadAllText($backups[0].FullName) -ceq $original) 'Backup differs from original.'
    Set-UabsGrokCompatCells -ConfigPath $config -HooksOnly
    Assert ([IO.File]::ReadAllText($config) -ceq $actual) 'Repeated hook repair is not idempotent.'
    Assert (@(Get-ChildItem -LiteralPath $fixtureRoot -Filter ([IO.Path]::GetFileName($config) + '.before-compat-*.bak')).Count -eq 1) 'No-op repair created another backup.'
    Set-UabsGrokCompatCells -ConfigPath $config
    $actual = [IO.File]::ReadAllText($config)
    $expected = $original.Replace('hooks = true','hooks = false').Replace('mcps = true','mcps = false').Replace('skills = true','skills = false')
    Assert ($actual -ceq $expected) 'Full repair dropped user keys or later MCP sections.'
    Set-UabsGrokCompatCells -ConfigPath $config -AllowMcp
    Assert ([IO.File]::ReadAllText($config) -ceq $expected.Replace('mcps = false','mcps = true')) 'Explicit inherited MCP preference not honored.'
  }
  $fresh = Join-Path $fixtureRoot 'fresh.toml'
  Set-UabsGrokCompatCells -ConfigPath $fresh -HooksOnly
  $freshText = [IO.File]::ReadAllText($fresh)
  Assert ($freshText -match '(?m)^hooks = false$') 'Fresh hook repair missing its setting.'
  Assert ($freshText -notmatch 'mcps|skills') 'Fresh hook-only repair imposed unrelated defaults.'
  $missing = Join-Path $fixtureRoot 'missing-section.toml'
  [IO.File]::WriteAllText($missing, "[ui]`ncompact_mode = true`n", $utf8)
  Set-UabsGrokCompatCells -ConfigPath $missing -HooksOnly
  Assert ([IO.File]::ReadAllText($missing).StartsWith("[ui]`ncompact_mode = true`n")) 'Missing-section repair overwrote existing config.'
  $invalid = Join-Path $fixtureRoot 'invalid.toml'
  $invalidText = "[compat.claude]`nhooks = 'invalid'`n"
  [IO.File]::WriteAllText($invalid, $invalidText, $utf8)
  $refused = $false
  try { Set-UabsGrokCompatCells -ConfigPath $invalid -HooksOnly } catch { $refused = $true }
  Assert ($refused -and [IO.File]::ReadAllText($invalid) -ceq $invalidText) 'Invalid owned cell was silently rewritten.'

  $inspection = [pscustomobject]@{
    externalCompat = [pscustomobject]@{ cells = @([pscustomobject]@{vendor='claude';surface='hooks';enabled=$true}) }
    hooks = @(
      [pscustomobject]@{event='stop'; target='& "python.exe" "completeness_gate.py" --stop';source=[pscustomobject]@{path='C:\fixture\.grok\hooks'}},
      [pscustomobject]@{event='stop'; target='"python.exe" "completeness_gate.py" --stop';source=[pscustomobject]@{path='C:\fixture\.claude'}}
    )
  }
  Assert (@(Get-UabsGrokHookIssues -Inspection $inspection).Count -eq 1) 'Inherited duplicate was not detected.'
  $inspection.externalCompat.cells[0].enabled = $false
  Assert (@(Get-UabsGrokHookIssues -Inspection $inspection).Count -eq 0) 'Disabled discovery was misreported as active.'
  $inspection.hooks[0].target = '"python.exe" "completeness_gate.py" --stop'
  Assert (@(Get-UabsGrokHookIssues -Inspection $inspection).Count -eq 1) 'Broken native PowerShell command was not detected.'
  $inspection.externalCompat.cells = @()
  $refused = $false
  try { Get-UabsGrokHookIssues -Inspection $inspection | Out-Null } catch { $refused = $true }
  Assert $refused 'Unknown inspect schema was silently accepted.'
  Write-Host 'GROK HOOK REPAIR GATE: PASS'
} finally {
  $resolved = (Resolve-Path -LiteralPath $fixtureRoot).Path
  $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
  if (-not $resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'uabs-grok-hooks-*') { throw 'Unsafe fixture cleanup target.' }
  Remove-Item -LiteralPath $resolved -Recurse -Force
}
