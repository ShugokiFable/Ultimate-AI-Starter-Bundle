---
name: skyrim-nexus-publishing
description: Prepare a Nexus Mods release page, BBCode description, requirements, permissions, changelog, credits, troubleshooting,
  and file metadata after the artifact passes the ship gate.
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
  final_pack_version: 4.3.0
when_to_use: Use for prepare a nexus mods release page, bbcode description, requirements, permissions, changelog, credits,
  troubleshooting, and file metadata after the artifact passes the ship gate.
---

# Nexus publishing

## Prerequisite

Do not write "tested," "compatible," "clean," or "safe to update" unless the supplied validation evidence supports the exact claim.

## Deliverables

- Short summary.
- Detailed BBCode description.
- Features and technical architecture.
- Requirements separated into hard, optional, and tool-only dependencies.
- Installation, update, uninstall, and compatibility instructions.
- Known limitations and unperformed tests.
- Changelog and version number matching the archive.
- Credits and permissions for every third-party asset or code source.
- Troubleshooting with exact log paths and information users should provide.

## Rules

- Do not claim ownership of derived assets.
- Do not copy another author's description or documentation.
- Remove references to assets or authors not actually used.
- Keep adult releases accurately tagged and described without sanitizing their technical purpose.
- Do not include personal local paths, API keys, crash-log identities, or private repository links.
- Ensure screenshots and file names match the shipped version.

The final page must distinguish static validation from in-game testing.

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

Publish only after the ship gate passes; keep claims aligned with the actual archive and permissions.
