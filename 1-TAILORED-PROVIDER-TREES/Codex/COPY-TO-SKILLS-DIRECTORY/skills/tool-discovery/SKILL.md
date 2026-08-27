---
name: tool-discovery
description: Resolve optional Skyrim and AI tooling on the current machine without assuming drive letters or usernames. Use at session start, when a tool path is unknown, or before recommending install.
metadata:
  version: 5.0.0
---

# Tool discovery (portable)

Never hardcode `C:\Users\<name>`, `S:\Apps`, or `Z:\Backup` as authority. Those may appear only as **example** paths on the pack author's machine.

## Resolution order (every tool)

1. Environment variable listed for that tool (if set and path exists).
2. Provider skill-local descriptor (`INSTALLATION.json` beside the skill) when present.
3. Well-known defaults under `%USERPROFILE%` and `%LOCALAPPDATA%`.
4. `PATH` / `where.exe` / `Get-Command`.
5. User-supplied absolute path from the current conversation.
6. **If the binary EXISTS but its MCP tools are not callable, stop — this is
   not an install problem.** Most MCP servers in this pack are registered per
   project on purpose (houseCARL alone costs ~41,768 tokens *every turn*), so
   "installed" and "enabled here" are different states. Recommending an install
   here tells the user to install something they already have.
7. Only if the binary is genuinely absent from disk → **recommend install**
   (do not invent a fake install).

## Two different failures, two different answers

| What you see | State | Response template |
|---|---|---|
| MCP tool search returns 0 results; binary present on disk | installed, **not enabled for this project** | NOT ENABLED (below) |
| Binary absent from every path in the resolution order | not installed | TOOL MISSING (below) |

### NOT ENABLED response template

```text
TOOL PRESENT BUT NOT ENABLED HERE: <name>
WHY: this pack registers most MCP servers per project, not machine-wide
ENABLE:  TOOLS\Set-McpProfile.ps1 -Auto -Path "<project>"
   or:   TOOLS\Set-McpProfile.ps1 -Enable <profile> -Path "<project>"
SEE:     TOOLS\Set-McpProfile.ps1 -Detect -Path "<project>"
THEN:    restart the AI app - a running session does not pick up a new MCP server
```

Profiles worth naming: `game-skyrim-load-order` (houseCARL), `game-skyrim`
(Skyrim Forge), `code-intel` (codebase-memory + serena), `web` (Playwright,
Chrome DevTools). `-List` marks each server `REGISTERED for the project above`
or `ready, but NOT registered`; the second one is always one command away, on
Claude, Codex, Grok, Kimi and Hermes alike.

### Missing-tool response template

```text
TOOL MISSING: <name>
WHY NEEDED: <one sentence>
INSTALL: <official URL or pack section>
VERIFY: <one command that must succeed>
OPTIONAL: continue without it using <fallback>
```

Only recommend tools that help the active task. Do not nag about every optional tool every turn.

## Environment variables (optional, user-set)

