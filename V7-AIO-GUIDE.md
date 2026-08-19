# Ultimate AI Starter Bundle v6 — AIO guide (users + AIs)

## What “AIO” means

One pack that delivers:

1. **Skills** for every supported AI (framework syntax, safety, routers)
2. **Plugins/process skills** (Superpowers, Ponytail)
3. **Runnable tools** (houseCARL, Spooky, codebase-memory, Headroom)
4. **Setup automation** (MCP wire, MO2/Vortex shim)
5. **GitHub update path** for newer upstream releases

## New user path

```text
Fresh machine:  powershell ... -Command "irm <INSTALL-REMOTE.ps1> | iex"
or locally:     INSTALL-V7-AIO.bat
then:           restart AI apps  →  ask a load-order question
```

Both installers wire the SOUL + AIO preamble into every provider's
instruction file automatically (v7.5.0). Web UIs without an instruction file
get `3-PREAMBLES\MANUAL-PASTE.txt` pasted by hand.

## AI agent path (when something is missing)

```text
1. Load tool-discovery / ai-tooling-stack
2. Run TOOLS\discover_tools.ps1  (or Ensure-Tools.ps1 -DiscoverOnly)
3. If MISSING → run or recommend:
     INSTALL-V7-AIO.ps1 -ToolsOnly -Components <ids>
     or TOOLS\Ensure-Tools.ps1
     or TOOLS\Update-From-GitHub.ps1 -Components <ids> -InstallAfter
4. For houseCARL instance: TOOLS\Setup-HouseCarl.ps1
5. Tell user to fully restart the AI app after MCP changes
6. Never invent load-order winners or tool output
```

## Component IDs (`CATALOG.json`)

| id | Role |
|---|---|
| housecarl | Live LO MCP + patches |
| spooky | ESP/Papyrus/NIF/BSA CLI |
| codebase-memory | Code graph MCP |
| headroom | Context compression MCP |
| superpowers | Process skills |
| ponytail | Minimal-diff skills |
| codeburn | Token/cost CLI |
| skyrim-forge | External product (not bundled) |

## GitHub sources

See `BUNDLED-TOOLS\CATALOG.json` → each component `github.owner/repo`.

`Update-From-GitHub.ps1` calls `GET /repos/{owner}/{repo}/releases/latest`.

## Grok MCP

Installer writes `%USERPROFILE%\.grok\config.toml` blocks for:

- housecarl
- codebase-memory-mcp
- headroom
- skyrim-forge (only if INSTALLATION.json exists)

Env vars (user scope): `HOUSECARL_MCP`, `HouseCarl__Mo2InstanceDir`, `SKYRIM_MO2_INSTANCE`, `CODEBASE_MEMORY_MCP`, `SPOOKY_AUTOMOD_ROOT`, `HEADROOM_CMD`, `SKYRIM_FORGE_ROOT`.

## Vortex

houseCARL still needs an MO2-shaped tree. Setup builds `%LOCALAPPDATA%\houseCARL-Shim`.
Refresh after LO changes: `Setup-HouseCarl.ps1 -RefreshOnly`.

## Gates (v6.8.2)

```powershell
.\TOOLS\Install-Completeness-Gate.ps1
python TOOLS\hooks\completeness_gate.py --selftest
python TOOLS\hooks\assumption_gate.py --selftest
.\TOOLS\Build-Toolbelt.ps1
Get-Content $env:LOCALAPPDATA\Skyrim-AI-V5\TOOLBELT.md
```

The completeness gate refuses a half-finished release. The assumption gate
refuses a path nobody verified. Both fail open. Hermes is wired by asking
`hermes config path`, not by writing the documented `~/.hermes/config.yaml`.

## Verification

```powershell
.\TOOLS\discover_tools.ps1
Get-Content $env:LOCALAPPDATA\Skyrim-AI-V5\install-state.json
Get-Content $env:LOCALAPPDATA\houseCARL-data\v5-setup-state.json
```

## Licensing

`BUNDLED-TOOLS\THIRD-PARTY-NOTICES.md`
