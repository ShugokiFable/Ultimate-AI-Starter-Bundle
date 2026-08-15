# BUNDLED-TOOLS

Offline snapshots + GitHub update path for Skyrim AI V5 AIO.

## Quick install (new users)

Double-click or run from pack root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\INSTALL-V6-AIO.ps1
```

## Layout

| Path | Purpose |
|---|---|
| `offline\` | Zipped tool snapshots shipped with the pack |
| `plugins\` | Superpowers + Ponytail plugin trees (Claude-friendly) |
| `CATALOG.json` | Component IDs, GitHub repos, install rules |
| `cache\` | Created at runtime for OnlineLatest downloads |

## Modes

| Mode | Behavior |
|---|---|
| `BundledFirst` (default) | Use offline zip if present; else GitHub latest |
| `OnlineLatest` | Always query GitHub releases/latest |
| `BundledOnly` | Never network; fail if offline asset missing |

## Update later

```powershell
.\TOOLS\Update-From-GitHub.ps1
.\TOOLS\Update-From-GitHub.ps1 -Components housecarl,codebase-memory
```

## Licenses

Redistributed binaries/zips remain under upstream licenses. See each project's GitHub.
Do not re-upload this pack to Nexus as if you own third-party tools.
