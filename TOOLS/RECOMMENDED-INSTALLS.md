# Recommended installs (V5 AIO)

## Easiest

```powershell
.\INSTALL-V7-AIO.bat
```

## What you get

| Tool | Bundled offline | GitHub updates |
|---|---|---|
| Skills (all providers) | yes (pack) | pack updates |
| houseCARL | yes zip | Avick3110/houseCARL |
| Spooky's AutoMod Toolkit | yes zip | SpookyPirate/spookys-automod-toolkit |
| codebase-memory-mcp | yes zip | DeusData/codebase-memory-mcp |
| Headroom | yes wheel | headroomlabs-ai/headroom |
| Superpowers | yes zip + plugins/ | obra/superpowers |
| Ponytail | yes zip + plugins/ | DietrichGebert/ponytail |
| CodeBurn | npx/npm | getagentseal/codeburn |
| Skyrim Forge 5.2.1 | **required payload bundled** | installed/repaired automatically by v7.9.0 |

## Later updates

```powershell
.\TOOLS\Update-From-GitHub.ps1
.\TOOLS\Ensure-Tools.ps1
```

## Runtimes (installer tries winget)

- .NET 9 Runtime + ASP.NET Core 9 (houseCARL)
- .NET 8 SDK (Spooky build/run from source)
- Python 3 (Headroom)
- Node.js LTS (CodeBurn)

## Bundle-managed

Skyrim Forge 5.2.1 ships with v7.9.0 and is installed, compatibility-checked, skill-wired, and MCP-registered by the AIO installer. `SKYRIM_FORGE_ROOT` and the per-provider skill descriptor are generated automatically; no manual extraction is part of a fresh install. The install directory never carries a version suffix, so an upgrade cannot disconnect a provider whose MCP command is an absolute path.
