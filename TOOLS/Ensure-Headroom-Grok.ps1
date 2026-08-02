# Ensure-Headroom-Grok.ps1  (v5.2.2 - auth aware)
#
# WHY THIS WAS REWRITTEN
# ----------------------
# v5.0 unconditionally applied a durable Headroom inference wrap for Grok:
#     headroom install apply --providers manual --target grok_build
#     User env GROK_MODELS_BASE_URL -> http://127.0.0.1:8787/v1
# That BREAKS Grok CLI for every user who signs in with a Grok subscription.
#
# Headroom's Grok proxy talks to https://api.x.ai and authenticates with
# XAI_API_KEY (headroom/providers/grok/runtime.py: DEFAULT_API_URL,
# headroom/cli/wrap.py: openai_api_url="https://api.x.ai").
# A subscription / OIDC login (~/.grok/auth.json auth_mode=oidc) does NOT use
# api.x.ai - its inference endpoint is https://cli-chat-proxy.grok.com/v1.
# Headroom has no code path for that endpoint, so the wrap produces:
#     "model catalog fetch returned no models"  -> model displays as "unknown"
#     "Unauthorized (401) from http://127.0.0.1:8787/.../v1/chat/completions"
# and grok-4.5 becomes unselectable.
#
# WHAT THIS SCRIPT DOES NOW
#   session/OIDC login (no XAI_API_KEY)  -> MCP registration ONLY (safe, default)
#   XAI_API_KEY present                  -> durable wrap allowed, but only with -Wrap
#   -Repair                              -> undo a wrap applied by v5.0
#
# Headroom still helps Grok in MCP mode: headroom_compress / headroom_retrieve /
# headroom_stats are callable as tools. Only the inference proxy is incompatible.

param(
  [int]$Port = 8787,
  [switch]$SkipMcp,
  [switch]$CheckOnly,
  [switch]$Wrap,       # opt in to the durable inference wrap (needs XAI_API_KEY)
  [switch]$Repair,     # remove a previously applied wrap and unbreak Grok
  [switch]$Force       # allow -Wrap even without XAI_API_KEY (not recommended)
)

$ErrorActionPreference = 'Continue'
function Ok($m){ Write-Host "  OK  $m" -ForegroundColor Green }
function Warn($m){ Write-Host "  !!  $m" -ForegroundColor Yellow }
function Bad($m){ Write-Host "  XX  $m" -ForegroundColor Red }
function Step($m){ Write-Host "==> $m" -ForegroundColor Cyan }

$GrokEnvNames = @('GROK_MODELS_BASE_URL', 'GROK_MODEL_GROK_BUILD_BASE_URL')

function Find-HeadroomExe {
  if ($env:HEADROOM_CMD -and (Test-Path -LiteralPath $env:HEADROOM_CMD)) { return $env:HEADROOM_CMD }
  $cands = @(
    (Join-Path $env:USERPROFILE '.local\bin\headroom.exe'),
    (Join-Path $env:USERPROFILE '.local\bin\headroom.EXE')
  )
  try { $g = (Get-Command headroom -EA SilentlyContinue).Source; if ($g) { $cands = @($g) + $cands } } catch {}
  foreach ($c in $cands) {
    if ($c -and (Test-Path -LiteralPath $c)) { return (Resolve-Path -LiteralPath $c).Path }
  }
  return $null
}

function Test-HeadroomProxy([int]$P) {
  foreach ($path in @('/readyz', '/health')) {
    try {
      $r = Invoke-WebRequest -Uri ("http://127.0.0.1:{0}{1}" -f $P, $path) -UseBasicParsing -TimeoutSec 3
      if ($r.StatusCode -ge 200 -and $r.StatusCode -lt 300) { return $true }
    } catch {}
  }
  return $false
}

