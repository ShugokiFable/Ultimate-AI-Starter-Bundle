<#
.SYNOPSIS
  Ultimate AI Starter Bundle - All-In-One installer for skills, plugins, MCP tools, and houseCARL (MO2/Vortex).

.DESCRIPTION
  New users: run this once from the pack root.
  - Installs provider skills (Claude/Codex/Grok/Kimi/Hermes)
  - Installs bundled offline tools OR fetches GitHub latest
  - Disables Grok's inheritance of Claude Code hooks (measured 60s/turn) and
    of the Claude MCP import; wires Grok MCP natively, budgeting six configured
    servers when a plugin-provided server may also run
  - NEVER wraps Grok inference through Headroom for subscription/OIDC logins
    (that caused model "unknown" / 401). Opt-in wrap only with XAI_API_KEY.
  - Installs the full catalog by default. Use -CoreOnly for the smaller core.
  - Runs houseCARL MO2/Vortex setup
  - Wires the SOUL + AIO preamble into every selected provider's
    instruction file (Claude CLAUDE.md, Codex/Kimi/Grok AGENTS.md, Hermes
    SOUL.md) - idempotent, backup first, -SkipPreamble to opt out
  - Writes discovery state

.PARAMETER Providers
  Which AI apps to install skills for. Default: all five.

.PARAMETER Mode
  BundledFirst | OnlineLatest | BundledOnly

.PARAMETER Components
  Base components to install. V8 adds the full optional catalog unless
  -CoreOnly is passed.

.PARAMETER WorkspaceRoot
  Optional workspace to receive AGENTS.md / CLAUDE.md / _PROJECT-TEMPLATE

.PARAMETER SkipRuntimes
  Do not try winget for .NET/Python/Node

.PARAMETER SkipHouseCarlSetup
  Do not run Setup-HouseCarl.ps1 at the end

.PARAMETER SkipMcpWire
  Do not edit Grok config.toml

.PARAMETER SkipGrokMcp
  Do not wire MCP servers into Grok. Wiring is on by default. Keep Grok at six
  configured servers when an enabled plugin contributes another server: seven
  running is fine; eight wedges startup.
  See GROK-MCP-TROUBLESHOOTING.md.

.PARAMETER SkipNativePlugins
  Do not install the two bundled skills-plugins (superpowers, ponytail) as
  NATIVE plugins per provider. Native install is on by default for every
  provider with a real plugin mechanism - Grok, Hermes, Codex, Kimi, and
  Claude through its own plugin CLI; fallback everywhere is the copied
  skills.
  -SkipNativePlugins keeps the plain copied-skills behavior and skips the
  plugin-owned skill dedupe.

.EXAMPLE
  .\INSTALL-AIO.ps1
  .\INSTALL-AIO.ps1 -Providers Grok,Claude -Mode OnlineLatest
  .\INSTALL-AIO.ps1 -WorkspaceRoot "D:\Modding\AI-Workspace"
#>
[CmdletBinding()]
param(
  # Empty = auto-detect. Through v8.0.4 this defaulted to all five, and the
  # provider bootstrap then DOWNLOADED the ones that were missing: a machine
  # with only Claude finished the install carrying four vendor CLIs nobody
  # asked for. Now a plain run wires the providers you already have.
  # -AllProviders restores the install-everything behavior for a fresh box.
  # Accepts 'Grok,Claude' as one token because START-HERE.bat forwards through
  # powershell -File, which does not split arrays.
  [string[]]$Providers = @(),
  [switch]$AllProviders,
  [ValidateSet('BundledFirst','OnlineLatest','BundledOnly')]
  [string]$Mode = 'OnlineLatest',
  [string[]]$Components = @('housecarl','spooky','codebase-memory','headroom','superpowers','ponytail','codeburn','impeccable','github-mcp-server','rtk'),
  [string]$WorkspaceRoot = '',
  # The directory Skyrim Forge is installed INTO, not the folder that
  # contains it: -ForgeRoot 'S:\Apps\Skyrim Tools\Skyrim-Forge' keeps Forge
  # next to xEdit and friends. Defaults to
  # %LOCALAPPDATA%\Skyrim-Tools\Skyrim-Forge, which needs no admin rights and
  # assumes no drive letter. An existing install or a set
  # SKYRIM_FORGE_ROOT is honoured without this. Never version-stamped.
  [string]$ForgeRoot = '',
  [switch]$SkipRuntimes,
  [switch]$SkipHouseCarlSetup,
  [switch]$SkipMcpWire,
  [switch]$SkillsOnly,
  [switch]$ToolsOnly,
  # Grok MCP is wired by default again as of v7.4.2 (v7.4.1 disabled it on a
  # false premise - see docs/history/V7.4.2-CHANGELOG.md). grok-cli 1.0.4
  # wedges at eight RUNNING MCP servers; reserve one slot for a plugin-provided
  # server and keep six configured.
  [switch]$SkipGrokMcp,
  # Max MCP servers to leave configured in ~/.grok/config.toml. grok-cli 1.0.4
  # wedges at EIGHT running; an enabled Claude plugin with a .mcp.json quietly
  # supplies one, so 6 configured is the safe default. Raise to 7 only if no
  # enabled plugin contributes a server.
  [int]$GrokMcpBudget = 6,
  # Compatibility alias. V8 installs extras by default; -CoreOnly opts out.
  #   code-review-skill  obsidian-skills
  #   playwright-mcp     firecrawl-mcp    perplexity-mcp
  [switch]$WithExtras,
  [switch]$CoreOnly,
  # claude-mem is opt-in as of v8.1.0. It is the only component that is not
  # one-click: it pulls in the Bun runtime, runs a background worker daemon,
  # and needs a Claude Code restart before its tools appear. Good software,
  # but three surprises for someone who double-clicked one .bat.
  [switch]$WithClaudeMem,
  # Compatibility alias: rtk is now a default component. The bundle's narrow
  # hook handles only exact status and standalone human-facing tests; the broad
  # upstream hook remains disabled.
  [switch]$WithRtk,
  # Register an optional-key MCP server even when its keyless surface is a
  # fraction of what it charges in schema. Off by default: see
  # keyless_skip_reason in CATALOG.json for the measured numbers.
  [switch]$RegisterKeylessExtras,
  # SOUL + AIO preamble wiring (v7.5.0). On by default: appends the marked
  # preamble block (SOUL.md + 0-UNRESTRAINT-PACKS/AIO-INSTRUCTION.md) to every selected
  # provider's instruction file and copies the same SOUL.md into Hermes'
  # home. -SkipPreamble opts out; -ForcePreamble rewrites an identical block.
  [switch]$SkipPreamble,
  [switch]$ForcePreamble,
  # Portable starter settings (v7.7.3; $HOME abort fixed in v7.7.4). On by default: merge/copy
  # 1-TAILORED-PROVIDER-TREES\<Provider>\COPY-TO-PROVIDER-HOME settings
  # into each provider home. Never overwrites CLAUDE.md / AGENTS.md /
  # SOUL.md (unrestraint + preamble live there) and never copies MCP
  # command lines from a live dump. -SkipStarterSettings opts out.
  [switch]$SkipStarterSettings,
  # Hermes config.yaml wiring. Kept as an alias for skipping only Hermes
  # in the starter-settings pass. -SkipHermesConfig opts out.
  [switch]$SkipHermesConfig,
  # Native plugin install for the two bundled skills-plugins (superpowers,
  # ponytail). On by default: a real plugin install where the CLI has a
  # plugin mechanism (Grok/Hermes/Codex), detect-only for Claude, unsupported
  # for Kimi; fallback is the copied skills. -SkipNativePlugins opts out.
  [switch]$SkipNativePlugins,
  # Fresh-machine default: install missing provider CLIs from each vendor's official Windows installer.
  [switch]$SkipProviderBootstrap,
  # Default install proves each always-on MCP with initialize + tools/list.
  [switch]$SkipMcpHandshake,
  # How much of houseCARL the Hermes 'skyrim' profile registers. Empty = leave
  # it to Migrate-HermesProfiles.ps1's own default (Lean) AND do not override a
  # filter the user set by hand -- passing the switch through on every install
  # would replace their `hermes mcp configure housecarl` choice every time.
  #   Full 45 tools ~41,768 tok/turn | Lean 42 ~31,369 (-25%) | ReadOnly 27 ~17,604 (-58%)
  [ValidateSet('', 'Full', 'Lean', 'ReadOnly')]
  [string]$SkyrimToolset = '',
  # Leftovers this pack created and never removed: skills it stopped shipping,
  # and its own .bak / log files, which had no ceiling. Cleaned every install so
  # a machine converges on the current tree instead of accumulating every
  # version it has ever seen. -SkipCleanup opts out; the tool is also runnable
  # on its own (TOOLS\Clean-StaleState.ps1, dry-run by default).
  [switch]$SkipCleanup
)

if (-not $CoreOnly) {
  $Components = @($Components) + @(
    'code-review-skill', 'obsidian-skills',
    'playwright-mcp', 'firecrawl-mcp', 'perplexity-mcp'
  ) | Select-Object -Unique
}
if ($WithClaudeMem) { $Components = @($Components) + @('claude-mem') | Select-Object -Unique }
if ($WithRtk) { $Components = @($Components) + @('rtk') | Select-Object -Unique }

$ErrorActionPreference = 'Stop'
$PackRoot = $PSScriptRoot

