---
name: skyrim-crash-diagnostics
description: Diagnose Skyrim startup, load, save, or runtime crashes from crash logs, recent changes, plugin lists, DLL inventories,
  and reproducible evidence without blaming the first named module.
compatibility: Windows 10/11; Skyrim Special Edition or Anniversary Edition; PowerShell and Python 3 when bundled scripts
  are used
metadata:
  version: 4.3.0
  updated: '2026-07-22'
  library: overseer-skyrim-agent-skills
  error_registry_revision: 4.3.0
  final_pack_version: 4.3.0
---

# Skyrim crash diagnostics

## Minimum evidence

- Full crash log, not a screenshot fragment.
- Exact game runtime and crash logger.
- `plugins.txt`, `loadorder.txt`, and mod-manager list.
- SKSE DLL inventory with versions.
- Recent additions, removals, updates, generated outputs, and behavior runs.
- Reproduction point and frequency.

## Method

1. Identify logger format and crash phase.
2. Separate exception, faulting instruction, registers, call stack, probable objects, loaded modules, and plugin list.
3. Treat named DLLs as stack participants until corroborated.
4. Correlate the log with recent changes and version compatibility.
5. Check missing masters, incompatible runtime DLLs, stale behavior output, bad assets, invalid FormIDs, and save-specific state.
6. Produce a ranked hypothesis list with evidence for and against each.
7. Recommend the smallest reversible isolation test.
8. After a culprit is confirmed, route the fix to the matching specialist.

## Avoid

- Declaring `Precision.dll`, `hdtSMP64.dll`, or another familiar module guilty solely because it appears near the top.
- Asking for mass disablement before testing the recent-change boundary.
- Editing the live modlist during diagnosis.
- Claiming certainty from a single ambiguous log.

## Evidence standard

Use this hierarchy for version-sensitive facts:

1. The active project's `ENVIRONMENT.md`, `TASK.md`, installed framework version, and build files.
2. Official upstream documentation or source for that exact version.
3. Known-good files from the user's installed mod library, read-only.
4. Direct inspection of the relevant ESM, ESP, DLL, script, log, or archive.

Do not substitute memory, an old example, or a plausible token. Record the evidence path or URL in `VALIDATION.md`.

## Evidence-derived environment controls

Compare the active installed build against every workspace/archive before diagnosing. Reproduce with the exact deployed dependency layout, not a same-directory harness. Include cell/world transitions, dialogue, followers, animation mods, appearance frameworks, and other competing systems when they share the lifecycle or actor state. Do not blame the named DLL before proving scope, lifetime, and the recent-change timeline.


## Non-crash runtime aborts

Some SKSE logs report that one feature declined to install a hook. Treat this as
a feature-level failure, not automatically a game crash or whole-plugin failure.

For `RVA outside .text`, `vtable mismatch`, or similar messages:

- confirm the plugin intentionally failed closed;
- record which feature is inactive;
- verify runtime, Address Library/CommonLib revision, relocation or vtable index;
- map the candidate pointer to its actual module;
- inspect target bytes and section permissions;
- test one setting toggle at a time;
- do not infer that another listed combat DLL is responsible without ownership
  evidence.

Route implementation fixes to `skyrim-skse-commonlib` and log interpretation to
`skyrim-runtime-log-forensics`.
