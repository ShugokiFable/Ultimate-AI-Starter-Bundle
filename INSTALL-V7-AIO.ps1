<#
.SYNOPSIS
  Ultimate AI Starter Bundle V7 - All-In-One installer for skills, plugins, MCP tools, and houseCARL (MO2/Vortex).

.DESCRIPTION
  New users: run this once from the pack root.
  - Installs provider skills (Claude/Codex/Grok/Kimi/Hermes)
  - Installs bundled offline tools OR fetches GitHub latest
  - Disables Grok's inheritance of Claude Code hooks (measured 60s/turn) and
    of the Claude MCP import; wires Grok MCP natively, budgeting six configured
    servers when a plugin-provided server may also run
  - NEVER wraps Grok inference through Headroom for subscription/OIDC logins
    (that caused model "unknown" / 401). Opt-in wrap only with XAI_API_KEY.
  - Optional -WithExtras: code-review, obsidian-skills, claude-mem, playwright,
    firecrawl, perplexity MCP
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
  Tool components to install. Default: core set (not codeburn desktop).

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
  .\INSTALL-V7-AIO.ps1
  .\INSTALL-V7-AIO.ps1 -Providers Grok,Claude -Mode OnlineLatest
  .\INSTALL-V7-AIO.ps1 -WorkspaceRoot "D:\Modding\AI-Workspace"
#>
[CmdletBinding()]
param(
  [ValidateSet('Claude','Codex','Grok','Kimi','Hermes')]
  [string[]]$Providers = @('Claude','Codex','Grok','Kimi','Hermes'),
  [ValidateSet('BundledFirst','OnlineLatest','BundledOnly')]
  [string]$Mode = 'BundledFirst',
  [string[]]$Components = @('housecarl','spooky','codebase-memory','headroom','superpowers','ponytail','codeburn'),
  [string]$WorkspaceRoot = '',
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
  # Opt-in third-party extras (see BUNDLED-TOOLS\CATALOG.json scope_note on each):
  #   code-review-skill  obsidian-skills  claude-mem
  #   playwright-mcp     firecrawl-mcp    perplexity-mcp
  [switch]$WithExtras,
  # SOUL + AIO preamble wiring (v7.5.0). On by default: appends the marked
  # preamble block (SOUL.md + AIO-INSTRUCTION.txt) to every selected
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
  [switch]$SkipNativePlugins
)

if ($WithExtras) {
  $Components = @($Components) + @(
    'code-review-skill', 'obsidian-skills', 'claude-mem',
    'playwright-mcp', 'firecrawl-mcp', 'perplexity-mcp'
  ) | Select-Object -Unique
}

$ErrorActionPreference = 'Stop'
$PackRoot = $PSScriptRoot
if (-not (Test-Path (Join-Path $PackRoot 'BUNDLED-TOOLS\CATALOG.json'))) {
  throw "Run INSTALL-V7-AIO.ps1 from the V7 pack root (folder containing BUNDLED-TOOLS)."
}
. (Join-Path $PackRoot 'TOOLS\V7-Common.ps1')
$script:V5PackRoot = $PackRoot
$catalog = Get-V5Catalog
$offline = Join-Path $PackRoot 'BUNDLED-TOOLS\offline'
$cache = Join-Path $PackRoot 'BUNDLED-TOOLS\cache'
$plugins = Join-Path $PackRoot 'BUNDLED-TOOLS\plugins'
$log = [System.Collections.Generic.List[string]]::new()
function L($m){ [void]$log.Add("$(Get-Date -Format o) $m"); Write-Host $m }