# ---------------------------------------------------------------------------
# Auth detection: the ONLY thing that decides whether the wrap can work.
# ---------------------------------------------------------------------------
function Get-GrokAuthMode {
  # 'apikey'  -> XAI_API_KEY set; Headroom proxy (api.x.ai) can authenticate.
  # 'session' -> OIDC / subscription login; Headroom proxy CANNOT authenticate.
  # 'none'    -> not signed in yet.
  foreach ($scope in @('Process', 'User', 'Machine')) {
    $k = [Environment]::GetEnvironmentVariable('XAI_API_KEY', $scope)
    if ($k -and $k.Trim()) { return 'apikey' }
  }
  $auth = Join-Path $env:USERPROFILE '.grok\auth.json'
  if (Test-Path -LiteralPath $auth) {
    try {
      $raw = Get-Content -LiteralPath $auth -Raw -Encoding UTF8
      if ($raw -match 'auth_mode"\s*:\s*"oidc"' -or $raw -match 'refresh_token') { return 'session' }
      return 'session'
    } catch { return 'session' }
  }
  return 'none'
}

function Get-GrokModelsOrigin {
  $cache = Join-Path $env:USERPROFILE '.grok\models_cache.json'
  if (-not (Test-Path -LiteralPath $cache)) { return $null }
  try {
    $j = Get-Content -LiteralPath $cache -Raw -Encoding UTF8 | ConvertFrom-Json
    return [pscustomobject]@{
      origin = $j.origin
      auth   = $j.auth_method
      models = @($j.models.PSObject.Properties.Name)
    }
  } catch { return $null }
}

function Get-HeadroomManifestPath { Join-Path $env:USERPROFILE '.headroom\deploy\default\manifest.json' }

function Get-HeadroomManifest {
  $manifest = Get-HeadroomManifestPath
  if (-not (Test-Path -LiteralPath $manifest)) { return $null }
  try { return Get-Content -LiteralPath $manifest -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return $null }
}

function Test-GrokDeployTargets($manifest) {
  if (-not $manifest -or -not $manifest.targets) { return $false }
  $t = @($manifest.targets | ForEach-Object { "$_".ToLowerInvariant() })
  return ($t -contains 'grok_build') -or ($t -contains 'grok')
}

function Get-GrokRoutingEnv {
  $found = @()
  foreach ($n in $GrokEnvNames) {
    foreach ($scope in @('Process', 'User', 'Machine')) {
      $v = [Environment]::GetEnvironmentVariable($n, $scope)
      if ($v -and $v.Trim()) { $found += [pscustomobject]@{ name = $n; scope = $scope; value = $v } }
    }
  }
  return $found
}

function Clear-GrokRoutingEnv {
  $cleared = 0
  foreach ($e in (Get-GrokRoutingEnv)) {
    if ($e.value -notmatch '127\.0\.0\.1|localhost') {
      Warn ("leaving non-local {0} ({1}) = {2}" -f $e.name, $e.scope, $e.value)
      continue
    }
    if ($e.scope -eq 'Machine') {
      Warn ("{0} is Machine-scoped; needs an elevated shell to clear" -f $e.name)
      continue
    }
    [Environment]::SetEnvironmentVariable($e.name, $null, $e.scope)
    Remove-Item -Path ("Env:" + $e.name) -ErrorAction SilentlyContinue
    Ok ("cleared {0} ({1})" -f $e.name, $e.scope)
    $cleared++
  }
  return $cleared
}

# ---------------------------------------------------------------------------
# PowerShell profile: strip a `function grok { ... headroom wrap grok ... }`
# override. v5.0 installs shipped one; it also clobbers grok-path-fix.ps1.
# ---------------------------------------------------------------------------
function Repair-GrokProfileFunction {
  $profiles = @(
    (Join-Path $env:USERPROFILE 'Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1'),
    (Join-Path $env:USERPROFILE 'Documents\WindowsPowerShell\profile.ps1'),
    (Join-Path $env:USERPROFILE 'Documents\PowerShell\Microsoft.PowerShell_profile.ps1'),
    (Join-Path $env:USERPROFILE 'Documents\PowerShell\profile.ps1')
  )
  foreach ($p in $profiles) {
    if (-not (Test-Path -LiteralPath $p)) { continue }
    $txt = Get-Content -LiteralPath $p -Raw -Encoding UTF8
    if ($txt -notmatch '(?ms)function\s+grok\s*\{[^}]*headroom') { continue }

    $bak = $p + '.before-headroom-repair-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.bak'
    Copy-Item -LiteralPath $p -Destination $bak -Force
    # Rename the wrapping function instead of deleting it, so nothing is lost
    # and the native `grok` (or grok-path-fix.ps1's) definition wins again.
    $new = [regex]::Replace($txt, '(?m)^(\s*)function\s+grok\s*\{', '$1function grok-headroom {')
    $enc = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($p, $new, $enc)
    Ok ("profile repaired: {0} (backup: {1})" -f $p, (Split-Path $bak -Leaf))
    Warn 'the Headroom-wrapping function is now named grok-headroom; `grok` runs natively again'
  }
}

