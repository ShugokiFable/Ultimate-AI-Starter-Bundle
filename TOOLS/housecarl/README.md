# houseCARL automatic setup (V5)

houseCARL reads an **MO2-shaped instance** (folder with `ModOrganizer.ini` + profile txt files + `mods\`).

| Your manager | What setup does |
|---|---|
| **Mod Organizer 2** | Finds instance(s) with `ModOrganizer.ini` and points houseCARL at one |
| **Vortex** | Builds a **shim** under `%LOCALAPPDATA%\houseCARL-Shim` that looks like MO2, with `mods` junctioned to Vortex staging and `plugins.txt` from `%LOCALAPPDATA%\Skyrim Special Edition` |

Source design for the Vortex path: `housecarl/houseCARL-Vortex-shim-setup.pdf` (in this folder).

## One command

```powershell
cd "<PACK>\TOOLS"
powershell -NoProfile -ExecutionPolicy Bypass -File .\Setup-HouseCarl.ps1
```

### Common options

```powershell
# Force Vortex shim
.\Setup-HouseCarl.ps1 -Manager Vortex

# Force a specific MO2 instance
.\Setup-HouseCarl.ps1 -Manager MO2 -Mo2Instance "D:\MO2\instances\MyList"

# Explicit Vortex staging + game path
.\Setup-HouseCarl.ps1 -Manager Vortex `
  -VortexStaging "D:\Vortex Mods\skyrimse\mods" `
  -SkyrimPath "C:\Program Files (x86)\Steam\steamapps\common\Skyrim Special Edition"

# After you change load order / install mods in Vortex (copy mode)
.\Setup-HouseCarl.ps1 -RefreshOnly

# Point at a non-default MCP binary
.\Setup-HouseCarl.ps1 -HouseCarlMcp "D:\tools\housecarl-mcp.exe"
```

## Prerequisites

1. **houseCARL installed** so `housecarl-mcp.exe` exists  
   - Official: run `houseCARL-Setup.exe`  
   - Or portable folder containing `server\housecarl-mcp.exe`
2. **.NET 9 Runtime** and **ASP.NET Core 9 Runtime**  
   https://dotnet.microsoft.com/download/dotnet/9.0  
   `winget install Microsoft.DotNet.Runtime.9`  
   `winget install Microsoft.DotNet.AspNetCore.9`
3. **Skyrim SE** install (for Vortex shim `gamePath`)
4. **plugins.txt** under `%LOCALAPPDATA%\Skyrim Special Edition` (launch game or Vortex once)

## What the script sets

| Item | Purpose |
|---|---|
| `HOUSECARL_MCP` | Path to MCP exe |
| `SKYRIM_MO2_INSTANCE` | MO2 instance **or** Vortex shim root |
| `HouseCarl__Mo2InstanceDir` | Same path — read by houseCARL server |
| `%LOCALAPPDATA%\houseCARL-data\v5-setup-state.json` | Machine state for AIs |
| Grok `%USERPROFILE%\.grok\config.toml` | `[mcp_servers.housecarl]` block (when `-WireGrok`) |

Then **fully restart** the AI app.

## Claude Code

Prefer `houseCARL-Setup.exe` for the plugin. Set plugin user config **MO2 instance folder** to the same path the script prints (real MO2 instance or the shim).

## Vortex caveats (important)

- Plugin load order from `plugins.txt` is **exact**.
- Loose-file priority via generated `modlist.txt` is **approximate** (mtime heuristic).
- Re-run `-RefreshOnly` after load-order changes if you did not symlink plugins.
- houseCARL patch folders appear as `houseCARL - <name>` under Vortex staging — **import into Vortex and Deploy** (drag folder or zip install).
- For heavy loose-file conflict authoring, a parallel real MO2 instance is cleaner than the shim.

## AI agent contract

When houseCARL is missing or unconfigured, agents should run or recommend:

```text
TOOLS\Setup-HouseCarl.ps1
```

Do not invent load-order winners. Do not require `S:\` or a specific username.
