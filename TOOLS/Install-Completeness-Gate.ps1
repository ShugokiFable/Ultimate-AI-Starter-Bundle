<#
.SYNOPSIS
  Install the completeness gate using each provider's real hook mechanism.

.DESCRIPTION
  The gate refuses a push, and refuses to end a turn, while a release is
  internally inconsistent - a version bumped without a changelog entry, a README
  left declaring the old version, source changes left uncommitted.

  v6.8.0 wired every provider by dropping the same JSON into
  `~/.<provider>/hooks/`. That was an assumption, and it was wrong for three of
  the five. Each provider is now installed the way it actually loads hooks,
  verified against its own documentation or CLI:

    Claude  ~/.claude/settings.json          hooks key, merged. VERIFIED.
    Grok    ~/.grok/hooks/*.json             always trusted, no folder-trust
                                             needed. VERIFIED against Grok's
                                             own docs/user-guide/10-hooks.md.
    Codex   plugin from a local marketplace  Codex loads hooks from PLUGINS and
                                             requires a trusted_hash entry in
                                             [hooks.state]. A bare JSON file in
                                             ~/.codex/hooks is never read.
                                             Codex prompts once to trust it.
    Hermes  ~/.hermes/config.yaml            `hooks:` block of shell hooks, per
                                             `hermes hooks --help`. Uses
                                             pre_tool_call and pre_verify, and
                                             accepts Claude-style
                                             {"decision":"block"} output.
    Kimi    NOT SUPPORTED                    Kimi Code has no hook or plugin
                                             system - skills and MCP only, per
                                             `kimi --help`. Any file placed in
                                             ~/.kimi-code/hooks is dead weight
                                             and is removed by this script.

.PARAMETER CheckOnly
  Report what would change and exit.

.PARAMETER Uninstall
  Remove the gate from every provider.
#>
[CmdletBinding()]
param(
  [string]$PackRoot,
  [string[]]$Providers = @('Claude', 'Grok', 'Codex', 'Hermes'),
  [switch]$CheckOnly,
  [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

# Windows PowerShell 5.1's `Set-Content -Encoding utf8` writes a UTF-8 BOM, and a
# strict JSON reader rejects a file that starts with one. This pack exists partly
# because a BOM once made seven skills invisible.
function Set-Utf8NoBom {
  param([string]$Path, [string]$Text)
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Text, $enc)
}

if (-not $PackRoot) {
  $here = $PSScriptRoot
  if (-not $here -and $PSCommandPath) { $here = Split-Path -Parent $PSCommandPath }
  if (-not $here) { $here = (Get-Location).Path }
  $PackRoot = Split-Path -Parent $here
}
$hooksSrc  = Join-Path $PackRoot 'TOOLS\hooks'
$gateSrc   = Join-Path $hooksSrc 'completeness_gate.py'
$pluginSrc = Join-Path $hooksSrc 'plugin'
if (-not (Test-Path -LiteralPath $gateSrc)) { throw "completeness_gate.py not found under $hooksSrc" }

$installRoot   = Join-Path $env:LOCALAPPDATA 'Skyrim-AI-V5\hooks'
$installedGate = Join-Path $installRoot 'completeness_gate.py'
$marketRoot    = Join-Path $env:LOCALAPPDATA 'Skyrim-AI-V5\codex-marketplace'

$python = $null
$candidates = @(
  $env:SKYRIM_FORGE_PYTHON
  (Get-Command python  -ErrorAction SilentlyContinue).Source
  (Get-Command python3 -ErrorAction SilentlyContinue).Source
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
$candidates = @($candidates | Where-Object { $_ -notlike '*\WindowsApps\*' }) +
              @($candidates | Where-Object { $_ -like  '*\WindowsApps\*' })
foreach ($c in $candidates) {
  try { if ((& $c -c "print('ok')" 2>&1 | Out-String) -match 'ok') { $python = $c; break } } catch { }
}
if (-not $python) {
  Write-Host 'SKIP: no working python found. Install Python 3.9+ and re-run.' -ForegroundColor Yellow
  exit 0
}

# Files v6.8.0 wrote where the provider never looks. Removing them is part of the
# fix: a hook file that is never read is worse than none, because it looks installed.
$deadDrops = @(
  (Join-Path $env:USERPROFILE '.codex\hooks\ultimate-bundle.json'),
  (Join-Path $env:USERPROFILE '.kimi-code\hooks\ultimate-bundle.json'),
  (Join-Path $env:USERPROFILE '.hermes\hooks\ultimate-bundle.json')
)

function Remove-DeadDrops {
  foreach ($d in $deadDrops) {
    if (Test-Path -LiteralPath $d) {
      if (-not $CheckOnly) { Remove-Item -LiteralPath $d -Force -ErrorAction SilentlyContinue }
      Write-Host "  removed inert file: $d"
    }
  }
}

function New-HookBlock {
  param([string]$Py, [string]$Script)
  [ordered]@{
    PreToolUse = @([ordered]@{
      matcher = 'Bash|Shell|Terminal|PowerShell|run_command|execute_command'
      hooks   = @([ordered]@{ type='command'; command=('"{0}" "{1}" --pre'  -f $Py,$Script); timeout=15 })
    })
    Stop = @([ordered]@{
      hooks = @([ordered]@{ type='command'; command=('"{0}" "{1}" --stop' -f $Py,$Script); timeout=30 })
    })
  }
}

if ($Uninstall) {
  Remove-DeadDrops
  $g = Join-Path $env:USERPROFILE '.grok\hooks\ultimate-bundle.json'
  if (Test-Path -LiteralPath $g) { if (-not $CheckOnly) { Remove-Item -LiteralPath $g -Force }; Write-Host "removed: $g" }
  $s = Join-Path $env:USERPROFILE '.claude\settings.json'
  if (Test-Path -LiteralPath $s) {
    $json = Get-Content -LiteralPath $s -Raw | ConvertFrom-Json
    if ($json.PSObject.Properties.Name -contains 'hooks') {
      foreach ($evt in @('PreToolUse','Stop')) {
        if ($json.hooks.PSObject.Properties.Name -contains $evt) {
          $json.hooks.$evt = @($json.hooks.$evt | Where-Object {
            -not ($_.hooks | Where-Object { $_.command -like '*completeness_gate.py*' }) })
        }
      }
      if (-not $CheckOnly) { Set-Utf8NoBom -Path $s -Text ($json | ConvertTo-Json -Depth 20) }
      Write-Host "cleaned: $s"
    }
  }
  Write-Host 'Codex: disable [plugins."completeness-gate@ultimate-bundle"] in ~/.codex/config.toml'
  Write-Host 'Hermes: remove the completeness_gate entries from ~/.hermes/config.yaml'
  exit 0
}

if (-not $CheckOnly) {
  New-Item -ItemType Directory -Force -Path $installRoot | Out-Null
  Copy-Item -LiteralPath $gateSrc -Destination $installedGate -Force
  $selftest = & $python $installedGate --selftest 2>&1 | Out-String
  if ($selftest -notmatch 'PASS') {
    Write-Host "SKIP: gate self-test failed, refusing to wire it:`n$selftest" -ForegroundColor Yellow
    exit 0
  }
  Write-Host "gate: $installedGate  (self-test PASS)"
}
Write-Host "interpreter: $python"
Remove-DeadDrops

$block = New-HookBlock -Py $python -Script $installedGate

foreach ($p in $Providers) {
  switch ($p) {

    'Claude' {
      $target = Join-Path $env:USERPROFILE '.claude\settings.json'
      if (-not (Test-Path -LiteralPath (Split-Path -Parent $target))) { Write-Host 'Claude  not installed'; break }
      if ($CheckOnly) { Write-Host "Claude  would merge $target"; break }
      $json = if (Test-Path -LiteralPath $target) { Get-Content -LiteralPath $target -Raw | ConvertFrom-Json } else { [pscustomobject]@{} }
      if ($json.PSObject.Properties.Name -notcontains 'hooks') { $json | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{}) }
      foreach ($evt in @('PreToolUse','Stop')) {
        $existing = @()
        if ($json.hooks.PSObject.Properties.Name -contains $evt) {
          $existing = @($json.hooks.$evt | Where-Object { -not ($_.hooks | Where-Object { $_.command -like '*completeness_gate.py*' }) })
        }
        $merged = @($existing) + @($block[$evt])
        if ($json.hooks.PSObject.Properties.Name -contains $evt) { $json.hooks.$evt = $merged }
        else { $json.hooks | Add-Member -NotePropertyName $evt -NotePropertyValue $merged }
      }
      Copy-Item -LiteralPath $target -Destination "$target.bak-gate-$(Get-Date -Format yyyyMMdd-HHmmss)" -Force -ErrorAction SilentlyContinue
      Set-Utf8NoBom -Path $target -Text ($json | ConvertTo-Json -Depth 20)
      Write-Host "Claude  merged into settings.json"
    }

    'Grok' {
      $dir = Join-Path $env:USERPROFILE '.grok\hooks'
      if (-not (Test-Path -LiteralPath (Split-Path -Parent $dir))) { Write-Host 'Grok    not installed'; break }
      if ($CheckOnly) { Write-Host "Grok    would write $dir\ultimate-bundle.json"; break }
      New-Item -ItemType Directory -Force -Path $dir | Out-Null
      Set-Utf8NoBom -Path (Join-Path $dir 'ultimate-bundle.json') -Text (([ordered]@{ hooks = $block }) | ConvertTo-Json -Depth 20)
      Write-Host "Grok    wired ~/.grok/hooks/ultimate-bundle.json"
    }

    'Codex' {
      $cfg = Join-Path $env:USERPROFILE '.codex\config.toml'
      if (-not (Test-Path -LiteralPath $cfg)) { Write-Host 'Codex   not installed'; break }
      if (-not (Test-Path -LiteralPath $pluginSrc)) { Write-Host 'Codex   plugin source missing from pack'; break }
      if ($CheckOnly) { Write-Host "Codex   would install plugin marketplace at $marketRoot"; break }

      # Materialise the marketplace, with the gate travelling inside the plugin
      # so ${CLAUDE_PLUGIN_ROOT} resolves without an absolute path.
      if (Test-Path -LiteralPath $marketRoot) { Remove-Item -LiteralPath $marketRoot -Recurse -Force }
      New-Item -ItemType Directory -Force -Path $marketRoot | Out-Null
      # -LiteralPath does NOT expand wildcards, so this silently copied nothing
      # and left a registered plugin with no files behind it.
      Copy-Item -Path (Join-Path $pluginSrc '*') -Destination $marketRoot -Recurse -Force
      $copied = @(Get-ChildItem -Recurse -File $marketRoot -ErrorAction SilentlyContinue).Count
      if ($copied -lt 3) { Write-Host "Codex   FAILED to materialise the plugin ($copied files)" -ForegroundColor Yellow; break }

      $toml = Get-Content -LiteralPath $cfg -Raw
      $add = ''
      if ($toml -notmatch '(?m)^\[marketplaces\.ultimate-bundle\]') {
        $add += "`r`n[marketplaces.ultimate-bundle]`r`nsource_type = `"local`"`r`nsource = '$marketRoot'`r`n"
      }
      if ($toml -notmatch '(?m)^\[plugins\."completeness-gate@ultimate-bundle"\]') {
        $add += "`r`n[plugins.`"completeness-gate@ultimate-bundle`"]`r`nenabled = true`r`n"
      }
      if ($add) {
        Copy-Item -LiteralPath $cfg -Destination "$cfg.bak-gate-$(Get-Date -Format yyyyMMdd-HHmmss)" -Force
        Set-Utf8NoBom -Path $cfg -Text ($toml + $add)
        Write-Host "Codex   plugin registered (Codex will ask once to trust the hook)"
      } else {
        Write-Host "Codex   plugin already registered"
      }
    }

    'Hermes' {
      $hermesHome = Join-Path $env:USERPROFILE '.hermes'
      if (-not (Test-Path -LiteralPath $hermesHome)) { Write-Host 'Hermes  not installed'; break }
      $cfg = Join-Path $hermesHome 'config.yaml'
      if ($CheckOnly) { Write-Host "Hermes  would add hooks to $cfg"; break }

      $existing = if (Test-Path -LiteralPath $cfg) { Get-Content -LiteralPath $cfg -Raw } else { '' }
      if ($existing -match 'completeness_gate') {
        Write-Host 'Hermes  hooks already present'
      } else {
        # Shell-hook schema per `hermes hooks --help`: pre_tool_call can block a
        # tool, pre_verify keeps the agent working at the verify gate. Both
        # accept Claude-style {"decision":"block"}, which the gate already emits.
        # YAML + shlex hazard: a Windows path inside a DOUBLE-quoted YAML
        # scalar makes the backslash sequences invalid escapes, the whole
        # config fails to parse, and Hermes silently reports no hooks at all.
        # Forward slashes are accepted by Windows and survive both YAML
        # single-quoting and Hermes's shlex.split.
        $pyF   = $python.Replace('\', '/')
        $gateF = $installedGate.Replace('\', '/')
        $pre  = ('"{0}" "{1}" --pre'  -f $pyF, $gateF)
        $stop = ('"{0}" "{1}" --stop' -f $pyF, $gateF)
        $yaml = @"

# Ultimate AI Starter Bundle - completeness gate
hooks:
  pre_tool_call:
    - matcher: "terminal"
      command: '$pre'
      timeout: 20
  pre_verify:
    - command: '$stop'
      timeout: 40
"@
        if ($existing -match '(?m)^hooks:') {
          Write-Host 'Hermes  config.yaml already has a hooks: block - not editing it.'
          Write-Host '        Add these two entries by hand:'
          Write-Host "          pre_tool_call: command: $pre"
          Write-Host "          pre_verify:    command: $stop"
        } else {
          if (Test-Path -LiteralPath $cfg) { Copy-Item -LiteralPath $cfg -Destination "$cfg.bak-gate-$(Get-Date -Format yyyyMMdd-HHmmss)" -Force }
          Set-Utf8NoBom -Path $cfg -Text ($existing + $yaml)
          Write-Host "Hermes  hooks added to config.yaml (first run asks for consent)"
        }
      }
    }
  }
}

Write-Host ''
Write-Host 'Kimi    NOT SUPPORTED - Kimi Code has no hook or plugin system (skills + MCP only).'
Write-Host ''
Write-Host 'Silent unless the current commit changed a version declaration. Restart each app.'
Write-Host 'Verify:  hermes hooks doctor    |    Codex: approve the trust prompt once'