| Variable | Tool |
|---|---|
| `SKYRIM_FORGE_ROOT` | Skyrim Forge product root |
| `HOUSECARL_ROOT` | houseCARL install folder (contains `housecarl\` or `housecarl-mcp.exe`) |
| `HOUSECARL_MCP` | Full path to `housecarl-mcp.exe` |
| `SPOOKY_AUTOMOD_ROOT` | Spooky's AutoMod Toolkit root (folder with `SpookysAutomod.sln` or `src\`) |
| `CODEBASE_MEMORY_MCP` | Full path to `codebase-memory-mcp.exe` |
| `HEADROOM_CMD` | `headroom` executable or `python -m headroom` entry |
| `SKYRIM_MO2_INSTANCE` | MO2 instance folder containing `ModOrganizer.ini` |

## Discovery script

Run the bundled script when available:

```text
tool-discovery\scripts\discover_tools.ps1
tool-discovery\scripts\discover_tools.ps1 -Json
```

It prints FOUND / MISSING for each known tool and never modifies the system.

## Per-tool checks (Windows)

### Skyrim Forge

- Env: `SKYRIM_FORGE_ROOT`
- Skill descriptor: `skyrim-forge\INSTALLATION.json` → `root`, `cli`, `mcp`
- Commands: `forge doctor`, or `python -m skyrim_forge doctor` from the product venv
- Install: user product tree / Forge release; skill alone is not the product
- Fallback: typed manual workflows + other tools; never write live Data

### houseCARL

- Env: `HOUSECARL_MCP`, `HOUSECARL_ROOT`
- Defaults to search (existence only):  
  `%LOCALAPPDATA%\Programs\houseCARL\**\housecarl-mcp.exe`  
  `%USERPROFILE%\.housecarl\**\housecarl-mcp.exe`  
  any path the user names
- MCP must be registered in the **current** AI app (Claude plugin, Codex config, Grok `config.toml`, etc.)
- Requirements: Windows x64, **.NET 9 Runtime + ASP.NET Core 9 Runtime**, MO2 instance
- Install: run `houseCARL-Setup.exe` from the houseCARL distribution, fully restart the AI app, then set MO2 instance
- Official product docs ship with the installer `START-HERE.txt` / `housecarl\README.md`
- Fallback when MCP absent: read-only file inspection + Forge if present; do **not** pretend load-order winners

### Spooky's AutoMod Toolkit

- Env: `SPOOKY_AUTOMOD_ROOT`
- Markers: `SpookysAutomod.sln`, `src\SpookysAutomod.Cli`, or built CLI under `src\`
- Verify:  
  `dotnet run --project src/SpookysAutomod.Cli -- --help`  
  (from toolkit root; always prefer `--json` on real commands)
- Requirements: Windows, **.NET 8 SDK** for build
- Install: https://github.com/SpookyPirate/spookys-automod-toolkit/releases or clone + `dotnet build`
- Fallback: houseCARL / Forge / Papyrus skill scripts

### codebase-memory-mcp

- Env: `CODEBASE_MEMORY_MCP`
- Default search:  
  `%LOCALAPPDATA%\Programs\codebase-memory-mcp\codebase-memory-mcp.exe`
- Verify: `codebase-memory-mcp.exe --version`
- Install: https://github.com/DeusData/codebase-memory-mcp  
  PowerShell installer from upstream `install.ps1` (optionally `--ui`)
- Provider wiring: MCP server entry must point at the **exe** with adequate startup timeout (Grok often needs 90s+)
- Grok repair helper ships in pack: `TOOLS\Fix-Grok-Codebase-Memory-Direct.ps1` (edit paths first)
- Fallback: ripgrep / codebase explore without graph

### Headroom

- Env: `HEADROOM_CMD`
- Verify: `headroom --help` or `python -m headroom --help`
- Install: https://github.com/headroomlabs-ai/headroom  
  `pip install "headroom-ai[mcp]"` or `"headroom-ai[proxy]"` then `headroom mcp install` where supported
- Tools (when MCP up): compress / retrieve / session stats
- Fallback: work without compression; warn on large contexts

### Superpowers

- Process skills under provider skills or Claude plugin cache
- Install: https://github.com/obra/superpowers
- If missing: follow pack-bundled copies of the skill markdown; recommend plugin install for hooks/automation

### Ponytail

- Skills: `ponytail`, `ponytail-review`, `ponytail-audit`, …
- Install: https://github.com/DietrichGebert/ponytail
- If missing: use bundled skill text; recommend plugin for native `/ponytail` UX

### CodeBurn

- Verify: `npx codeburn --help` or `codeburn --help`
- Install: https://github.com/getagentseal/codeburn — `npx codeburn` or `npm i -g codeburn` (Node 22.13+)
- Purpose: local AI token/cost dashboards and waste scans — not a Skyrim mod compiler
- Fallback: skip cost analytics

### MO2 instance

- Env: `SKYRIM_MO2_INSTANCE`
- Marker file: `ModOrganizer.ini` in the instance root
- Never assume a drive letter. Ask the user once and persist via houseCARL set-instance or project `STATE.md`.

## Provider MCP config pointers

| App | Typical config |
|---|---|
| Claude Code | Plugin / `.mcp.json` / Claude settings |
| Codex | `%CODEX_HOME%\config.toml` or Codex MCP UI |
| Grok Build | `%USERPROFILE%\.grok\config.toml` → `[mcp_servers.<name>]` |
| Cursor | MCP settings JSON |
| Others | Follow that app's MCP docs |

After editing MCP config: **fully restart** the AI application.

## Safety

- Discovery is read-only.
- Never copy another user's absolute paths into a shareable mod release.
- Never write to live Skyrim `Data`, MO2 overwrite, or saves while "just checking tools".

## houseCARL setup automation

If `housecarl-mcp` is FOUND but `SKYRIM_MO2_INSTANCE` / shim is unset, or MCP tools fail on missing instance:

```powershell
# Pack root:
TOOLS\Setup-HouseCarl.ps1
# Or skill-local:
housecarl\scripts\Setup-HouseCarl.ps1
```

Supports **MO2** (native) and **Vortex** (automatic MO2-shaped shim). See `housecarl` skill and `TOOLS\housecarl\README.md`.

State file after success:

```text
%LOCALAPPDATA%\houseCARL-data\uabs-setup-state.json
```

---

## AIO installer (pack)

New users and missing-tool recovery:

```powershell
# Pack root
.\INSTALL-AIO.ps1
.\INSTALL-AIO.ps1 -Mode OnlineLatest
.\TOOLS\Ensure-Tools.ps1
.\TOOLS\Update-From-GitHub.ps1
```

Offline snapshots live in `BUNDLED-TOOLS\offline\`. Component registry: `BUNDLED-TOOLS\CATALOG.json`.
After MCP changes the user must **fully restart** the AI application.
