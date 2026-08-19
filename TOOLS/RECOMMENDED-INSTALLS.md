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
| Skyrim Forge | **not bundled** | your product install |

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

## Manual only

Skyrim Forge 5.1.5+ — extract as `Skyrim-Forge-x.y.z` under your Skyrim tools folder (not Documents). Set `SKYRIM_FORGE_ROOT` or skill `INSTALLATION.json`. Claude Code needs 5.1.5+ (`resultType` on `tools/call`).
