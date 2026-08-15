<#
.SYNOPSIS
  Install the completeness gate into every AI provider that supports hooks.

.DESCRIPTION
  The gate refuses a push, and refuses to end a turn, while a release is
  internally inconsistent - a version bumped without a changelog entry, a README
  left declaring the old version, source changes left uncommitted.

  This is a control rather than a reminder. Every provider's instructions
  already say "be thorough" and agents still ship half a release, because they
  are literal: they do what the sentence said and stop. A hook is the only layer
  that can refuse.

  Providers all read the Claude-compatible hook shape:
    Grok   ~/.grok/hooks/*.json          (always trusted, no folder-trust needed)
    Claude ~/.claude/settings.json       (hooks key, merged)
    Codex  ~/.codex/hooks/*.json
    Kimi   ~/.kimi-code/hooks/*.json
    Hermes ~/.hermes/hooks/*.json

.PARAMETER CheckOnly
  Report what would change and exit.

.PARAMETER Uninstall
  Remove the gate from every provider.
#>
[CmdletBinding()]
param(
  [string]$PackRoot,
  [string[]]$Providers = @('Grok', 'Claude', 'Codex', 'Kimi', 'Hermes'),
  [switch]$CheckOnly,
  [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

if (-not $PackRoot) {
  $here = $PSScriptRoot
  if (-not $here -and $PSCommandPath) { $here = Split-Path -Parent $PSCommandPath }
  if (-not $here) { $here = (Get-Location).Path }
  $PackRoot = Split-Path -Parent $here
}
$hooksSrc = Join-Path $PackRoot 'TOOLS\hooks'
$gate = Join-Path $hooksSrc 'completeness_gate.py'
if (-not (Test-Path -LiteralPath $gate)) { throw "completeness_gate.py not found under $hooksSrc" }

# Resolve a python that will still exist when the hook fires. Prefer an absolute
# interpreter over bare "python": a hook runs in whatever environment the host
# gives it, which is not necessarily one with python on PATH.
$candidates = @(
  $env:SKYRIM_FORGE_PYTHON
  (Get-Command python  -ErrorAction SilentlyContinue).Source
  (Get-Command python3 -ErrorAction SilentlyContinue).Source
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

# Deprioritise the WindowsApps alias: it is sometimes a Store stub that opens a
# shop page instead of running, which would wire a hook that can never fire.
$candidates = @($candidates | Where-Object { $_ -notlike '*\WindowsApps\*' }) +
              @($candidates | Where-Object { $_ -like  '*\WindowsApps\*' })

$python = $null
foreach ($candidate in $candidates) {
  try {
    $out = & $candidate -c "print('ok')" 2>&1 | Out-String
    if ($out -match 'ok') { $python = $candidate; break }
  } catch { }
}
if (-not $python) {
  Write-Host 'SKIP: no python found; the completeness gate needs one. Install Python 3.9+ and re-run.' -ForegroundColor Yellow
  exit 0
}

# Install the script to a stable location that does not depend on the pack
# staying where it is.
$installRoot = Join-Path $env:LOCALAPPDATA 'Skyrim-AI-V5\hooks'
$installed = Join-Path $installRoot 'completeness_gate.py'

$homeMap = @{
  'Grok'   = @{ Dir = Join-Path $env:USERPROFILE '.grok\hooks';      File = 'ultimate-bundle.json'; Style = 'file' }
  'Codex'  = @{ Dir = Join-Path $env:USERPROFILE '.codex\hooks';     File = 'ultimate-bundle.json'; Style = 'file' }
  'Kimi'   = @{ Dir = Join-Path $env:USERPROFILE '.kimi-code\hooks'; File = 'ultimate-bundle.json'; Style = 'file' }
  'Hermes' = @{ Dir = Join-Path $env:USERPROFILE '.hermes\hooks';    File = 'ultimate-bundle.json'; Style = 'file' }
  'Claude' = @{ Dir = Join-Path $env:USERPROFILE '.claude';          File = 'settings.json';        Style = 'settings' }
}

function New-HookBlock {
  param([string]$Py, [string]$Script)
  $pre = '"{0}" "{1}" --pre' -f $Py, $Script
  $stop = '"{0}" "{1}" --stop' -f $Py, $Script
  [ordered]@{
    PreToolUse = @(
      [ordered]@{
        matcher = 'Bash|Shell|Terminal|run_command|execute_command'
        hooks   = @([ordered]@{ type = 'command'; command = $pre; timeout = 15 })
      }
    )
    Stop = @(
      [ordered]@{
        hooks = @([ordered]@{ type = 'command'; command = $stop; timeout = 30 })
      }
    )
  }
}

if ($Uninstall) {
  foreach ($p in $Providers) {
    $m = $homeMap[$p]; if (-not $m) { continue }
    if ($m.Style -eq 'file') {
      $target = Join-Path $m.Dir $m.File
      if (Test-Path -LiteralPath $target) {
        if (-not $CheckOnly) { Remove-Item -LiteralPath $target -Force }
        Write-Host "removed: $target"
      }
    } else {
      $target = Join-Path $m.Dir $m.File
      if (Test-Path -LiteralPath $target) {
        $json = Get-Content -LiteralPath $target -Raw | ConvertFrom-Json
        if ($json.PSObject.Properties.Name -contains 'hooks') {
          foreach ($evt in @('PreToolUse', 'Stop')) {
            if ($json.hooks.PSObject.Properties.Name -contains $evt) {
              $kept = @($json.hooks.$evt | Where-Object {
                -not ($_.hooks | Where-Object { $_.command -like '*completeness_gate.py*' })
              })
              $json.hooks.$evt = $kept
            }
          }
          if (-not $CheckOnly) {
            $json | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $target -Encoding utf8
          }
          Write-Host "cleaned: $target"
        }
      }
    }
  }
  exit 0
}

if (-not $CheckOnly) {
  New-Item -ItemType Directory -Force -Path $installRoot | Out-Null
  Copy-Item -LiteralPath $gate -Destination $installed -Force
}
Write-Host "gate script: $installed"
Write-Host "interpreter: $python"

# Prove it runs before wiring it anywhere. A gate that throws is worse than none,
# even though it fails open.
if (-not $CheckOnly) {
  $selftest = & $python $installed --selftest 2>&1 | Out-String
  if ($selftest -notmatch 'PASS') {
    Write-Host "SKIP: gate self-test did not pass, refusing to wire it:`n$selftest" -ForegroundColor Yellow
    exit 0
  }
  Write-Host 'self-test: PASS'
}

$block = New-HookBlock -Py $python -Script $installed

foreach ($p in $Providers) {
  $m = $homeMap[$p]
  if (-not $m) { Write-Host "unknown provider: $p"; continue }
  $providerHome = Split-Path -Parent $m.Dir
  if ($m.Style -eq 'settings') { $providerHome = $m.Dir }
  if (-not (Test-Path -LiteralPath $providerHome)) {
    Write-Host ("{0,-7} not installed, skipped" -f $p)
    continue
  }
  $target = Join-Path $m.Dir $m.File
  if ($CheckOnly) { Write-Host ("{0,-7} would write {1}" -f $p, $target); continue }

  New-Item -ItemType Directory -Force -Path $m.Dir | Out-Null

  if ($m.Style -eq 'file') {
    ([ordered]@{ hooks = $block }) | ConvertTo-Json -Depth 20 |
      Set-Content -LiteralPath $target -Encoding utf8
    Write-Host ("{0,-7} wired  {1}" -f $p, $target)
  } else {
    # Merge into existing settings.json without disturbing anything else.
    $json = if (Test-Path -LiteralPath $target) {
      Get-Content -LiteralPath $target -Raw | ConvertFrom-Json
    } else { [pscustomobject]@{} }
    if ($json.PSObject.Properties.Name -notcontains 'hooks') {
      $json | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{})
    }
    foreach ($evt in @('PreToolUse', 'Stop')) {
      $existing = @()
      if ($json.hooks.PSObject.Properties.Name -contains $evt) {
        # Drop any previous copy of this gate so re-running is idempotent.
        $existing = @($json.hooks.$evt | Where-Object {
          -not ($_.hooks | Where-Object { $_.command -like '*completeness_gate.py*' })
        })
      }
      $merged = @($existing) + @($block[$evt])
      if ($json.hooks.PSObject.Properties.Name -contains $evt) {
        $json.hooks.$evt = $merged
      } else {
        $json.hooks | Add-Member -NotePropertyName $evt -NotePropertyValue $merged
      }
    }
    $backup = "$target.bak-gate-$(Get-Date -Format yyyyMMdd-HHmmss)"
    if (Test-Path -LiteralPath $target) { Copy-Item -LiteralPath $target -Destination $backup -Force }
    $json | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $target -Encoding utf8
    Write-Host ("{0,-7} merged {1}" -f $p, $target)
  }
}

Write-Host ''
Write-Host 'The gate is silent unless the current commit changed a version declaration.'
Write-Host 'Restart your AI apps for it to take effect.'
