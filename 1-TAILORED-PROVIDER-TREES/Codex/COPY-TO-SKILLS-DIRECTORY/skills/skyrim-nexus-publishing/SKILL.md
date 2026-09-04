---
name: skyrim-nexus-publishing
description: Prepare a truthful, visually strong Nexus Mods publication kit: page copy, screenshots and previews, requirements,
  permissions, credits, changelog, troubleshooting, and file metadata after the artifact passes the ship gate.
compatibility: Windows 10/11; Skyrim Special Edition or Anniversary Edition; PowerShell and Python 3 when bundled scripts
  are used
metadata:
  version: 4.4.0
  updated: '2026-09-03'
  library: overseer-skyrim-agent-skills
  provider: codex
  provider_pack_version: 1.0.0
  base_library: Skyrim-Agent-Skills-v6
  error_registry_revision: 4.3.0
when_to_use: Use for preparing a Nexus Mods page, media gallery, BBCode description, requirements, permissions, changelog,
  credits, troubleshooting, and file metadata after the artifact passes the ship gate.
---

# Nexus publishing

## Prerequisites

Do not write "tested," "compatible," "clean," or "safe to update" unless the supplied validation evidence supports the exact claim.

For a public Skyrim release, use Skyrim Forge's `nexus-*` workflow for the archive, rights inventory, policy review, uploader
attestation, and generated compliance documents. This skill owns the public presentation pass; Forge's audit does not prove that
the page or screenshots look good.

## Deliverables

- Short summary.
- Detailed BBCode description with a clear visual hierarchy.
- Upload-ready media folder and `NEXUS-MEDIA-PLAN.md` describing every image/video, caption, purpose, version, author, source,
  editing, and permission basis.
- Features and technical architecture.
- Requirements separated into hard, optional, and tool-only dependencies.
- Installation, update, uninstall, and compatibility instructions.
- Known limitations and unperformed tests.
- Changelog and version number matching the archive.
- Credits and permissions for every third-party asset or code source.
- Troubleshooting with exact log paths and information users should provide.

Keep publication media beside the publication workspace, not inside the gameplay archive unless the project deliberately ships it.

## Presentation contract

Build the media set from the final release, then inspect the actual pixels with `visual-verification`.

- Make one crop-safe 16:9 hero/thumbnail with a readable title, one obvious focal subject, and enough contrast to survive card size.
- Aim for four to eight useful images: hero, core feature, proof of the feature working, a close/detail view, and before/after,
  configuration, compatibility, or installation views only when they add information.
- For animation, combat, interaction, audio, or workflow mods, add one short representative video or GIF; a still frame is not
  runtime proof.
- Give every visual concise alt text and a caption that says what is visible and what it proves.
- Keep a consistent title treatment, accent palette, crop, and visual identity across the hero and gallery. Composition matters more
  than decoration.
- Remove desktop clutter, notifications, debug overlays, unrelated UI, and accidental personal information. Keep HUD elements when
  they are the feature being demonstrated.
- If other visual mods, ENB/ReShade, post-processing, composites, generated art, or edits materially affect the image, disclose them
  in the caption/media plan. Never present concept art or generated imagery as an in-game result.
- Screenshots, video, filenames, captions, and displayed version must match the exact archive being published.

If no verified final-state media exists, create a precise capture list and mark presentation incomplete. Do not fabricate gameplay
screenshots or quietly reuse media from an older version.

## Page hierarchy

Use this order unless the mod genuinely needs something different:

1. Mod name, one-sentence value proposition, and hero/showcase.
2. Short introduction explaining the player-facing problem and result.
3. Scannable feature highlights, with a proof image or clip near the relevant feature.
4. Quick start, hard requirements, installation, update, and uninstall.
5. Compatibility, configuration, known limitations, and unperformed tests.
6. Troubleshooting and support evidence to provide.
7. Authors, asset-by-asset credits, licences/permissions, source links, and AI disclosure.
8. Concise version-matched changelog.

Lead with the experience; keep implementation detail below the player-facing explanation. Use headings and short paragraphs, not a
single wall of text. Do not copy another author's branding, images, page text, or visual assets.

## Media rights

Treat public screenshots, thumbnails, logos, music, fonts, renders, and video as publication assets even when they are not inside the
download ZIP. Record for each item:

- author/creator and source URL;
- whether it is original, commissioned, captured from the final mod, generated, or third-party;
- licence or explicit permission basis, required credit, and any edit/redistribution limits;
- the release version and capture/edit disclosure.

Credit is not permission. Do not use another mod author's promotional image merely because it is public. When third-party assets are
visible in a screenshot, credit/disclose them when their licence or the presentation context requires it.

## Minimal-input behavior

Derive the first draft, feature list, capture list, requirements, credits candidates, and page structure from the project files,
release archive, validation evidence, and existing final-state captures. Ask the user only for facts that cannot be established safely:
an uploader attestation, missing permission evidence, or a real in-game capture/test that tools cannot perform. Leave explicit
placeholders for those facts; never fill them with guesses.

## Rules

- Do not claim ownership of derived assets.
- Do not copy another author's description or documentation.
- Remove references to assets or authors not actually used.
- Keep adult releases accurately tagged and described without sanitizing their technical purpose.
- Do not include personal local paths, API keys, crash-log identities, or private repository links.
- Ensure screenshots, previews, links, and file names match the shipped version.

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
