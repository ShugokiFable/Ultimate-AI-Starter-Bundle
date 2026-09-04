---
name: skyrim-mod-development
description: Orchestrate a new Skyrim SE/AE mod or major feature from requirements through implementation, validation, packaging,
  and release. This skill coordinates specialists and does not own framework syntax.
compatibility: Windows 10/11; Skyrim Special Edition or Anniversary Edition; PowerShell and Python 3 when bundled scripts
  are used
metadata:
  version: 4.4.0
  updated: '2026-09-03'
  library: overseer-skyrim-agent-skills
  provider: claude
  provider_pack_version: 1.0.0
  base_library: Skyrim-Agent-Skills-v6
  error_registry_revision: 4.3.0
when_to_use: Use for orchestrate a new skyrim se/ae mod or major feature from requirements through implementation, validation,
  packaging, and release. this skill coordinates specialists and does not own framework syntax.
effort: high
---

# New Skyrim mod development

## Phase 1: define

- Write the player-facing behavior and non-goals.
- Record runtime, dependencies, compatibility promises, save policy, and adult-content scope if applicable.
- Choose the smallest architecture using `skyrim-tool-router`.
- Create the versioned workspace and a test matrix.

## Phase 2: design

Produce a machine-readable plan separating:

- plugin records;
- Papyrus;
- runtime configuration;
- native DLL code;
- assets and animations;
- installer and documentation.

Each component needs an owner skill and its own validation command.

### Player experience and visual direction

Treat usability and visual quality as product requirements, not release-page decoration. For any player-facing menu, HUD, preview,
asset, or interaction:

- define the primary player loop and keep its most common actions in one coherent surface;
- give the result/character/object enough screen space to be the focal point, with live preview when the framework can support it;
- use a consistent grid, spacing scale, typography, icon family, selected state, and restrained accent palette;
- group complex controls by task, use progressive disclosure for advanced options, and keep search/filter/category state visible;
- provide immediate apply/undo/error feedback and safe defaults; auto-discover valid content instead of demanding manual IDs when
  the installed framework exposes a supported discovery path;
- design empty, loading, unsupported-dependency, long-list, and failure states instead of only the ideal screenshot;
- preserve legibility at supported resolutions/UI scales and do not use colour as the only state signal;
- plan keyboard and controller navigation, focus order, tooltips, and escape/back behaviour when the chosen UI framework supports them.

Load `visual-verification` for the vertical slice. A polished reference can guide hierarchy and interaction patterns, but never copy
its branding, artwork, source, exact layout, or proprietary assets.

When a concrete Skyrim reference is useful, study the current public visuals for
[`Fitting Room - ESO Style Transmog`](https://www.nexusmods.com/skyrimspecialedition/mods/185342): its preview-dominant split
layout, task navigation, search/filter/category hierarchy, item cards, live character feedback, cohesive translucent surfaces, and
compact controls are quality patterns, not assets or a layout to clone.

## Phase 3: implement

- Build a minimal vertical slice first.
- Make the vertical slice include the real player-facing interaction and final visual system, not a disposable debug UI.
- Validate each layer before adding the next.
- Keep generated records/configs reproducible from manifests or source.
- Preserve optional dependencies as soft dependencies when practical.
- Do not add a DLL or ESP merely because the model can write one.

## Phase 4: integrate

- Test dependency absent/present cases.
- Test new game and existing-save scenarios when relevant.
- Check conflicts with the explicit target frameworks and mods.
- Review performance on the actual event or hook frequency.
- Exercise every supported input path, resolution/UI scale, empty/error state, and a realistically large content set. Inspect final
  rendered pixels after the last change; code and screenshots from an older build are not visual evidence.

## Phase 5: ship

Use `skyrim-fomod-packaging`, `skyrim-ship-gate`, then `skyrim-nexus-publishing`. The publication media should demonstrate the same
final in-game quality; it must not hide an unfinished interface behind attractive concept art.

A new mod is not complete because files exist. It is complete when the required build and validators pass and unresolved in-game tests are disclosed.

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

Create a requirements ledger, ownership record, and validation plan before implementation.
