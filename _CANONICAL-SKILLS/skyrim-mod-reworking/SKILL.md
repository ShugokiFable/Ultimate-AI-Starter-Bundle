---
name: skyrim-mod-reworking
description: Orchestrate repair, modernization, compatibility work, or cleanup of an existing Skyrim mod while preserving
  behavior, save compatibility, ownership, and a reversible release history.
compatibility: Windows 10/11; Skyrim Special Edition or Anniversary Edition; PowerShell and Python 3 when bundled scripts
  are used
metadata:
  version: 4.3.0
  updated: '2026-07-22'
  library: overseer-skyrim-agent-skills
  provider: claude
  provider_pack_version: 1.0.0
  base_library: Skyrim-Agent-Skills-v6
  error_registry_revision: 4.3.0
when_to_use: Use for orchestrate repair, modernization, compatibility work, or cleanup of an existing skyrim mod while preserving
  behavior, save compatibility, ownership, and a reversible release history.
effort: high
---

# Existing mod reworking

## Inspect before changing

1. Inventory plugin records, scripts, DLLs, runtime configs, assets, installer, and documentation.
2. Reproduce the reported defect from logs or static evidence.
3. Identify the original mod's public contracts: FormIDs, EditorIDs, script names, properties, events, config paths, and save data.
4. Locate all compatibility patches and optional dependency paths.
5. Create the next full-copy version.

## Classify each proposed change

- bug fix;
- migration to a runtime framework;
- dependency replacement;
- plugin record change;
- Papyrus state migration;
- native DLL change;
- asset repair;
- packaging-only change.

Load the matching specialist. Do not let this orchestrator become a second syntax manual.

## Preservation rules

- Never clean, compact, renumber, strip masters, or rebuild a source plugin without a specific proven need.
- Preserve FormIDs and persisted Papyrus property/state contracts whenever possible.
- Do not delete unknown data simply because a custom parser cannot understand it.
- Treat generated FaceGen, behavior, cache, and LOD output as derived artifacts with identifiable source.
- Compare old and new release trees and document every removed file.

## Validation

Reproduce the original failure, prove the fix, then run regression checks for the preserved behavior. Use `skyrim-ship-gate` last.

## Evidence standard

Use this hierarchy for version-sensitive facts:

1. The active project's `ENVIRONMENT.md`, `TASK.md`, installed framework version, and build files.
2. Official upstream documentation or source for that exact version.
3. Known-good files from the user's installed mod library, read-only.
4. Direct inspection of the relevant ESM, ESP, DLL, script, log, or archive.

Do not substitute memory, an old example, or a plausible token. Record the evidence path or URL in `VALIDATION.md`.

## Claude Code execution adapter

- Keep `CLAUDE.md` concise and use this skill for procedural detail.
- Load only the skills needed for the current milestone because invoked skill content remains in context.
- Use high or xhigh effort for risky architecture, plugins, DLLs, and hostile review.
- Before compaction or a usage boundary, persist exact state, commands, uncommitted changes, and remaining validation.
- Treat auto memory as candidate learning, not verified truth, until it passes the memory-promotion protocol.

### Skill-specific provider control

Diff against the last known-good release and explain every removed feature, file, record family, and installer option.

## Evidence-derived regression accounting

Maintain a defect and feature matrix across original, parent, active, and final artifacts. Separate inherited defects from regressions introduced by the current AI. Trace every README, MCM, and Nexus claim to implemented files and validation. Label prototypes, bootstraps, and approximations explicitly. Test the real user symptom before and after the rework.
