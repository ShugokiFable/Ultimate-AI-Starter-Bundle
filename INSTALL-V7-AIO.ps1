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
  # Hermes config.yaml wiring (v7.5.5). On by default: copies the operator's
  # tailored Hermes config (model/routing/MCP/hooks) from
  # 1-RECOMMENDED-SEPARATE-TAILORED\Hermes\config.yaml into the Hermes home.
  # Backup-first, idempotent. -SkipHermesConfig opts out.
  [switch]$SkipHermesConfig
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
Write-Host " Ultimate AI Starter Bundle v7.6.5 - ALL-IN-ONE INSTALLER (Headroom MCP-only for Grok)" -ForegroundColor Magenta
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
  $tailored = Join-Path $PackRoot '1-RECOMMENDED-SEPARATE-TAILORED'
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

# ---------- AI preamble: SOUL + AIO for every agent (v7.5.0) ----------
# Wires the same preamble into every selected provider so a fresh machine
# behaves like the operator's own setup. Idempotent: re-running replaces the
# marked block instead of stacking copies; every write gets a .bak first.
if (-not $ToolsOnly -and -not $SkipPreamble) {
  Write-V5Step "SOUL + AIO preamble wiring"
  $preDir = Join-Path $PackRoot '4-PREAMBLES'
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
      Write-V5Warn ("$prov preamble skipped: 4-PREAMBLES or AIO-INSTRUCTION.txt missing")
      continue
    }
    try {
      Install-V5PreambleBlock -Path $target -SoulFile $soulF -AioFile $aioF -Force:$ForcePreamble
    } catch {
      Write-V5Warn ("$prov preamble failed: " + $_.Exception.Message)
    }
  }
}

# ---------- Hermes config.yaml (v7.5.5) ----------
# Copies the operator's tailored Hermes config (model/routing/MCP/hooks) into
# the Hermes home. Backup-first, idempotent - same pattern as the SOUL wiring.
if (-not $ToolsOnly -and -not $SkipHermesConfig -and $Providers -contains 'Hermes') {
  Write-V5Step "Hermes config.yaml wiring"
  $hCfgSrc = Join-Path $PackRoot '1-RECOMMENDED-SEPARATE-TAILORED\Hermes\config.yaml'
  if (-not (Test-Path -LiteralPath $hCfgSrc)) {
    Write-V5Warn "Hermes config.yaml skipped: $hCfgSrc missing"
  } else {
    $hhome = Get-V5ProviderHome -Provider Hermes -Catalog $catalog
    $hCfg = Join-Path $hhome 'config.yaml'
    try {
      if (Test-Path -LiteralPath $hCfg) {
        $same = (Get-FileHash -LiteralPath $hCfg -Algorithm SHA256).Hash -eq
                (Get-FileHash -LiteralPath $hCfgSrc -Algorithm SHA256).Hash
        if (-not $same) {
          Copy-Item -LiteralPath $hCfg -Destination ($hCfg + '.before-config-' + (Get-Date -Format 'yyyyMMdd-HHmmssfff') + '.bak') -Force
          Copy-Item -LiteralPath $hCfgSrc -Destination $hCfg -Force
          Write-V5Ok ("Hermes config.yaml updated: " + $hCfg)
        } else {
          Write-V5Ok ('Hermes config.yaml already current: ' + $hCfg)
        }
      } else {
        New-Item -ItemType Directory -Force -Path $hhome | Out-Null
        Copy-Item -LiteralPath $hCfgSrc -Destination $hCfg -Force
        Write-V5Ok ("Hermes config.yaml installed: " + $hCfg)
      }
    } catch {
      Write-V5Warn ("Hermes config.yaml wiring failed: " + $_.Exception.Message)
    }
  }
}

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
        # already in provider skills from pack; also ensure plugin tree for Claude
        $plugSrc = Join-Path $plugins $id
        if (Test-Path $plugSrc) {
          foreach ($prov in $Providers) {
            if ($prov -ne 'Claude') { continue }
            $providerHome = Get-V5ProviderHome -Provider Claude -Catalog $catalog
            $dest = Join-Path $providerHome "plugins\v5-bundled\$id"
            Copy-V5Robo -From $plugSrc -To $dest
            Write-V5Ok "Claude plugin tree $id -> $dest"
          }
        }
        $installed[$id] = @{ status='skills+plugin' }
        Write-V5Ok "$id skills present via provider skill install"
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
      & powershell @hrArgs
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
      & powershell -NoProfile -ExecutionPolicy Bypass -File $setup
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
  & powershell -NoProfile -File $disc | Tee-Object -Variable discOut | Out-Host
}

$stateDir = Join-Path $env:LOCALAPPDATA 'Skyrim-AI-V5'
New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
$state = @{
  version = '7.6.5'
  installed_utc = [DateTime]::UtcNow.ToString('o')
  mode = $Mode
  providers = $Providers
  components = $installed
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
      & powershell -NoProfile -ExecutionPolicy Bypass -File $gateInstaller -Providers ($Providers -join ',')
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
      & powershell -NoProfile -ExecutionPolicy Bypass -File $mcpReason -Providers ($Providers -join ',')
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
      & powershell -NoProfile -ExecutionPolicy Bypass -File $mcpRepair -Apply -Quiet
      L 'dead MCP command paths repaired'
    } catch {
      Write-V5Warn ('MCP path repair: ' + $_.Exception.Message)
    }
  }

  $toolbelt = Join-Path $PackRoot 'TOOLS\Build-Toolbelt.ps1'
  if (Test-Path -LiteralPath $toolbelt) {
    try {
      & powershell -NoProfile -ExecutionPolicy Bypass -File $toolbelt
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
Write-Host '  6. Optional Forge: set SKYRIM_FORGE_ROOT or skill INSTALLATION.json'
Write-Host '  7. Preamble: SOUL + AIO were wired into your agent files automatically.'
Write-Host '     Web UIs (ChatGPT/Gemini) have no instruction file - paste 4-PREAMBLES\MANUAL-PASTE.txt.'
Write-Host '  8. Codex: approve the one-time plugin trust prompt. Hermes: hermes --accept-hooks once.'
Write-Host ''
Write-Host 'AI usage: skills load automatically. Start with skyrim-memory + skyrim-tool-router.'
Write-Host 'Missing tools: run TOOLS\Ensure-Tools.ps1 or INSTALL-V7-AIO.ps1 - do not invent paths.'
Write-Host ''