function Invoke-V5Native {
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

Write-Host ""
Write-Host "=====================================================" -ForegroundColor Magenta
Write-Host " Ultimate AI Starter Bundle v7.7.12 - ALL-IN-ONE INSTALLER (keeps existing tool installs)" -ForegroundColor Magenta
Write-Host " Mode=$Mode  Providers=$($Providers -join ',')" -ForegroundColor Magenta
Write-Host "=====================================================" -ForegroundColor Magenta
Write-Host ""

# ---------- Runtimes ----------
if (-not $SkipRuntimes -and -not $SkillsOnly) {
  Write-V5Step "Runtime checks"
  $needNet9 = -not (Test-V5DotNetRuntime 'Microsoft\.NETCore\.App 9\.')
  $needAsp9 = -not (Test-V5DotNetRuntime 'Microsoft\.AspNetCore\.App 9\.')
  if ($needNet9) { Install-V5Winget @('Microsoft.DotNet.Runtime.9') | Out-Null } else { Write-V5Ok '.NET 9 runtime' }
  if ($needAsp9) { Install-V5Winget @('Microsoft.DotNet.AspNetCore.9') | Out-Null } else { Write-V5Ok 'ASP.NET Core 9' }
  if (-not (Get-Command python -EA SilentlyContinue) -and -not (Get-Command py -EA SilentlyContinue)) {
    Write-V5Warn 'Python not found (needed for Headroom) - attempting winget'
    Install-V5Winget @('Python.Python.3.12') | Out-Null
  } else { Write-V5Ok 'Python present' }
  if (-not (Get-Command node -EA SilentlyContinue)) {
    Write-V5Warn 'Node not found (optional CodeBurn) - attempting winget LTS'
    Install-V5Winget @('OpenJS.NodeJS.LTS') | Out-Null
  } else { Write-V5Ok "Node $(node -v)" }
  if (-not (Get-Command dotnet -EA SilentlyContinue)) {
    Write-V5Warn 'dotnet SDK/runtime host missing - Spooky CLI may need SDK 8'
  }
}

function Get-ComponentAssetPath {
  param($Comp)
  $name = $Comp.offline_asset
  if ($Mode -eq 'OnlineLatest') {
    # prefer cache newest matching
    if ($Comp.github) {
      try {
        $rel = Invoke-V5GitHubLatest -Owner $Comp.github.owner -Repo $Comp.github.repo
        $asset = $null
        if ($Comp.asset_match) { $asset = Get-V5ReleaseAsset -Release $rel -Patterns @($Comp.asset_match) }
        if ($asset) {
          $dest = Join-Path $cache $asset.name
          if (-not (Test-Path $dest) -or (Get-Item $dest).Length -lt 1000) {
            Save-V5Url -Url $asset.browser_download_url -OutFile $dest
          }
          return $dest
        }
        if ($Comp.kind -eq 'skills-plugin') {
          $dest = Join-Path $cache "$($Comp.id)-$($rel.tag_name).zip"
          if (-not (Test-Path $dest)) {
            $zipUrl = "https://github.com/$($Comp.github.owner)/$($Comp.github.repo)/archive/refs/tags/$($rel.tag_name).zip"
            try { Save-V5Url -Url $zipUrl -OutFile $dest } catch { Save-V5Url -Url $rel.zipball_url -OutFile $dest }
          }
          return $dest
        }
      } catch { Write-V5Warn "OnlineLatest failed for $($Comp.id): $($_.Exception.Message)" }
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
      $rel = Invoke-V5GitHubLatest -Owner $Comp.github.owner -Repo $Comp.github.repo
      $asset = $null
      if ($Comp.asset_match) { $asset = Get-V5ReleaseAsset -Release $rel -Patterns @($Comp.asset_match) }
      if ($asset) {
        $dest = Join-Path $cache $asset.name
        Save-V5Url -Url $asset.browser_download_url -OutFile $dest
        return $dest
      }
    } catch {}
  }
  return $null
}

# ---------- Skills ----------
if (-not $ToolsOnly) {
  Write-V5Step "Installing provider skills"
  $tailored = Join-Path $PackRoot '1-TAILORED-PROVIDER-TREES'
  foreach ($prov in $Providers) {
    $srcSkills = Join-Path $tailored "$prov\COPY-TO-SKILLS-DIRECTORY\skills"
    if (-not (Test-Path $srcSkills)) { Write-V5Bad "Missing $srcSkills"; continue }
    $providerHome = Get-V5ProviderHome -Provider $prov -Catalog $catalog
    $destSkills = Join-Path $providerHome 'skills'
    Write-Host "  $prov -> $destSkills"
    Copy-V5Robo -From $srcSkills -To $destSkills
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
        Copy-Item $srcInst (Join-Path $providerHome $pmeta.instructions) -Force
        Write-V5Ok ("{0} instructions -> {1}\{2}" -f $prov, $providerHome, $pmeta.instructions)
      }
    }
    Write-V5Ok "$prov skills installed"
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
      Write-V5Warn ('Starter settings: ' + $_.Exception.Message)
    }
  } else {
    Write-V5Warn 'TOOLS\Install-Provider-Starter-Settings.ps1 missing from pack'
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
# md5 matches the pack canonical (_V7-CANONICAL-SKILLS).
$nativePlugins = [ordered]@{}
if (-not $ToolsOnly -and -not $SkipNativePlugins) {
  Write-V5Step "Native plugins (superpowers + ponytail)"
  $canonicalSkills = Join-Path $PackRoot '_V7-CANONICAL-SKILLS'
  $backupRoot = Join-Path $env:LOCALAPPDATA 'Skyrim-AI-V5\backups'
  New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null

  function New-V5PluginStateEntry {
    param([string]$Status = 'fallback-skills', [string]$Reason = '')
    return [ordered]@{ native = $false; status = $Status; reason = $Reason; deduped = @(); skipped_modified = @(); skipped_kept = @() }
  }

  function Invoke-V5SkillDedupe {
    param([string]$Provider, [string]$PluginId, [string]$SkillsDir, $StateEntry)
    $names = Get-V5PluginOwnedSkillNames -PluginRoot (Join-Path $plugins $PluginId)
    if (-not $names -or $names.Count -eq 0) {
      $StateEntry.skipped_kept = @('bundled plugin tree has no skills dir')
      return
    }
    $res = Remove-V5PluginOwnedSkillCopies -Provider $Provider -SkillsDir $SkillsDir -Names $names -CanonicalRoot $canonicalSkills -BackupRoot $backupRoot -Log $log
    $StateEntry.deduped = @($res.removed)
    $StateEntry.skipped_modified = @($res.skipped_modified)
    $StateEntry.skipped_kept = @($res.skipped)
  }

  foreach ($prov in $Providers) {
    $providerHome = Get-V5ProviderHome -Provider $prov -Catalog $catalog
    $skillsDir = Join-Path $providerHome 'skills'
    $pstate = [ordered]@{ supported = $true; reason = ''; plugins = [ordered]@{} }
    $nativePlugins[$prov] = $pstate

    switch ($prov) {

      'Grok' {
        # ponytail ships no Grok manifest -> copied skills remain its path.
        $pstate.plugins['ponytail'] = New-V5PluginStateEntry -Status 'fallback-skills' -Reason 'ponytail has no Grok manifest; copied skills stay'
        $spEntry = New-V5PluginStateEntry
        $pstate.plugins['superpowers'] = $spEntry
        $grokExe = Join-Path $env:USERPROFILE '.grok\bin\grok.exe'
        if (-not (Test-Path -LiteralPath $grokExe -PathType Leaf)) {
          $gc = Get-Command grok -EA SilentlyContinue
          if ($gc) { $grokExe = $gc.Source } else { $grokExe = $null }
        }
        if (-not $grokExe) {
          $spEntry.status = 'fallback-skills'
          $spEntry.reason = 'grok CLI not found (neither ~/.grok/bin/grok.exe nor PATH); copied skills stay'
          Write-V5Warn 'Grok CLI not found - superpowers stays as copied skills'
          break
        }
        $pluginStage = Join-Path $env:LOCALAPPDATA 'Skyrim-AI-V5\plugins-src\superpowers'
        Copy-V5Robo -From (Join-Path $plugins 'superpowers') -To $pluginStage
        # Collapse marketplace + local-path clones BEFORE treating "already
        # native" as success. Two plugins named superpowers both own
        # systematic-debugging and Grok reports that as a skill error.
        $hits = @(Repair-V5GrokDuplicatePlugins -GrokExe $grokExe -PluginName 'superpowers')
        if ($hits.Count -ge 1) {
          $spEntry.native = $true
          $spEntry.status = 'already-native'
          Write-V5Ok ('Grok: superpowers already native (' + $hits[0].repo_key + ')')
        } else {
          Write-Host '  grok plugin install superpowers --trust'
          [void](Invoke-V5Native $grokExe @('plugin', 'install', 'superpowers', '--trust'))
          $hits = @(Get-V5GrokPluginList -GrokExe $grokExe | Where-Object { $_.name -eq 'superpowers' })
          if ($hits.Count -eq 0) {
            Write-Host ('  grok plugin install "' + $pluginStage + '" --trust')
            [void](Invoke-V5Native $grokExe @('plugin', 'install', $pluginStage, '--trust'))
            $hits = @(Get-V5GrokPluginList -GrokExe $grokExe | Where-Object { $_.name -eq 'superpowers' })
          }
          if ($hits.Count -gt 1) {
            $hits = @(Repair-V5GrokDuplicatePlugins -GrokExe $grokExe -PluginName 'superpowers')
          }
          if ($hits.Count -ge 1) {
            $spEntry.native = $true
            $spEntry.status = 'installed'
            Write-V5Ok ('Grok: superpowers installed native (' + $hits[0].repo_key + ')')
          } else {
            $spEntry.status = 'fallback-skills'
            $spEntry.reason = 'grok plugin install did not take; copied skills stay'
            Write-V5Warn 'Grok: superpowers native install failed - copied skills stay'
          }
        }
        if ($spEntry.native) {
          # Keep the copies. Grok chats and slash commands load
          # ~/.grok/skills/<name>/SKILL.md. Dedupe left that path missing, and
          # the TUI reports the skill as failed with no reason
          # (verification-before-completion, systematic-debugging, ...).
          Write-V5Ok 'Grok: superpowers copies stay under ~/.grok/skills (TUI loads that path; plugin path is opaque)'
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
            $pstate.plugins[$pluginId] = New-V5PluginStateEntry -Status 'fallback-skills' -Reason 'hermes CLI not found; copied skills stay'
          }
          Write-V5Warn 'Hermes CLI not found - plugins stay as copied skills'
          break
        }
        $gitCmd = Get-Command git -EA SilentlyContinue
        # The scanner refuses both bundled plugins (false-positive 'traversal'
        # findings; --force does not override) - disarm scan-at-install first.
        $pstate.scan_on_install_fix = Set-V5HermesPluginScanOff -ConfigPath (Join-Path $providerHome 'config.yaml')
        $newInstalls = 0
        foreach ($pluginId in @('superpowers', 'ponytail')) {
          $hEntry = New-V5PluginStateEntry
          $pstate.plugins[$pluginId] = $hEntry
          # Offline bridge: Hermes rejects plain local paths, so stage the
          # bundled tree as a local git repo and hand Hermes a file:/// URL.
          $pluginStage = Join-Path $env:LOCALAPPDATA ('Skyrim-AI-V5\hermes-plugin-src\' + $pluginId)
          if (-not (Test-Path -LiteralPath (Join-Path $pluginStage 'skills') -PathType Container)) {
            Copy-V5Robo -From (Join-Path $plugins $pluginId) -To $pluginStage
          }
          if (-not (Test-Path -LiteralPath (Join-Path $pluginStage '.git') -PathType Container)) {
            if (-not $gitCmd) {
              $hEntry.status = 'fallback-skills'
              $hEntry.reason = 'git not found - cannot build the local git bridge Hermes requires; copied skills stay'
              Write-V5Warn ('Hermes: git missing - cannot stage ' + $pluginId + ' as a git repo; copied skills stay')
              continue
            }
            [void](Invoke-V5Native 'git' @('-C', $pluginStage, 'init'))
            [void](Invoke-V5Native 'git' @('-C', $pluginStage, 'add', '-A'))
            if (-not (Invoke-V5Native 'git' @('-C', $pluginStage, '-c', 'user.email=bundle@local', '-c', 'user.name=bundle', 'commit', '-m', 'bundled pin'))) {
              $hEntry.status = 'fallback-skills'
              $hEntry.reason = 'git init/commit of the offline plugin bridge failed; copied skills stay'
              Write-V5Warn ('Hermes: git commit failed for ' + $pluginStage + ' - copied skills stay')
              continue
            }
          } else {
            # Bridge exists: refresh files from the pack and commit if the
            # bundle changed (safely corrective; a no-op when nothing changed).
            Copy-V5Robo -From (Join-Path $plugins $pluginId) -To $pluginStage
            $dirty = Get-V5NativeOutput -Exe 'git' -CmdArgs @('-C', $pluginStage, 'status', '--porcelain')
            if ($dirty -and $dirty.Trim()) {
              [void](Invoke-V5Native 'git' @('-C', $pluginStage, 'add', '-A'))
              [void](Invoke-V5Native 'git' @('-C', $pluginStage, '-c', 'user.email=bundle@local', '-c', 'user.name=bundle', 'commit', '-m', 'bundled pin refresh'))
            }
          }
          $fileUrl = 'file:///' + ($pluginStage -replace '\\', '/')
          $listed = Get-V5NativeOutput -Exe $hermesExe -CmdArgs @('plugins', 'list')
          if ($listed -match $pluginId) {
            $hEntry.native = $true
            $hEntry.status = 'already-native'
            Write-V5Ok ('Hermes: ' + $pluginId + ' already native')
          } else {
            Write-Host ('  hermes plugins install "' + $fileUrl + '" --enable')
            [void](Invoke-V5Native $hermesExe @('plugins', 'install', $fileUrl, '--enable'))
            $listed = Get-V5NativeOutput -Exe $hermesExe -CmdArgs @('plugins', 'list')
            if ($listed -match $pluginId) {
              $hEntry.native = $true
              $hEntry.status = 'installed'
              $newInstalls++
              Write-V5Ok ('Hermes: ' + $pluginId + ' installed native')
            } else {
              $hEntry.status = 'fallback-skills'
              $hEntry.reason = 'hermes plugins install did not take; copied skills stay'
              Write-V5Warn ('Hermes: ' + $pluginId + ' native install failed - copied skills stay')
            }
          }
          if ($hEntry.native) {
            # Keep the copies. Hermes derives /skill-name slash commands and
            # desktop autofill from the skills dir (scan_skill_commands scans
            # SKILLS_DIR, not plugin registrations). Dedupe left that path
            # missing and /using-superpowers etc. stopped autocompleting -
            # same failure class as Grok's TUI (v7.7.5).
            Write-V5Ok ('Hermes: ' + $pluginId + ' copies stay under ' + $skillsDir + ' (slash commands load that path; plugin path is opaque)')
          }
        }
        # Restart the gateway ONLY when a plugin actually changed hands and the
        # gateway is already running - never start a process the user did not
        # have running.
        if ($newInstalls -gt 0) {
          $gw = Get-V5NativeOutput -Exe $hermesExe -CmdArgs @('gateway', 'status')
          if ($gw -match '(?i)running' -and $gw -notmatch '(?i)not running') {
            [void](Invoke-V5Native $hermesExe @('gateway', 'restart'))
            Write-V5Ok 'Hermes gateway restarted (was running; picks up the new plugins)'
          } else {
            Write-V5Ok 'Hermes gateway not running - left stopped'
          }
        }
        # Put the scanner BACK even when plugins were already native. A
        # previous run used to skip restore when newInstalls was 0, so
        # scan_on_install: false leaked into the live config forever.
        $pstate.scan_on_install_restore = Restore-V5HermesPluginScan `
          -ConfigPath (Join-Path $providerHome 'config.yaml') `
          -State $pstate.scan_on_install_fix
      }

      'Codex' {
        $cfg = Join-Path $providerHome 'config.toml'
        $mp = Join-Path $env:LOCALAPPDATA 'Skyrim-AI-V5\codex-marketplace'
        # 1) stage the bundled superpowers tree into the local marketplace
        $mpSp = Join-Path $mp 'superpowers'
        if (Test-Path -LiteralPath (Join-Path $mpSp 'skills') -PathType Container) {
          Write-V5Ok 'Codex marketplace: superpowers already staged'
        } else {
          Copy-V5Robo -From (Join-Path $plugins 'superpowers') -To $mpSp
          Write-V5Ok ('Codex marketplace: staged superpowers -> ' + $mpSp)
        }
        # 2) manifest entry (Install-Completeness-Gate rebuilds this whole
        #    marketplace from the canonical tree later in this run; this keeps
        #    an already-materialised marketplace coherent in the meantime)
        $manifest = Join-Path $mp '.claude-plugin\marketplace.json'
        if (Test-Path -LiteralPath $manifest -PathType Leaf) {
          if (Add-V5MarketplacePluginEntry -ManifestPath $manifest -EntryName 'superpowers' -EntryDescription 'Agentic skills framework: brainstorming, TDD, systematic debugging, plans, code review.' -EntrySource './superpowers' -EntryCategory 'productivity') {
            Write-V5Ok 'Codex marketplace manifest: superpowers entry present'
          }
        } else {
          New-Item -ItemType Directory -Force -Path (Split-Path $manifest -Parent) | Out-Null
          $mini = @(
            '{'
            '  "$schema": "https://anthropic.com/claude-code/marketplace.schema.json",'
            '  "name": "ultimate-bundle",'
            '  "description": "Ultimate AI Starter Bundle - controls that refuse incomplete or assumed work.",'
            '  "owner": {'
            '    "name": "Ultimate AI Starter Bundle",'
            '    "url": "https://github.com/ShugokiFable/Ultimate-AI-Starter-Bundle"'
            '  },'
            '  "plugins": ['
            '    {'
            '      "name": "superpowers",'
            '      "description": "Agentic skills framework: brainstorming, TDD, systematic debugging, plans, code review.",'
            '      "source": "./superpowers",'
            '      "category": "productivity"'
            '    }'
            '  ]'
            '}'
          ) -join "`n"
          $encM = New-Object System.Text.UTF8Encoding($false)
          [IO.File]::WriteAllText($manifest, ($mini + "`n"), $encM)
          Write-V5Warn 'Codex marketplace manifest did not exist yet - created a minimal one (Install-Completeness-Gate rebuilds the full marketplace later in this run)'
        }
        # 3) config.toml: [plugins."superpowers@ultimate-bundle"] enabled = true
        $toml = ''
        if (Test-Path -LiteralPath $cfg -PathType Leaf) { $toml = [IO.File]::ReadAllText($cfg) }
        $spEntry = New-V5PluginStateEntry
        $pstate.plugins['superpowers'] = $spEntry
        # Append ONLY when the exact section header is absent - appending a
        # duplicate table header would make config.toml unparseable, and an
        # existing-but-disabled section is the user's deliberate choice.
        $spSectionPresent = ($toml -match '(?m)^\[plugins\."superpowers@ultimate-bundle"\]')
        if ($spSectionPresent -and (Test-V5TomlPluginEnabled -Content $toml -HeaderPrefix 'plugins."superpowers@ultimate-bundle"')) {
          $spEntry.native = $true
          $spEntry.status = 'already-native'
          Write-V5Ok 'Codex: superpowers@ultimate-bundle already enabled in config.toml'
        } elseif ($spSectionPresent) {
          $spEntry.status = 'disabled-in-config'
          $spEntry.reason = 'config.toml section exists but enabled is not true - left as-is; copied skills stay'
          Write-V5Warn 'Codex: superpowers@ultimate-bundle present but not enabled - left as the user set it'
        } else {
          if (Test-Path -LiteralPath $cfg -PathType Leaf) {
            Copy-Item -LiteralPath $cfg -Destination ($cfg + '.bak-' + (Get-Date -Format 'yyyyMMdd-HHmmss')) -Force
          } else {
            New-Item -ItemType Directory -Force -Path $providerHome | Out-Null
          }
          $add = "`n[plugins.`"superpowers@ultimate-bundle`"]`nenabled = true`n"
          $newToml = $toml + $add
          if (-not $toml) { $newToml = $add.TrimStart("`n") }
          $encT = New-Object System.Text.UTF8Encoding($false)
          [IO.File]::WriteAllText($cfg, $newToml, $encT)
          # Any config.toml write gets a parse check when python is around.
          $pyExe = $null
          foreach ($cand in @('python', 'py', 'python3')) {
            $pyc = Get-Command $cand -EA SilentlyContinue
            if ($pyc) { $pyExe = $pyc.Source; break }
          }
          if ($pyExe) {
            if (Invoke-V5Native $pyExe @('-c', "import tomllib,sys; tomllib.load(open(sys.argv[1],'rb'))", $cfg)) {
              Write-V5Ok 'Codex config.toml re-parsed OK (python tomllib)'
            } else {
              Write-V5Warn 'Codex config.toml written but tomllib validation failed (or python < 3.11) - original backed up beside it as config.toml.bak-*'
            }
          } else {
            Write-V5Warn 'python not found - skipped TOML validation of Codex config.toml'
          }
          $spEntry.native = $true
          $spEntry.status = 'enabled-in-config'
          Write-V5Ok 'Codex: enabled superpowers@ultimate-bundle in config.toml (picked up on next app launch)'
        }
        if ($spEntry.native) {
          Invoke-V5SkillDedupe -Provider 'Codex' -PluginId 'superpowers' -SkillsDir $skillsDir -StateEntry $spEntry
        }
        # 4) ponytail: detect an existing native enablement (the user's own
        #    git-marketplace install) - do NOT reinstall it.
        $ptEntry = New-V5PluginStateEntry
        $pstate.plugins['ponytail'] = $ptEntry
        $tomlNow = ''
        if (Test-Path -LiteralPath $cfg -PathType Leaf) { $tomlNow = [IO.File]::ReadAllText($cfg) }
        if (Test-V5TomlPluginEnabled -Content $tomlNow -HeaderPrefix 'plugins."ponytail@') {
          $ptEntry.native = $true
          $ptEntry.status = 'already-native'
          Write-V5Ok 'Codex: ponytail natively enabled (existing marketplace install) - not reinstalling'
          Invoke-V5SkillDedupe -Provider 'Codex' -PluginId 'ponytail' -SkillsDir $skillsDir -StateEntry $ptEntry
        } else {
          $ptEntry.status = 'fallback-skills'
          $ptEntry.reason = 'no enabled ponytail plugin section in config.toml; copied skills stay'
          Write-V5Warn 'Codex: ponytail not natively enabled - copied skills stay'
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
          $cEntry = New-V5PluginStateEntry
          $pstate.plugins[$pluginId] = $cEntry
          $srcRoot = Join-Path $plugins $pluginId
          $mkName = Get-V5ClaudeMarketplaceName -PluginRoot $srcRoot
          $cacheHit = $false
          if ($mkName) {
            $cachePath = Join-Path $providerHome ('plugins\cache\' + $mkName + '\' + $pluginId)
            $cacheHit = Test-Path -LiteralPath $cachePath -PathType Container
          }
          if ($cacheHit) {
            $cEntry.native = $true
            $cEntry.status = 'already-native'
            Write-V5Ok ('Claude: ' + $pluginId + ' already native (' + $mkName + ') - deduping its copied skills')
            Invoke-V5SkillDedupe -Provider 'Claude' -PluginId $pluginId -SkillsDir $skillsDir -StateEntry $cEntry
            continue
          }
          if (-not $mkName) {
            $cEntry.status = 'fallback-skills'
            $cEntry.reason = 'bundled tree has no .claude-plugin\marketplace.json'
            Write-V5Warn ('Claude: ' + $pluginId + ' has no Claude marketplace in the bundle - copied skills stay')
            continue
          }
          if (-not $claudeCli) {
            $cEntry.status = 'fallback-skills'
            $cEntry.reason = 'claude CLI not on PATH; copied skills stay'
            Write-V5Warn ('Claude: ' + $pluginId + ' not native and no claude CLI on PATH - copied skills stay. To wire it natively:')
            Write-Host ('    claude plugin marketplace add "' + $srcRoot + '"')
            Write-Host ('    claude plugin install ' + $pluginId + '@' + $mkName + ' --scope user')
            continue
          }
          try {
            & claude plugin marketplace add "$srcRoot" 2>&1 | Out-Null
            & claude plugin install ("$pluginId@$mkName") --scope user 2>&1 | Out-Null
            $cachePath = Join-Path $providerHome ('plugins\cache\' + $mkName + '\' + $pluginId)
            if (Test-Path -LiteralPath $cachePath -PathType Container) {
              $cEntry.native = $true
              $cEntry.status = 'installed'
              Write-V5Ok ('Claude: native plugin installed - ' + $pluginId + '@' + $mkName)
              Invoke-V5SkillDedupe -Provider 'Claude' -PluginId $pluginId -SkillsDir $skillsDir -StateEntry $cEntry
            } else {
              # The CLI returned without producing a cache entry. Do not
              # report success on an exit code alone - the cache directory is
              # the only proof Claude actually loaded it.
              $cEntry.status = 'failed'
              $cEntry.reason = 'claude plugin install left no plugins\cache entry'
              Write-V5Warn ('Claude: ' + $pluginId + ' install did not take - copied skills stay')
            }
          } catch {
            $cEntry.status = 'failed'
            $cEntry.reason = $_.Exception.Message
            Write-V5Warn ('Claude: ' + $pluginId + ' install failed (' + $_.Exception.Message + ') - copied skills stay')
          }
        }
        # Retire the old UNREGISTERED plugins\v5-bundled\<id> drop - dead
        # weight Claude never loaded. Move to the backup dir, never delete.
        $moved = @()
        foreach ($pluginId in @('superpowers', 'ponytail')) {
          $dead = Join-Path $providerHome ('plugins\v5-bundled\' + $pluginId)
          if (Test-Path -LiteralPath $dead -PathType Container) {
            $mdest = Join-Path $backupRoot ('v5-bundled-cleanup-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '\' + $pluginId)
            Copy-V5Robo -From $dead -To $mdest
            Remove-Item -LiteralPath $dead -Recurse -Force
            $moved += $mdest
            Write-V5Ok ('Claude: moved dead drop ' + $dead + ' -> ' + $mdest)
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
          $kEntry = New-V5PluginStateEntry
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
            Write-V5Ok ('Kimi: ' + $pluginId + ' has no Kimi adapter - copied skills stay')
            continue
          }
          $kr = Install-V5KimiPlugin -KimiHome $providerHome -PluginId $pluginId -SourceRoot $src
          if ($kr.ok) {
            $kEntry.status = 'installed'
            $kEntry.native = $true
            $kEntry.root = $kr.root
            Write-V5Ok ('Kimi: native plugin installed - ' + $pluginId + ' (' + $kr.root + ')')
            Invoke-V5SkillDedupe -Provider 'Kimi' -PluginId $pluginId -SkillsDir $skillsDir -StateEntry $kEntry
          } else {
            $kEntry.status = 'failed'
            $kEntry.reason = $kr.reason
            Write-V5Warn ('Kimi: ' + $pluginId + ' native install failed (' + $kr.reason + ') - copied skills stay')
          }
        }
      }
    }
  }
}

# ---------- AI preamble: SOUL + AIO for every agent (v7.5.0) ----------
# Wires the same preamble into every selected provider so a fresh machine
# behaves like the operator's own setup. Idempotent: re-running replaces the
# marked block instead of stacking copies; every write gets a .bak first.
if (-not $ToolsOnly -and -not $SkipPreamble) {
  Write-V5Step "SOUL + AIO preamble wiring"
  $preDir = Join-Path $PackRoot '3-PREAMBLES'
  # One soul source for every provider. Until v7.6.2 there were two files -
  # SOUL.md opened with 'You are Hermes Agent' and SOUL-UNIVERSAL.md was the
  # de-branded copy. v7.6.0 genericised SOUL.md itself (a provider identity
  # injected into four other providers is what made Kimi refuse its own
  # unrestraint block), which left the two files identical. Keeping a second
  # copy only invites them to drift apart again.
  $soulF = Join-Path $preDir 'SOUL.md'
  $aioF  = Join-Path $PackRoot 'AIO-INSTRUCTION.txt'
  foreach ($prov in $Providers) {
    if ($prov -eq 'Hermes') {
      # Hermes reads SOUL.md from its home - copy the verbatim soul
      $hhome = Get-V5ProviderHome -Provider Hermes -Catalog $catalog
      $hSoul = Join-Path $hhome 'SOUL.md'
      if (Test-Path -LiteralPath $hSoul) {
        $same = (Get-FileHash -LiteralPath $hSoul -Algorithm SHA256).Hash -eq
                (Get-FileHash -LiteralPath $soulF -Algorithm SHA256).Hash
        if (-not $same) {
          Copy-Item -LiteralPath $hSoul -Destination ($hSoul + '.before-soul-' + (Get-Date -Format 'yyyyMMdd-HHmmssfff') + '.bak') -Force
          Copy-Item -LiteralPath $soulF -Destination $hSoul -Force
          Write-V5Ok ("Hermes soul updated: " + $hSoul)
        } else {
          Write-V5Ok ('Hermes soul already current: ' + $hSoul)
        }
      } else {
        New-Item -ItemType Directory -Force -Path $hhome | Out-Null
        Copy-Item -LiteralPath $soulF -Destination $hSoul -Force
        Write-V5Ok ("Hermes soul installed: " + $hSoul)
      }
      continue
    }
    $pmeta = $catalog.providers.$prov
    $instName = $pmeta.instructions
    if (-not $instName) { $instName = 'AGENTS.md' }
    $target = Join-Path (Get-V5ProviderHome -Provider $prov -Catalog $catalog) $instName
    if (-not (Test-Path -LiteralPath $soulF) -or -not (Test-Path -LiteralPath $aioF)) {
      Write-V5Warn ("$prov preamble skipped: 3-PREAMBLES or AIO-INSTRUCTION.txt missing")
      continue
    }
    try {
      Install-V5PreambleBlock -Path $target -SoulFile $soulF -AioFile $aioF -Force:$ForcePreamble
    } catch {
      Write-V5Warn ("$prov preamble failed: " + $_.Exception.Message)
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
  Write-V5Step "Workspace files -> $WorkspaceRoot"
  New-Item -ItemType Directory -Force -Path $WorkspaceRoot | Out-Null
  $ws = Join-Path $PackRoot 'COPY-TO-YOUR-WORKSPACE'
  Copy-Item (Join-Path $ws 'AGENTS.md') (Join-Path $WorkspaceRoot 'AGENTS.md') -Force -EA SilentlyContinue
  Copy-Item (Join-Path $ws 'CLAUDE.md') (Join-Path $WorkspaceRoot 'CLAUDE.md') -Force -EA SilentlyContinue
  $tpl = Join-Path $ws '_PROJECT-TEMPLATE'
  if (Test-Path $tpl) { Copy-V5Robo -From $tpl -To (Join-Path $WorkspaceRoot '_PROJECT-TEMPLATE') }
  Write-V5Ok "Workspace template copied"
}

# ---------- Tools ----------
$installed = [ordered]@{}
if (-not $SkillsOnly) {
  foreach ($id in $Components) {
    $comp = $catalog.components | Where-Object { $_.id -eq $id } | Select-Object -First 1
    if (-not $comp) { Write-V5Warn "skip unknown $id"; continue }
    Write-V5Step "Component: $($comp.name) [$id]"

    switch ($comp.install) {
      'manual-user-product' {
        Write-V5Warn $comp.note
        $installed[$id] = @{ status='manual'; note=$comp.note }
      }
      'npx-or-npm' {
        if (Get-Command npm -EA SilentlyContinue) {
          try {
            if (Invoke-V5Native 'npm' @('install','-g', $comp.npm_spec)) {
              $installed[$id] = @{ status='npm-global'; spec=$comp.npm_spec }
              Write-V5Ok "npm -g $($comp.npm_spec)"
            } else { throw "npm exited with code $LASTEXITCODE" }
          } catch {
            Write-V5Warn "npm global failed - users can run: npx $($comp.npm_spec)"
            $installed[$id] = @{ status='npx-fallback' }
          }
        } else {
          Write-V5Warn "Node/npm missing - CodeBurn via npx when Node is installed"
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
                  try { & $c @probe *> $null; $py = $c; break } catch { }
                }
              }
              if (-not $py) {
                Write-V5Bad 'No python with pip found - install Python 3.12 and re-run'
                $installed[$id] = @{ status = 'failed' }
                continue
              }
              $asset = Get-ComponentAssetPath -Comp $comp
              $ok = $false
              if ($asset -and $asset.EndsWith('.whl') -and $py) {
                Write-Host "  pip install $asset"
                $env:PYTHONPATH = ''
                # Invoke-V5Native keeps pip's stderr ("already satisfied", the
                # pip-version notice) from surfacing as a NativeCommandError.
                if ($py -eq 'py') { $ok = Invoke-V5Native 'py' (@('-3','-m','pip','install','--user',$asset)) }
                else { $ok = Invoke-V5Native $py @('-m','pip','install','--user',$asset) }
              }
              if (-not $ok -and $py) {
                $spec = $comp.pip_spec
                $env:PYTHONPATH = ''
                if ($py -eq 'py') { $ok = Invoke-V5Native 'py' (@('-3','-m','pip','install','--user',$spec)) }
                else { $ok = Invoke-V5Native $py @('-m','pip','install','--user',$spec) }
              }
        if ($ok) {
          $hr = $null
          try { $hr = (Get-Command headroom -EA SilentlyContinue).Source } catch {}
          if ($hr) { Set-V5UserEnv 'HEADROOM_CMD' $hr }
          $installed[$id] = @{ status='pip'; headroom=$hr }
          Write-V5Ok 'Headroom installed'
        } else {
          Write-V5Bad 'Headroom install failed (need Python)'
          $installed[$id] = @{ status='failed' }
        }
      }
      'skills-copy' {
        # The plugin tree is now installed NATIVE per provider by the "Native
        # plugins" section above (Grok/Hermes/Codex real installs, Claude
        # detect-only, Kimi unsupported). The old unregistered
        # plugins\v5-bundled\<id> drop for Claude was dead weight - Claude
        # never loaded it - so it is gone; the native section moves any
        # existing drop to the backup dir instead of deleting it.
        $installed[$id] = @{ status='native-or-skills' }
        Write-V5Ok "$id handled by the native-plugin section (fallback: copied skills)"
      }
      'zip-extract' {
        $asset = Get-ComponentAssetPath -Comp $comp
        if (-not $asset) {
          Write-V5Bad "No asset for $id - run TOOLS\Update-From-GitHub.ps1 -$id or check network"
          $installed[$id] = @{ status='missing-asset' }
          continue
        }
        $target = Expand-V5EnvPath $comp.target_dir
        $stage = Join-Path $env:TEMP "v5-extract-$id-$(Get-Random)"
        New-Item -ItemType Directory -Force -Path $stage | Out-Null
        try {
          Expand-V5Zip -Zip $asset -Dest $stage
          $rootExtract = Resolve-V5SingleRoot $stage
          # houseCARL zip layout: may contain housecarl\server or server
          if ($id -eq 'housecarl') {
            # NEVER overwrite a live/working houseCARL install. Respect an
            # existing HOUSECARL_MCP (user-curated root) instead.
            $existingMcp = $env:HOUSECARL_MCP
            if ($existingMcp -and (Test-Path $existingMcp)) {
              $existingRoot = if ($env:HOUSECARL_ROOT -and (Test-Path $env:HOUSECARL_ROOT)) { $env:HOUSECARL_ROOT } else { Split-Path (Split-Path $existingMcp -Parent) -Parent }
              Set-V5UserEnv 'HOUSECARL_MCP' $existingMcp
              Set-V5UserEnv 'HOUSECARL_ROOT' $existingRoot
              $installed[$id] = @{ status='kept-existing'; mcp=$existingMcp; root=$existingRoot }
              Write-V5Ok ("houseCARL kept existing (no overwrite): " + $existingMcp)
            }
            else {
              $mcp = Find-V5FileUnder $rootExtract 'housecarl-mcp.exe' 8
              if (-not $mcp) { throw "housecarl-mcp.exe not in zip" }
              $serverDir = Split-Path $mcp -Parent
              $productRoot = Split-Path $serverDir -Parent
              # Install to LOCALAPPDATA\houseCARL
              New-Item -ItemType Directory -Force -Path $target | Out-Null
              Copy-V5Robo -From $productRoot -To $target
              # If setup exe present at outer folder
              $setup = Find-V5FileUnder $rootExtract 'houseCARL-Setup.exe' 4
              if ($setup) {
                Copy-Item $setup (Join-Path $target 'houseCARL-Setup.exe') -Force
              }
              $mcpFinal = Join-Path $target 'server\housecarl-mcp.exe'
              if (-not (Test-Path $mcpFinal)) { $mcpFinal = Find-V5FileUnder $target 'housecarl-mcp.exe' 5 }
              Set-V5UserEnv 'HOUSECARL_MCP' $mcpFinal
              Set-V5UserEnv 'HOUSECARL_ROOT' $target
              $installed[$id] = @{ status='installed'; mcp=$mcpFinal; root=$target }
              Write-V5Ok "houseCARL -> $target"
            }
          }
          elseif ($id -eq 'codebase-memory') {
            # NEVER overwrite a live/working codebase-memory install.
            # Prefer existing Programs install; only extract when missing.
            $existing = Find-V5CodebaseMemoryExe
            if ($existing) {
              Set-V5UserEnv 'CODEBASE_MEMORY_MCP' $existing
              $installed[$id] = @{ status = 'kept-existing'; exe = $existing }
              Write-V5Ok ("codebase-memory kept existing (no overwrite): " + $existing)
            }
            else {
              New-Item -ItemType Directory -Force -Path $target | Out-Null
              $destExe = Join-Path $target 'codebase-memory-mcp.exe'
              if ((Test-Path -LiteralPath $destExe) -and (Test-V5FileLocked $destExe)) {
                Write-V5Warn 'codebase-memory exe is locked (MCP running) - skip binary copy'
                Set-V5UserEnv 'CODEBASE_MEMORY_MCP' $destExe
                $installed[$id] = @{ status = 'skipped-locked'; exe = $destExe }
              }
              else {
                Copy-V5RoboSafe -From $rootExtract -To $target -CriticalFiles @('codebase-memory-mcp.exe')
                $exe = Join-Path $target 'codebase-memory-mcp.exe'
                if (-not (Test-Path $exe)) { $exe = Find-V5FileUnder $target 'codebase-memory-mcp.exe' 4 }
                if (-not $exe) { throw 'codebase-memory-mcp.exe missing after extract' }
                Set-V5UserEnv 'CODEBASE_MEMORY_MCP' $exe
                $installed[$id] = @{ status = 'installed'; exe = $exe }
                Write-V5Ok ("codebase-memory -> " + $exe)
              }
            }
          }
          elseif ($id -eq 'spooky') {
            # NEVER overwrite a live/working Spooky install. Respect an
            # existing SPOOKY_AUTOMOD_ROOT (user-curated root) instead.
            $existingRoot = $env:SPOOKY_AUTOMOD_ROOT
            if ($existingRoot -and (Test-Path (Join-Path $existingRoot 'SpookysAutomod.sln'))) {
              Set-V5UserEnv 'SPOOKY_AUTOMOD_ROOT' $existingRoot
              $installed[$id] = @{ status='kept-existing'; root=$existingRoot }
              Write-V5Ok ("Spooky kept existing (no overwrite): " + $existingRoot)
            }
            else {
              New-Item -ItemType Directory -Force -Path $target | Out-Null
              Copy-V5Robo -From $rootExtract -To $target
              # find sln
              $sln = Find-V5FileUnder $target 'SpookysAutomod.sln' 5
              $toolkitRoot = if ($sln) { Split-Path $sln -Parent } else { $target }
              # nested spookys-automod-toolkit folder
              $inner = Join-Path $toolkitRoot 'spookys-automod-toolkit'
              if (Test-Path (Join-Path $inner 'SpookysAutomod.sln')) { $toolkitRoot = $inner }
              Set-V5UserEnv 'SPOOKY_AUTOMOD_ROOT' $toolkitRoot
              $installed[$id] = @{ status='installed'; root=$toolkitRoot }
              Write-V5Ok "Spooky -> $toolkitRoot"
              Write-V5Warn "Optional: run SpookysAutomodSetup.exe inside the toolkit folder for headers/compiler"
            }
          }
          else {
            Copy-V5Robo -From $rootExtract -To $target
            $installed[$id] = @{ status='installed'; root=$target }
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
        if (-not $wanted) { Write-V5Warn "${id}: no selected provider wants it"; $installed[$id] = @{ status='skipped' }; continue }
        $stage = Join-Path $env:TEMP "v5-skillsgit-$id-$(Get-Random)"
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
            Save-V5Url -Url $u -OutFile $zip
            Expand-V5Zip -Zip $zip -Dest $stage
            $stage = Resolve-V5SingleRoot $stage
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
          foreach ($prov in $wanted) {
            $destRoot = Join-Path (Get-V5ProviderHome -Provider $prov -Catalog $catalog) 'skills'
            foreach ($pair in $pairs) {
              Copy-V5Robo -From $pair.path -To (Join-Path $destRoot $pair.name)
            }
            Write-V5Ok ("$id -> $prov ({0} skill(s))" -f $pairs.Count)
          }
          $installed[$id] = @{ status='installed'; skills=@($pairs.name); providers=$wanted }
          if ($comp.scope_note) { Write-V5Warn ("scope: " + $comp.scope_note) }
        } catch {
          Write-V5Bad ("$id failed: " + $_.Exception.Message)
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
            Write-V5Warn "$id is Claude Code ONLY - skipped (not for Grok/Codex/Kimi/Hermes)"
            $installed[$id] = @{ status='skipped-claude-only' }
            continue
          }
        }
        if ($Providers -notcontains 'Claude') { Write-V5Warn "$id is Claude Code only - skipped"; $installed[$id] = @{ status='skipped' }; continue }
        # claude-mem worker needs Bun (bun:sqlite). Without it Claude shows red MCP errors.
        if ($id -eq 'claude-mem') {
          $bunOk = $false
          try { $bunOk = [bool](Get-Command bun -EA SilentlyContinue) } catch {}
          if (-not $bunOk -and $env:BUN -and (Test-Path -LiteralPath $env:BUN)) { $bunOk = $true }
          if (-not $bunOk) {
            $bunUser = Join-Path $env:USERPROFILE '.bun\bin\bun.exe'
            if (Test-Path -LiteralPath $bunUser) { $bunOk = $true; $env:PATH = ((Join-Path $env:USERPROFILE '.bun\bin') + ';' + $env:PATH) }
          }
          if (-not $bunOk) {
            Write-V5Warn 'claude-mem requires Bun (https://bun.sh). Install Bun, open a NEW shell, then re-run -WithExtras.'
            Write-V5Warn 'Without Bun the plugin installs but MCP tools go red (worker cannot start).'
            $installed[$id] = @{ status='skipped-no-bun'; note='install Bun then re-run' }
            continue
          } else {
            Write-V5Ok 'Bun present (required for claude-mem worker)'
          }
        }
        if (-not (Get-Command npx -EA SilentlyContinue)) {
          Write-V5Warn "$id needs Node/npx. Install Node, then: npx $($comp.npx_install -join ' ')"
          $installed[$id] = @{ status='skipped-no-node' }
          continue
        }
        try {
          if (-not (Invoke-V5Native 'npx' @($comp.npx_install))) { throw "npx exited with code $LASTEXITCODE" }
          $installed[$id] = @{ status='installed'; via='npx' }
          Write-V5Ok "$id installed (restart Claude Code to load the plugin)"
          if ($comp.scope_note) { Write-V5Warn ("scope: " + $comp.scope_note) }
        } catch {
          Write-V5Warn ("$id via npx failed. In Claude Code run: /plugin marketplace add $($comp.marketplace[0])  then  /plugin install $($comp.marketplace[1])")
          $installed[$id] = @{ status='manual'; error=$_.Exception.Message }
        }
      }

      # ---- extras: npx-launched MCP servers --------------------------------
      # Nothing is installed; npx resolves the package on first launch. We only
      # write the server block into each provider's MCP config.
      'mcp-npx' {
        $wanted = @($Providers | Where-Object { $comp.providers -contains $_ })
        if (-not $wanted) { Write-V5Warn "${id}: not wanted by any selected provider"; $installed[$id] = @{ status='skipped' }; continue }
        if (-not (Get-Command npx -EA SilentlyContinue)) {
          Write-V5Warn "$id needs Node/npx - skipping registration so we do not write a broken MCP entry"
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
          } elseif ($comp.api_key_optional) {
            Write-V5Warn "${id}: no $keyName - registering anyway ($($comp.keyless_note))"
          } else {
            Write-V5Warn "${id}: no $keyName set. Get a key, run: setx $keyName ""<key>"" then re-run with -WithExtras"
            $installed[$id] = @{ status='skipped-no-key'; needs=$keyName }
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
            Write-V5Ok ("$id extra args from $extraEnv : " + (($npxArgs | Select-Object -Skip $comp.npx_args.Count) -join ' '))
          } else {
            Write-V5Warn "${id}: $extraEnv not set - using defaults ($($comp.id) may fall back to Google Chrome; set it to your browser exe to override)"
          }
        }
        $regs = @()
        foreach ($prov in $wanted) {
          switch ($prov) {
            'Grok'  {
              Update-V5GrokMcpBlock -Name $id -Command $comp.npx_command -ArgList $npxArgs -EnvMap $envMap -Startup 120 -Tool 6000 -SkipIfPresent
              $regs += 'Grok'
            }
            'Codex' {
              $cfg = Join-Path (Get-V5ProviderHome -Provider Codex -Catalog $catalog) 'config.toml'
              Update-V5GrokMcpBlock -Name $id -Command $comp.npx_command -ArgList $npxArgs -EnvMap $envMap -Startup 120 -Tool 6000 -SkipIfPresent -ConfigPath $cfg
              $regs += 'Codex'
            }
            'Claude' {
              if (Get-Command claude -EA SilentlyContinue) {
                $addArgs = @('mcp', 'add', '--scope', 'user')
                if ($envMap) { foreach ($k in $envMap.Keys) { $addArgs += @('--env', ("{0}={1}" -f $k, $envMap[$k])) } }
                $addArgs += @($id, '--', $comp.npx_command) + $npxArgs
                [void](Invoke-V5Native 'claude' $addArgs)
                $regs += 'Claude'
              } else {
                Write-V5Warn "$id for Claude: run  claude mcp add --scope user $id -- $($comp.npx_command) $($npxArgs -join ' ')"
              }
            }
            default {
              Write-V5Warn ("{0}: add this MCP block to {1} yourself:" -f $id, $prov)
              Write-Host ("      command = ""{0}""  args = [{1}]" -f $comp.npx_command, (($npxArgs | ForEach-Object { '"' + $_ + '"' }) -join ', '))
            }
          }
        }
        $installed[$id] = @{ status='registered'; providers=$regs; key=$keyName }
        Write-V5Ok ("$id registered for: " + ($regs -join ', '))
        if ($comp.scope_note) { Write-V5Warn ("scope: " + $comp.scope_note) }
      }

      default { Write-V5Warn "No installer for $($comp.install)" }
    }
  }
}

# ---------- Grok compat cells (always, before any MCP decision) ----------
# Grok ships Claude-Code compatibility ON: it adopts ~/.claude skills, agents,
# plugins (with their hooks and .mcp.json), ~/.claude.json and settings.json.
# The hook and MCP halves of that were measured as pure cost - see
# GROK-MCP-TROUBLESHOOTING.md. Skills/rules/agents compat stays on.
if (-not $SkillsOnly -and ($Providers -contains 'Grok')) {
  Write-V5Step "Grok Claude-compat cells"
  try {
    Set-V5GrokCompatCells
  } catch { Write-V5Warn ("Grok compat cells: " + $_.Exception.Message) }
}

# ---------- MCP wire (Grok) ----------
if (-not $SkipGrokMcp -and -not $SkipMcpWire -and -not $SkillsOnly -and ($Providers -contains 'Grok')) {
  Write-V5Step "Wiring Grok MCP servers"
  $hc = [Environment]::GetEnvironmentVariable('HOUSECARL_MCP','User')
  if (-not $hc) { $hc = $env:HOUSECARL_MCP }
  if ($hc -and (Test-Path $hc)) {
    Update-V5GrokMcpBlock -Name 'housecarl' -Command $hc -Startup 120 -Tool 6000 -EnvMap @{ HouseCarl__Mo2InstanceDir = '%SKYRIM_MO2_INSTANCE%'; SKYRIM_MO2_INSTANCE = '%SKYRIM_MO2_INSTANCE%' } -SkipIfPresent
  }
  $cm = Find-V5CodebaseMemoryExe
  if (-not $cm) {
    $cm = [Environment]::GetEnvironmentVariable('CODEBASE_MEMORY_MCP','User')
    if (-not $cm) { $cm = $env:CODEBASE_MEMORY_MCP }
  }
  if ($cm -and (Test-Path $cm)) {
    $programs = Join-Path $env:LOCALAPPDATA 'Programs\codebase-memory-mcp\codebase-memory-mcp.exe'
    if (Test-Path -LiteralPath $programs) { $cm = $programs }
    Set-V5UserEnv 'CODEBASE_MEMORY_MCP' $cm
    Update-V5GrokMcpBlock -Name 'codebase-memory-mcp' -Command $cm -Startup 90 -Tool 6000 -SkipIfPresent
  }
  $hr = $null
  try { $hr = (Get-Command headroom -EA SilentlyContinue).Source } catch {}
  if (-not $hr) { $hr = [Environment]::GetEnvironmentVariable('HEADROOM_CMD','User') }
  if ($hr -and (Test-Path $hr)) {
    Update-V5GrokMcpBlock -Name 'headroom' -Command $hr -ArgList @('mcp','serve') -Startup 60 -Tool 600 -SkipIfPresent
  } elseif ($hr) {
    # might be bare command name
    Update-V5GrokMcpBlock -Name 'headroom' -Command 'headroom' -ArgList @('mcp','serve') -Startup 60 -Tool 600 -SkipIfPresent
  }
  # Forge if INSTALLATION.json exists in grok skills.
  # Budget check FIRST. The four servers above use -SkipIfPresent, so they only
  # ever re-confirm what is already wired; Forge is the one that can add a NEW
  # server, and adding it blind is how Grok reached 7 configured (8 running with
  # a plugin-provided server) and wedged. Warning after the fact does not help
  # anyone: refuse the add and say what to do instead.
  $forgeInst = Join-Path (Get-V5ProviderHome Grok $catalog) 'skills\skyrim-forge\INSTALLATION.json'
  $grokCfgNow = Join-Path $env:USERPROFILE '.grok\config.toml'
  $grokNow = 0
  if (Test-Path -LiteralPath $grokCfgNow) {
    $grokNow = ([regex]::Matches(([IO.File]::ReadAllText($grokCfgNow)), '(?m)^[ 	]*\[mcp_servers\.[A-Za-z0-9_-]+\][ 	
]*$')).Count
  }
  $forgeAlready = $grokNow -gt 0 -and ([IO.File]::ReadAllText($grokCfgNow)) -match '(?m)^[ 	]*\[mcp_servers\.skyrim-forge\]'
  if ((Test-Path $forgeInst) -and -not $forgeAlready -and $grokNow -ge $GrokMcpBudget) {
    Write-V5Warn ("Grok already has $grokNow MCP servers (budget $GrokMcpBudget); skyrim-forge NOT added.")
    Write-V5Warn ('  Eight RUNNING servers wedge grok-cli 1.0.4 and enabled Claude plugins add servers')
    Write-V5Warn ('  that never appear in config.toml. To take Forge on Grok, comment out a server in')
    Write-V5Warn ('  ~/.grok/config.toml first, or re-run with -GrokMcpBudget 7 if no plugin adds one.')
  }
  elseif (Test-Path $forgeInst) {
    try {
      $j = [IO.File]::ReadAllText($forgeInst) | ConvertFrom-Json
      if ($j.mcp -and $j.mcp.Count -ge 1) {
        $cmd = $j.mcp[0]
        $args = @()
        if ($j.mcp.Count -gt 1) { $args = @($j.mcp[1..($j.mcp.Count-1)]) }
        Update-V5GrokMcpBlock -Name 'skyrim-forge' -Command $cmd -ArgList $args -Startup 120 -Tool 6000
      }
    } catch { Write-V5Warn "Forge MCP wire skipped: $_" }
  } else {
    Write-V5Warn "Skyrim Forge not configured (optional). Set SKYRIM_FORGE_ROOT or skill INSTALLATION.json"
  }
}
elseif (-not $SkillsOnly -and ($Providers -contains 'Grok')) {
  Write-V5Warn 'Grok MCP wiring skipped (-SkipGrokMcp).'
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
      Write-V5Warn ("Grok has $srvCount MCP servers configured. Eight RUNNING wedges grok-cli 1.0.4, and enabled Claude plugins add servers you cannot see here - comment some out in ~/.grok/config.toml (see GROK-MCP-TROUBLESHOOTING.md).")
    } else {
      Write-V5Ok ("Grok MCP servers: $srvCount configured (budget 6; plugin-provided servers also count)")
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
    Write-V5Step "Headroom Grok MCP registration (auth aware; repairs a v5.0 inference wrap)"
    try {
      $hrArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $hrEnsure)
      if ($SkipMcpWire) { $hrArgs += '-SkipMcp' }
      & (Join-Path $PSHOME 'powershell.exe') @hrArgs
      if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) {
        Write-V5Warn ("Ensure-Headroom-Grok exited " + $LASTEXITCODE)
      } else {
        Write-V5Ok 'Headroom registered for Grok as MCP (inference left on the native endpoint)'
        $installed['headroom-grok-mcp'] = @{ status = 'mcp-only' }
      }
    } catch {
      Write-V5Warn ("Ensure-Headroom-Grok: " + $_.Exception.Message)
      $installed['headroom-grok-mcp'] = @{ status = 'error'; error = $_.Exception.Message }
    }
  } else {
    Write-V5Warn 'TOOLS\Ensure-Headroom-Grok.ps1 missing from pack'
  }
}
# ---------- houseCARL MO2/Vortex ----------
if (-not $SkipHouseCarlSetup -and -not $SkillsOnly) {
  $setup = Join-Path $PackRoot 'TOOLS\Setup-HouseCarl.ps1'
  if (Test-Path $setup) {
    Write-V5Step "houseCARL MO2/Vortex setup"
    try {
      & (Join-Path $PSHOME 'powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $setup
      $installed['housecarl-setup'] = @{ status='ran' }
    } catch {
      Write-V5Warn "Setup-HouseCarl: $($_.Exception.Message)"
      $installed['housecarl-setup'] = @{ status='error'; error=$_.Exception.Message }
    }
  }
}

# ---------- Discover + state ----------
Write-V5Step "Post-install discovery"
$disc = Join-Path $PackRoot 'TOOLS\discover_tools.ps1'
if (Test-Path $disc) {
  & (Join-Path $PSHOME 'powershell.exe') -NoProfile -File $disc | Tee-Object -Variable discOut | Out-Host
}

$stateDir = Join-Path $env:LOCALAPPDATA 'Skyrim-AI-V5'
New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
$state = @{
  version = '7.7.12'
  installed_utc = [DateTime]::UtcNow.ToString('o')
  mode = $Mode
  providers = $Providers
  components = $installed
  native_plugins = $nativePlugins
  pack_root = $PackRoot
}
$state | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $stateDir 'install-state.json') -Encoding UTF8
$log | Set-Content (Join-Path $stateDir 'install-log.txt') -Encoding UTF8

# Completeness + assumption gates. Every provider's prose already says 'be
# thorough' and 'do not assume'; these are the layers that can actually refuse.
if (-not $ToolsOnly) {
  $gateInstaller = Join-Path $PackRoot 'TOOLS\Install-Completeness-Gate.ps1'
  if (Test-Path -LiteralPath $gateInstaller) {
    try {
      & (Join-Path $PSHOME 'powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $gateInstaller -Providers ($Providers -join ',')
      L 'completeness + assumption gates installed'
    } catch {
      Write-V5Warn ('Gates: ' + $_.Exception.Message)
    }
  } else {
    Write-V5Warn 'TOOLS\Install-Completeness-Gate.ps1 missing from pack'
  }

  $mcpReason = Join-Path $PackRoot 'TOOLS\Add-Reasoning-MCPs.ps1'
  if (Test-Path -LiteralPath $mcpReason) {
    try {
      & (Join-Path $PSHOME 'powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $mcpReason -Providers ($Providers -join ',')
      L 'reasoning MCP servers wired'
    } catch {
      Write-V5Warn ('Reasoning MCPs: ' + $_.Exception.Message)
    }
  }

  # After every provider config has been written, repoint any MCP command that
  # points at a version-stamped folder which no longer exists. An upgraded tool
  # (Skyrim-Forge-5.1.0 -> 5.1.3) renames its folder, and a provider that was
  # missed just stops connecting silently.
  $mcpRepair = Join-Path $PackRoot 'TOOLS\Repair-McpPaths.ps1'
  if (Test-Path -LiteralPath $mcpRepair) {
    try {
      & (Join-Path $PSHOME 'powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $mcpRepair -Apply -Quiet
      L 'dead MCP command paths repaired'
    } catch {
      Write-V5Warn ('MCP path repair: ' + $_.Exception.Message)
    }
  }

  $toolbelt = Join-Path $PackRoot 'TOOLS\Build-Toolbelt.ps1'
  if (Test-Path -LiteralPath $toolbelt) {
    try {
      & (Join-Path $PSHOME 'powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $toolbelt
      L 'toolbelt inventory written'
    } catch {
      Write-V5Warn ('Toolbelt: ' + $_.Exception.Message)
    }
  }
}

Write-Host ""
Write-Host "=====================================================" -ForegroundColor Green
Write-Host " INSTALL COMPLETE" -ForegroundColor Green
Write-Host " State: $stateDir\install-state.json" -ForegroundColor Green
Write-Host "=====================================================" -ForegroundColor Green
Write-Host ""
Write-Host 'NEXT STEPS:' -ForegroundColor Yellow
Write-Host '  1. FULLY restart every AI app you use (Grok / Claude / Codex / ...).'
Write-Host '  2. Grok: run /mcp and confirm housecarl, codebase-memory-mcp, headroom.'
Write-Host '  3. Claude houseCARL plugin: set MO2 instance to SKYRIM_MO2_INSTANCE path.'
Write-Host '  4. Vortex users after LO changes: TOOLS\Setup-HouseCarl.ps1 -RefreshOnly'
Write-Host '  5. Update tools later: TOOLS\Update-From-GitHub.ps1'
Write-Host '  6. Optional Forge 5.1.5+: extract to your Skyrim tools folder as Skyrim-Forge-x.y.z (not Documents). Set SKYRIM_FORGE_ROOT or skill INSTALLATION.json.'
Write-Host '  7. Preamble: SOUL + AIO were wired into your agent files automatically.'
Write-Host '     Web UIs (ChatGPT/Gemini) have no instruction file - paste 3-PREAMBLES\MANUAL-PASTE.txt.'
Write-Host '  8. Codex: approve the one-time plugin trust prompt. Hermes: hermes --accept-hooks once.'
Write-Host ''
Write-Host 'AI usage: skills load automatically. Start with skyrim-memory + skyrim-tool-router.'
Write-Host 'Missing tools: run TOOLS\Ensure-Tools.ps1 or INSTALL-V7-AIO.ps1 - do not invent paths.'
Write-Host ''
