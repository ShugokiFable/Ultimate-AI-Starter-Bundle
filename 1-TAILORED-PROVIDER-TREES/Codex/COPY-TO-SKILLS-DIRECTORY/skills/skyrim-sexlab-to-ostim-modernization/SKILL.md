---
name: skyrim-sexlab-to-ostim-modernization
description: Migrate a fictional adult-only Skyrim mod from SexLab APIs and events to the exact installed OStim ecosystem
  while preserving gameplay semantics, explicit content, configuration, and save compatibility.
compatibility: Windows 10/11; Skyrim Special Edition or Anniversary Edition; PowerShell and Python 3 when bundled scripts
  are used
metadata:
  version: 4.3.0
  updated: '2026-07-22'
  library: overseer-skyrim-agent-skills
  provider: codex
  provider_pack_version: 1.0.0
  base_library: Skyrim-Agent-Skills-v6
  error_registry_revision: 4.3.0
when_to_use: Use for migrate a fictional adult-only skyrim mod from sexlab apis and events to the exact installed ostim ecosystem
  while preserving gameplay semantics, explicit content, configuration, and save compatibility.
---

# SexLab to OStim modernization

## Scope

This skill is for technical work on fictional adults. Preserve explicit strings, scene identifiers, and intended behavior. Do not sanitize the mod. Exclude child races, child actors, age-ambiguous characters, and real-person sexual content.

## Workflow

1. Inventory every SexLab import, property, event, callback, animation tag, actor-selection rule, stripping rule, scene state, and MCM option.
2. Record the exact installed OStim core and add-on versions. API names are version-sensitive.
3. Build a mapping table from old behavior to new behavior. Mark unsupported semantics explicitly.
4. Inspect the actual declaration scripts and known-good installed integrations.
5. Migrate one vertical scene path first and compile it in isolation.
6. Preserve actor eligibility, consent/design rules, interruption, cleanup, equipment restoration, failure recovery, and save state.
7. Migrate plugin properties and optional dependencies through `skyrim-plugin-authoring`.
8. Update FOMOD choices and documentation without shipping incompatible scripts together.
9. Compile all scripts and test start, transition, interruption, end, reload, and missing-dependency paths.

Never perform a blind namespace substitution. Similar names do not imply equivalent lifecycle semantics.

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

Preserve explicit adult-only fictional behavior while verifying the exact installed OStim lifecycle and API.