# Durable installer diagnostics. A double-clicked .bat used to vanish on the
# first terminating error, leaving only a one-frame red message. Keep one
# timestamped transcript plus stable LAST/FAILED files under LOCALAPPDATA so a
# rerun is self-diagnosing even when the console is gone.
$installLogBase = $env:LOCALAPPDATA
if (-not $installLogBase) { $installLogBase = $env:TEMP }
if (-not $installLogBase) { $installLogBase = $PackRoot }
$installLogRoot = Join-Path $installLogBase 'Ultimate-AI-Starter-Bundle\logs'
New-Item -ItemType Directory -Force -Path $installLogRoot | Out-Null
$installLogPath = Join-Path $installLogRoot ('install-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
$installLastPath = Join-Path $installLogRoot 'INSTALL-LAST.log'
$installFailedPath = Join-Path $installLogRoot 'INSTALL-FAILED.txt'
$script:UabsTranscriptStarted = $false
try {
  Start-Transcript -LiteralPath $installLogPath -Force | Out-Null
  $script:UabsTranscriptStarted = $true
} catch {
  # Logging must never become the reason installation fails.
}

trap {
  $failure = $_
  Write-Host ''
  Write-Host '=====================================================' -ForegroundColor Red
  Write-Host ' INSTALL FAILED' -ForegroundColor Red
  Write-Host (' ' + $failure.Exception.Message) -ForegroundColor Red
  Write-Host (' Diagnostics: ' + $installFailedPath) -ForegroundColor Yellow
  Write-Host (' Transcript:  ' + $installLogPath) -ForegroundColor Yellow
  Write-Host '=====================================================' -ForegroundColor Red
  $summary = @(
    'Ultimate AI Starter Bundle installation failed.'
    ('UTC: ' + [DateTime]::UtcNow.ToString('o'))
    ('Pack: ' + $PackRoot)
    ('Error: ' + $failure.Exception.Message)
    ('Category: ' + $failure.CategoryInfo)
    ('Target: ' + $failure.TargetObject)
    ('ScriptStackTrace: ' + $failure.ScriptStackTrace)
    ('Transcript: ' + $installLogPath)
  ) -join [Environment]::NewLine
  try {
    $enc = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($installFailedPath, $summary, $enc)
  } catch {}
  if ($script:UabsTranscriptStarted) {
    try { Stop-Transcript | Out-Null } catch {}
    $script:UabsTranscriptStarted = $false
  }
  try { Copy-Item -LiteralPath $installLogPath -Destination $installLastPath -Force } catch {}
  exit 1
}

if (-not (Test-Path (Join-Path $PackRoot 'BUNDLED-TOOLS\CATALOG.json'))) {
  throw "Run INSTALL-AIO.ps1 from the pack root (folder containing BUNDLED-TOOLS)."
}
. (Join-Path $PackRoot 'TOOLS\UABS-Common.ps1')
. (Join-Path $PackRoot 'TOOLS\UABS-Mcp-Write.ps1')
$script:UabsPackRoot = $PackRoot

# ---------- Which providers this run touches ----------
# powershell -File collapses -Providers Grok,Claude into ONE string, so split
# before validating. ValidateSet cannot do that, which is why it is gone.
$script:UabsAllProviders = @('Claude','Codex','Grok','Kimi','Hermes')
$Providers = @($Providers | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
foreach ($requested in $Providers) {
  if ($script:UabsAllProviders -notcontains $requested) {
    throw ("Unknown provider '$requested'. Valid: " + ($script:UabsAllProviders -join ', '))
  }
}
$script:UabsProviderSource = 'explicit'
if ($AllProviders) {
  if ($Providers.Count) { throw 'Use -Providers or -AllProviders, not both.' }
  $Providers = $script:UabsAllProviders
  $script:UabsProviderSource = 'all (-AllProviders)'
} elseif (-not $Providers.Count) {
  $Providers = @(Get-UabsInstalledProviders -Candidates $script:UabsAllProviders)
  $script:UabsProviderSource = 'auto-detected'
  if (-not $Providers.Count) {
    # A genuinely fresh machine has nothing to detect. Bootstrapping all five
    # is the only outcome that leaves the box usable, and it is what someone
    # who ran an installer on an empty profile actually asked for.
    $Providers = $script:UabsAllProviders
    $script:UabsProviderSource = 'none detected - bootstrapping all'
  }
}
$script:UabsSkippedProviders = @($script:UabsAllProviders | Where-Object { $Providers -notcontains $_ })
Invoke-UabsLegacyStateMigration
$catalog = Get-UabsCatalog
$offline = Join-Path $PackRoot 'BUNDLED-TOOLS\offline'
$cache = Join-Path $PackRoot 'BUNDLED-TOOLS\cache'
$plugins = Join-Path $PackRoot 'BUNDLED-TOOLS\plugins'
$log = [System.Collections.Generic.List[string]]::new()
function L($m){ [void]$log.Add("$(Get-Date -Format o) $m"); Write-Host $m }

function Invoke-UabsNative {
  <#
  Run a native command without PowerShell 5.1 mangling its stderr.
  With 2>&1, every stderr line becomes an ErrorRecord: under the script-wide
  $ErrorActionPreference='Stop' that is a TERMINATING NativeCommandError, and
  even under 'Continue' each record prints as a red "RemoteException" block
  (pip's "already satisfied" / pip-version notice did exactly that).
  Fix: drop EAP to Continue locally and stringify every record before it can
  reach the host's error formatting. Returns $true when the exit code is 0.
  NOTE: the parameter must NOT be named $Args - shadowing the automatic
  variable silently breaks $LASTEXITCODE propagation (measured, PS 5.1).
  #>
  param([string]$Exe, [string[]]$ArgList)
  $prevEap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    & $Exe @ArgList 2>&1 | ForEach-Object { Write-Host ("  " + $_) }
  } finally { $ErrorActionPreference = $prevEap }
  return ($null -eq $LASTEXITCODE) -or ($LASTEXITCODE -eq 0)
}

function Remove-UabsOutdatedHermesNpmDuplicate {
  <#
  Older pack releases could install CodeBurn/Impeccable through Hermes' private
  Node prefix. Once normal npm became first on PATH, updates landed elsewhere
  and left the old package plus every dependency behind. Remove only that one
  proven shape: this run installed the exact catalog version in the active
  global root, its command resolves there, and Hermes carries a lower version.
  #>
  param([object]$Component, [string]$ActiveNpm)
  try {
    $spec = [string]$Component.npm_spec
    $expectedVersion = [string]$Component.version
    if (-not $expectedVersion -or -not $spec.EndsWith('@' + $expectedVersion)) { return }
    $packageName = Get-UabsNpxPackageBase -Arguments @($spec)
    if (-not $packageName) { return }
    $legacyPrefix = Join-Path $env:LOCALAPPDATA 'hermes\node'
    $legacyNpm = Join-Path $legacyPrefix 'npm.cmd'
    $legacyRoot = Join-Path $legacyPrefix 'node_modules'
    $legacyJson = Join-Path (Join-Path $legacyRoot $packageName) 'package.json'
    if (-not (Test-Path -LiteralPath $legacyNpm -PathType Leaf) -or
        -not (Test-Path -LiteralPath $legacyJson -PathType Leaf)) { return }

    $activeRootText = [string](& $ActiveNpm root -g | Select-Object -Last 1)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($activeRootText)) { return }
    $activeRoot = [IO.Path]::GetFullPath($activeRootText.Trim()).TrimEnd('\')
    $legacyRootFull = [IO.Path]::GetFullPath($legacyRoot).TrimEnd('\')
    if ([string]::Equals($activeRoot, $legacyRootFull, [StringComparison]::OrdinalIgnoreCase)) { return }
    $activeJson = Join-Path (Join-Path $activeRoot $packageName) 'package.json'
    if (-not (Test-Path -LiteralPath $activeJson -PathType Leaf)) { return }

    $activeVersion = [string](([IO.File]::ReadAllText($activeJson) | ConvertFrom-Json).version)
    $legacyVersion = [string](([IO.File]::ReadAllText($legacyJson) | ConvertFrom-Json).version)
    if ($activeVersion -ne $expectedVersion -or
        ([version]$legacyVersion) -ge ([version]$activeVersion)) { return }

    if (Invoke-UabsNative $legacyNpm @('--prefix', $legacyPrefix, 'uninstall', '-g', $packageName)) {
      if (Test-Path -LiteralPath $legacyJson -PathType Leaf) {
        Write-UabsWarn "$packageName $legacyVersion remains in Hermes' private Node prefix after npm uninstall"
      } else {
        Write-UabsOk "removed obsolete Hermes-private $packageName $legacyVersion (active: $activeVersion)"
      }
    } else {
      Write-UabsWarn "could not remove obsolete Hermes-private $packageName $legacyVersion; active $activeVersion is still correct"
    }
  } catch {
    Write-UabsWarn ("left Hermes-private npm duplicate alone: " + $_.Exception.Message)
  }
}

function Remove-UabsGlobalMcpRegistration {
  param([string[]]$Ids, [string[]]$FromProviders)
  $removed = @()
  $targets = Get-UabsMcpTargets
  foreach ($prov in @($FromProviders)) {
    if ($prov -eq 'Hermes') {
      $done = @(Remove-UabsMcpHermes -Ids $Ids)
    } else {
      $target = $targets[$prov]
      if (-not $target) { continue }
      if ($target.Style -eq 'json') {
        $done = @(Remove-UabsMcpJson -Path $target.Path -Section $target.Section -Ids $Ids)
      } else {
        $done = @(Remove-UabsMcpToml -Path $target.Path -Section $target.Section -Ids $Ids)
      }
      if ($target.Desktop) {
        $desktop = Get-ClaudeDesktopConfigPath
        if ($desktop) { $done += @(Remove-UabsMcpJson -Path $desktop -Section 'mcpServers' -Ids $Ids) }
      }
    }
    if ($done.Count) {
      $removed += $prov
      Write-UabsOk ("{0}: removed retired global MCP entry {1}" -f $prov, (($done | Select-Object -Unique) -join ', '))
    }
  }
  return @($removed | Select-Object -Unique)
}

function Find-UabsBunExecutable {
  $cmd = Get-Command bun -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $candidates = @(
    (Join-Path $env:USERPROFILE '.bun\bin\bun.exe'),
    (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\bun.exe')
  )
  $winget = Get-ChildItem -Path (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages\Oven-sh.Bun_*\bun-windows-*\bun.exe') `
                          -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
  if ($winget) { $candidates += $winget.FullName }
  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
  }
  return $null
}

Write-Host ""
Write-Host "=====================================================" -ForegroundColor Magenta
Write-Host " Ultimate AI Starter Bundle v8.7.15 - ALL-IN-ONE INSTALLER" -ForegroundColor Magenta
Write-Host " Mode=$Mode  Providers=$($Providers -join ',') [$script:UabsProviderSource]" -ForegroundColor Magenta
if ($script:UabsSkippedProviders.Count) {
  Write-Host (" Not installed here, so not touched: " + ($script:UabsSkippedProviders -join ', ') + "  (add them with -AllProviders)") -ForegroundColor DarkGray
}
Write-Host "=====================================================" -ForegroundColor Magenta
Write-Host ""

# ---------- Runtimes ----------
if (-not $SkipRuntimes -and -not $SkillsOnly) {
  Write-UabsStep "Runtime checks"
  $needNet9 = -not (Test-UabsDotNetRuntime 'Microsoft\.NETCore\.App 9\.')
  $needAsp9 = -not (Test-UabsDotNetRuntime 'Microsoft\.AspNetCore\.App 9\.')
  $needSdk8 = -not (Test-UabsDotNetSdk '^8\.')
  if ($needNet9 -and -not (Install-UabsWinget @('Microsoft.DotNet.Runtime.9'))) { throw '.NET 9 runtime installation failed.' } elseif (-not $needNet9) { Write-UabsOk '.NET 9 runtime' }
  if ($needAsp9 -and -not (Install-UabsWinget @('Microsoft.DotNet.AspNetCore.9'))) { throw 'ASP.NET Core 9 installation failed.' } elseif (-not $needAsp9) { Write-UabsOk 'ASP.NET Core 9' }
  if ($needSdk8 -and -not (Install-UabsWinget @('Microsoft.DotNet.SDK.8'))) { throw '.NET 8 SDK installation failed.' } elseif (-not $needSdk8) { Write-UabsOk '.NET 8 SDK' }
  if (-not (Get-Command python -EA SilentlyContinue) -and -not (Get-Command py -EA SilentlyContinue)) {
    Write-UabsWarn 'Python not found (needed for Headroom/Forge) - attempting winget'
    if (-not (Install-UabsWinget @('Python.Python.3.12'))) { throw 'Python 3.12 installation failed.' }
  } else { Write-UabsOk 'Python present' }
  if (-not (Get-Command node -EA SilentlyContinue)) {
    Write-UabsWarn 'Node not found (CodeBurn + reasoning MCPs) - attempting winget LTS'
    if (-not (Install-UabsWinget @('OpenJS.NodeJS.LTS'))) { throw 'Node LTS installation failed.' }
  } else { Write-UabsOk "Node $(node -v)" }
  if (($Components -contains 'claude-mem') -and ($Providers -contains 'Claude')) {
    $bunExe = Find-UabsBunExecutable
    if (-not $bunExe) {
      Write-UabsWarn 'Bun not found (required by claude-mem) - attempting official winget package'
      if (-not (Install-UabsWinget @('Oven-sh.Bun'))) { throw 'Bun installation failed.' }
      $bunExe = Find-UabsBunExecutable
    }
    if (-not $bunExe) { throw 'Bun installed but bun.exe did not resolve in the current installer process.' }
    $env:BUN = $bunExe
    $env:PATH = (Split-Path $bunExe -Parent) + ';' + $env:PATH
    Write-UabsOk ("Bun " + (& $bunExe --version))
  }
}

# Fresh-machine provider bootstrap. Existing commands are preserved; only missing
# CLIs use official vendor Windows installers and every command is --version tested.
if (-not $ToolsOnly -and -not $SkipProviderBootstrap) {
  $providerBootstrap = Join-Path $PackRoot 'TOOLS\Ensure-Provider-CLIs.ps1'
  if (-not (Test-Path -LiteralPath $providerBootstrap -PathType Leaf)) { throw 'Provider bootstrap script missing.' }
  & (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File $providerBootstrap -Providers ($Providers -join ',')
  if ($LASTEXITCODE -ne 0) { throw "Provider bootstrap failed with exit code $LASTEXITCODE." }
}

function Get-ComponentAssetPath {
  param($Comp)
  $name = $Comp.offline_asset
  if ($Mode -eq 'OnlineLatest') {
    # prefer cache newest matching
    if ($Comp.github) {
      try {
        $rel = Invoke-UabsGitHubLatest -Owner $Comp.github.owner -Repo $Comp.github.repo
        $asset = $null
        if ($Comp.asset_match) { $asset = Get-UabsReleaseAsset -Release $rel -Patterns @($Comp.asset_match) }
        if ($asset) {
          $dest = Join-Path $cache $asset.name
          [void](Save-UabsReleaseAsset -Asset $asset -OutFile $dest -ReuseValid)
          return $dest
        }
        if ($Comp.kind -eq 'skills-plugin') {
          $dest = Join-Path $cache "$($Comp.id)-$($rel.tag_name).zip"
          if (-not (Test-Path $dest)) {
            $zipUrl = "https://github.com/$($Comp.github.owner)/$($Comp.github.repo)/archive/refs/tags/$($rel.tag_name).zip"
            try { Save-UabsUrl -Url $zipUrl -OutFile $dest } catch { Save-UabsUrl -Url $rel.zipball_url -OutFile $dest }
          }
          return $dest
        }
      } catch { Write-UabsWarn "OnlineLatest failed for $($Comp.id): $($_.Exception.Message)" }
    }
  }
  if ($name) {
    $p = Join-Path $offline $name
    if (Test-Path $p) { return $p }
    # any cache match
    if ($Comp.asset_match) {
      foreach ($pat in $Comp.asset_match) {
        $hit = Get-ChildItem $cache,$offline -Filter $pat -File -EA SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($hit) { return $hit.FullName }
      }
    }
  }
  if ($Mode -eq 'BundledOnly') { return $null }
  # fallback online
  if ($Comp.github) {
    try {
      $rel = Invoke-UabsGitHubLatest -Owner $Comp.github.owner -Repo $Comp.github.repo
      $asset = $null
      if ($Comp.asset_match) { $asset = Get-UabsReleaseAsset -Release $rel -Patterns @($Comp.asset_match) }
      if ($asset) {
        $dest = Join-Path $cache $asset.name
        [void](Save-UabsReleaseAsset -Asset $asset -OutFile $dest -ReuseValid)
        return $dest
      }
    } catch {}
  }
  return $null
}

# ---------- Skills ----------
if (-not $ToolsOnly) {
  Write-UabsStep "Installing provider skills"
  $tailored = Join-Path $PackRoot '1-TAILORED-PROVIDER-TREES'
  foreach ($prov in $Providers) {
    $srcSkills = Join-Path $tailored "$prov\COPY-TO-SKILLS-DIRECTORY\skills"
    if (-not (Test-Path $srcSkills)) { Write-UabsBad "Missing $srcSkills"; continue }
    $providerHome = Get-UabsProviderHome -Provider $prov -Catalog $catalog
    $destSkills = Get-UabsProviderSkillsDir -Provider $prov -Catalog $catalog
    Write-Host "  $prov -> $destSkills"
    # Codex stores pack skills in ~/.agents/skills, outside CODEX_HOME. On a
    # clean machine syncing those skills therefore does not create ~/.codex,
    # but the instruction and starter-setting writers need that home.
    New-Item -ItemType Directory -Force -Path $providerHome | Out-Null

    # Codex standardized on ~/.agents/skills but still scans the old
    # $CODEX_HOME/skills root. Snapshot the old ownership ledger before the
    # sync rewrites it, then move only proven bundle copies out of that legacy
    # root after the supported root is healthy.
    $legacyCodexSkills = $null
    $legacyCodexDigests = @{}
    $codexBuiltins = @()
    if ($prov -eq 'Codex') {
      $legacyCodexSkills = Join-Path $providerHome 'skills'
      $codexBuiltins = @(Get-UabsCodexBuiltinSkillNames -CodexHome $providerHome)
      $ledgerPath = Join-Path (Get-UabsStateRoot) 'managed-skills\codex.json'
      if (Test-Path -LiteralPath $ledgerPath -PathType Leaf) {
        try {
          foreach ($entry in @(([IO.File]::ReadAllText($ledgerPath) | ConvertFrom-Json).skills)) {
            $legacyCodexDigests[[string]$entry.name] = [string]$entry.digest
          }
        } catch { Write-UabsWarn ('Codex legacy skill ledger unreadable; only current exact copies can migrate: ' + $_.Exception.Message) }
      }
    }

    Sync-UabsProviderSkills -From $srcSkills -To $destSkills -Provider $prov -ExcludeNames $codexBuiltins
    if ($legacyCodexSkills -and
        $legacyCodexSkills.TrimEnd('\') -ine $destSkills.TrimEnd('\') -and
        (Test-Path -LiteralPath $legacyCodexSkills -PathType Container)) {
      $legacyBackup = $null
      $movedLegacy = 0
      foreach ($oldSkill in @(Get-ChildItem -LiteralPath $legacyCodexSkills -Directory -Force -ErrorAction SilentlyContinue)) {
        if ($oldSkill.Name -eq '.system' -or ($oldSkill.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
        $expected = $legacyCodexDigests[$oldSkill.Name]
        if (-not $expected) {
          $currentSource = Join-Path $srcSkills $oldSkill.Name
          if (Test-Path -LiteralPath $currentSource -PathType Container) { $expected = Get-UabsTreeDigest $currentSource }
        }
        if (-not $expected) {
          # A non-pack skill may also exist in both Codex's supported and
          # deprecated roots. Move only a byte-identical legacy duplicate.
          $supportedCopy = Join-Path $destSkills $oldSkill.Name
          if (Test-Path -LiteralPath $supportedCopy -PathType Container) {
            $supportedItem = Get-Item -LiteralPath $supportedCopy -Force
            if (($supportedItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) {
              $supportedDigest = Get-UabsTreeDigest $supportedCopy
              if ((Get-UabsTreeDigest $oldSkill.FullName) -ceq $supportedDigest) { $expected = $supportedDigest }
            }
          }
        }
        if (-not $expected) { continue }
        if ((Get-UabsTreeDigest $oldSkill.FullName) -cne $expected) {
          Write-UabsWarn ('Codex legacy skill was modified; preserved: ' + $oldSkill.FullName)
          continue
        }
        if (-not $legacyBackup) {
          $legacyBackup = Join-Path (Get-UabsStateRoot) ('backups\codex-legacy-skills-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
          New-Item -ItemType Directory -Force -Path $legacyBackup | Out-Null
        }
        Move-Item -LiteralPath $oldSkill.FullName -Destination (Join-Path $legacyBackup $oldSkill.Name)
        $movedLegacy++
      }
      if ($movedLegacy) { Write-UabsOk "Codex: moved $movedLegacy legacy duplicate skill(s) to $legacyBackup" }
    }
    # provider home instructions
    $pmeta = $catalog.providers.$prov
    if ($pmeta.instructions) {
      $srcInst = Join-Path $tailored "$prov\COPY-TO-PROVIDER-HOME\$($pmeta.instruction_src)"
      if (-not (Test-Path $srcInst)) {
        $srcInst = Join-Path $tailored "$prov\COPY-TO-WORKSPACE\$($pmeta.instruction_src)"
      }
      # Claude uses CLAUDE.md
      if ($prov -eq 'Claude') {
        $srcInst = Join-Path $tailored 'Claude\COPY-TO-PROVIDER-HOME\CLAUDE.md'
        if (-not (Test-Path $srcInst)) { $srcInst = Join-Path $PackRoot 'COPY-TO-YOUR-WORKSPACE\CLAUDE.md' }
      }
      if (Test-Path $srcInst) {
        $instructionTarget = Join-Path $providerHome $pmeta.instructions
        if (Test-Path -LiteralPath $instructionTarget -PathType Leaf) {
          Write-UabsOk ("{0} existing instructions preserved; managed SOUL/AIO block refreshes later" -f $prov)
        } else {
          Copy-Item -LiteralPath $srcInst -Destination $instructionTarget
          Write-UabsOk ("{0} instructions -> {1}" -f $prov, $instructionTarget)
        }
      }
    }
    Write-UabsOk "$prov skills installed"
  }
}

# ---------- Portable starter settings (v7.7.3) ----------
# New users get Claude settings.json / Codex+Grok+Kimi config.toml /
# Hermes config.yaml without a live-machine dump. Existing homes are
# preserved. Instruction files (unrestraint / SOUL / AIO preamble) are
# not touched here.
if (-not $ToolsOnly -and -not $SkipStarterSettings) {
  $starter = Join-Path $PackRoot 'TOOLS\Install-Provider-Starter-Settings.ps1'
  if (Test-Path -LiteralPath $starter) {
    try {
      $starterArgs = @{
        PackRoot = $PackRoot
        Providers = $Providers
      }
      if ($SkipHermesConfig) { $starterArgs.SkipHermes = $true }
      & $starter @starterArgs
    } catch {
      Write-UabsWarn ('Starter settings: ' + $_.Exception.Message)
    }
  } else {
    Write-UabsWarn 'TOOLS\Install-Provider-Starter-Settings.ps1 missing from pack'
  }
}

# ---------- Native plugins: superpowers + ponytail ----------
# Installs the two bundled skills-plugins NATIVE per provider where the CLI
# has a real plugin mechanism (all mechanisms verified live on the reference
# machine):
#   Grok    grok plugin install superpowers --trust from the marketplace
#           (never a second local clone next to official_marketplace auto-
#           install - two plugins named superpowers collide on
#           systematic-debugging). ponytail has no Grok manifest and stays
#           as copied skills.
#   Hermes  hermes plugins install file:///<path> --enable from a local git
#           bridge (Hermes rejects plain paths), with
#           plugins.scan_on_install: false in config.yaml because the security
#           scanner false-positives on both plugins and --force does not
#           override it. Gateway restart ONLY if it was already running.
#   Codex   bundled superpowers staged into the local marketplace +
#           [plugins."superpowers@ultimate-bundle"] enabled = true in
#           config.toml; ponytail is detected (user's own marketplace
#           install), never reinstalled.
#   Claude  installed through Claude's own plugin CLI when it is on PATH, with
#           the marketplace name read from each plugin's own
#           .claude-plugin\marketplace.json; success is confirmed by the cache
#           directory appearing, not by an exit code. Without the CLI this
#           falls back to detect-only plus the copied skills.
#   Kimi    native plugin written to plugins\managed\<id> + a thin entry in
#           plugins\installed.json. There is no `kimi plugin` subcommand -
#           the plugin system is driven by an in-session /plugins command -
#           but the registry format is stable because Kimi re-derives every
#           record from disk on load.
# Where a plugin is native, its skill name list is computed from the bundled
# tree (never hardcoded) and the matching copies are deduped from the
# provider's skills dir - backup-first, and only when the copy's SKILL.md
# md5 matches that provider's tailored source. Comparing to canonical falsely
# labels deliberate Claude-to-Codex tailoring as a user edit.
$nativePlugins = [ordered]@{}
if (-not $ToolsOnly -and -not $SkipNativePlugins) {
  Write-UabsStep "Native plugins (superpowers + ponytail)"
  $backupRoot = Join-Path $env:LOCALAPPDATA 'Ultimate-AI-Starter-Bundle\backups'
  New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null

  function New-UabsPluginStateEntry {
    param([string]$Status = 'fallback-skills', [string]$Reason = '')
    return [ordered]@{ native = $false; status = $Status; reason = $Reason; deduped = @(); skipped_modified = @(); skipped_kept = @() }
  }

  function Invoke-UabsSkillDedupe {
    param([string]$Provider, [string]$PluginId, [string]$SkillsDir, $StateEntry)
    $names = Get-UabsPluginOwnedSkillNames -PluginRoot (Join-Path $plugins $PluginId)
    if (-not $names -or $names.Count -eq 0) {
      $StateEntry.skipped_kept = @('bundled plugin tree has no skills dir')
      return
    }
    $expectedRoot = Join-Path $tailored "$Provider\COPY-TO-SKILLS-DIRECTORY\skills"
    $res = Remove-UabsPluginOwnedSkillCopies -Provider $Provider -SkillsDir $SkillsDir -Names $names -ExpectedRoot $expectedRoot -BackupRoot $backupRoot -Log $log
    $StateEntry.deduped = @($res.removed)
    $StateEntry.skipped_modified = @($res.skipped_modified)
    $StateEntry.skipped_kept = @($res.skipped)
  }

  foreach ($prov in $Providers) {
    $providerHome = Get-UabsProviderHome -Provider $prov -Catalog $catalog
    $skillsDir = Get-UabsProviderSkillsDir -Provider $prov -Catalog $catalog
    $pstate = [ordered]@{ supported = $true; reason = ''; plugins = [ordered]@{} }
    $nativePlugins[$prov] = $pstate

    switch ($prov) {

      'Grok' {
        # ponytail ships no Grok manifest -> copied skills remain its path.
        $pstate.plugins['ponytail'] = New-UabsPluginStateEntry -Status 'fallback-skills' -Reason 'ponytail has no Grok manifest; copied skills stay'
        $spEntry = New-UabsPluginStateEntry
        $pstate.plugins['superpowers'] = $spEntry
        $grokExe = Join-Path $env:USERPROFILE '.grok\bin\grok.exe'
        if (-not (Test-Path -LiteralPath $grokExe -PathType Leaf)) {
          $gc = Get-Command grok -EA SilentlyContinue
          if ($gc) { $grokExe = $gc.Source } else { $grokExe = $null }
        }
        if (-not $grokExe) {
          $spEntry.status = 'fallback-skills'
          $spEntry.reason = 'grok CLI not found (neither ~/.grok/bin/grok.exe nor PATH); copied skills stay'
          Write-UabsWarn 'Grok CLI not found - superpowers stays as copied skills'
          break
        }
        $pluginStage = Join-Path $env:LOCALAPPDATA 'Ultimate-AI-Starter-Bundle\plugins-src\superpowers'
        Copy-UabsRobo -From (Join-Path $plugins 'superpowers') -To $pluginStage
        # Collapse marketplace + local-path clones BEFORE treating "already
        # native" as success. Two plugins named superpowers both own
        # systematic-debugging and Grok reports that as a skill error.
        $hits = @(Repair-UabsGrokDuplicatePlugins -GrokExe $grokExe -PluginName 'superpowers')
        $hits = @($hits | Where-Object { -not $_.path -or (Test-Path -LiteralPath $_.path -PathType Container) })
        if ($hits.Count -ge 1) {
          [void](Invoke-UabsNative $grokExe @('plugin','update','superpowers'))
          $hits = @(Repair-UabsGrokDuplicatePlugins -GrokExe $grokExe -PluginName 'superpowers')
          $spEntry.native = $true
          $spEntry.status = 'updated-official-cli'
          Write-UabsOk ('Grok: superpowers installed/updated (' + $hits[0].repo_key + ')')
        } else {
          Write-Host '  grok plugin install superpowers --trust'
          [void](Invoke-UabsNative $grokExe @('plugin', 'install', 'superpowers', '--trust'))
          $hits = @(Get-UabsGrokPluginList -GrokExe $grokExe | Where-Object { $_.name -eq 'superpowers' })
          if ($hits.Count -eq 0) {
            Write-Host ('  grok plugin install "' + $pluginStage + '" --trust')
            [void](Invoke-UabsNative $grokExe @('plugin', 'install', $pluginStage, '--trust'))
            $hits = @(Get-UabsGrokPluginList -GrokExe $grokExe | Where-Object { $_.name -eq 'superpowers' })
          }
          if ($hits.Count -gt 1) {
            $hits = @(Repair-UabsGrokDuplicatePlugins -GrokExe $grokExe -PluginName 'superpowers')
          }
          if ($hits.Count -ge 1) {
            $spEntry.native = $true
            $spEntry.status = 'installed'
            Write-UabsOk ('Grok: superpowers installed native (' + $hits[0].repo_key + ')')
          } else {
            $spEntry.status = 'fallback-skills'
            $spEntry.reason = 'grok plugin install did not take; copied skills stay'
            Write-UabsWarn 'Grok: superpowers native install failed - copied skills stay'
          }
        }
        if ($spEntry.native) {
          # Keep the copies. Grok chats and slash commands load
          # ~/.grok/skills/<name>/SKILL.md. Dedupe left that path missing, and
          # the TUI reports the skill as failed with no reason
          # (verification-before-completion, systematic-debugging, ...).
          Write-UabsOk 'Grok: superpowers copies stay under ~/.grok/skills (TUI loads that path; plugin path is opaque)'
        }
      }

      'Hermes' {
        $hermesExe = Join-Path $env:LOCALAPPDATA 'hermes\hermes-agent\venv\Scripts\hermes.exe'
        if (-not (Test-Path -LiteralPath $hermesExe -PathType Leaf)) {
          $hc = Get-Command hermes -EA SilentlyContinue
          if ($hc) { $hermesExe = $hc.Source } else { $hermesExe = $null }
        }
        if (-not $hermesExe) {
          foreach ($pluginId in @('superpowers', 'ponytail')) {
            $pstate.plugins[$pluginId] = New-UabsPluginStateEntry -Status 'fallback-skills' -Reason 'hermes CLI not found; copied skills stay'
          }
          Write-UabsWarn 'Hermes CLI not found - plugins stay as copied skills'
          break
        }
        $gitCmd = Get-Command git -EA SilentlyContinue
        $gatewayStatus = Get-UabsNativeOutput -Exe $hermesExe -CmdArgs @('gateway', 'status')
        $gatewayWasRunning = $gatewayStatus -match '(?i)running' -and $gatewayStatus -notmatch '(?i)not running'
        if ($gatewayWasRunning) {
          if (-not (Invoke-UabsNative $hermesExe @('gateway', 'stop'))) { throw 'Hermes gateway could not be stopped for plugin refresh' }
          Write-UabsOk 'Hermes gateway stopped for native plugin refresh'
        }
        # Hermes desktop (Hermes.exe) loads config.yaml once at startup and
        # persists ITS in-memory copy on later saves. Left running, it rewrites
        # the file from pre-install state and silently wipes every mcp_servers
        # entry this install adds (same stale-config class as the gateway).
        # Stop it alongside the gateway; relaunched at the end of the script
        # once config.yaml is final.
        $hermesDesktop = Get-Process -Name 'Hermes' -ErrorAction SilentlyContinue
        if ($hermesDesktop) {
          $script:UabsHermesDesktopExe = ($hermesDesktop | Select-Object -First 1).Path
          Write-UabsWarn ('Hermes desktop is running - closing it for the install so its stale config cannot wipe the MCP entries (it will be relaunched when done)')
          $hermesDesktop | Stop-Process -Force -ErrorAction SilentlyContinue
          Start-Sleep -Milliseconds 500
        }
        # The scanner refuses both bundled plugins (false-positive 'traversal'
        # findings; --force does not override) - disarm scan-at-install first.
        $pstate.scan_on_install_fix = Set-UabsHermesPluginScanOff -ConfigPath (Join-Path $providerHome 'config.yaml')
        if ($pstate.scan_on_install_fix -eq 'failed') { throw 'Hermes plugin scanner override failed' }
        $newInstalls = 0
        try {
          foreach ($pluginId in @('superpowers', 'ponytail')) {
          $hEntry = New-UabsPluginStateEntry
          $pstate.plugins[$pluginId] = $hEntry
          # Offline bridge: Hermes rejects plain local paths, so stage the
          # bundled tree as a local git repo and hand Hermes a file:/// URL.
          $pluginStage = Join-Path $env:LOCALAPPDATA ('Ultimate-AI-Starter-Bundle\hermes-plugin-src\' + $pluginId)
          if (-not (Test-Path -LiteralPath (Join-Path $pluginStage 'skills') -PathType Container)) {
            Copy-UabsRobo -From (Join-Path $plugins $pluginId) -To $pluginStage
          }
          if (-not (Test-Path -LiteralPath (Join-Path $pluginStage '.git') -PathType Container)) {
            if (-not $gitCmd) {
              $hEntry.status = 'fallback-skills'
              $hEntry.reason = 'git not found - cannot build the local git bridge Hermes requires; copied skills stay'
              Write-UabsWarn ('Hermes: git missing - cannot stage ' + $pluginId + ' as a git repo; copied skills stay')
              continue
            }
            [void](Invoke-UabsNative 'git' @('-C', $pluginStage, 'init'))
            [void](Invoke-UabsNative 'git' @('-C', $pluginStage, 'add', '-A'))
            if (-not (Invoke-UabsNative 'git' @('-C', $pluginStage, '-c', 'user.email=bundle@local', '-c', 'user.name=bundle', 'commit', '-m', 'bundled pin'))) {
              $hEntry.status = 'fallback-skills'
              $hEntry.reason = 'git init/commit of the offline plugin bridge failed; copied skills stay'
              Write-UabsWarn ('Hermes: git commit failed for ' + $pluginStage + ' - copied skills stay')
              continue
            }
          } else {
            # Bridge exists: refresh files from the pack and commit if the
            # bundle changed (safely corrective; a no-op when nothing changed).
            Copy-UabsRobo -From (Join-Path $plugins $pluginId) -To $pluginStage
            $dirty = Get-UabsNativeOutput -Exe 'git' -CmdArgs @('-C', $pluginStage, 'status', '--porcelain')
            if ($dirty -and $dirty.Trim()) {
              [void](Invoke-UabsNative 'git' @('-C', $pluginStage, 'add', '-A'))
              [void](Invoke-UabsNative 'git' @('-C', $pluginStage, '-c', 'user.email=bundle@local', '-c', 'user.name=bundle', 'commit', '-m', 'bundled pin refresh'))
            }
          }
          $fileUrl = 'file:///' + ($pluginStage -replace '\\', '/')
          $listed = Get-UabsNativeOutput -Exe $hermesExe -CmdArgs @('plugins', 'list')
          if ($listed -match $pluginId) {
            $updated = Invoke-UabsNative $hermesExe @('plugins','update',$pluginId)
            if (-not $updated) {
              # V7 local file URLs can point at the retired state root. Replace
              # that official registration with the stable bridge.
              [void](Invoke-UabsNative $hermesExe @('plugins','remove',$pluginId))
              $updated = Invoke-UabsNative $hermesExe @('plugins','install',$fileUrl,'--enable')
            }
            $listed = Get-UabsNativeOutput -Exe $hermesExe -CmdArgs @('plugins','list')
            if ($updated -and $listed -match $pluginId) {
              $newInstalls++
              $hEntry.native = $true
              $hEntry.status = 'updated-official-cli'
              Write-UabsOk ('Hermes: ' + $pluginId + ' installed/updated')
            } else {
              $hEntry.status = 'fallback-skills'
              $hEntry.reason = 'official Hermes update/reinstall failed; copied skills stay'
            }
          } else {
            Write-Host ('  hermes plugins install "' + $fileUrl + '" --enable')
            [void](Invoke-UabsNative $hermesExe @('plugins', 'install', $fileUrl, '--enable'))
            $listed = Get-UabsNativeOutput -Exe $hermesExe -CmdArgs @('plugins', 'list')
            if ($listed -match $pluginId) {
              $hEntry.native = $true
              $hEntry.status = 'installed'
              $newInstalls++
              Write-UabsOk ('Hermes: ' + $pluginId + ' installed native')
            } else {
              $hEntry.status = 'fallback-skills'
              $hEntry.reason = 'hermes plugins install did not take; copied skills stay'
              Write-UabsWarn ('Hermes: ' + $pluginId + ' native install failed - copied skills stay')
            }
          }
            if ($hEntry.native) {
            # Keep the copies. Hermes derives /skill-name slash commands and
            # desktop autofill from the skills dir (scan_skill_commands scans
            # SKILLS_DIR, not plugin registrations). Dedupe left that path
            # missing and /using-superpowers etc. stopped autocompleting -
            # same failure class as Grok's TUI (v7.7.5).
              Write-UabsOk ('Hermes: ' + $pluginId + ' copies stay under ' + $skillsDir + ' (slash commands load that path; plugin path is opaque)')
            }
          }
        } finally {
          # Restore both user-owned security policy and the gateway's prior
          # running state even if an official plugin command fails midway.
          $pstate.scan_on_install_restore = Restore-UabsHermesPluginScan `
            -ConfigPath (Join-Path $providerHome 'config.yaml') `
            -State $pstate.scan_on_install_fix
          if ($gatewayWasRunning) {
            if (Invoke-UabsNative $hermesExe @('gateway', 'start')) {
              Write-UabsOk 'Hermes gateway restarted (it was running before plugin refresh)'
            } else {
              Write-UabsWarn 'Hermes gateway was running before refresh but could not be restarted'
            }
          } elseif ($newInstalls -gt 0) {
            Write-UabsOk 'Hermes gateway was stopped before install - left stopped'
          }
        }
      }

      'Codex' {
        $codexCli = Get-UabsCodexCli
        if (-not $codexCli) {
          foreach ($pluginId in @('superpowers','ponytail')) {
            $pstate.plugins[$pluginId] = New-UabsPluginStateEntry -Reason 'codex CLI not found; copied skills stay'
          }
          Write-UabsWarn 'Codex CLI not found - plugins stay as copied skills'
          break
        }

        # `codex plugin list --json` refuses to answer AT ALL when any one
        # configured marketplace snapshot is unloadable -- including a
        # marketplace that has nothing to do with the plugin being checked.
        # An empty inventory then reads as "the native install failed", the
        # dedupe below never runs, and the copied skills stay in the index
        # alongside the plugin's own. Measured on this machine: a stale
        # headroom-marketplace snapshot cost 20 duplicate skill entries.
        # Codex's config.toml is the registry the CLI renders, so fall back
        # to it rather than treating an unreadable inventory as empty.
        $script:UabsCodexInventoryDegraded = $false
        function Get-UabsCodexInstalledPluginIds {
          $raw = Get-UabsNativeOutput -Exe $codexCli.Source -CmdArgs @('plugin','list','--json')
          $ids = @()
          try { $ids = @((($raw | ConvertFrom-Json).installed) | ForEach-Object { [string]$_.pluginId }) } catch { }
          if ($ids.Count) { return $ids }
          $fallback = @(Get-UabsCodexEnabledPluginIds -CodexHome $providerHome)
          if ($fallback.Count -and -not $script:UabsCodexInventoryDegraded) {
            $script:UabsCodexInventoryDegraded = $true
            Write-UabsWarn ('Codex: `plugin list --json` returned nothing usable; read ' +
              $fallback.Count + ' plugin(s) from config.toml instead. Repair it with: codex plugin marketplace upgrade <name>')
          }
          return $fallback
        }

        # Retire the manually-written V7 marketplace through Codex's official
        # lifecycle so later upgrades are owned by Codex, not stale TOML.
        $ids = @(Get-UabsCodexInstalledPluginIds)
        foreach ($legacyId in @('completeness-gate@ultimate-bundle','superpowers@ultimate-bundle')) {
          if ($ids -contains $legacyId) {
            [void](Invoke-UabsNative $codexCli.Source @('plugin','remove',$legacyId,'--json'))
            Write-UabsOk ('Codex: removed legacy manual plugin ' + $legacyId)
          }
        }
        $marketRaw = Get-UabsNativeOutput -Exe $codexCli.Source -CmdArgs @('plugin','marketplace','list','--json')
        if ($marketRaw -match '"name"\s*:\s*"ultimate-bundle"') {
          [void](Invoke-UabsNative $codexCli.Source @('plugin','marketplace','remove','ultimate-bundle','--json'))
          Write-UabsOk 'Codex: removed legacy manual ultimate-bundle marketplace'
        }
        foreach ($legacyMarketplace in @(
          (Join-Path $env:LOCALAPPDATA ('Skyrim-AI-' + 'V5\codex-marketplace')),
          (Join-Path (Get-UabsStateRoot) 'codex-marketplace')
        )) {
          $legacyManifest = Join-Path $legacyMarketplace '.claude-plugin\marketplace.json'
          if ((Test-Path -LiteralPath $legacyManifest -PathType Leaf) -and
              ([IO.File]::ReadAllText($legacyManifest) -match '"name"\s*:\s*"ultimate-bundle"')) {
            Remove-Item -LiteralPath $legacyMarketplace -Recurse -Force
            Write-UabsOk ('Codex: removed legacy owned marketplace tree ' + $legacyMarketplace)
          }
        }

        foreach ($pluginId in @('superpowers','ponytail')) {
          $entry = New-UabsPluginStateEntry
          $pstate.plugins[$pluginId] = $entry
          $srcRoot = Join-Path $plugins $pluginId
          $upstreamUrl = @{
            superpowers = 'https://github.com/obra/superpowers.git'
            ponytail    = 'https://github.com/DietrichGebert/ponytail.git'
          }[$pluginId]
          $preferOnline = ($Mode -ne 'BundledOnly') -and $upstreamUrl
          $marketName = Get-UabsClaudeMarketplaceName -PluginRoot $srcRoot
          if (-not $marketName) {
            $entry.reason = 'bundled marketplace manifest missing; copied skills stay'
            continue
          }
          $marketRaw = Get-UabsNativeOutput -Exe $codexCli.Source -CmdArgs @('plugin','marketplace','list','--json')
          $marketEntry = $null
          try {
            $marketDoc = $marketRaw | ConvertFrom-Json
            $marketEntry = @($marketDoc.marketplaces | Where-Object { $_.name -eq $marketName } | Select-Object -First 1)
            if ($marketEntry.Count) { $marketEntry = $marketEntry[0] } else { $marketEntry = $null }
          } catch { }
          # V8.0.0's offline bridge was valid but deliberately had no remote,
          # so Codex correctly disabled Marketplace -> Upgrade. Online modes
          # migrate only our owned bridge to the upstream Git marketplace;
          # BundledOnly and failed network attempts keep the offline source.
          if ($marketEntry -and $preferOnline -and
              $marketEntry.marketplaceSource.sourceType -ne 'git' -and
              $marketEntry.root -and (Test-UabsPathWithin $marketEntry.root (Get-UabsStateRoot))) {
            $oldRoot = [string]$marketEntry.root
            $oldNativeId = $pluginId + '@' + $marketName
            if (@(Get-UabsCodexInstalledPluginIds) -contains $oldNativeId) {
              [void](Invoke-UabsNative $codexCli.Source @('plugin','remove',$oldNativeId,'--json'))
            }
            $removed = Invoke-UabsNative $codexCli.Source @('plugin','marketplace','remove',$marketName,'--json')
            $migrated = $false
            if ($removed) {
              $migrated = Invoke-UabsNative $codexCli.Source @('plugin','marketplace','add',$upstreamUrl,'--json')
            }
            if ($migrated) {
              $marketRaw = Get-UabsNativeOutput -Exe $codexCli.Source -CmdArgs @('plugin','marketplace','list','--json')
              try {
                $marketDoc = $marketRaw | ConvertFrom-Json
                $marketEntry = @($marketDoc.marketplaces | Where-Object { $_.name -eq $marketName } | Select-Object -First 1)[0]
              } catch { $marketEntry = $null }
              if (Test-Path -LiteralPath $oldRoot -PathType Container) {
                Remove-Item -LiteralPath $oldRoot -Recurse -Force
              }
              Write-UabsOk ('Codex: migrated ' + $marketName + ' to its upgradeable upstream Git marketplace')
            } else {
              [void](Invoke-UabsNative $codexCli.Source @('plugin','marketplace','add',$oldRoot,'--json'))
              $marketEntry = [pscustomobject]@{ root = $oldRoot; marketplaceSource = [pscustomobject]@{ sourceType = 'local' } }
              Write-UabsWarn ('Codex: upstream marketplace unavailable for ' + $marketName + '; kept the bundled offline source')
            }
          }
          if ($marketEntry) {
            if ($marketEntry.marketplaceSource.sourceType -eq 'git') {
              [void](Invoke-UabsNative $codexCli.Source @('plugin','marketplace','upgrade',$marketName,'--json'))
            } elseif ($marketEntry.root -and (Test-UabsPathWithin $marketEntry.root (Get-UabsStateRoot)) -and
                      (Test-Path -LiteralPath (Join-Path $marketEntry.root '.git') -PathType Container)) {
              # This is the owned offline marketplace. Refresh its tracked tree
              # in place, then the official plugin remove/add below refreshes
              # Codex's cache. `marketplace upgrade` is Git-remote-only and
              # prints a false error for a local source.
              $gitExe = Get-Command git -ErrorAction SilentlyContinue
              if (-not $gitExe) { $entry.reason = 'git missing; cannot refresh local Codex marketplace'; continue }
              [void](Invoke-UabsNative $gitExe.Source @('-C',$marketEntry.root,'rm','-r','-f','--ignore-unmatch','.'))
              Copy-UabsRobo -From $srcRoot -To $marketEntry.root
              $agentMarket = Join-Path $marketEntry.root '.agents\plugins\marketplace.json'
              if (Test-Path -LiteralPath $agentMarket -PathType Leaf) {
                $agentDoc = [IO.File]::ReadAllText($agentMarket) | ConvertFrom-Json
                foreach ($agentPlugin in @($agentDoc.plugins | Where-Object { $_.name -eq $pluginId })) {
                  $agentPlugin.source = [pscustomobject]@{ source = 'url'; url = './' }
                }
                [IO.File]::WriteAllText($agentMarket, (($agentDoc | ConvertTo-Json -Depth 20) + "`n"), (New-Object Text.UTF8Encoding $false))
              }
              [void](Invoke-UabsNative $gitExe.Source @('-C',$marketEntry.root,'add','-A'))
              $dirty = Get-UabsNativeOutput -Exe $gitExe.Source -CmdArgs @('-C',$marketEntry.root,'status','--porcelain')
              if ($dirty -and $dirty.Trim()) {
                [void](Invoke-UabsNative $gitExe.Source @('-C',$marketEntry.root,'-c','user.email=bundle@local','-c','user.name=bundle','commit','-m','bundled plugin pin refresh'))
              }
              Write-UabsOk ('Codex: refreshed owned local marketplace ' + $marketName)
            } else {
              Write-UabsWarn ('Codex: marketplace ' + $marketName + ' is local but not bundle-owned; preserved without upgrade')
            }
          } else {
            # Codex installs marketplace entries by Git-cloning their source,
            # even when the marketplace itself was added from a local path.
            # Release ZIPs contain no .git directory, so build a small owned
            # local repo and make the Agent Plugins manifest point at itself.
            if ($preferOnline -and (Invoke-UabsNative $codexCli.Source @('plugin','marketplace','add',$upstreamUrl,'--json'))) {
              Write-UabsOk ('Codex: added upgradeable upstream marketplace ' + $marketName)
            } else {
            $gitExe = Get-Command git -ErrorAction SilentlyContinue
            if (-not $gitExe) {
              $entry.reason = 'git missing; official Codex plugin install needs a Git source; copied skills stay'
              continue
            }
            $codexSource = Join-Path (Get-UabsStateRoot) ('codex-plugin-src\' + $pluginId)
            if (Test-Path -LiteralPath $codexSource -PathType Container) {
              Remove-Item -LiteralPath $codexSource -Recurse -Force
            }
            Copy-UabsRobo -From $srcRoot -To $codexSource
            $agentMarket = Join-Path $codexSource '.agents\plugins\marketplace.json'
            if (Test-Path -LiteralPath $agentMarket -PathType Leaf) {
              $agentDoc = [IO.File]::ReadAllText($agentMarket) | ConvertFrom-Json
              foreach ($agentPlugin in @($agentDoc.plugins | Where-Object { $_.name -eq $pluginId })) {
                $agentPlugin.source = [pscustomobject]@{ source = 'url'; url = './' }
              }
              [IO.File]::WriteAllText($agentMarket, (($agentDoc | ConvertTo-Json -Depth 20) + "`n"), (New-Object Text.UTF8Encoding $false))
            }
            [void](Invoke-UabsNative $gitExe.Source @('-C',$codexSource,'init'))
            [void](Invoke-UabsNative $gitExe.Source @('-C',$codexSource,'add','-A'))
            if (-not (Invoke-UabsNative $gitExe.Source @('-C',$codexSource,'-c','user.email=bundle@local','-c','user.name=bundle','commit','-m','bundled plugin pin'))) {
              $entry.reason = 'failed to commit the local Codex plugin source; copied skills stay'
              continue
            }
            if (-not (Invoke-UabsNative $codexCli.Source @('plugin','marketplace','add',$codexSource,'--json'))) {
              $entry.reason = 'official marketplace add failed; copied skills stay'
              continue
            }
            }
          }
          $nativeId = $pluginId + '@' + $marketName
          $ids = @(Get-UabsCodexInstalledPluginIds)
          if ($ids -contains $nativeId) {
            [void](Invoke-UabsNative $codexCli.Source @('plugin','remove',$nativeId,'--json'))
          }
          if (Invoke-UabsNative $codexCli.Source @('plugin','add',$nativeId,'--json')) {
            $ids = @(Get-UabsCodexInstalledPluginIds)
          }
          if ($ids -contains $nativeId) {
            $entry.native = $true
            $entry.status = 'installed-official-cli'
            Write-UabsOk ('Codex: installed/updated through official CLI: ' + $nativeId)
            Invoke-UabsSkillDedupe -Provider 'Codex' -PluginId $pluginId -SkillsDir $skillsDir -StateEntry $entry
          } else {
            $entry.status = 'fallback-skills'
            $entry.reason = 'official plugin add did not appear in inventory; copied skills stay'
            Write-UabsWarn ('Codex: ' + $pluginId + ' native install failed - copied skills stay')
          }
        }

        # Codex also ships skills of its OWN (<CodexHome>\skills\.system), and
        # a canonical skill sharing one of those names is indexed twice on Codex
        # alone. Same waste as a plugin-owned duplicate, different owner, so it
        # reuses the same verified remover and backup. A modified copy is moved
        # too: keeping a second definition under a provider-owned name is never
        # a usable customization, only a shadow/duplicate. The backup preserves
        # its exact bytes for manual recovery.
        $expectedSkills = Join-Path $tailored 'Codex\COPY-TO-SKILLS-DIRECTORY\skills'
        $builtins = @(Get-UabsCodexBuiltinSkillNames -CodexHome $providerHome | Where-Object {
          Test-Path -LiteralPath (Join-Path $expectedSkills $_) -PathType Container
        })
        if ($builtins.Count) {
          $pstate.codex_builtin_deduped = @($builtins)
          $bres = Remove-UabsPluginOwnedSkillCopies -Provider 'Codex' -SkillsDir $skillsDir `
                    -Names $builtins -ExpectedRoot $expectedSkills -BackupRoot $backupRoot -Log $log -BackupModified
          if (@($bres.removed).Count) {
            Write-UabsOk ('Codex: removed ' + @($bres.removed).Count +
              ' copy/copies of a skill Codex ships itself: ' + (@($bres.removed) -join ', '))
          }
        }
      }

      'Claude' {
        # Native install via Claude's own plugin CLI when it is on PATH.
        #
        # Both bundled plugins already ship a Claude marketplace of their own
        # (BUNDLED-TOOLS\plugins\<id>\.claude-plugin\marketplace.json, each
        # with source "./"), so the marketplace name comes from that file
        # rather than a hardcoded string - superpowers publishes itself as
        # 'superpowers-dev', ponytail as 'ponytail'.
        #
        # What this deliberately does NOT do: hand-write
        # plugins\cache\<marketplace>\<plugin> plus the matching
        # .install-manifests entry. That manifest is a per-file SHA256
        # integrity map, and forging one means reimplementing Claude Code's
        # own verification against a format we cannot test here. Kimi's
        # registry was safe to write because the shipped CLI re-derives every
        # record from disk on load; this one is not. Without the CLI the
        # copied skills stay, which is a working fallback.
        $claudeCli = Get-Command claude -ErrorAction SilentlyContinue
        foreach ($pluginId in @('superpowers', 'ponytail')) {
          $cEntry = New-UabsPluginStateEntry
          $pstate.plugins[$pluginId] = $cEntry
          $srcRoot = Join-Path $plugins $pluginId
          $mkName = Get-UabsClaudeMarketplaceName -PluginRoot $srcRoot
          $cacheHit = $false
          if ($mkName) {
            $cachePath = Join-Path $providerHome ('plugins\cache\' + $mkName + '\' + $pluginId)
            $cacheHit = Test-Path -LiteralPath $cachePath -PathType Container
          }
          if ($cacheHit) {
            $updatedClaude = $false
            if ($claudeCli) {
              [void](Invoke-UabsNative $claudeCli.Source @('plugin','marketplace','update',$mkName))
              $updatedClaude = Invoke-UabsNative $claudeCli.Source @('plugin','update',($pluginId + '@' + $mkName),'--scope','user','--yes')
            }
            $cEntry.native = $true
            $cEntry.status = if ($updatedClaude) { 'updated-official-cli' } else { 'already-native' }
            Write-UabsOk ('Claude: ' + $pluginId + ' native (' + $mkName + ') - deduping its copied skills')
            Invoke-UabsSkillDedupe -Provider 'Claude' -PluginId $pluginId -SkillsDir $skillsDir -StateEntry $cEntry
            continue
          }
          if (-not $mkName) {
            $cEntry.status = 'fallback-skills'
            $cEntry.reason = 'bundled tree has no .claude-plugin\marketplace.json'
            Write-UabsWarn ('Claude: ' + $pluginId + ' has no Claude marketplace in the bundle - copied skills stay')
            continue
          }
          if (-not $claudeCli) {
            $cEntry.status = 'fallback-skills'
            $cEntry.reason = 'claude CLI not on PATH; copied skills stay'
            Write-UabsWarn ('Claude: ' + $pluginId + ' not native and no claude CLI on PATH - copied skills stay. To wire it natively:')
            Write-Host ('    claude plugin marketplace add "' + $srcRoot + '"')
            Write-Host ('    claude plugin install ' + $pluginId + '@' + $mkName + ' --scope user')
            continue
          }
          try {
            $prevEap=$ErrorActionPreference; $ErrorActionPreference='Continue'
            & claude plugin marketplace add "$srcRoot" 2>&1 | Out-Null
            & claude plugin install ("$pluginId@$mkName") --scope user 2>&1 | Out-Null
            $ErrorActionPreference=$prevEap
            $cachePath = Join-Path $providerHome ('plugins\cache\' + $mkName + '\' + $pluginId)
            if (Test-Path -LiteralPath $cachePath -PathType Container) {
              $cEntry.native = $true
              $cEntry.status = 'installed'
              Write-UabsOk ('Claude: native plugin installed - ' + $pluginId + '@' + $mkName)
              Invoke-UabsSkillDedupe -Provider 'Claude' -PluginId $pluginId -SkillsDir $skillsDir -StateEntry $cEntry
            } else {
              # The CLI returned without producing a cache entry. Do not
              # report success on an exit code alone - the cache directory is
              # the only proof Claude actually loaded it.
              $cEntry.status = 'failed'
              $cEntry.reason = 'claude plugin install left no plugins\cache entry'
              Write-UabsWarn ('Claude: ' + $pluginId + ' install did not take - copied skills stay')
            }
          } catch {
            $cEntry.status = 'failed'
            $cEntry.reason = $_.Exception.Message
            Write-UabsWarn ('Claude: ' + $pluginId + ' install failed (' + $_.Exception.Message + ') - copied skills stay')
          }
        }
        # Retire the old UNREGISTERED plugins\uabs-bundled\<id> drop - dead
        # weight Claude never loaded. Move to the backup dir, never delete.
        $moved = @()
        foreach ($pluginId in @('superpowers', 'ponytail')) {
          $dead = Join-Path $providerHome ('plugins\uabs-bundled\' + $pluginId)
          if (Test-Path -LiteralPath $dead -PathType Container) {
            $mdest = Join-Path $backupRoot ('uabs-bundled-cleanup-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '\' + $pluginId)
            Copy-UabsRobo -From $dead -To $mdest
            Remove-Item -LiteralPath $dead -Recurse -Force
            $moved += $mdest
            Write-UabsOk ('Claude: moved dead drop ' + $dead + ' -> ' + $mdest)
          }
        }
        $pstate.v5_bundled_moved = $moved
      }

      'Kimi' {
        # Kimi DOES have a native plugin system. Earlier builds of this
        # installer checked for a `kimi plugin` subcommand, did not find one
        # (correctly - there is none), and concluded Kimi had no plugins at
        # all. It is driven by the in-session `/plugins` slash command, whose
        # install path writes <home>\plugins\managed\<id> plus a thin entry
        # in <home>\plugins\installed.json. Prompt mode cannot stand in for
        # the slash command (it requires a login first), so the registry is
        # written directly - safe because Kimi re-parses each plugin's
        # manifest from disk on load rather than trusting the stored record.
        #
        # This is the fix for "Kimi has the brain but ignores my addons": the
        # bundled adapter declares sessionStart.skill = using-superpowers, so
        # Superpowers bootstraps itself on every Kimi session instead of
        # sitting inert as copied skill files.
        $pstate.supported = $true
        foreach ($pluginId in @('superpowers', 'ponytail')) {
          $kEntry = New-UabsPluginStateEntry
          $pstate.plugins[$pluginId] = $kEntry
          $src = Join-Path (Join-Path $PackRoot 'BUNDLED-TOOLS\plugins') $pluginId
          $manifestDir = Join-Path $src '.kimi-plugin\plugin.json'
          $manifestRoot = Join-Path $src 'plugin.json'
          if (-not (Test-Path -LiteralPath $manifestDir) -and
              -not (Test-Path -LiteralPath $manifestRoot)) {
            # Ponytail ships no Kimi adapter today; that is not a failure,
            # its copied skills remain the delivery path.
            $kEntry.status = 'unsupported'
            $kEntry.reason = 'no Kimi plugin manifest in the bundled tree'
            Write-UabsOk ('Kimi: ' + $pluginId + ' has no Kimi adapter - copied skills stay')
            continue
          }
          $kr = Install-UabsKimiPlugin -KimiHome $providerHome -PluginId $pluginId -SourceRoot $src
          if ($kr.ok) {
            $kEntry.status = 'installed'
            $kEntry.native = $true
            $kEntry.root = $kr.root
            Write-UabsOk ('Kimi: native plugin installed - ' + $pluginId + ' (' + $kr.root + ')')
            Invoke-UabsSkillDedupe -Provider 'Kimi' -PluginId $pluginId -SkillsDir $skillsDir -StateEntry $kEntry
          } else {
            $kEntry.status = 'failed'
            $kEntry.reason = $kr.reason
            Write-UabsWarn ('Kimi: ' + $pluginId + ' native install failed (' + $kr.reason + ') - copied skills stay')
          }
        }
      }
    }
  }
}

# -SkipNativePlugins means "do not install, update, remove, or reconfigure a
# plugin". It must not mean "pretend already-enabled plugins own no skills".
# A skills-only sync recreates canonical copies first; reconcile those copies
# against the provider's existing registry without invoking any plugin CLI.
if (-not $ToolsOnly -and $SkipNativePlugins) {
  $backupRoot = Join-Path $env:LOCALAPPDATA 'Ultimate-AI-Starter-Bundle\backups'
  New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
  foreach ($prov in @($Providers | Where-Object { $_ -in @('Claude', 'Codex') })) {
    $providerHome = Get-UabsProviderHome -Provider $prov -Catalog $catalog
    $skillsDir = Get-UabsProviderSkillsDir -Provider $prov -Catalog $catalog
    $enabledIds = @()
    if ($prov -eq 'Codex') {
      $enabledIds = @(Get-UabsCodexEnabledPluginIds -CodexHome $providerHome)
    } else {
      $settingsPath = Join-Path $providerHome 'settings.json'
      if (Test-Path -LiteralPath $settingsPath -PathType Leaf) {
        try {
          $settings = [IO.File]::ReadAllText($settingsPath) | ConvertFrom-Json
          if ($settings.enabledPlugins) {
            $enabledIds = @($settings.enabledPlugins.PSObject.Properties |
              Where-Object { $_.Value -eq $true } | ForEach-Object { [string]$_.Name })
          }
        } catch { Write-UabsWarn 'Claude enabled-plugin registry is unreadable; copied skills were kept.' }
      }
    }

    $pstate = [ordered]@{ supported = $true; reason = 'plugin lifecycle skipped; existing ownership reconciled read-only'; plugins = [ordered]@{} }
    foreach ($pluginId in @('superpowers', 'ponytail')) {
      $srcRoot = Join-Path $plugins $pluginId
      $marketName = Get-UabsClaudeMarketplaceName -PluginRoot $srcRoot
      $nativeId = if ($marketName) { $pluginId + '@' + $marketName } else { '' }
      $isNative = $nativeId -and ($enabledIds -contains $nativeId)
      if ($isNative -and $prov -eq 'Claude') {
        $isNative = Test-Path -LiteralPath (Join-Path $providerHome ('plugins\cache\' + $marketName + '\' + $pluginId)) -PathType Container
      }
      $entry = [ordered]@{
        native = [bool]$isNative
        status = $(if ($isNative) { 'detected-existing' } else { 'fallback-skills' })
        reason = $(if ($isNative) { 'left installed plugin unchanged' } else { 'no enabled, reachable native plugin detected' })
        deduped = @(); skipped_modified = @(); skipped_kept = @()
      }
      $pstate.plugins[$pluginId] = $entry
      if (-not $isNative) { continue }
      $names = @(Get-UabsPluginOwnedSkillNames -PluginRoot $srcRoot)
      $expectedRoot = Join-Path $tailored "$prov\COPY-TO-SKILLS-DIRECTORY\skills"
      $res = Remove-UabsPluginOwnedSkillCopies -Provider $prov -SkillsDir $skillsDir `
               -Names $names -ExpectedRoot $expectedRoot -BackupRoot $backupRoot -Log $log
      $entry.deduped = @($res.removed)
      $entry.skipped_modified = @($res.skipped_modified)
      $entry.skipped_kept = @($res.skipped)
      Write-UabsOk ("${prov}: existing $nativeId left unchanged; reconciled " + @($res.removed).Count + ' copied skill(s)')
    }
    $nativePlugins[$prov] = $pstate
  }
}

# ---------- AI preamble: SOUL + AIO for every agent (v7.5.0) ----------
# Wires the same preamble into every selected provider so a fresh machine
# behaves like the operator's own setup. Idempotent: re-running replaces the
# marked block instead of stacking copies; every write gets a .bak first.
if (-not $ToolsOnly -and -not $SkipPreamble) {
  Write-UabsStep "SOUL + AIO preamble wiring"
  $preDir = Join-Path $PackRoot '3-PREAMBLES'
  # One soul source for every provider. Until v7.6.2 there were two files -
  # SOUL.md opened with 'You are Hermes Agent' and SOUL-UNIVERSAL.md was the
  # de-branded copy. v7.6.0 genericised SOUL.md itself (a provider identity
  # injected into four other providers is what made Kimi refuse its own
  # unrestraint block), which left the two files identical. Keeping a second
  # copy only invites them to drift apart again.
  $soulF = Join-Path $preDir 'SOUL.md'
  $aioF  = Join-Path $PackRoot '0-UNRESTRAINT-PACKS/AIO-INSTRUCTION.md'
  foreach ($prov in $Providers) {
    if ($prov -eq 'Hermes') {
      # Hermes reads SOUL.md from its home. Use the same marked SOUL + AIO
      # writer as every other provider; the old raw-copy branch reset Hermes
      # to the short base soul and skipped the operating contract entirely.
      $hhome = Get-UabsProviderHome -Provider Hermes -Catalog $catalog
      $hSoul = Join-Path $hhome 'SOUL.md'
      Install-UabsPreambleBlock -Path $hSoul -SoulFile $soulF -AioFile $aioF -Force:$ForcePreamble
      continue
    }
    $pmeta = $catalog.providers.$prov
    $instName = $pmeta.instructions
    if (-not $instName) { $instName = 'AGENTS.md' }
    $target = Join-Path (Get-UabsProviderHome -Provider $prov -Catalog $catalog) $instName
    if (-not (Test-Path -LiteralPath $soulF) -or -not (Test-Path -LiteralPath $aioF)) {
      Write-UabsWarn ("$prov preamble skipped: 3-PREAMBLES or 0-UNRESTRAINT-PACKS/AIO-INSTRUCTION.md missing")
      continue
    }
    try {
      Install-UabsPreambleBlock -Path $target -SoulFile $soulF -AioFile $aioF -Force:$ForcePreamble
    } catch {
      Write-UabsWarn ("$prov preamble failed: " + $_.Exception.Message)
    }
  }
}

# ---------- Hermes config.yaml ----------
# v7.7.3: wholesale replace of a live Hermes YAML is gone. That used to
# stamp one operator's MCP paths onto every install. New Hermes homes get
# the portable starter above; existing homes keep their YAML. MCP and
# completeness-gate hooks are still wired later in this script.

# ---------- Workspace ----------
if ($WorkspaceRoot) {
  Write-UabsStep "Workspace files -> $WorkspaceRoot"
  New-Item -ItemType Directory -Force -Path $WorkspaceRoot | Out-Null
  $ws = Join-Path $PackRoot 'COPY-TO-YOUR-WORKSPACE'
  Copy-Item (Join-Path $ws 'AGENTS.md') (Join-Path $WorkspaceRoot 'AGENTS.md') -Force -EA SilentlyContinue
  Copy-Item (Join-Path $ws 'CLAUDE.md') (Join-Path $WorkspaceRoot 'CLAUDE.md') -Force -EA SilentlyContinue
  $tpl = Join-Path $ws '_PROJECT-TEMPLATE'
  if (Test-Path $tpl) { Copy-UabsRobo -From $tpl -To (Join-Path $WorkspaceRoot '_PROJECT-TEMPLATE') }
  Write-UabsOk "Workspace template copied"
}

# ---------- Tools ----------
$installed = [ordered]@{}
if (-not $SkillsOnly) {
  foreach ($id in $Components) {
    $comp = $catalog.components | Where-Object { $_.id -eq $id } | Select-Object -First 1
    if (-not $comp) { Write-UabsWarn "skip unknown $id"; continue }
    Write-UabsStep "Component: $($comp.name) [$id]"

    switch ($comp.install) {
      'manual-user-product' {
        Write-UabsWarn $comp.note
        $installed[$id] = @{ status='manual'; note=$comp.note }
      }
      'npx-or-npm' {
        $npm = Get-Command npm -EA SilentlyContinue
        if ($npm) {
          try {
            if ($comp.npm_integrity) {
              $reported = (& $npm.Source view $comp.npm_spec dist.integrity --json 2>$null | Out-String).Trim()
              if ($LASTEXITCODE -ne 0 -or -not $reported) { throw "INTEGRITY: npm could not verify $($comp.npm_spec)" }
              $actualIntegrity = [string]($reported | ConvertFrom-Json)
              if ($actualIntegrity -cne [string]$comp.npm_integrity) {
                throw "INTEGRITY: $($comp.npm_spec) registry integrity changed"
              }
            }
            $npmArgs = @('install', '-g')
            if ($comp.npm_args) { $npmArgs += @($comp.npm_args) }
            $npmArgs += $comp.npm_spec
            if (Invoke-UabsNative $npm.Source $npmArgs) {
              $installed[$id] = @{ status='npm-global'; spec=$comp.npm_spec; integrity=$comp.npm_integrity; args=@($comp.npm_args) }
              Write-UabsOk "npm -g $($comp.npm_spec)"
              Remove-UabsOutdatedHermesNpmDuplicate -Component $comp -ActiveNpm $npm.Source
            } else { throw "npm exited with code $LASTEXITCODE" }
          } catch {
            if ($_.Exception.Message -like 'INTEGRITY:*') {
              Write-UabsBad $_.Exception.Message
              $installed[$id] = @{ status='blocked-integrity'; spec=$comp.npm_spec }
            } else {
              Write-UabsWarn "npm global failed - users can run: npx $($comp.npm_spec)"
              $installed[$id] = @{ status='npx-fallback' }
            }
          }
        } else {
          Write-UabsWarn "Node/npm missing - $($comp.name) can run through its pinned npx package after Node is installed"
          $installed[$id] = @{ status='skipped-no-node' }
        }
      }
      'pip-or-wheel' {
              <#
              Prefer a python that actually has pip. The Hermes desktop exports its
              own venv python on PATH first (no pip), which used to kill this step
              instantly. Try 'python', then 'py -3', then 'python3', and strip
              PYTHONPATH so pip does not see a venv's site-packages.
              #>
              $py = $null
              foreach ($c in @('python', 'py', 'python3')) {
                if (Get-Command $c -EA SilentlyContinue) {
                  $probe = if ($c -eq 'py') { @('-3', '-m', 'pip', '--version') } else { @('-m', 'pip', '--version') }
                  try { & $c @probe *> $null; if ($LASTEXITCODE -ne 0) { continue } } catch { continue }
                  # A venv interpreter cannot --user install (user site-packages
                  # are invisible inside a virtualenv), and shells whose PATH
                  # puts a venv first used to fail the whole component here.
                  $kind = ''
                  try { $kind = (& $c -c "import sys; print('venv' if sys.prefix != sys.base_prefix else 'base')").Trim() } catch { }
                  if ($kind -eq 'base' -or $c -eq 'py') { $py = $c; break }
                }
              }
              $uv = Get-Command uv -ErrorAction SilentlyContinue
              if (-not $py -and -not $uv) {
                Write-UabsBad 'No base Python with pip or uv found - install Python 3.12 and re-run'
                $installed[$id] = @{ status = 'failed' }
                continue
              }
              $asset = Get-ComponentAssetPath -Comp $comp
              $ok = $false
              $hrInstalled = $null
              $installMethod = 'pip'
              if ($uv) {
                # Prefer uv's isolated tool environment. A pip --user install
                # can succeed into a Scripts directory that is not on PATH,
                # leaving an older ~/.local/bin/headroom.exe active.
                $activeHeadroom = Get-Command headroom -ErrorAction SilentlyContinue
                if ($activeHeadroom -and $activeHeadroom.Source) {
                  [void](Stop-UabsProcessUsingExecutable $activeHeadroom.Source)
                }
                $uvSpec = if ($asset -and $asset.EndsWith('.whl')) { ("{0}[mcp]" -f $asset) } else { $comp.pip_spec }
                $ok = Invoke-UabsNative $uv.Source @('tool','install','--force',$uvSpec)
                if ($ok) {
                  $installMethod = 'uv-tool'
                  $uvBin = @(& $uv.Source tool dir --bin 2>$null | Where-Object { $_ } | Select-Object -Last 1)
                  if ($uvBin.Count) {
                    $candidate = Join-Path ([string]$uvBin[0]) 'headroom.exe'
                    if (Test-Path -LiteralPath $candidate -PathType Leaf) { $hrInstalled = $candidate }
                  }
                  Refresh-ProcessPath
                }
              }
              if (-not $ok -and $asset -and $asset.EndsWith('.whl') -and $py) {
                Write-Host "  pip install $asset"
                $env:PYTHONPATH = ''
                $wheelSpec = ("{0}[mcp]" -f $asset)
                # Invoke-UabsNative keeps pip's stderr ("already satisfied", the
                # pip-version notice) from surfacing as a NativeCommandError.
                if ($py -eq 'py') { $ok = Invoke-UabsNative 'py' (@('-3','-m','pip','install','--user',$wheelSpec)) }
                else { $ok = Invoke-UabsNative $py @('-m','pip','install','--user',$wheelSpec) }
              }
              if (-not $ok -and $py) {
                $spec = $comp.pip_spec
                $env:PYTHONPATH = ''
                if ($py -eq 'py') { $ok = Invoke-UabsNative 'py' (@('-3','-m','pip','install','--user',$spec)) }
                else { $ok = Invoke-UabsNative $py @('-m','pip','install','--user',$spec) }
              }
              if ($ok -and -not $hrInstalled -and $py) {
                $scriptsProbe = "import os,sysconfig; print(os.path.join(sysconfig.get_path('scripts', scheme='nt_user'), 'headroom.exe'))"
                $probeArgs = if ($py -eq 'py') { @('-3','-c',$scriptsProbe) } else { @('-c',$scriptsProbe) }
                $candidate = @(& $py @probeArgs 2>$null | Where-Object { $_ } | Select-Object -Last 1)
                if ($candidate.Count -and (Test-Path -LiteralPath $candidate[0] -PathType Leaf)) { $hrInstalled = [string]$candidate[0] }
              }
        if ($ok) {
          $hr = $hrInstalled
          if (-not $hr) { try { $hr = (Get-Command headroom -EA SilentlyContinue).Source } catch {} }
          if ($hr) { Set-UabsUserEnv 'HEADROOM_CMD' $hr }
          $installed[$id] = @{ status=$installMethod; headroom=$hr }
          Write-UabsOk 'Headroom installed'
        } else {
          Write-UabsBad 'Headroom install failed (need Python)'
          $installed[$id] = @{ status='failed' }
        }
      }
      'skills-copy' {
        # The plugin tree is now installed NATIVE per provider by the "Native
        # plugins" section above (Grok/Hermes/Codex real installs, Claude
        # detect-only, Kimi unsupported). The old unregistered
        # plugins\uabs-bundled\<id> drop for Claude was dead weight - Claude
        # never loaded it - so it is gone; the native section moves any
        # existing drop to the backup dir instead of deleting it.
        $installed[$id] = @{ status='native-or-skills' }
        Write-UabsOk "$id handled by the native-plugin section (fallback: copied skills)"
      }
      'zip-extract' {
        $asset = Get-ComponentAssetPath -Comp $comp
        if (-not $asset) {
          Write-UabsBad "No asset for $id - run TOOLS\Update-From-GitHub.ps1 -$id or check network"
          $installed[$id] = @{ status='missing-asset' }
          continue
        }
        $target = Expand-UabsEnvPath $comp.target_dir
        $stage = Join-Path $env:TEMP "uabs-extract-$id-$(Get-Random)"
        New-Item -ItemType Directory -Force -Path $stage | Out-Null
        try {
          Expand-UabsZip -Zip $asset -Dest $stage
          $rootExtract = Resolve-UabsSingleRoot $stage
          # houseCARL zip layout: may contain housecarl\server or server
          if ($id -eq 'housecarl') {
            $existingMcp = $env:HOUSECARL_MCP
            if ($existingMcp -and (Test-Path $existingMcp) -and -not (Test-UabsPathWithin $existingMcp $target)) {
              $existingRoot = if ($env:HOUSECARL_ROOT -and (Test-Path $env:HOUSECARL_ROOT)) { $env:HOUSECARL_ROOT } else { Split-Path (Split-Path $existingMcp -Parent) -Parent }
              Set-UabsUserEnv 'HOUSECARL_MCP' $existingMcp
              Set-UabsUserEnv 'HOUSECARL_ROOT' $existingRoot
              $installed[$id] = @{ status='kept-external'; mcp=$existingMcp; root=$existingRoot }
              Write-UabsOk ("houseCARL kept external user install: " + $existingMcp)
            }
            else {
              $mcp = Find-UabsFileUnder $rootExtract 'housecarl-mcp.exe' 8
              if (-not $mcp) { throw "housecarl-mcp.exe not in zip" }
              $serverDir = Split-Path $mcp -Parent
              $productRoot = Split-Path $serverDir -Parent
              # Install to LOCALAPPDATA\houseCARL
              New-Item -ItemType Directory -Force -Path $target | Out-Null
              Copy-UabsRoboSafe -From $productRoot -To $target -CriticalFiles @('server\housecarl-mcp.exe')
              # If setup exe present at outer folder
              $setup = Find-UabsFileUnder $rootExtract 'houseCARL-Setup.exe' 4
              if ($setup) {
                Copy-Item $setup (Join-Path $target 'houseCARL-Setup.exe') -Force
              }
              $mcpFinal = Join-Path $target 'server\housecarl-mcp.exe'
              if (-not (Test-Path $mcpFinal)) { $mcpFinal = Find-UabsFileUnder $target 'housecarl-mcp.exe' 5 }
              Set-UabsUserEnv 'HOUSECARL_MCP' $mcpFinal
              Set-UabsUserEnv 'HOUSECARL_ROOT' $target
              $installed[$id] = @{ status='installed-or-updated'; mcp=$mcpFinal; root=$target }
              Write-UabsOk "houseCARL installed/updated -> $target"
            }
          }
          elseif ($id -eq 'codebase-memory') {
            $existing = Find-UabsCodebaseMemoryExe
            if ($existing -and -not (Test-UabsPathWithin $existing $target)) {
              Set-UabsUserEnv 'CODEBASE_MEMORY_MCP' $existing
              $installed[$id] = @{ status = 'kept-external'; exe = $existing }
              Write-UabsOk ("codebase-memory kept external user install: " + $existing)
            }
              else {
                New-Item -ItemType Directory -Force -Path $target | Out-Null
                $destExe = Join-Path $target 'codebase-memory-mcp.exe'
                if ((Test-Path -LiteralPath $destExe) -and (Test-UabsFileLocked $destExe)) {
                  $stopped = Stop-UabsProcessUsingExecutable $destExe
                  if (-not $stopped -or (Test-UabsFileLocked $destExe)) {
                    throw 'codebase-memory exe is locked and its exact owning process could not be stopped safely'
                  }
                  Write-UabsOk 'codebase-memory MCP process stopped for binary refresh; providers will reconnect on demand'
                }
                Copy-UabsRoboSafe -From $rootExtract -To $target -CriticalFiles @('codebase-memory-mcp.exe')
                $exe = Join-Path $target 'codebase-memory-mcp.exe'
                if (-not (Test-Path $exe)) { $exe = Find-UabsFileUnder $target 'codebase-memory-mcp.exe' 4 }
                if (-not $exe) { throw 'codebase-memory-mcp.exe missing after extract' }
                Set-UabsUserEnv 'CODEBASE_MEMORY_MCP' $exe
                $installed[$id] = @{ status = 'installed-or-updated'; exe = $exe }
                Write-UabsOk ("codebase-memory installed/updated -> " + $exe)
              }
          }
          elseif ($id -eq 'spooky') {
            $existingRoot = $env:SPOOKY_AUTOMOD_ROOT
            if ($existingRoot -and (Test-Path (Join-Path $existingRoot 'SpookysAutomod.sln')) -and -not (Test-UabsPathWithin $existingRoot $target)) {
              Set-UabsUserEnv 'SPOOKY_AUTOMOD_ROOT' $existingRoot
              $installed[$id] = @{ status='kept-external'; root=$existingRoot }
              Write-UabsOk ("Spooky kept external user install: " + $existingRoot)
            }
            else {
              New-Item -ItemType Directory -Force -Path $target | Out-Null
              Copy-UabsRobo -From $rootExtract -To $target
              # find sln
              $sln = Find-UabsFileUnder $target 'SpookysAutomod.sln' 5
              $toolkitRoot = if ($sln) { Split-Path $sln -Parent } else { $target }
              # nested spookys-automod-toolkit folder
              $inner = Join-Path $toolkitRoot 'spookys-automod-toolkit'
              if (Test-Path (Join-Path $inner 'SpookysAutomod.sln')) { $toolkitRoot = $inner }
              Set-UabsUserEnv 'SPOOKY_AUTOMOD_ROOT' $toolkitRoot
              $installed[$id] = @{ status='installed-or-updated'; root=$toolkitRoot }
              Write-UabsOk "Spooky installed/updated -> $toolkitRoot"
              Write-UabsWarn "Optional: run SpookysAutomodSetup.exe inside the toolkit folder for headers/compiler"
            }
          }
          else {
            # A component whose binary is CURRENTLY RUNNING cannot be
            # overwritten, and robocopy's answer to that is exit code 8, which
            # Copy-UabsRobo turns into a throw, which aborts the ENTIRE
            # install. Measured 2026-08-27: four github-mcp-server processes
            # were alive as MCP servers for open Claude/Codex/Grok/Kimi/Hermes
            # sessions, and running the installer produced
            #   INSTALL FAILED
            #   robocopy failed exit=8 from=...uabs-extract-github-mcp-server...
            # That is the ordinary case -- a user runs the installer with their
            # AI apps open -- and it took the whole run down over one file.
            #
            # houseCARL and codebase-memory already handle this; this generic
            # branch, which every other zip component falls through to, did
            # not. Same treatment: stop the exact owning process, and if it
            # still will not release, SKIP this one component with a loud
            # warning rather than failing everything around it.
            $lockedExes = @()
            if (Test-Path -LiteralPath $target -PathType Container) {
              foreach ($e in @(Get-ChildItem -LiteralPath $target -Recurse -File -Filter '*.exe' -EA SilentlyContinue)) {
                if (Test-UabsFileLocked $e.FullName) { $lockedExes += $e.FullName }
              }
            }
            foreach ($le in $lockedExes) {
              try { [void](Stop-UabsProcessUsingExecutable $le) } catch { }
            }
            $stillLocked = @($lockedExes | Where-Object { Test-UabsFileLocked $_ })
            if ($stillLocked.Count) {
              $installed[$id] = @{
                status = 'skipped-in-use'
                root   = $target
                locked = @($stillLocked)
              }
              Write-UabsWarn ($id + ': binary in use, left at the installed version -- ' +
                (($stillLocked | ForEach-Object { Split-Path -Leaf $_ }) -join ', '))
              Write-Host '     Close every AI app (their MCP servers hold this file) and re-run to update it.' -ForegroundColor DarkGray
              Write-Host '     Nothing else in this install was affected.' -ForegroundColor DarkGray
            } else {
              Copy-UabsRobo -From $rootExtract -To $target
              $componentState = @{ status='installed'; root=$target }
              if ($comp.exe_rel) {
                $installedExe = Join-Path $target $comp.exe_rel
                if (-not (Test-Path -LiteralPath $installedExe -PathType Leaf)) {
                  throw "$id executable missing after extract: $installedExe"
                }
                $componentState.exe = $installedExe
                if ($id -eq 'rtk' -and $comp.version) {
                  $prevEap = $ErrorActionPreference
                  $ErrorActionPreference = 'Continue'
                  try {
                    $versionText = (& $installedExe --version 2>&1 | Out-String).Trim()
                    $versionExit = $LASTEXITCODE
                  } finally { $ErrorActionPreference = $prevEap }
                  $versionMatch = [regex]::Match($versionText, '(?im)^rtk\s+([0-9]+(?:\.[0-9]+){2,})\s*$')
                  if ($versionExit -ne 0 -or -not $versionMatch.Success) {
                    throw "rtk failed its installed --version check: $versionText"
                  }
                  $actualVersion = $versionMatch.Groups[1].Value
                  if ($actualVersion -ne [string]$comp.version) {
                    throw "rtk installed version $actualVersion, expected $($comp.version)"
                  }
                  $componentState.version = $actualVersion
                  Write-UabsOk "rtk $actualVersion installed and verified"
                }
              }
              $installed[$id] = $componentState
            }
          }
        } finally {
          Remove-Item -LiteralPath $stage -Recurse -Force -EA SilentlyContinue
        }
      }
      # ---- extras: skills fetched from a git repo -------------------------
      # Layout differs per repo: some ARE one skill (skill_folder), some ship a
      # skills/ directory of several (skills_subdir). Both land in every
      # selected provider's skills folder, which is what all five CLIs read.
      'skills-git' {
        $wanted = @($Providers | Where-Object { $comp.providers -contains $_ })
        if (-not $wanted) { Write-UabsWarn "${id}: no selected provider wants it"; $installed[$id] = @{ status='skipped' }; continue }
        $stage = Join-Path $env:TEMP "uabs-skillsgit-$id-$(Get-Random)"
        try {
          if (Get-Command git -EA SilentlyContinue) {
            # git writes "Cloning into ..." to stderr even on success; with
            # $ErrorActionPreference='Stop' that would surface as a failure.
            $prevEap = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            try {
              & git clone --depth 1 --quiet $comp.git_url $stage 2>&1 | ForEach-Object { Write-Host ("     " + $_) }
              $gitCode = $LASTEXITCODE
            } finally { $ErrorActionPreference = $prevEap }
            if ($gitCode -ne 0) { throw "git clone exited $gitCode for $($comp.git_url)" }
          } else {
            # No git: fall back to the branch tarball via the release/zip path.
            $zip = Join-Path $cache "$id-main.zip"
            $u = "https://github.com/$($comp.github.owner)/$($comp.github.repo)/archive/refs/heads/main.zip"
            Save-UabsUrl -Url $u -OutFile $zip
            Expand-UabsZip -Zip $zip -Dest $stage
            $stage = Resolve-UabsSingleRoot $stage
          }
          if (-not (Test-Path $stage)) { throw "fetch failed for $id" }
          $pairs = @()
          if ($comp.skills_subdir) {
            $srcRoot = Join-Path $stage $comp.skills_subdir
            if (-not (Test-Path $srcRoot)) { throw "${id}: expected '$($comp.skills_subdir)' in the repo" }
            foreach ($sk in Get-ChildItem $srcRoot -Directory) { $pairs += @{ name = $sk.Name; path = $sk.FullName } }
          } else {
            $pairs += @{ name = $comp.skill_folder; path = $stage }
          }
          # The bundle vendors a snapshot of several of these skills in
          # _CANONICAL-SKILLS, and the final doctor verifies every provider
          # skill against what the bundle shipped. Copying an upstream clone
          # over the top makes those two facts disagree: the doctor reported six
          # skills stale/modified on five providers and failed the install, for
          # a switch this installer documents and offers. One owner per skill --
          # canonical owns what it ships, and this component installs the rest.
          $canonRoot = Join-Path $PackRoot '_CANONICAL-SKILLS'
          $ownedByCanonical = @()
          if (Test-Path -LiteralPath $canonRoot) {
            $ownedByCanonical = @(Get-ChildItem -LiteralPath $canonRoot -Directory -EA SilentlyContinue |
              Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') } |
              ForEach-Object { $_.Name })
          }
          $skipped = @($pairs | Where-Object { $ownedByCanonical -contains $_.name } | ForEach-Object { $_.name })
          $pairs = @($pairs | Where-Object { $ownedByCanonical -notcontains $_.name })
          if ($skipped.Count) {
            Write-UabsWarn ("{0}: already vendored by this pack, not overwritten: {1}" -f $id, ($skipped -join ', '))
          }
          if (-not $pairs.Count) {
            Write-UabsOk ("${id}: every skill it provides is already vendored; nothing to copy")
            $installed[$id] = @{ status='vendored'; skills=@($skipped); providers=@() }
          } else {
            foreach ($prov in $wanted) {
              $destRoot = Get-UabsProviderSkillsDir -Provider $prov -Catalog $catalog
              foreach ($pair in $pairs) {
                Copy-UabsRobo -From $pair.path -To (Join-Path $destRoot $pair.name)
              }
              Write-UabsOk ("$id -> $prov ({0} skill(s))" -f $pairs.Count)
            }
            $installed[$id] = @{ status='installed'; skills=@($pairs.name); vendored=@($skipped); providers=$wanted }
          }
          if ($comp.scope_note) { Write-UabsWarn ("scope: " + $comp.scope_note) }
        } catch {
          Write-UabsBad ("$id failed: " + $_.Exception.Message)
          $installed[$id] = @{ status='failed'; error=$_.Exception.Message }
        } finally {
          Remove-Item -LiteralPath $stage -Recurse -Force -EA SilentlyContinue
        }
      }

      # ---- extras: Claude Code plugin --------------------------------------
      'claude-plugin' {
        # HARD LOCK: never install Claude-only plugins for other providers
        if ($id -eq 'claude-mem' -or ($comp.providers -and ($comp.providers -notcontains 'Grok') -and ($comp.providers -contains 'Claude') -and ($comp.providers.Count -eq 1))) {
          if ($Providers -notcontains 'Claude') {
            Write-UabsWarn "$id is Claude Code ONLY - skipped (not for Grok/Codex/Kimi/Hermes)"
            $installed[$id] = @{ status='skipped-claude-only' }
            continue
          }
        }
        if ($Providers -notcontains 'Claude') { Write-UabsWarn "$id is Claude Code only - skipped"; $installed[$id] = @{ status='skipped' }; continue }
        # claude-mem worker needs Bun (bun:sqlite). Without it Claude shows red MCP errors.
        if ($id -eq 'claude-mem') {
          $bunExe = Find-UabsBunExecutable
          if (-not $bunExe) {
            Write-UabsWarn 'claude-mem requires Bun (https://bun.sh). Install Bun, open a NEW shell, then re-run the installer.'
            Write-UabsWarn 'Without Bun the plugin installs but MCP tools go red (worker cannot start).'
            $installed[$id] = @{ status='skipped-no-bun'; note='install Bun then re-run' }
            continue
          } else {
            $env:BUN = $bunExe
            $env:PATH = (Split-Path $bunExe -Parent) + ';' + $env:PATH
            Write-UabsOk 'Bun present (required for claude-mem worker)'
          }
        }
        if (-not (Get-Command npx -EA SilentlyContinue)) {
          Write-UabsWarn "$id needs Node/npx. Install Node, then: npx $($comp.npx_install -join ' ')"
          $installed[$id] = @{ status='skipped-no-node' }
          continue
        }
        try {
          if (-not (Invoke-UabsNative 'npx' @($comp.npx_install))) { throw "npx exited with code $LASTEXITCODE" }
          if ($id -eq 'claude-mem') {
            if (-not (Invoke-UabsNative 'npx' @('claude-mem','telemetry','disable'))) { throw 'claude-mem telemetry opt-out failed' }
            if (-not (Invoke-UabsNative 'npx' @('claude-mem','start'))) { throw 'claude-mem worker failed to start' }
          }
          $installed[$id] = @{ status='installed'; via='npx' }
          Write-UabsOk "$id installed (restart Claude Code to load the plugin)"
          if ($comp.scope_note) { Write-UabsWarn ("scope: " + $comp.scope_note) }
        } catch {
          Write-UabsWarn ("$id via npx failed. In Claude Code run: /plugin marketplace add $($comp.marketplace[0])  then  /plugin install $($comp.marketplace[1])")
          $installed[$id] = @{ status='manual'; error=$_.Exception.Message }
        }
      }

      # ---- extras: npx-launched MCP servers --------------------------------
      # Nothing is installed; npx resolves the package on first launch. We only
      # write the server block into each provider's MCP config.
      'mcp-npx' {
        $wanted = @($Providers | Where-Object { $comp.providers -contains $_ })
        if (-not $wanted) { Write-UabsWarn "${id}: not wanted by any selected provider"; $installed[$id] = @{ status='skipped' }; continue }
        if ($comp.PSObject.Properties.Name -contains 'auto_register' -and $comp.auto_register -eq $false) {
          $aliases = @($id, ($id -replace '-mcp$', '')) | Select-Object -Unique
          $cleaned = @(Remove-UabsGlobalMcpRegistration -Ids $aliases -FromProviders $wanted)
          Write-UabsOk "${id}: available through project-scoped profile '$($comp.profile)'; not registered globally"
          $installed[$id] = @{ status='profile-only'; profile=$comp.profile; cleaned_global=$cleaned }
          continue
        }
        if (-not (Get-Command npx -EA SilentlyContinue)) {
          Write-UabsWarn "$id needs Node/npx - skipping registration so we do not write a broken MCP entry"
          $installed[$id] = @{ status='skipped-no-node' }
          continue
        }
        $envMap = $null
        $keyName = $comp.api_key_env
        if ($keyName) {
          $keyVal = [Environment]::GetEnvironmentVariable($keyName, 'User')
          if (-not $keyVal) { $keyVal = [Environment]::GetEnvironmentVariable($keyName, 'Process') }
          if ($keyVal) {
            $envMap = @{ $keyName = $keyVal }
          } elseif ($comp.api_key_optional -and $comp.keyless_registration -eq 'skip' -and -not $RegisterKeylessExtras) {
            # Installed is not registered. A server whose keyless surface is a
            # small fraction of its schema costs full price for a sliver of
            # capability -- firecrawl-mcp keyless is 2 usable tools out of 25,
            # ~9,080 tokens every turn, duplicating a native capability. Through
            # 7.9.8 -WithExtras registered it anyway and said so in one line
            # nobody reads. Note this is an mcp-npx component: registering IS
            # installing, because npx resolves the package on first launch. So
            # nothing is cached here and nothing is lost -- the entry simply
            # waits for the key that makes the server worth carrying.
            Write-UabsWarn "${id}: NOT registered (no $keyName)"
            if ($comp.keyless_skip_reason) { Write-Host ("     " + $comp.keyless_skip_reason) -ForegroundColor DarkGray }
            Write-Host ("     Enable: setx $keyName ""<key>"" then re-run the installer") -ForegroundColor DarkGray
            Write-Host ("     Or register it keyless anyway: -RegisterKeylessExtras") -ForegroundColor DarkGray
            $aliases = @($id, ($id -replace '-mcp$', '')) | Select-Object -Unique
            $cleaned = @(Remove-UabsGlobalMcpRegistration -Ids $aliases -FromProviders $wanted)
            $installed[$id] = @{ status='not-registered-no-key'; needs=$keyName; cleaned_global=$cleaned }
            continue
          } elseif ($comp.api_key_optional) {
            Write-UabsWarn "${id}: no $keyName - registering anyway ($($comp.keyless_note))"
          } else {
            Write-UabsWarn "${id}: no $keyName set. Get a key, run: setx $keyName ""<key>"" then re-run the installer"
            $aliases = @($id, ($id -replace '-mcp$', '')) | Select-Object -Unique
            $cleaned = @(Remove-UabsGlobalMcpRegistration -Ids $aliases -FromProviders $wanted)
            $installed[$id] = @{ status='skipped-no-key'; needs=$keyName; cleaned_global=$cleaned }
            continue
          }
        }
        # Optional extra CLI args from a user env var (v7.5.6). Lets an MCP
        # component be pointed at a user-chosen binary without a code change;
        # playwright-mcp uses it for --executable-path so it does not force
        # Google Chrome on people who run Opera GX / Brave / Vivaldi / etc.
        $npxArgs = @($comp.npx_args)
        $extraEnv = $comp.extra_args_env
        if ($extraEnv) {
          $extraVal = [Environment]::GetEnvironmentVariable($extraEnv, 'User')
          if (-not $extraVal) { $extraVal = [Environment]::GetEnvironmentVariable($extraEnv, 'Process') }
          if ($extraVal) {
            foreach ($part in @($comp.extra_args_template)) {
              $npxArgs += ($part -replace [regex]::Escape('{value}'), $extraVal)
            }
            Write-UabsOk ("$id extra args from $extraEnv : " + (($npxArgs | Select-Object -Skip $comp.npx_args.Count) -join ' '))
          } else {
            Write-UabsWarn "${id}: $extraEnv not set - using defaults ($($comp.id) may fall back to Google Chrome; set it to your browser exe to override)"
          }
        }
        $regs = @()
        foreach ($prov in $wanted) {
          switch ($prov) {
            'Grok'  {
              # grok-cli wedges at eight servers running. Add-Reasoning-MCPs and
              # Set-McpProfile both check this ceiling; the extras branch did
              # not, and walked Grok past it with no message.
              $grokCfg = Join-Path $env:USERPROFILE '.grok\config.toml'
              $grokDeclared = (Test-Path -LiteralPath $grokCfg) -and
                ([IO.File]::ReadAllText($grokCfg) -match [regex]::Escape("[mcp_servers.$id]"))
              if (-not $grokDeclared -and (Get-UabsGrokMcpCount) -ge $GrokMcpBudget) {
                Write-UabsWarn ("{0}: Grok already has {1} MCP server(s) (budget {2}); not added." -f $id, (Get-UabsGrokMcpCount), $GrokMcpBudget)
                Write-UabsWarn ('  Remove one from ~/.grok/config.toml, or re-run with -GrokMcpBudget 7 if no plugin adds one.')
              } else {
                Update-UabsGrokMcpBlock -Name $id -Command $comp.npx_command -ArgList $npxArgs -EnvMap $envMap -Startup 120 -Tool 6000 -SkipIfPresent
                $regs += 'Grok'
              }
            }
            'Codex' {
              $cfg = Join-Path (Get-UabsProviderHome -Provider Codex -Catalog $catalog) 'config.toml'
              Update-UabsGrokMcpBlock -Name $id -Command $comp.npx_command -ArgList $npxArgs -EnvMap $envMap -Startup 120 -Tool 6000 -SkipIfPresent -ConfigPath $cfg
              $regs += 'Codex'
            }
            'Claude' {
              if (Get-Command claude -EA SilentlyContinue) {
                $addArgs = @('mcp', 'add', '--scope', 'user')
                if ($envMap) { foreach ($k in $envMap.Keys) { $addArgs += @('--env', ("{0}={1}" -f $k, $envMap[$k])) } }
                $addArgs += @($id, '--', $comp.npx_command) + $npxArgs
                [void](Invoke-UabsNative 'claude' $addArgs)
                $regs += 'Claude'
              } else {
                Write-UabsWarn "$id for Claude: run  claude mcp add --scope user $id -- $($comp.npx_command) $($npxArgs -join ' ')"
              }
            }
            'Kimi' {
              $kimiCfg = Join-Path $env:USERPROFILE '.kimi-code\mcp.json'
              if (Test-Path -LiteralPath (Split-Path -Parent $kimiCfg)) {
                # Adding by catalog id is blind to the same server already
                # present under another name, which is how Hermes ended up with
                # both `playwright` and `playwright-mcp`. Match the package.
                $existingText = if (Test-Path -LiteralPath $kimiCfg) { [IO.File]::ReadAllText($kimiCfg) } else { '' }
                $dupe = Find-UabsServerByPackage -ConfigText $existingText -PackageBase (Get-UabsNpxPackageBase -Arguments $npxArgs)
                if ($dupe -and $dupe -ne $id) {
                  Write-UabsWarn ("{0}: Kimi already runs this package as '{1}', not adding a second entry" -f $id, $dupe)
                } else {
                  $spec = @{ id = $id; command = $comp.npx_command; args = $npxArgs; note = $id; key = $keyName }
                  [void](Add-UabsMcpJson -Path $kimiCfg -Section 'mcpServers' -Servers @($spec) -Provider 'Kimi' -Refresh)
                  $regs += 'Kimi'
                }
              } else {
                Write-UabsWarn "${id}: Kimi not installed, skipped"
              }
            }
            'Hermes' {
              $hp = Get-UabsHermesPaths
              if (Test-Path -LiteralPath $hp.Python -PathType Leaf) {
                $existingText = if (Test-Path -LiteralPath $hp.Config) { [IO.File]::ReadAllText($hp.Config) } else { '' }
                $dupe = Find-UabsServerByPackage -ConfigText $existingText -PackageBase (Get-UabsNpxPackageBase -Arguments $npxArgs)
                if ($dupe -and $dupe -ne $id) {
                  Write-UabsWarn ("{0}: Hermes already runs this package as '{1}', not adding a second entry" -f $id, $dupe)
                } else {
                  $spec = @{ id = $id; command = $comp.npx_command; args = $npxArgs; note = $id; key = $keyName }
                  [void](Add-UabsMcpHermes -Servers @($spec) -Refresh)
                  $regs += 'Hermes'
                }
              } else {
                Write-UabsWarn "${id}: Hermes not installed, skipped"
              }
            }
            default {
              # Reached only by a provider this pack does not know how to write.
              # Printing the block is a handoff, and it is the last resort, not
              # the plan -- Hermes and Kimi used to land here and silently got
              # nothing while the catalog claimed five providers.
              Write-UabsWarn ("{0}: add this MCP block to {1} yourself:" -f $id, $prov)
              Write-Host ("      command = ""{0}""  args = [{1}]" -f $comp.npx_command, (($npxArgs | ForEach-Object { '"' + $_ + '"' }) -join ', '))
            }
          }
        }
        $installed[$id] = @{ status='registered'; providers=$regs; key=$keyName }
        Write-UabsOk ("$id registered for: " + ($regs -join ', '))
        if ($comp.scope_note) { Write-UabsWarn ("scope: " + $comp.scope_note) }
      }

      default { Write-UabsWarn "No installer for $($comp.install)" }
    }
  }

  # Never print an upstream init command here: it enables the broad rewrite
  # table. The bundle-owned hook installed below has a measured allowlist.
  if ($installed['rtk']) {
    Write-UabsStep 'rtk is installed - safe routing covers status + standalone pytest/cargo/go tests'
    Write-Host '     Broad upstream hooks remain off; diff/log/show/find/read/search and mutating Git stay raw.' -ForegroundColor Yellow
    Write-Host '     Use rtk explicitly for other noisy output, then verify savings with `rtk gain`.' -ForegroundColor DarkGray
  }
}

# ---------- Grok compat cells (always, before any MCP decision) ----------
# Grok ships Claude-Code compatibility ON: it adopts ~/.claude skills, agents,
# plugins (with their hooks and .mcp.json), ~/.claude.json and settings.json.
# The hook and MCP halves of that were measured as pure cost - see
# GROK-MCP-TROUBLESHOOTING.md. Skills/rules/agents compat stays on.
if (-not $SkillsOnly -and ($Providers -contains 'Grok')) {
  Write-UabsStep "Grok Claude-compat cells"
  try {
    Set-UabsGrokCompatCells
  } catch { Write-UabsWarn ("Grok compat cells: " + $_.Exception.Message) }
}

# ---------- MCP wire (Grok) ----------
if (-not $SkipGrokMcp -and -not $SkipMcpWire -and -not $SkillsOnly -and ($Providers -contains 'Grok')) {
  Write-UabsStep "Wiring Grok MCP servers"
  $hr = $null
  try { $hr = (Get-Command headroom -EA SilentlyContinue).Source } catch {}
  if (-not $hr) { $hr = [Environment]::GetEnvironmentVariable('HEADROOM_CMD','User') }
  if ($hr -and (Test-Path $hr)) {
    Update-UabsGrokMcpBlock -Name 'headroom' -Command $hr -ArgList @('mcp','serve') -Startup 60 -Tool 600 -SkipIfPresent
  } elseif ($hr) {
    # might be bare command name
    Update-UabsGrokMcpBlock -Name 'headroom' -Command 'headroom' -ArgList @('mcp','serve') -Startup 60 -Tool 600 -SkipIfPresent
  }
  Write-UabsOk 'Skyrim MCPs stay out of the global Grok config; game profiles own activation'
}
elseif (-not $SkillsOnly -and ($Providers -contains 'Grok')) {
  Write-UabsWarn 'Grok MCP wiring skipped (-SkipGrokMcp).'
}

# grok-cli 1.0.4 wedges startup at eight RUNNING MCP servers (measured: 7 running
# = 0ms wait, 8 = ~34900ms and the process never exits). Plugin-provided servers
# count toward that but never appear in config.toml, so budget 6 configured.
if (-not $SkillsOnly -and ($Providers -contains 'Grok')) {
  $grokCfg = Join-Path $env:USERPROFILE '.grok\config.toml'
  if (Test-Path -LiteralPath $grokCfg) {
    # [ \t\r]* not [ \t]*: config.toml is CRLF and .NET's multiline $ matches
    # before the \n, so a trailing \r fails the anchor and the count reads 0.
    $srvCount = ([regex]::Matches(([IO.File]::ReadAllText($grokCfg)), '(?m)^[ \t]*\[mcp_servers\.[A-Za-z0-9_-]+\][ \t\r]*$')).Count
    # grok-cli 1.0.4 wedges at EIGHT running servers. Enabled Claude plugins with
    # a .mcp.json still load even with [compat.claude] mcps = false, so each one
    # eats a slot that never appears in config.toml. Budget 6 configured.
    if ($srvCount -ge 7) {
      Write-UabsWarn ("Grok has $srvCount MCP servers configured. Eight RUNNING wedges grok-cli 1.0.4, and enabled Claude plugins add servers you cannot see here - comment some out in ~/.grok/config.toml (see GROK-MCP-TROUBLESHOOTING.md).")
    } else {
      Write-UabsOk ("Grok MCP servers: $srvCount configured (budget 6; plugin-provided servers also count)")
    }
  }
}


# ---------- Headroom + Grok (MCP only; NEVER reroute inference) ----------
# Headroom's Grok proxy authenticates against https://api.x.ai with XAI_API_KEY.
# A Grok subscription / OIDC login uses https://cli-chat-proxy.grok.com instead,
# which Headroom cannot forward - wrapping it kills the model catalog (the model
# shows as "unknown") and 401s every turn. So the installer registers the
# Headroom MCP tools and leaves inference alone.
# API-key users can opt in afterwards:  .\TOOLS\Ensure-Headroom-Grok.ps1 -Wrap
if (-not $SkillsOnly -and ($Providers -contains 'Grok')) {
  $hrEnsure = Join-Path $PackRoot 'TOOLS\Ensure-Headroom-Grok.ps1'
  if (Test-Path $hrEnsure) {
    Write-UabsStep "Headroom Grok MCP registration (auth aware; repairs a v5.0 inference wrap)"
    try {
      $hrArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $hrEnsure)
      if ($SkipMcpWire) { $hrArgs += '-SkipMcp' }
      & (Get-Command powershell.exe -ErrorAction Stop).Source @hrArgs
      if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) {
        Write-UabsWarn ("Ensure-Headroom-Grok exited " + $LASTEXITCODE)
      } else {
        Write-UabsOk 'Headroom registered for Grok as MCP (inference left on the native endpoint)'
        $installed['headroom-grok-mcp'] = @{ status = 'mcp-only' }
      }
    } catch {
      Write-UabsWarn ("Ensure-Headroom-Grok: " + $_.Exception.Message)
      $installed['headroom-grok-mcp'] = @{ status = 'error'; error = $_.Exception.Message }
    }
  } else {
    Write-UabsWarn 'TOOLS\Ensure-Headroom-Grok.ps1 missing from pack'
  }
}
# ---------- houseCARL MO2/Vortex ----------
if (-not $SkipHouseCarlSetup -and -not $SkillsOnly) {
  $setup = Join-Path $PackRoot 'TOOLS\Setup-HouseCarl.ps1'
  if (Test-Path $setup) {
    Write-UabsStep "houseCARL MO2/Vortex setup"
    try {
      & $setup -WireGrok:$false -WireCodex:$false
      $installed['housecarl-setup'] = @{ status='ran' }
    } catch {
      Write-UabsWarn "Setup-HouseCarl: $($_.Exception.Message)"
      $installed['housecarl-setup'] = @{ status='error'; error=$_.Exception.Message }
    }
  }
}

# ---------- Bundled Skyrim Forge ----------
# Forge's source lives in this repository at BUNDLED-TOOLS\skyrim-forge, so
# what installs is whatever this commit contains -- there is no separately
# released archive to drift. The installer resolves ONE versionless install
# root (migrating a version-stamped install onto it), refreshes provider skill
# descriptors without global MCP registration, and proves `forge doctor`.
#
# No -BundleVersion is passed any more. 7.8.0 negotiated a compatibility range
# with a separately released Forge and read a field back that Forge has never
# emitted, so this step threw on every run and aborted the whole install here.
if (-not $ToolsOnly -and -not $SkillsOnly) {
  $forgeInstaller = Join-Path $PackRoot 'TOOLS\Install-SkyrimForge.ps1'
  if (-not (Test-Path -LiteralPath $forgeInstaller -PathType Leaf)) { throw 'TOOLS\Install-SkyrimForge.ps1 missing from pack.' }
  $forgeVersionFile = Join-Path $PackRoot 'BUNDLED-TOOLS\skyrim-forge\VERSION.txt'
  if (-not (Test-Path -LiteralPath $forgeVersionFile -PathType Leaf)) { throw 'BUNDLED-TOOLS\skyrim-forge is missing from pack.' }
  $forgeSourceVersion = if ([IO.File]::ReadAllText($forgeVersionFile) -match '(?m)^Skyrim Forge\s+(?<ver>\d+\.\d+\.\d+)\s*$') { $Matches['ver'] } else { 'unknown' }
  $forgeArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$forgeInstaller,'-PackRoot',$PackRoot,'-Providers',($Providers -join ','),'-BundleOwnsProviderSkills')
  if ($ForgeRoot) { $forgeArgs += @('-ForgeRoot', $ForgeRoot) }
  & (Get-Command powershell.exe -ErrorAction Stop).Source @forgeArgs
  if ($LASTEXITCODE -ne 0) { throw "Skyrim Forge installation failed with exit code $LASTEXITCODE." }
  $installed['skyrim-forge'] = @{ status='installed'; version=$forgeSourceVersion; root=$env:SKYRIM_FORGE_ROOT }

  # Earlier bundles owned these machine-wide entries. Keep the tools and
  # skills installed, but migrate their schemas out of unrelated sessions.
  $cleaned = @(Remove-UabsGlobalMcpRegistration -Ids @('skyrim-forge','housecarl','codebase-memory-mcp') -FromProviders $Providers)
  $installed['game-mcp-global-migration'] = @{ status='profile-only'; removed_from=$cleaned }
}

# Discover separately installed game Forges without baking this maintainer's
# drive letter into a shipped provider config. Existing valid choices win.
function Set-UabsDiscoveredGameForgeRoot {
  param([string]$Variable, [string]$Marker, [string[]]$RelativeCandidates)
  $root = [Environment]::GetEnvironmentVariable($Variable, 'User')
  if (-not $root) { $root = [Environment]::GetEnvironmentVariable($Variable, 'Process') }
  if ($root -and (Test-Path -LiteralPath (Join-Path $root $Marker) -PathType Leaf)) {
    Set-Item -Path ("Env:" + $Variable) -Value $root
    return $root
  }
  $bases = @($env:LOCALAPPDATA)
  foreach ($letter in @('C','D','E','F','G','H','S','T','Z')) {
    $drive = "${letter}:\"
    if (Test-Path -LiteralPath $drive) { $bases += $drive }
  }
  foreach ($base in @($bases | Where-Object { $_ } | Select-Object -Unique)) {
    foreach ($relative in $RelativeCandidates) {
      $candidate = Join-Path $base $relative
      if (-not (Test-Path -LiteralPath (Join-Path $candidate $Marker) -PathType Leaf)) { continue }
      Set-UabsUserEnv $Variable $candidate
      Set-Item -Path ("Env:" + $Variable) -Value $candidate
      Write-UabsOk ("{0} discovered: {1}" -f $Variable, $candidate)
      return $candidate
    }
  }
  return $null
}

$robloxForge = Set-UabsDiscoveredGameForgeRoot -Variable 'ROBLOX_FORGE_ROOT' -Marker 'mcp_server\server.py' -RelativeCandidates @('RobloxForge','Apps\Roblox Tools\RobloxForge')
$saintsForge = Set-UabsDiscoveredGameForgeRoot -Variable 'SAINTSROW_FORGE_ROOT' -Marker 'mcp_server\server.py' -RelativeCandidates @('SaintsRowForge','Apps\Saints Row Tools\SaintsRowForge')
$installed['roblox-forge-discovery'] = @{ status=$(if($robloxForge){'found'}else{'not-installed'}); root=$robloxForge }
$installed['saints-row-forge-discovery'] = @{ status=$(if($saintsForge){'found'}else{'not-installed'}); root=$saintsForge }

if (-not $SkipMcpWire -and -not $SkillsOnly) {
  $mcpProfile = Join-Path $PackRoot 'TOOLS\Set-McpProfile.ps1'
  if (Test-Path -LiteralPath $mcpProfile) {
    & $mcpProfile -Repair -Providers $Providers -PackRoot $PackRoot
    if ($WorkspaceRoot) {
      & $mcpProfile -Auto -Path $WorkspaceRoot -Providers $Providers -PackRoot $PackRoot
    }
  }
}

# ---------- Discover + state ----------
Write-UabsStep "Post-install discovery"
$disc = Join-Path $PackRoot 'TOOLS\discover_tools.ps1'
if (Test-Path $disc) {
  & (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -File $disc | Tee-Object -Variable discOut | Out-Host
}

$stateDir = Join-Path $env:LOCALAPPDATA 'Ultimate-AI-Starter-Bundle'
New-Item -ItemType Directory -Force -Path $stateDir | Out-Null

# A partial run must update what it touched without forgetting everything else.
# native_plugins is always provider-scoped; components are carried forward only
# for SkillsOnly or an explicitly narrowed -Components run. A normal full tool
# pass remains authoritative and can retire old component records.
$statePath = Join-Path $stateDir 'install-state.json'
$priorState = $null
if (Test-Path -LiteralPath $statePath -PathType Leaf) {
  try {
    $priorState = [IO.File]::ReadAllText($statePath) | ConvertFrom-Json
    $priorPlugins = $priorState.native_plugins
    if ($priorPlugins) {
      foreach ($p in $priorPlugins.PSObject.Properties) {
        if (-not $nativePlugins.Contains($p.Name)) { $nativePlugins[$p.Name] = $p.Value }
      }
    }
    $partialComponentRun = $SkillsOnly -or $PSBoundParameters.ContainsKey('Components')
    if ($partialComponentRun -and $priorState.components) {
      foreach ($p in $priorState.components.PSObject.Properties) {
        if (-not $installed.Contains($p.Name)) { $installed[$p.Name] = $p.Value }
      }
    }
  } catch { Write-UabsWarn 'Could not read the previous install state; untouched partial-install records were not carried forward.' }
}
$knownProviders = @($Providers)
if ($priorState -and $priorState.providers) { $knownProviders += @($priorState.providers) }
$stateProviders = @($script:UabsAllProviders | Where-Object { $knownProviders -contains $_ })

  $state = @{
version = '8.7.15'
  status = 'verifying'
  installed_utc = [DateTime]::UtcNow.ToString('o')
  mode = $Mode
  providers = $stateProviders
  components = $installed
  native_plugins = $nativePlugins
  pack_root = $PackRoot
}
$state | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $stateDir 'install-state.json') -Encoding UTF8
$log | Set-Content (Join-Path $stateDir 'install-log.txt') -Encoding UTF8

# Completeness + assumption gates, plus narrow RTK output routing. Every
# provider's prose already says 'be thorough' and 'do not assume'; the first
# two can actually refuse, while RTK only modifies commands on its allowlist.
if (-not $ToolsOnly) {
  $gateInstaller = Join-Path $PackRoot 'TOOLS\Install-Completeness-Gate.ps1'
  if (Test-Path -LiteralPath $gateInstaller) {
    try {
      & (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File $gateInstaller -Providers ($Providers -join ',')
      L 'completeness + assumption gates and safe RTK routing installed'
    } catch {
      Write-UabsWarn ('Gates: ' + $_.Exception.Message)
    }
  } else {
    Write-UabsWarn 'TOOLS\Install-Completeness-Gate.ps1 missing from pack'
  }

  $mcpReason = Join-Path $PackRoot 'TOOLS\Add-Reasoning-MCPs.ps1'
  if (-not $SkillsOnly -and -not $SkipMcpWire -and (Test-Path -LiteralPath $mcpReason)) {
    try {
      & (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File $mcpReason -Providers ($Providers -join ',') -Refresh
      L 'reasoning MCP servers wired'
    } catch {
      Write-UabsWarn ('Reasoning MCPs: ' + $_.Exception.Message)
    }
  }

  $hermesProfiles = Join-Path $PackRoot 'TOOLS\Migrate-HermesProfiles.ps1'
  if (-not $SkillsOnly -and -not $SkipMcpWire -and ($Providers -contains 'Hermes') -and (Test-Path -LiteralPath $hermesProfiles)) {
    try {
      # The migrator refuses to run while Hermes.exe is up, because the desktop
      # app persists its stale in-memory config on the next save and would undo
      # the migration (the v8.0.4 defect, in a new place). The install already
      # closes it -- but only inside the plugin block, which -SkipNativePlugins
      # and an absent Hermes CLI both skip. Without this the migration became a
      # warning on exactly the runs that skipped that block, and the profile
      # topology silently never landed.
      $hermesUp = Get-Process -Name 'Hermes' -ErrorAction SilentlyContinue
      if ($hermesUp) {
        if (-not $script:UabsHermesDesktopExe) {
          $script:UabsHermesDesktopExe = ($hermesUp | Select-Object -First 1).Path
        }
        Write-UabsWarn 'Hermes desktop is running - closing it so the profile migration cannot be overwritten (relaunched when the install finishes)'
        $hermesUp | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
      }
      $profileArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $hermesProfiles, '-Apply')
      if ($SkyrimToolset) { $profileArgs += @('-SkyrimToolset', $SkyrimToolset) }
      & (Get-Command powershell.exe -ErrorAction Stop).Source @profileArgs
      if ($LASTEXITCODE -ne 0) { throw "Hermes profile migrator failed with exit code $LASTEXITCODE" }
      $installed['hermes-native-profiles'] = @{ status='evaluated'; profiles=@('default','code','roblox','skyrim'); skyrim_toolset=$(if ($SkyrimToolset) { $SkyrimToolset } else { 'default (Lean)' }) }
      L 'Hermes native profiles evaluated'
    } catch {
      Write-UabsWarn ('Hermes native profiles: ' + $_.Exception.Message)
    }
  }

  # After every provider config has been written, repoint any MCP command that
  # points at a version-stamped folder which no longer exists. An upgraded tool
  # (Skyrim-Forge-5.1.0 -> 5.1.3) renames its folder, and a provider that was
  # missed just stops connecting silently.
  $mcpRepair = Join-Path $PackRoot 'TOOLS\Repair-McpPaths.ps1'
  if (Test-Path -LiteralPath $mcpRepair) {
    try {
      & (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File $mcpRepair -Apply -Quiet
      L 'dead MCP command paths repaired'
    } catch {
      Write-UabsWarn ('MCP path repair: ' + $_.Exception.Message)
    }
  }

  $toolbelt = Join-Path $PackRoot 'TOOLS\Build-Toolbelt.ps1'
  if (Test-Path -LiteralPath $toolbelt) {
    try {
      & (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File $toolbelt
      L 'toolbelt inventory written'
    } catch {
      Write-UabsWarn ('Toolbelt: ' + $_.Exception.Message)
    }
  }

  if (-not $SkillsOnly -and -not $SkipMcpWire -and -not $SkipMcpHandshake) {
    $probe = Join-Path $PackRoot 'TOOLS\Test-McpHandshake.ps1'
    if (-not (Test-Path -LiteralPath $probe -PathType Leaf)) { throw 'MCP handshake probe missing.' }
    $coreMcp = @()
    if (Get-Command npx -ErrorAction SilentlyContinue) { $coreMcp += 'context7' }
    if (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'Ultimate-AI-Starter-Bundle\github-mcp-server\github-mcp-server.exe') -PathType Leaf) { $coreMcp += 'github' }
    $hrCheck = [Environment]::GetEnvironmentVariable('HEADROOM_CMD','User')
    if (-not $hrCheck) { try { $hrCheck = (Get-Command headroom -ErrorAction SilentlyContinue).Source } catch { } }
    if ($hrCheck -and (Test-Path -LiteralPath $hrCheck -PathType Leaf)) { $coreMcp += 'headroom' }
    foreach ($prov in $Providers) {
      if ($prov -eq 'Grok' -and $SkipGrokMcp) { continue }
      foreach ($serverName in $coreMcp) {
        $handshakeOk = $false
        foreach ($attempt in 1..2) {
          Write-UabsStep ("MCP handshake: {0}/{1} (attempt {2}/2)" -f $prov, $serverName, $attempt)
          & (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File $probe -Provider $prov -Name $serverName -TimeoutSeconds 90 -RequireMatch
          if ($LASTEXITCODE -eq 0) { $handshakeOk = $true; break }
          if ($attempt -eq 1) { Write-UabsWarn 'Handshake failed once; retrying the already-resolved server command' }
        }
        if (-not $handshakeOk) { throw "MCP handshake failed: $prov/$serverName after 2 attempts" }
      }
    }
  }
}

# Final fail-closed proof. Avoid -Switch:$false because powershell.exe -File on
# Windows PowerShell 5.1 cannot bind explicit Boolean values to [switch].
$doctorScript = Join-Path $PackRoot 'TOOLS\Test-Installed-State.ps1'
if (-not (Test-Path -LiteralPath $doctorScript -PathType Leaf)) { throw 'Final installed-state doctor missing.' }
$doctorArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$doctorScript,'-PackRoot',$PackRoot,'-Providers',($Providers -join ','))
if ($ToolsOnly) { $doctorArgs += @('-SkipSkills','-SkipForge') }
elseif ($SkillsOnly) { $doctorArgs += '-SkipForge' }
# Capture the child doctor's streams, then replay them in this process. Windows
# Start-Transcript does not reliably capture output written directly by a child
# powershell.exe process, which previously left INSTALL-LAST.log with only the
# generic exit code and hid the actual failing doctor check.
$prevEap=$ErrorActionPreference; $ErrorActionPreference='Continue'
$doctorOutput = @(& (Get-Command powershell.exe -ErrorAction Stop).Source @doctorArgs 2>&1)
$ErrorActionPreference=$prevEap
$doctorExitCode = $LASTEXITCODE
foreach ($doctorLine in $doctorOutput) { Write-Host ([string]$doctorLine) }
if ($doctorExitCode -ne 0) {
  $doctorTail = (@($doctorOutput | Select-Object -Last 12 | ForEach-Object { [string]$_ }) -join ' | ')
  throw "Final installed-state doctor failed with exit code $doctorExitCode. Doctor tail: $doctorTail"
}

# Leftovers, last: only a run that got this far has a current tree to converge
# on, and a failed install must keep every log and backup for diagnosis.
if (-not $SkipCleanup -and -not $ToolsOnly) {
  $cleanTool = Join-Path $PackRoot 'TOOLS\Clean-StaleState.ps1'
  if (Test-Path -LiteralPath $cleanTool -PathType Leaf) {
    try {
      $cleanArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $cleanTool, '-Apply', '-PackRoot', $PackRoot)
      if ($SkillsOnly) { $cleanArgs += '-SkipSkills' }
      & (Get-Command powershell.exe -ErrorAction Stop).Source @cleanArgs
      $installed['stale-state-cleanup'] = @{ status = 'applied' }
    } catch {
      # Never fail an otherwise-good install over housekeeping.
      Write-UabsWarn ('Leftover cleanup: ' + $_.Exception.Message)
      $installed['stale-state-cleanup'] = @{ status = 'failed'; error = $_.Exception.Message }
    }
  }
}

$state.status = 'complete'
$state.completed_utc = [DateTime]::UtcNow.ToString('o')
$state | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $stateDir 'install-state.json') -Encoding UTF8

# Relaunch Hermes desktop only after every config write is done, so it starts
# with the complete MCP board instead of a stale pre-install copy.
if ($script:UabsHermesDesktopExe) {
  if (Test-Path -LiteralPath $script:UabsHermesDesktopExe -PathType Leaf) {
    Start-Process -FilePath $script:UabsHermesDesktopExe
    Write-UabsOk 'Hermes desktop relaunched with the final config'
  } else {
    Write-UabsWarn ('Hermes desktop was closed for the install but its exe is gone (' + $script:UabsHermesDesktopExe + ') - relaunch it manually')
  }
  $script:UabsHermesDesktopExe = $null
}

Write-Host ""
Write-Host "=====================================================" -ForegroundColor Green
Write-Host " INSTALL COMPLETE" -ForegroundColor Green
Write-Host " State: $stateDir\install-state.json" -ForegroundColor Green
Write-Host "=====================================================" -ForegroundColor Green
Write-Host ""
Write-Host 'NEXT STEPS:' -ForegroundColor Yellow
Write-Host '  1. FULLY restart every AI app you use (Grok / Claude / Codex / ...).'
Write-Host '  2. Run /mcp and confirm the always-on core: context7, github, headroom.'
Write-Host '  3. Claude houseCARL plugin: set MO2 instance to SKYRIM_MO2_INSTANCE path.'
Write-Host '  4. Vortex users after LO changes: TOOLS\Setup-HouseCarl.ps1 -RefreshOnly'
Write-Host '  5. Update tools later: TOOLS\Update-From-GitHub.ps1'
Write-Host '  6. Core MCP handshakes passed during install. Re-check any provider with:'
Write-Host '     TOOLS\Test-McpHandshake.ps1 -Provider Claude'
Write-Host '     Capability profiles (code memory, games, browser, Serena, Blender, Godot, Unity, reasoning) are off'
Write-Host '     until a project needs them, and are then wired for THAT project only:'
Write-Host '     TOOLS\Set-McpProfile.ps1 -List | -Auto -Path <project> | -Disable <id>'
# Say, concretely, whether ANY project profile is enabled. -Auto only runs
# above when -WorkspaceRoot was passed, and START-HERE.bat never passes it --
# so on a default install this detection has never run and nothing said so.
# The symptom is an agent whose houseCARL / Forge / codebase-memory tool calls
# return nothing, with no hint that the fix is one command rather than an
# install. Reported here because guessing a project directory and enabling
# servers for it would be worse than saying nothing.
$profileStateFile = Join-Path $stateDir 'mcp-profiles.json'
$enabledProfiles = @()
if (Test-Path -LiteralPath $profileStateFile -PathType Leaf) {
  try {
    $ps = [IO.File]::ReadAllText($profileStateFile) | ConvertFrom-Json
    if ($ps.profiles) {
      foreach ($pr in $ps.profiles.PSObject.Properties) {
        $projs = @()
        try {
          $projs = @($pr.Value.projects.PSObject.Properties.Name |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        } catch { $projs = @() }
        if ($projs.Count) { $enabledProfiles += ('{0} -> {1}' -f $pr.Name, ($projs -join '; ')) }
        if ($pr.Value.global) { $enabledProfiles += ('{0} -> (global)' -f $pr.Name) }
      }
    }
  } catch { }
}
if ($enabledProfiles.Count) {
  Write-Host '     Currently enabled:' -ForegroundColor DarkGray
  foreach ($ep in $enabledProfiles) { Write-Host ('       ' + $ep) -ForegroundColor DarkGray }
} else {
  Write-Host '     NONE are enabled for any project yet. Until you enable one, houseCARL,' -ForegroundColor Yellow
  Write-Host '     Skyrim Forge, codebase-memory and Serena tools will NOT appear in any AI' -ForegroundColor Yellow
  Write-Host '     app, and an agent asked to use them will simply find nothing. That is a' -ForegroundColor Yellow
  Write-Host '     one-command fix, not an install problem:' -ForegroundColor Yellow
  Write-Host '       TOOLS\Set-McpProfile.ps1 -Detect -Path "<your project>"   # what applies' -ForegroundColor Yellow
  Write-Host '       TOOLS\Set-McpProfile.ps1 -Auto   -Path "<your project>"   # enable it' -ForegroundColor Yellow
  Write-Host '     Project scope is supported by Claude and Grok. Hermes uses the native code profile below.' -ForegroundColor Yellow
}
Write-Host '  7. Preamble: SOUL + AIO were wired into your agent files automatically.'
Write-Host '     Web UIs (ChatGPT/Gemini) have no instruction file - paste 3-PREAMBLES\MANUAL-PASTE.txt.'
Write-Host '  8. Hermes: run hermes --accept-hooks once if it asks for hook trust.'
Write-Host '  9. Leftovers from older versions are removed automatically each install.'
Write-Host '     See what would go without deleting: TOOLS\Clean-StaleState.ps1'
Write-Host '     Native MCP profiles when installed: hermes (core), code (codebase-memory), roblox (official Studio MCP), skyrim (houseCARL).'
Write-Host '     Audit/migrate: TOOLS\Migrate-HermesProfiles.ps1 [-Apply]'
Write-Host '     houseCARL costs ~41,768 tokens/turn at full size. The skyrim profile registers a'
Write-Host '     Lean subset (~31,369, -25%). Cheaper: -SkyrimToolset ReadOnly (~17,604, -58%).'
Write-Host ''
Write-Host 'AI usage: skills load automatically. Start with skyrim-memory + skyrim-tool-router.'
Write-Host 'Missing tools: run TOOLS\Ensure-Tools.ps1 or INSTALL-AIO.ps1 - do not invent paths.'
Write-Host ''

# Close the durable transcript only after the success banner/next steps have
# been written, then update the stable LAST log and clear any stale failure note.
if ($script:UabsTranscriptStarted) {
  try { Stop-Transcript | Out-Null } catch {}
  $script:UabsTranscriptStarted = $false
}
try { Copy-Item -LiteralPath $installLogPath -Destination $installLastPath -Force } catch {}
try { Remove-Item -LiteralPath $installFailedPath -Force -ErrorAction SilentlyContinue } catch {}