# Older Headroom persistent deployments can leave scheduled tasks behind after
# their manifest or ensure-headroom.cmd has been removed. A task that launches
# cmd.exe /c <missing-script> still flashes a console window, so checking only
# Actions.Execute is insufficient: cmd.exe exists while its argument target does
# not. Detect both the executable and script paths carried in task arguments.
function Get-HeadroomTaskActionTargetPaths($Action) {
  $targets = @()

  $execute = [Environment]::ExpandEnvironmentVariables([string]$Action.Execute).Trim()
  if ($execute) {
    $execute = $execute.Trim([char]34, [char]39)
    if ($execute -match '(?i)(?:headroom|\.headroom).*\.(?:cmd|bat|ps1|exe)$') {
      $targets += $execute
    }
  }

  $arguments = [Environment]::ExpandEnvironmentVariables([string]$Action.Arguments)
  if ($arguments) {
    $quoted = [regex]::Matches(
      $arguments,
      '"([^"]*(?:headroom|\.headroom)[^"]*\.(?:cmd|bat|ps1|exe))"',
      [Text.RegularExpressions.RegexOptions]::IgnoreCase
    )
    foreach ($match in $quoted) {
      $targets += $match.Groups[1].Value
    }

    foreach ($token in ($arguments -split '\s+')) {
      $candidate = $token.Trim([char]34, [char]39)
      if ($candidate -match '(?i)(?:headroom|\.headroom).*\.(?:cmd|bat|ps1|exe)$') {
        $targets += $candidate
      }
    }
  }

  return @($targets | Where-Object { $_ } | Select-Object -Unique)
}

function Test-HeadroomTaskOrphaned($Task) {
  $actionText = @(
    $Task.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }
  ) -join ' '

  foreach ($action in @($Task.Actions)) {
    foreach ($target in @(Get-HeadroomTaskActionTargetPaths $action)) {
      if ([IO.Path]::IsPathRooted($target) -and -not (Test-Path -LiteralPath $target)) {
        return $true
      }
    }
  }

  $manifestPath = Get-HeadroomManifestPath
  if (
    -not (Test-Path -LiteralPath $manifestPath) -and
    $actionText -match '(?i)(?:ensure-headroom|[\\/]\.headroom[\\/]deploy[\\/]default)'
  ) {
    return $true
  }

  return $false
}

function Remove-OrphanHeadroomTasks {
  if (-not (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue)) {
    return
  }

  $tasks = @(Get-ScheduledTask -TaskName 'headroom-*' -ErrorAction SilentlyContinue)
  foreach ($t in $tasks) {
    if (-not (Test-HeadroomTaskOrphaned $t)) {
      Ok ("scheduled task still live, leaving alone: " + $t.TaskName)
      continue
    }

    $removeArgs = @{
      TaskName    = $t.TaskName
      Confirm     = $false
      ErrorAction = 'Stop'
    }
    if ($t.TaskPath) { $removeArgs.TaskPath = $t.TaskPath }

    try {
      Unregister-ScheduledTask @removeArgs
      Ok ("removed orphaned scheduled task: " + $t.TaskName)
    } catch {
      $disableArgs = @{
        TaskName    = $t.TaskName
        ErrorAction = 'Stop'
      }
      if ($t.TaskPath) { $disableArgs.TaskPath = $t.TaskPath }

      try {
        Disable-ScheduledTask @disableArgs | Out-Null
        Warn ("could not remove orphaned scheduled task, so it was disabled: " + $t.TaskName)
      } catch {
        Warn ("could not remove or disable scheduled task " + $t.TaskName + "; run this script once as Administrator.")
      }
    }
  }
}

