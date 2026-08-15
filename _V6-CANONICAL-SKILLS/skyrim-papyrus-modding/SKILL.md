---
name: skyrim-papyrus-modding
description: Create, repair, compile, and validate Skyrim Papyrus scripts, quests, aliases, magic effects, MCM Helper integration,
  and save-safe event logic.
compatibility: Windows 10/11; Skyrim Special Edition or Anniversary Edition; PowerShell and Python 3 when bundled scripts
  are used
metadata:
  version: 4.3.0
  updated: '2026-07-22'
  library: overseer-skyrim-agent-skills
  error_registry_revision: 4.3.0
  final_pack_version: 4.3.0
---

# Papyrus modding

## Required inputs

- Exact Skyrim runtime and compiler.
- Source script, import roots, flags file, and output directory.
- Owning quest, alias, magic effect, or form.
- Required script-extender libraries and versions.
- Save-upgrade expectations.

## Architecture rules

- Choose the smallest lifecycle owner that matches the behavior.
- Prefer events and registered callbacks over polling loops.
- Unregister listeners and timers when the object stops owning them.
- Avoid expensive work in frequently firing events.
- Treat properties and VMAD attachment as part of the plugin contract.
- Use `Game.GetFormFromFile` or a verified soft-dependency pattern when a dependency is optional.
- Preserve property names and persisted state across updates unless a migration is provided.
- Use MCM Helper as the default for new configuration menus when the installed stack supports it; verify its exact schema from installed examples. Maintain SKI_ConfigBase as a legacy fallback and do not auto-migrate an existing menu without a save/configuration migration plan.

## Workflow

1. Map the script lifecycle and all external calls.
2. Inspect the exact declaration scripts for every dependency.
3. Implement source changes in the versioned workspace.
4. Compile with explicit import order. Use `scripts/compile_papyrus.ps1` or the project's equivalent.
5. Treat a successful compile as necessary but not sufficient.
6. Check VMAD attachment, properties, event registration, save upgrade, and runtime logs.
7. Package matching PSC and PEX policy intentionally. Do not ship stale PEX files.

## Adult projects

Preserve explicit technical strings, events, and intended adult-only behavior. Do not sanitize the implementation. Exclude child races, child actors, age-ambiguous characters, and real-person sexual content from adult systems.

## Evidence standard

Use this hierarchy for version-sensitive facts:

1. The active project's `ENVIRONMENT.md`, `TASK.md`, installed framework version, and build files.
2. Official upstream documentation or source for that exact version.
3. Known-good files from the user's installed mod library, read-only.
4. Direct inspection of the relevant ESM, ESP, DLL, script, log, or archive.

Do not substitute memory, an old example, or a plausible token. Record the evidence path or URL in `VALIDATION.md`.


## Runtime storage references

- `references/papyrusutil.md`
- `references/jcontainers.md`
- `references/runtime-data-storage-selection.md`
