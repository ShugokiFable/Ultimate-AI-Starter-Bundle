---
name: skyrim-racemenu-followers
description: Build or repair a shareable Skyrim follower from a RaceMenu or CharGen preset, including plugin records, FaceGen,
  head parts, tint, body assets, voice, recruitment, and skin-normal compatibility.
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
when_to_use: Use for build or repair a shareable skyrim follower from a racemenu or chargen preset, including plugin records,
  facegen, head parts, tint, body assets, voice, recruitment, and skin-normal compatibility.
---

# RaceMenu follower workflow

## Inputs

- Preset and sculpt data.
- Race, sex, weight, height, voice, combat style, class, outfit, and follower behavior.
- Body, skin, hair, eye, brow, and head-part dependencies.
- Redistribution permissions.

## Workflow

1. Freeze the asset and dependency plan before plugin authoring.
2. Create NPC, race/head-part, outfit, faction, relationship, package, and voice records through `skyrim-plugin-authoring`.
3. Generate FaceGen using a verified authoring path. Do not fake FaceGen by copying unrelated meshes.
4. Match weight, tint, head mesh, face normal, body normal, and skin texture sets.
5. Check dynamic normal-map or skin frameworks for post-load overrides when a match briefly appears then changes.
6. Add recruitment and dismissal through the smallest compatible framework or dialogue path.
7. Verify loose-file paths, archive layout, masters, and optional asset conditions.
8. Test dark-face, neck seam, expression, blinking, inventory, combat, dismissal, and save reload.

Do not ship presets or third-party assets without permission.

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

Test appearance across summon order, actor 3D readiness, save/reload, reset, and dynamic body/normal-map systems.

## Evidence-derived follower asset and lifecycle controls

- Detect dependencies by exact plugin name and active plugin set, not substrings or profile timestamps.
- Inspect BSA/BA2 archives and mod-manager virtual/deployed files; loose-file absence is not asset absence.
- Verify the actual face-tint/texture slot instead of assuming slot zero.
- Test dynamic body, skin, normal-map, OBody/preset, and appearance systems reapplying after actor 3D loads, summon order, reset, outfit change, and save reload.