function Register-HeadroomMcp([string]$Hr) {
  $packCommon = Join-Path $PSScriptRoot 'V5-Common.ps1'
  if (Test-Path -LiteralPath $packCommon) {
    . $packCommon
    Update-V5GrokMcpBlock -Name 'headroom' -Command $Hr -ArgList @('mcp','serve') -Startup 60 -Tool 600 -SkipIfPresent
  } else {
    Warn 'V5-Common.ps1 not beside this script; add [mcp_servers.headroom] to ~/.grok/config.toml manually'
  }
}

# ---- main -----------------------------------------------------------------
Step 'Headroom + Grok (auth aware)'
# Clean stale persistent-task remnants on every normal run. This must happen
# before Find-HeadroomExe because the executable may already have been removed.
if (-not $CheckOnly) {
  Remove-OrphanHeadroomTasks
}
$hr = Find-HeadroomExe
if (-not $hr) {
  Bad 'headroom.exe not found. Install Headroom first (AIO component "headroom", or: pip install headroom-ai[mcp]).'
  exit 2
}
Ok ("headroom = " + $hr)

$authMode = Get-GrokAuthMode
$modelInfo = Get-GrokModelsOrigin
switch ($authMode) {
  'apikey'  { Ok  'Grok auth = XAI_API_KEY (api.x.ai) - Headroom inference wrap is possible' }
  'session' { Ok  'Grok auth = subscription / OIDC session - Headroom inference wrap is NOT possible' }
  'none'    { Warn 'Grok auth = not signed in yet - treating as session (safe default)' }
}
if ($modelInfo) {
  Ok ("model catalog origin = {0} (auth_method={1}; models: {2})" -f $modelInfo.origin, $modelInfo.auth, ($modelInfo.models -join ', '))
}

$proxyUp = Test-HeadroomProxy -P $Port
if ($proxyUp) { Ok ("Headroom proxy healthy on port " + $Port) } else { Ok ("no Headroom proxy on port " + $Port + " (fine - MCP mode does not need it)") }

$routing = Get-GrokRoutingEnv
$manifest = Get-HeadroomManifest
$hasGrokTarget = Test-GrokDeployTargets $manifest
$wrapped = ($routing.Count -gt 0) -or $hasGrokTarget

if ($wrapped) {
  Warn 'Grok is currently routed through Headroom:'
  foreach ($e in $routing) { Warn ("  env {0} ({1}) = {2}" -f $e.name, $e.scope, $e.value) }
  if ($hasGrokTarget) { Warn ('  deploy manifest targets: ' + ($manifest.targets -join ', ')) }
} else {
  Ok 'Grok inference is NOT routed through Headroom (correct for a session login)'
}

# ---- repair path ----------------------------------------------------------
$needRepair = $Repair -or ($wrapped -and $authMode -ne 'apikey' -and -not $Wrap)
if ($needRepair -and -not $CheckOnly) {
  Step 'Repairing Grok routing (removing the incompatible inference wrap)'
  [void](Clear-GrokRoutingEnv)
  Repair-GrokProfileFunction
  Remove-OrphanHeadroomTasks
  if ($hasGrokTarget) {
    Warn 'Headroom deploy manifest still lists grok targets.'
    Warn ('  Remove them with:  "' + $hr + '" install remove --profile default')
    Warn ('  or edit ' + (Get-HeadroomManifestPath) + ' and drop "grok"/"grok_build" from "targets".')
    Warn '  Leaving the proxy itself alone - other tools may be using it.'
  }
  $cache = Join-Path $env:USERPROFILE '.grok\models_cache.json'
  if (Test-Path -LiteralPath $cache) {
    $ci = Get-GrokModelsOrigin
    if ($ci -and $ci.origin -match '127\.0\.0\.1|localhost') {
      Remove-Item -LiteralPath $cache -Force -ErrorAction SilentlyContinue
      Ok 'removed poisoned models_cache.json (Grok will refetch the real catalog on next start)'
    }
  }
  Ok 'repair done - start a NEW PowerShell window, then run: grok'
}

