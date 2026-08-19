---
name: skyrim-fomod-packaging
description: Create and validate a Skyrim FOMOD installer, ModuleConfig.xml, info.xml, option groups, dependency flags, and
  deterministic Vortex/MO2-ready archive layout.
compatibility: Windows 10/11; Skyrim Special Edition or Anniversary Edition; PowerShell and Python 3 when bundled scripts
  are used
metadata:
  version: 4.3.0
  updated: '2026-07-22'
  library: overseer-skyrim-agent-skills
  provider: hermes
  provider_pack_version: 1.0.0
  base_library: Skyrim-Agent-Skills-v6
  error_registry_revision: 4.3.0
  final_pack_version: 4.3.0
when_to_use: Use for create and validate a skyrim fomod installer, moduleconfig.xml, info.xml, option groups, dependency flags,
  and deterministic vortex/mo2-ready archive layout.
effort: high
---

# FOMOD packaging

## Inputs

- Final validated core files and patches.
- Option matrix with mutually exclusive, optional, and required choices.
- Exact plugin and file dependencies.
- Install destinations and conflict policy.

## Rules

- Keep installer source folders separate from the deployed `Data` layout.
- Use explicit option names and descriptions that state dependencies and conflicts.
- Do not use file-existence conditions as a substitute for plugin dependency checks when the schema supports the correct dependency type.
- Avoid duplicate installation of the same destination from multiple selected options unless intentional and ordered.
- Keep one canonical core copy; patches should contain only their deltas.
- XML element order and schema behavior must match a known-good installed FOMOD or the current spec used by Vortex/MO2.

## Workflow

1. Draft the option matrix in a table.
2. Generate `fomod/info.xml` and `fomod/ModuleConfig.xml`.
3. Parse both XML files.
4. Run `scripts/validate_fomod.py` against the installer root.
5. Simulate every valid option combination or at least every dependency branch.
6. Inspect the final archive for an accidental extra root folder, nested `Data`, stale files, and missing sources.
7. Pass the result to `skyrim-ship-gate`.

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

Validate schema order and every branch against the final archive, not only the staging folder.

## Evidence-derived release inventory controls

Audit all public version strings across DLL metadata, manifests, MCM, README, changelog, installer, archive name, and logs. Validate an explicit release allowlist and keep PDBs, caches, intermediate outputs, and debug logs out of the user archive unless intentionally shipped in a separate developer/symbol package.
