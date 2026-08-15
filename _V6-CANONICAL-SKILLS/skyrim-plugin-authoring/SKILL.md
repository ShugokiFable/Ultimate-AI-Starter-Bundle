---
name: skyrim-plugin-authoring
description: Author or patch Skyrim ESP, ESL, and ESM files, masters, records, and VMAD using typed tooling and structural
  validation. Use when a text framework cannot express the change.
compatibility: Windows 10/11; Skyrim Special Edition or Anniversary Edition; PowerShell and Python 3 when bundled scripts
  are used
metadata:
  version: 4.3.0
  updated: '2026-07-22'
  library: overseer-skyrim-agent-skills
  error_registry_revision: 4.3.0
  final_pack_version: 4.3.0
---

# Skyrim plugin authoring

## Decision order

1. Confirm a plugin is actually required. Prefer SPID, KID, SkyPatcher, FLM, BOS, CDF, or Papyrus runtime lookup when they express the change safely.
2. For typed record creation or overrides, prefer a Mutagen C# tool or Synthesis patcher pinned to the target game release.
3. For an existing plugin, load a workspace copy and preserve masters, flags, unknown subrecords, and override identity unless the plan explicitly changes them.
4. Use raw binary surgery only for a narrow, fully specified transformation with a parser, fixture tests, before/after structural audit, and byte-level diff. It is never the default writer.
5. If the selected typed library cannot represent the required record family, stop rather than improvising bytes.

## Required inputs

- Target runtime and plugin type.
- Source plugin and required masters.
- Exact record plan with EditorIDs or resolved FormIDs.
- Save-compatibility requirements.
- Script and VMAD requirements.
- Expected new-record count and light-plugin eligibility.

## Plugin defaults

Read `references/plugin-invariants.md`. Legacy light plugins use HEDR 1.70 and new local IDs 0x800-0xFFF. Extended light output uses HEDR 1.71 and local IDs 0x001-0xFFF; when any local ID below 0x800 is used, `Skyrim.esm` must be the first master. Validate the complete master chain.

## Workflow

1. Run Forge Bridge header/scan where useful.
2. Generate a machine-readable record plan.
3. Implement with a typed writer in an isolated project.
4. Reload the produced plugin with the same library and compare intended records.
5. Run `scripts/audit_plugin_headers.py`; supply `--master-root` when master files are available.
6. Run `scripts/test_plugin_header_fixtures.py` after changing the validator.
6. Compile attached Papyrus scripts separately.
7. Verify masters, record count, FormID allocation, ESL flag, and archive path.
8. Record what was not semantically validated without xEdit or Creation Kit.

## Stop conditions

Do not claim completion for navmesh, facegen, complex dialogue/scene data, or unsupported VMAD structures unless the actual authoring and validation path exists.

## Evidence standard

Use this hierarchy for version-sensitive facts:

1. The active project's `ENVIRONMENT.md`, `TASK.md`, installed framework version, and build files.
2. Official upstream documentation or source for that exact version.
3. Known-good files from the user's installed mod library, read-only.
4. Direct inspection of the relevant ESM, ESP, DLL, script, log, or archive.

Do not substitute memory, an old example, or a plausible token. Record the evidence path or URL in `VALIDATION.md`.

## Evidence-derived plugin controls

- VMAD validation must cover string encoding, object format, property data order, script/property visibility, and master/local FormID ownership.
- Treat SEQ as a verified binary artifact. Never emit ASCII FormIDs or invent a `SEQS` header.
- Audit HEDR counts against the exact parser/tool contract, including GRUP handling when required by that format.
- Keep an immutable original and parent. Classify defects as inherited, fixed, newly introduced, or unverified.
- Compare final public claims, MCM text, record plan, and actual implementation.
