<#
.SYNOPSIS
  Install the completeness gate and the assumption gate using each provider's
  real hook mechanism.

.DESCRIPTION
  Two controls, same three design rules (precise, cheap, fail open):

    completeness_gate.py  refuses a push, and refuses to end a turn, while a
                          release is internally inconsistent - a version bumped
                          without a changelog entry, a README left declaring the
                          old version, source changes left uncommitted.
    assumption_gate.py    refuses a path nobody verified and code nobody read -
                          a drive letter that does not exist on this machine,
                          another user's home directory hardcoded into a script,
                          remote content piped straight into a shell.

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
    Hermes  the path `hermes config path`    NOT ~/.hermes/config.yaml. Hermes's
            reports                          own docs name that path; the
                                             resolved one honours HERMES_HOME.
                                             v6.8.1 shipped an installer that
                                             still wrote to the documented path
                                             and detected Hermes by testing for
                                             a directory a working install does
                                             not have. Both are fixed here by
                                             asking the tool instead.
    Kimi    GATE NOT WIRED                   Both halves of the old claim here
                                             (`no hook or plugin system`) are
                                             false. v7.7.0 established the
                                             plugin system and the AIO installer
                                             now uses it. The shipped binary also
                                             carries a hook engine - PreToolUse,
                                             PostToolUse and Stop - fed from
                                             `config.hooks` plus every enabled
                                             plugin's own hooks. What is NOT
                                             established is the exact config
                                             schema those entries take, so this
                                             script does not write one: guessing
                                             it would corrupt a working
                                             config.toml. Kimi gets the skills
                                             and the native plugin, not the gate.
                                             ~/.kimi-code/hooks is still not a
                                             path Kimi reads, so files dropped
                                             there are still removed.

.PARAMETER CheckOnly
  Report what would change and exit.

.PARAMETER Uninstall
  Remove both gates from every provider.
