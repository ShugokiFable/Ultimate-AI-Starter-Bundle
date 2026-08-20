[CmdletBinding()]
param(
    [ValidateSet('All', 'Codex', 'Claude', 'Grok', 'Kimi', 'Hermes')]
    [string]$Provider = 'All',
    [switch]$Yes,
    [string]$ReportPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$Python = Join-Path $Root '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $Python -PathType Leaf)) { throw 'Install Forge first.' }

function Ask {
    param([string]$Text)
    if ($Yes) { return $true }
    return (Read-Host "$Text [y/N]") -match '^(?i:y|yes)$'
}

function Resolve-ProviderCommand {
    param([string]$Name)
    if ($Name -eq 'Codex') {
        $CodexBin = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'OpenAI\Codex\bin'
        if (Test-Path -LiteralPath $CodexBin) {
            $Direct = @(Get-ChildItem -LiteralPath $CodexBin -Recurse -Filter 'codex.exe' -File -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending |
                Select-Object -ExpandProperty FullName)
            if ($Direct.Count -gt 0) { return $Direct[0] }
        }
    }
    if ($Name -eq 'Grok') {
        $GrokDirect = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.grok\bin\grok.exe'
        if (Test-Path -LiteralPath $GrokDirect -PathType Leaf) { return $GrokDirect }
    }
    if ($Name -eq 'Kimi') {
        $KimiHome = if ($env:KIMI_CODE_HOME) { $env:KIMI_CODE_HOME } else { Join-Path ([Environment]::GetFolderPath('UserProfile')) '.kimi-code' }
        $KimiDirect = Join-Path $KimiHome 'bin\kimi.exe'
        if (Test-Path -LiteralPath $KimiDirect -PathType Leaf) { return $KimiDirect }
    }
    if ($Name -eq 'Hermes') {
        $HermesHome = if ($env:HERMES_HOME) { $env:HERMES_HOME } else { Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'hermes' }
        $HermesDirect = Join-Path $HermesHome 'hermes-agent\venv\Scripts\hermes.exe'
        if (Test-Path -LiteralPath $HermesDirect -PathType Leaf) { return $HermesDirect }
    }
    $Command = Get-Command $Name.ToLowerInvariant() -ErrorAction SilentlyContinue
    if ($Command) { return $Command.Source }
    return $null
}

function Test-GrokForgeRegistrationAllowed {
    # Same cliff as Ultimate AI Starter Bundle GROK-MCP-TROUBLESHOOTING.md:
    # 8 running MCP servers wedge Grok (process never exits). Budget is 7
    # configured once claude-mem's mcp-search plugin is disabled for Grok,
    # else 6 while that plugin still loads. Replacing an existing Forge
    # entry does not consume a new slot.
    $CfgPath = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.grok\config.toml'
    if (-not (Test-Path -LiteralPath $CfgPath -PathType Leaf)) { return $true }
    $Raw = [IO.File]::ReadAllText($CfgPath)
    if ([regex]::IsMatch($Raw, '(?m)^\[mcp_servers\.skyrim-forge\]')) { return $true }
    $Configured = ([regex]::Matches($Raw, '(?m)^\[mcp_servers\.')).Count
    $PluginActive = -not [regex]::IsMatch($Raw, '(?m)^disabled_mcp_servers\s*=.*mcp-search')
    if ($Configured -ge 7 -or ($Configured -ge 6 -and $PluginActive)) { return $false }
    return $true
}

function Get-ClaudeDesktopConfigPath {
    # Claude Desktop app ships as either a normal install (%APPDATA%\Claude)
    # or a Microsoft Store package (LocalCache\Roaming\Claude). Return the
    # live claude_desktop_config.json, or $null when the app is absent.
    $Normal = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'Claude\claude_desktop_config.json'
    if (Test-Path -LiteralPath $Normal -PathType Leaf) { return $Normal }
    $Store = Get-ChildItem -LiteralPath (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Packages') -Directory -Filter 'Claude_*' -ErrorAction SilentlyContinue |
        ForEach-Object { Join-Path $_.FullName 'LocalCache\Roaming\Claude\claude_desktop_config.json' } |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
        Select-Object -First 1
    return $Store
}

function Write-ClaudeDesktopMcp {
    # Merge one MCP entry into claude_desktop_config.json (desktop schema:
    # command/args/env, no 'type'). Backs up the original and restores it on
    # any failed write so the app's preferences are never corrupted.
    param([string]$ConfigPath, [string]$Name, [hashtable]$Entry)
    $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $Original = if (Test-Path -LiteralPath $ConfigPath -PathType Leaf) { [IO.File]::ReadAllBytes($ConfigPath) } else { $null }
    $Config = if ($Original) { [IO.File]::ReadAllText($ConfigPath) | ConvertFrom-Json } else { [pscustomobject]@{} }
    if (-not $Config.PSObject.Properties['mcpServers']) {
        $Config | Add-Member -MemberType NoteProperty -Name mcpServers -Value ([pscustomobject]@{})
    }
    if ($null -eq $Config.mcpServers -or -not ($Config.mcpServers -is [psobject])) {
        throw 'Claude desktop config mcpServers must be an object.'
    }
    $Clean = [ordered]@{}
    foreach ($Key in @('command', 'args', 'env')) { if ($Entry.ContainsKey($Key)) { $Clean[$Key] = $Entry[$Key] } }
    $Config.mcpServers | Add-Member -MemberType NoteProperty -Name $Name -Value ([pscustomobject]$Clean) -Force
    try {
        [IO.File]::WriteAllText($ConfigPath, ($Config | ConvertTo-Json -Depth 32) + [Environment]::NewLine, $Utf8NoBom)
    } catch {
        if ($Original) { [IO.File]::WriteAllBytes($ConfigPath, $Original) } elseif (Test-Path -LiteralPath $ConfigPath) { Remove-Item -LiteralPath $ConfigPath -Force }
        throw
    }
    $Verified = [IO.File]::ReadAllText($ConfigPath) | ConvertFrom-Json
    $Got = $Verified.mcpServers.PSObject.Properties[$Name]
    if (-not $Got -or $Got.Value.command -ne $Entry['command']) { throw 'Claude desktop MCP verification failed.' }
    return $true
}

function Invoke-Registration {
    param([string]$Name)
    $Executable = Resolve-ProviderCommand -Name $Name
    # Claude Desktop app has no CLI on PATH. Detect its config so a
    # desktop-only install still gets Forge registered.
    $DesktopCfg = if ($Name -eq 'Claude') { Get-ClaudeDesktopConfigPath } else { $null }
    if (-not $Executable -and -not $DesktopCfg) {
        return [ordered]@{
            provider = $Name
            mode = 'mcp'
            status = 'NOT_INSTALLED'
            command = $null
            detail = 'Provider command was not found. The installed skill still contains the exact Forge CLI and MCP launch descriptor.'
        }
    }
    if (-not (Ask -Text "Register Skyrim Forge MCP with ${Name}?")) {
        return [ordered]@{
            provider = $Name
            mode = 'mcp'
            status = 'SKIPPED'
            command = $Executable
            detail = 'Registration was not approved.'
        }
    }
    try {
        switch ($Name) {
            'Codex' {
                & $Executable mcp remove skyrim-forge 2>$null | Out-Null
                & $Executable mcp add skyrim-forge -- $Python -m skyrim_forge mcp | Out-Null
                if ($LASTEXITCODE -ne 0) { throw "Codex registration exited $LASTEXITCODE." }
                & $Executable mcp get skyrim-forge | Out-Null
                if ($LASTEXITCODE -ne 0) { throw "Codex verification exited $LASTEXITCODE." }
            }
            'Claude' {
                if ($Executable) {
                    # Claude Code CLI surface (~/.claude.json)
                    & $Executable mcp remove skyrim-forge -s user 2>$null | Out-Null
                    & $Executable mcp add --transport stdio --scope user skyrim-forge -- $Python -m skyrim_forge mcp | Out-Null
                    if ($LASTEXITCODE -ne 0) { throw "Claude registration exited $LASTEXITCODE." }
                }
                if ($DesktopCfg) {
                    # Claude Desktop app surface (claude_desktop_config.json)
                    [void](Write-ClaudeDesktopMcp -ConfigPath $DesktopCfg -Name 'skyrim-forge' -Entry @{ command = $Python; args = @('-m', 'skyrim_forge', 'mcp') })
                }
            }
            'Grok' {
                if (-not (Test-GrokForgeRegistrationAllowed)) {
                    return [ordered]@{
                        provider = $Name
                        mode = 'mcp'
                        status = 'SKIPPED'
                        command = $Executable
                        detail = 'Grok wedges at 8 running MCP servers. Forge was not added. Run grok mcp disable mcp-search and/or disable another server, then rerun Register-MCP.ps1 -Provider Grok. Require Forge 5.1.5+ so tools/call carries resultType.'
                    }
                }
                & $Executable mcp remove skyrim-forge 2>$null | Out-Null
                # Windows PowerShell 5 rewrites native `--` boundaries when the
                # executable is invoked through a variable. Start-Process keeps
                # Grok's documented separator and Python's `-m` as server args.
                $GrokArguments = @(
                    'mcp', 'add', '--scope', 'user', 'skyrim-forge', '--',
                    ('"' + $Python + '"'), '-m', 'skyrim_forge', 'mcp'
                )
                $GrokProcess = Start-Process -FilePath $Executable -ArgumentList $GrokArguments -NoNewWindow -Wait -PassThru
                if ($GrokProcess.ExitCode -ne 0) { throw "Grok registration exited $($GrokProcess.ExitCode)." }
                $GrokServers = @((& $Executable mcp list --json | ConvertFrom-Json))
                if ($LASTEXITCODE -ne 0) { throw "Grok MCP list exited $LASTEXITCODE." }
                $GrokForge = @($GrokServers | Where-Object {
                    $_.name -eq 'skyrim-forge' -and
                    $_.command -eq $Python -and
                    (@($_.args) -join ' ') -eq '-m skyrim_forge mcp' -and
                    $_.enabled
                })
                if ($GrokForge.Count -ne 1) { throw 'Grok MCP verification did not return the exact enabled Forge command.' }
            }
            'Kimi' {
                $KimiHome = if ($env:KIMI_CODE_HOME) { $env:KIMI_CODE_HOME } else { Join-Path ([Environment]::GetFolderPath('UserProfile')) '.kimi-code' }
                $KimiConfigPath = Join-Path $KimiHome 'mcp.json'
                $KimiOriginal = if (Test-Path -LiteralPath $KimiConfigPath -PathType Leaf) { [IO.File]::ReadAllBytes($KimiConfigPath) } else { $null }
                if (Test-Path -LiteralPath $KimiConfigPath -PathType Leaf) {
                    # ReadAllText, not Get-Content -Raw. On PS 5.1 Get-Content
                    # without -Encoding decodes with the ANSI codepage, and this
                    # object is written straight back at the WriteAllText below,
                    # so every non-ASCII char in the user's mcp.json would be
                    # replaced by mojibake.
                    $KimiConfig = [IO.File]::ReadAllText($KimiConfigPath) | ConvertFrom-Json
                } else {
                    $KimiConfig = [pscustomobject]@{}
                }
                if (-not $KimiConfig.PSObject.Properties['mcpServers']) {
                    $KimiConfig | Add-Member -MemberType NoteProperty -Name mcpServers -Value ([pscustomobject]@{})
                }
                if ($null -eq $KimiConfig.mcpServers -or -not ($KimiConfig.mcpServers -is [psobject])) {
                    throw 'Kimi mcp.json must contain an object-valued mcpServers property.'
                }
                $ForgeEntry = [pscustomobject][ordered]@{
                    command = $Python
                    args = @('-m', 'skyrim_forge', 'mcp')
                }
                if ($KimiConfig.mcpServers.PSObject.Properties['skyrim-forge']) {
                    $KimiConfig.mcpServers.'skyrim-forge' = $ForgeEntry
                } else {
                    $KimiConfig.mcpServers | Add-Member -MemberType NoteProperty -Name 'skyrim-forge' -Value $ForgeEntry
                }
                New-Item -ItemType Directory -Force -Path $KimiHome | Out-Null
                $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
                try {
                    [IO.File]::WriteAllText($KimiConfigPath, ($KimiConfig | ConvertTo-Json -Depth 32) + [Environment]::NewLine, $Utf8NoBom)
                    & $Executable doctor | Out-Null
                    if ($LASTEXITCODE -ne 0) { throw "Kimi doctor exited $LASTEXITCODE." }
                    $KimiVerified = [IO.File]::ReadAllText($KimiConfigPath) | ConvertFrom-Json
                    $KimiForge = $KimiVerified.mcpServers.'skyrim-forge'
                    if ($KimiForge.command -ne $Python -or (@($KimiForge.args) -join ' ') -ne '-m skyrim_forge mcp') {
                        throw 'Kimi MCP verification did not return the exact Forge command.'
                    }
                } catch {
                    if ($null -ne $KimiOriginal) {
                        [IO.File]::WriteAllBytes($KimiConfigPath, $KimiOriginal)
                    } elseif (Test-Path -LiteralPath $KimiConfigPath -PathType Leaf) {
                        Remove-Item -LiteralPath $KimiConfigPath -Force
                    }
                    throw
                }
            }
            'Hermes' {
                $HermesHome = if ($env:HERMES_HOME) { $env:HERMES_HOME } else { Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'hermes' }
                $HermesConfigPath = Join-Path $HermesHome 'config.yaml'
                $HermesOriginal = if (Test-Path -LiteralPath $HermesConfigPath -PathType Leaf) { [IO.File]::ReadAllBytes($HermesConfigPath) } else { $null }
                $HermesPython = Join-Path (Split-Path -Parent $Executable) 'python.exe'
                if (-not (Test-Path -LiteralPath $HermesPython -PathType Leaf)) { throw "Hermes Python runtime missing beside executable: $HermesPython" }
                $HermesConfigHelper = Join-Path ([IO.Path]::GetTempPath()) ('uabs-hermes-forge-' + [guid]::NewGuid().ToString('N') + '.py')
                $HermesStdout = Join-Path ([IO.Path]::GetTempPath()) ('uabs-hermes-probe-' + [guid]::NewGuid().ToString('N') + '.out')
                $HermesStderr = $HermesStdout + '.err'
                $HermesResult = $HermesStdout + '.json'
                $OldForgePython = $env:UABS_FORGE_PYTHON
                $OldHermesResult = $env:UABS_HERMES_RESULT
                try {
                    # Do NOT launch hermes.exe here. Full CLI startup registers shell hooks,
                    # and Hermes intentionally prompts on first use of unseen hooks when stdin
                    # is a TTY. That made an unattended bundle install wait for Enter. Use the
                    # same low-level MCP probe that `hermes mcp test` and Hermes doctor call,
                    # without starting the interactive CLI layer at all.
                    $HelperSource = @'
import json
import os
from pathlib import Path
from hermes_cli.config import load_config, save_config
from hermes_cli.mcp_config import _probe_single_server

result_path = Path(os.environ["UABS_HERMES_RESULT"])
server = {
    "command": os.environ["UABS_FORGE_PYTHON"],
    "args": ["-m", "skyrim_forge", "mcp"],
    "enabled": True,
    "connect_timeout": 30,
}
try:
    cfg = load_config()
    servers = cfg.setdefault("mcp_servers", {})
    servers["skyrim-forge"] = server
    save_config(cfg)

    verify = load_config().get("mcp_servers", {}).get("skyrim-forge", {})
    if verify.get("command") != server["command"] or verify.get("args") != server["args"]:
        raise RuntimeError("saved Hermes Forge MCP entry did not round-trip exactly")

    tools = _probe_single_server("skyrim-forge", verify, connect_timeout=30)
    result_path.write_text(json.dumps({
        "connected": True,
        "tool_count": len(tools),
        "tools": [item[0] for item in tools],
    }), encoding="utf-8")
except Exception as exc:
    result_path.write_text(json.dumps({
        "connected": False,
        "error": f"{type(exc).__name__}: {exc}",
    }), encoding="utf-8")
    raise
'@
                    $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
                    [IO.File]::WriteAllText($HermesConfigHelper, $HelperSource, $Utf8NoBom)
                    $env:UABS_FORGE_PYTHON = $Python
                    $env:UABS_HERMES_RESULT = $HermesResult
                    Write-Host '  .. Hermes: saving + probing Forge MCP directly (hard limit 45s; no CLI prompts)...' -ForegroundColor DarkCyan
                    $HermesProcess = Start-Process -FilePath $HermesPython -ArgumentList @($HermesConfigHelper) -NoNewWindow -PassThru -RedirectStandardOutput $HermesStdout -RedirectStandardError $HermesStderr
                    $HermesStarted = [DateTime]::UtcNow
                    $HermesNextProgress = 5
                    $HermesExited = $HermesProcess.WaitForExit(250)
                    while (-not $HermesExited) {
                        $Elapsed = [int]([DateTime]::UtcNow - $HermesStarted).TotalSeconds
                        if ($Elapsed -ge 45) {
                            try { $HermesProcess.Kill() } catch {}
                            try { $HermesProcess.WaitForExit() } catch {}
                            throw 'Hermes direct MCP probe timed out after 45 seconds.'
                        }
                        if ($Elapsed -ge $HermesNextProgress) {
                            Write-Host ("  .. Hermes: direct Forge MCP probe still running ($Elapsed s / 45 s)...") -ForegroundColor DarkCyan
                            $HermesNextProgress += 5
                        }
                        $HermesExited = $HermesProcess.WaitForExit(250)
                    }
                    # On Windows PowerShell 5.1/.NET Framework, a timed WaitForExit() can
                    # report completion before redirected streams and ExitCode are fully
                    # finalized. The parameterless call is required before consuming either.
                    $HermesProcess.WaitForExit()
                    $HermesProcess.Refresh()
                    $HermesExitCode = [int]$HermesProcess.ExitCode
                    $HermesOutput = ''
                    if (Test-Path -LiteralPath $HermesStdout -PathType Leaf) { $HermesOutput += [IO.File]::ReadAllText($HermesStdout) }
                    if (Test-Path -LiteralPath $HermesStderr -PathType Leaf) { $HermesOutput += [IO.File]::ReadAllText($HermesStderr) }
                    if ($HermesExitCode -ne 0) { throw "Hermes direct MCP probe exited ${HermesExitCode}: $HermesOutput" }
                    if (-not (Test-Path -LiteralPath $HermesResult -PathType Leaf)) { throw "Hermes direct MCP probe produced no result file: $HermesOutput" }
                    $HermesProbe = [IO.File]::ReadAllText($HermesResult) | ConvertFrom-Json
                    if (-not $HermesProbe.connected) { throw "Hermes direct MCP probe did not connect: $($HermesProbe.error)" }
                    Write-Host ("  OK  Hermes: Forge MCP connection verified ({0} tool(s))" -f $HermesProbe.tool_count) -ForegroundColor Green
                } catch {
                    if ($null -ne $HermesOriginal) {
                        [IO.File]::WriteAllBytes($HermesConfigPath, $HermesOriginal)
                    } elseif (Test-Path -LiteralPath $HermesConfigPath -PathType Leaf) {
                        Remove-Item -LiteralPath $HermesConfigPath -Force
                    }
                    throw
                } finally {
                    if ($null -eq $OldForgePython) { Remove-Item Env:UABS_FORGE_PYTHON -ErrorAction SilentlyContinue } else { $env:UABS_FORGE_PYTHON = $OldForgePython }
                    if ($null -eq $OldHermesResult) { Remove-Item Env:UABS_HERMES_RESULT -ErrorAction SilentlyContinue } else { $env:UABS_HERMES_RESULT = $OldHermesResult }
                    Remove-Item -LiteralPath $HermesConfigHelper,$HermesStdout,$HermesStderr,$HermesResult -Force -ErrorAction SilentlyContinue
                }
            }
        }
        return [ordered]@{
            provider = $Name
            mode = 'mcp'
            status = 'READY'
            command = if ($Executable) { $Executable } elseif ($DesktopCfg) { $DesktopCfg } else { $null }
            detail = if ($Executable -and $DesktopCfg) {
                'MCP registered with Claude Code CLI and Claude Desktop app; verification passed.'
            } elseif ($DesktopCfg) {
                'Claude Desktop app detected (no CLI); MCP written to claude_desktop_config.json and verified.'
            } else {
                'MCP registration and provider verification passed.'
            }
        }
    } catch {
        return [ordered]@{
            provider = $Name
            mode = 'mcp'
            status = 'FAILED'
            command = $Executable
            detail = $_.Exception.Message
        }
    }
}

$Selected = if ($Provider -eq 'All') {
    @('Codex', 'Claude', 'Grok', 'Kimi', 'Hermes')
} else {
    @($Provider)
}
$Results = @()
foreach ($Name in $Selected) {
    $Result = Invoke-Registration -Name $Name
    $Results += $Result
    $Color = if ($Result.status -eq 'READY') { 'Green' } elseif ($Result.status -eq 'FAILED') { 'Red' } else { 'Yellow' }
    Write-Host ('{0}: {1} ({2})' -f $Name, $Result.status, $Result.mode) -ForegroundColor $Color
    Write-Host ('  {0}' -f $Result.detail)
}

if (-not $ReportPath) { $ReportPath = Join-Path $Root 'REPORTS\ai-integration.json' }
$ReportPath = [IO.Path]::GetFullPath($ReportPath)
$ReportDirectory = Split-Path -Parent $ReportPath
New-Item -ItemType Directory -Force -Path $ReportDirectory | Out-Null
$Version = (& $Python -m skyrim_forge version | ConvertFrom-Json).version
$Report = [ordered]@{
    product = 'Skyrim Forge'
    version = $Version
    root = $Root
    python = $Python
    mcp_command = @($Python, '-m', 'skyrim_forge', 'mcp')
    providers = @($Results)
}
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($ReportPath, ($Report | ConvertTo-Json -Depth 8) + [Environment]::NewLine, $Utf8NoBom)
Write-Host "Integration report: $ReportPath"

if (@($Results | Where-Object { $_.status -eq 'FAILED' }).Count -gt 0) {
    throw 'One or more installed-provider MCP registrations failed. See the integration report.'
}
