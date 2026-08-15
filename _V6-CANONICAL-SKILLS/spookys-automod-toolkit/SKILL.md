---
name: spookys-automod-toolkit
description: Drive Spooky's AutoMod Toolkit CLI for Skyrim ESP, Papyrus, MCM, NIF, BSA/BA2, audio, and SKSE project workflows. Resolve toolkit root portably; recommend install when missing. Use with module skills skyrim-esp, skyrim-papyrus, skyrim-mcm, skyrim-nif, skyrim-archive, skyrim-audio, skyrim-skse.
metadata:
  version: 5.0.0
  toolkit_version_pinned: 1.11.2
  final_pack_version: 5.0.0
---

# Spooky's AutoMod Toolkit

CLI toolkit designed for AI assistants to create and modify Skyrim mods programmatically.

Upstream: https://github.com/SpookyPirate/spookys-automod-toolkit

## Resolve installation

1. `$env:SPOOKY_AUTOMOD_ROOT` if set and valid
2. `tool-discovery` script result for `spookys-automod-toolkit`
3. User-supplied path
4. If missing → recommend install (do not invent commands against a phantom tree)

**Valid root markers:** `SpookysAutomod.sln` and/or `src/SpookysAutomod.Cli`

## Install recommendation

```text
TOOL MISSING: Spooky's AutoMod Toolkit
INSTALL:
  - Release zip + SpookysAutomodSetup.exe from GitHub Releases
  - or: git clone + dotnet build SpookysAutomod.sln
REQUIREMENTS: Windows, .NET 8 SDK
VERIFY: dotnet run --project src/SpookysAutomod.Cli -- --help
DOCS: references/README.md , references/llm-init-prompt.md , references/llm-guide.md
```

## Command shape

From toolkit root:

```bash
dotnet run --project src/SpookysAutomod.Cli -- <module> <command> [args] [options]
```

**Always pass `--json`** on non-interactive AI runs for parseable output.

Modules (load matching skill for details):

| Module | Skill |
|---|---|
| esp | `skyrim-esp` |
| papyrus | `skyrim-papyrus` |
| mcm | `skyrim-mcm` |
| nif | `skyrim-nif` |
| archive | `skyrim-archive` |
| audio | `skyrim-audio` |
| skse | `skyrim-skse` |

## Safety (mandatory)

- Work only in the **user-owned project / version snapshot**, never live MO2 mods or game `Data` unless the user explicitly owns that path as the project.
- Prefer `--light` ESL-friendly plugins when appropriate; still obey HEDR/light-id laws from the pack.
- Papyrus headers come from the user's Creation Kit — do not download Bethesda sources from random internet mirrors.
- Read `references/llm-init-prompt.md` once per session before large toolkit work.
- Use module skills for flags; do not invent subcommands — run `--help` / check references.

## When to choose Spooky vs houseCARL vs Forge

- **Spooky:** greenfield CLI authoring inside a project tree; BSA surgery; NIF CLI; SKSE project scaffold.
- **houseCARL:** questions about the **live load order**, conflict winners, reviewable patches into MO2.
- **Forge:** typed multi-step validation, release/FOMOD/nexus gates, capability broker.

## If toolkit build fails

1. Confirm `dotnet --version` is 8+ SDK
2. `dotnet nuget add source https://api.nuget.org/v3/index.json -n nuget.org` if restore fails
3. Re-run setup wizard when present
4. Fall back to houseCARL/Forge/Papyrus skills and report the blocker