#>
[CmdletBinding()]
param(
  [string]$PackRoot,
  [string[]]$Providers = @('Claude', 'Grok', 'Codex', 'Hermes'),
  [switch]$CheckOnly,
  [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

# powershell.exe -File serializes Claude,Codex as one comma-delimited string.
$Providers = @($Providers | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$AllowedProviders = @('Claude','Grok','Codex','Hermes','Kimi')
foreach ($ProviderName in $Providers) { if ($AllowedProviders -notcontains $ProviderName) { throw "Unknown provider: $ProviderName" } }

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
$pluginSrc = Join-Path $hooksSrc 'plugin'
$wireSrc   = Join-Path $hooksSrc 'hermes_wire.py'

# Add-UabsMarketplacePluginEntry lives in the installer's shared module. The
# gate also runs standalone, so this load is optional - without it the
# marketplace is still built, just with a warning instead of the entry.
$v7Common = Join-Path $PackRoot 'TOOLS\UABS-Common.ps1'
if (Test-Path -LiteralPath $v7Common) { . $v7Common }

# Every gate the pack ships, with the tools each one needs to see.
$gates = @(
  @{ Name = 'completeness_gate.py'; Matcher = 'Bash|Shell|Terminal|PowerShell|run_command|execute_command'; AllTools = $false }
  @{ Name = 'assumption_gate.py';   Matcher = 'Bash|Shell|Terminal|PowerShell|run_command|execute_command|Write|Edit|MultiEdit|NotebookEdit|write_file|create_file|str_replace.*'; AllTools = $true }
)
foreach ($g in $gates) {
  if (-not (Test-Path -LiteralPath (Join-Path $hooksSrc $g.Name))) { throw "$($g.Name) not found under $hooksSrc" }
}

$installRoot = Join-Path $env:LOCALAPPDATA 'Ultimate-AI-Starter-Bundle\hooks'
$marketRoot  = Join-Path $env:LOCALAPPDATA 'Ultimate-AI-Starter-Bundle\codex-marketplace'

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
  (Join-Path $env:USERPROFILE '.hermes\hooks\ultimate-bundle.json'),
  # v6.8.1's installer wrote a Hermes config at the documented path. Hermes
  # never reads it, so it is the same kind of dead weight.
  (Join-Path $env:USERPROFILE '.hermes\config.yaml')
)

function Remove-DeadDrops {
  foreach ($d in $deadDrops) {
    if (Test-Path -LiteralPath $d) {
      # Only reclaim a config this pack created; never touch a user's own file.
      if ($d -like '*config.yaml' -and ([IO.File]::ReadAllText($d)) -notmatch '_gate\.py') { continue }
      if (-not $CheckOnly) { Remove-Item -LiteralPath $d -Force -ErrorAction SilentlyContinue }
      Write-Host "  removed inert file: $d"
    }
  }
}

function Get-HermesExe {
  # Never assume ~/.hermes: a working install keeps its home wherever
  # HERMES_HOME points, and on Windows that is under LOCALAPPDATA.
  $cmd = (Get-Command hermes -ErrorAction SilentlyContinue).Source
  if ($cmd) { return $cmd }
  $venv = Join-Path $env:LOCALAPPDATA 'hermes\hermes-agent\venv\Scripts\hermes.exe'
  if (Test-Path -LiteralPath $venv) { return $venv }
  return $null
}

function New-HookBlock {
  param([string]$Py, [string]$Root, [switch]$CallOperator)
  # Grok executes hook commands through PowerShell, where `"exe" "arg"` is a
  # parse error ("Unexpected token ... At line:1 char:65") because a quoted
  # command needs the call operator. cmd.exe (Claude Code's shell) chokes on a
  # leading `&` instead, so only Grok's block gets the `& ` prefix (v7.6.4).
  $co = if ($CallOperator) { '& ' } else { '' }
  $pre  = @()
  $stop = @()
  foreach ($g in $gates) {
    $script = Join-Path $Root $g.Name
    $pre  += [ordered]@{
      matcher = $g.Matcher
      hooks   = @([ordered]@{ type='command'; command=('{0}"{1}" "{2}" --pre'  -f $co,$Py,$script); timeout=15 })
    }
    $stop += [ordered]@{
      hooks = @([ordered]@{ type='command'; command=('{0}"{1}" "{2}" --stop' -f $co,$Py,$script); timeout=30 })
    }
  }
  [ordered]@{ PreToolUse = $pre; Stop = $stop }
}

if ($Uninstall) {
  Remove-DeadDrops
  $g = Join-Path $env:USERPROFILE '.grok\hooks\ultimate-bundle.json'
  if (Test-Path -LiteralPath $g) { if (-not $CheckOnly) { Remove-Item -LiteralPath $g -Force }; Write-Host "removed: $g" }
  $s = Join-Path $env:USERPROFILE '.claude\settings.json'
  if (Test-Path -LiteralPath $s) {
    $json = [IO.File]::ReadAllText($s) | ConvertFrom-Json
    if ($json.PSObject.Properties.Name -contains 'hooks') {
      foreach ($evt in @('PreToolUse','Stop')) {
        if ($json.hooks.PSObject.Properties.Name -contains $evt) {
          $json.hooks.$evt = @($json.hooks.$evt | Where-Object {
            -not ($_.hooks | Where-Object { $_.command -like '*_gate.py*' }) })
        }
      }
      if (-not $CheckOnly) { Set-Utf8NoBom -Path $s -Text ($json | ConvertTo-Json -Depth 20) }
      Write-Host "cleaned: $s"
    }
  }
  $hx = Get-HermesExe
  if ($hx -and -not $CheckOnly -and (Test-Path -LiteralPath $wireSrc)) {
    foreach ($g in $gates) { & $python $wireSrc $hx $python (Join-Path $installRoot $g.Name) --remove }
  }
  Write-Host 'Codex: disable [plugins."completeness-gate@ultimate-bundle"] in ~/.codex/config.toml'
  exit 0
}

if (-not $CheckOnly) {
  New-Item -ItemType Directory -Force -Path $installRoot | Out-Null
  foreach ($g in $gates) {
    $dest = Join-Path $installRoot $g.Name
    Copy-Item -LiteralPath (Join-Path $hooksSrc $g.Name) -Destination $dest -Force
    # Never wire a gate that cannot prove itself first.
    $selftest = & $python $dest --selftest 2>&1 | Out-String
    if ($selftest -notmatch 'PASS') {
      Write-Host "SKIP: $($g.Name) self-test failed, refusing to wire it:`n$selftest" -ForegroundColor Yellow
      exit 0
    }
    Write-Host "gate: $dest  (self-test PASS)"
  }
}
Write-Host "interpreter: $python"
Remove-DeadDrops

$block = New-HookBlock -Py $python -Root $installRoot

foreach ($p in $Providers) {
  switch ($p) {

    'Claude' {
      $target = Join-Path $env:USERPROFILE '.claude\settings.json'
      if (-not (Test-Path -LiteralPath (Split-Path -Parent $target))) { Write-Host 'Claude  not installed'; break }
      if ($CheckOnly) { Write-Host "Claude  would merge $target"; break }
      $json = if (Test-Path -LiteralPath $target) { [IO.File]::ReadAllText($target) | ConvertFrom-Json } else { [pscustomobject]@{} }
      if ($json.PSObject.Properties.Name -notcontains 'hooks') { $json | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{}) }
      foreach ($evt in @('PreToolUse','Stop')) {
        $existing = @()
        if ($json.hooks.PSObject.Properties.Name -contains $evt) {
          $existing = @($json.hooks.$evt | Where-Object { -not ($_.hooks | Where-Object { $_.command -like '*_gate.py*' }) })
        }
        $merged = @($existing) + @($block[$evt])
        if ($json.hooks.PSObject.Properties.Name -contains $evt) { $json.hooks.$evt = $merged }
        else { $json.hooks | Add-Member -NotePropertyName $evt -NotePropertyValue $merged }
      }
      Copy-Item -LiteralPath $target -Destination "$target.bak-gate-$(Get-Date -Format yyyyMMdd-HHmmss)" -Force -ErrorAction SilentlyContinue
      Set-Utf8NoBom -Path $target -Text ($json | ConvertTo-Json -Depth 20)
      Write-Host "Claude  merged $($gates.Count) gates into settings.json"
    }

    'Grok' {
      $dir = Join-Path $env:USERPROFILE '.grok\hooks'
      if (-not (Test-Path -LiteralPath (Split-Path -Parent $dir))) { Write-Host 'Grok    not installed'; break }
      if ($CheckOnly) { Write-Host "Grok    would write $dir\ultimate-bundle.json"; break }
      New-Item -ItemType Directory -Force -Path $dir | Out-Null
      $grokBlock = New-HookBlock -Py $python -Root $installRoot -CallOperator
      Set-Utf8NoBom -Path (Join-Path $dir 'ultimate-bundle.json') -Text (([ordered]@{ hooks = $grokBlock }) | ConvertTo-Json -Depth 20)
      Write-Host "Grok    wired ~/.grok/hooks/ultimate-bundle.json ($($gates.Count) gates, PowerShell call-operator form)"
    }

    'Codex' {
      $cfg = Join-Path $env:USERPROFILE '.codex\config.toml'
      if (-not (Test-Path -LiteralPath $cfg)) { Write-Host 'Codex   not installed'; break }
      if ($CheckOnly) { Write-Host 'Codex   skill/native-plugin enforcement (no executable trust prompt)'; break }

      # Codex deliberately requires explicit trust for executable plugin hooks.
      # Do not forge [hooks.state] hashes. v7.8 uses the reliability skills and
      # native provider plugin rules instead, and disables only our legacy gate
      # entry if an older bundle registered it.
      $toml = [IO.File]::ReadAllText($cfg)
      $updated = [regex]::Replace(
        $toml,
        '(?ms)(^\[plugins\."completeness-gate@ultimate-bundle"\]\s*.*?^enabled\s*=\s*)true',
        '${1}false'
      )
      if ($updated -ne $toml) {
        Copy-Item -LiteralPath $cfg -Destination "$cfg.bak-gate-$(Get-Date -Format yyyyMMdd-HHmmss)" -Force
        Set-Utf8NoBom -Path $cfg -Text $updated
      }
      Write-Host 'Codex   skill/native-plugin enforcement (legacy executable gate disabled; trust state untouched)'
    }

    'Hermes' {
      $hx = Get-HermesExe
      if (-not $hx) { Write-Host 'Hermes  not installed'; break }
      if (-not (Test-Path -LiteralPath $wireSrc)) { Write-Host 'Hermes  hermes_wire.py missing from pack'; break }
      if ($CheckOnly) { Write-Host "Hermes  would merge hooks into $(& $hx config path)"; break }

      # Hand off to hermes_wire.py: it asks `hermes config path` for the real
      # location, parses the existing YAML instead of appending text to it, and
      # verifies the result round-trips before reporting success. Writing this
      # config by hand is what shipped broken in v6.8.1.
      foreach ($g in $gates) {
        $args = @($wireSrc, $hx, $python, (Join-Path $installRoot $g.Name))
        if ($g.AllTools) { $args += '--all-tools' }
        & $python @args
      }
      # Auto-accept only the installer-owned hooks for this one verification
      # process. Never persist hooks_auto_accept=true for future third-party hooks.
      $previousAccept = $env:HERMES_ACCEPT_HOOKS
      try {
        $env:HERMES_ACCEPT_HOOKS = '1'
        & $hx hooks list
        if ($LASTEXITCODE -ne 0) { throw "Hermes hook verification failed with exit $LASTEXITCODE." }
      } finally {
        if ($null -eq $previousAccept) { Remove-Item Env:HERMES_ACCEPT_HOOKS -ErrorAction SilentlyContinue }
        else { $env:HERMES_ACCEPT_HOOKS = $previousAccept }
      }
    }
  }
}

Write-Host ''
Write-Host 'Kimi    gate not wired - Kimi has a plugin system (installed by the AIO run) and a'
Write-Host '        hook engine, but its hook config schema is not established, so nothing is'
Write-Host '        guessed into config.toml. Skills and the native plugin are installed.'
Write-Host ''
Write-Host 'Restart each app. Verify: hermes hooks doctor. Codex uses skill/native-plugin enforcement without an executable trust prompt.'