# ---- wrap path (opt in, API key only) -------------------------------------
if ($Wrap -and -not $CheckOnly) {
  if ($authMode -ne 'apikey' -and -not $Force) {
    Bad 'REFUSING -Wrap: no XAI_API_KEY. A subscription/OIDC login 401s through the Headroom proxy.'
    Bad 'Set XAI_API_KEY (api.x.ai account) and re-run, or use -Force if you really mean it.'
    exit 1
  }
  Step 'Applying durable Headroom deploy for Grok (opt in)'
  $applyArgs = @(
    'install', 'apply',
    '--preset', 'persistent-task',
    '--providers', 'manual',
    '--target', 'grok_build',
    '--scope', 'user',
    '--port', "$Port",
    '--mode', 'cache',
    '--no-telemetry'
  )
  Write-Host ("  >> headroom " + ($applyArgs -join ' '))
  & $hr @applyArgs 2>&1 | ForEach-Object { Write-Host ("     " + $_) }
  $urlV1 = "http://127.0.0.1:$Port/v1"
  foreach ($n in $GrokEnvNames) {
    [Environment]::SetEnvironmentVariable($n, $urlV1, 'User')
    Set-Item -Path ("Env:" + $n) -Value $urlV1 -EA SilentlyContinue
    Ok ("set User env $n = $urlV1")
  }
  if (-not (Test-HeadroomProxy -P $Port)) {
    & $hr install start 2>&1 | ForEach-Object { Write-Host ("     " + $_) }
    Start-Sleep -Seconds 2
  }
  if (Test-HeadroomProxy -P $Port) { Ok 'proxy healthy' } else { Bad 'proxy still down' }
}

# ---- MCP registration (always safe, always wanted) ------------------------
if (-not $SkipMcp -and -not $CheckOnly) {
  Step 'Registering Headroom as a Grok MCP server (compression tools, no inference reroute)'
  Register-HeadroomMcp -Hr $hr
}

# ---- final status ---------------------------------------------------------
$routing = Get-GrokRoutingEnv
$mcpOk = $false
$cfgPath = Join-Path $env:USERPROFILE '.grok\config.toml'
if (Test-Path -LiteralPath $cfgPath) {
  $mcpOk = ((Get-Content -LiteralPath $cfgPath -Raw -Encoding UTF8) -match '\[mcp_servers\.headroom\]')
}

Write-Host ''
Write-Host 'EXPECTED STATE (Grok subscription / OIDC login):' -ForegroundColor Cyan
Write-Host '  1. NO GROK_MODELS_BASE_URL / GROK_MODEL_GROK_BUILD_BASE_URL env var'
Write-Host '  2. NO `function grok` that calls `headroom wrap grok`'
Write-Host '  3. [mcp_servers.headroom] present in ~/.grok/config.toml'
Write-Host '  4. `grok` shows grok-4.5, not "unknown"'
Write-Host ''
Write-Host 'EXPECTED STATE (XAI_API_KEY account, opt in):' -ForegroundColor Cyan
Write-Host '  .\Ensure-Headroom-Grok.ps1 -Wrap    (adds the proxy routing back)'
Write-Host ''

$pass = $true
if ($authMode -eq 'apikey' -and $Wrap) {
  if ($routing.Count -gt 0) { Ok 'PASS wrap routing present (API key mode)' } else { Bad 'FAIL wrap requested but no routing env'; $pass = $false }
} else {
  if ($routing.Count -eq 0) { Ok 'PASS no incompatible Grok inference routing' } else { Bad 'FAIL Grok still routed through Headroom - re-run with -Repair'; $pass = $false }
}
if ($SkipMcp) { Ok 'SKIP MCP check' } elseif ($mcpOk) { Ok 'PASS Grok MCP headroom registered' } else { Warn 'WARN [mcp_servers.headroom] missing' }

if ($pass) { Ok 'RESULT: Grok + Headroom configured correctly for this account type'; exit 0 }
Bad 'RESULT: incomplete - see messages above'
exit 1
