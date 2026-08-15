---
name: skyrim-modding-facts
description: Evidence gate for Skyrim facts that are easy to hallucinate, including framework syntax, FormIDs, EditorIDs,
  plugin headers, Papyrus APIs, hooks, and paths. Use when any such detail is uncertain.
compatibility: Windows 10/11; Skyrim Special Edition or Anniversary Edition; PowerShell and Python 3 when bundled scripts
  are used
metadata:
  version: 4.3.0
  updated: '2026-07-22'
  library: overseer-skyrim-agent-skills
  error_registry_revision: 4.3.0
  final_pack_version: 4.3.0
---

# Skyrim modding facts


## Evidence standard

Use this hierarchy for version-sensitive facts:

1. The active project's `ENVIRONMENT.md`, `TASK.md`, installed framework version, and build files.
2. Official upstream documentation or source for that exact version.
3. Known-good files from the user's installed mod library, read-only.
4. Direct inspection of the relevant ESM, ESP, DLL, script, log, or archive.

Do not substitute memory, an old example, or a plausible token. Record the evidence path or URL in `VALIDATION.md`.


## Hard rules

- Search the installed version and known-good files before generating syntax.
- Resolve every plugin-qualified FormID against the named plugin.
- Distinguish file-local IDs from load-order-resolved IDs.
- Distinguish an API declaration from runtime availability.
- Distinguish a crash-log module mention from a proven culprit.
- Do not infer support from a framework name alone. Check the exact release.
- Do not launch SSEEdit, xEdit, or Creation Kit GUI under this user's workflow. Never fabricate their results.

## Target-aware plugin defaults

- Declare runtime, toolchain, and backport support before choosing HEDR.
- Legacy light allocation: HEDR 1.70 and new local IDs 0x800-0xFFF.
- Extended allocation: HEDR 1.71 and new local IDs 0x001-0xFFF.
- A plugin using any extended local ID below 0x800 must list `Skyrim.esm` as its first master.
- A dependent module must be compatible with 1.71 masters and preserve their complete required master chain.
- New SSE/AE records normally use form version 44; inspect historical records before normalization.

Read `references/plugin-invariants.md` before plugin work.

## Stop conditions

Stop rather than guess when:

- a record field is unsupported by the selected writer;
- a framework token cannot be found in official or installed examples;
- a FormID cannot be resolved to the intended record;
- the target runtime or dependency version is unknown;
- validation would require a GUI step the agent cannot truthfully perform.

## Evidence-derived fact checks

Resolve exact condition semantics, parser field types, quoting rules, encodings, filenames, asset slots, archive behavior, and binary sidecar formats from the installed version or upstream source. Plausible function names are not enough. Verify whether a helper tests presence, reads keyword DATA, returns an index, expects an integer, or treats quotes literally.


## Locked parser facts

- Current SPID does not define a `Weapon` key. Inventory objects use `Item` or
  generic `Form`.
- SPID LevelFilters `65/` is malformed; both range endpoints are required.
- SPID trait `D`/`-D` is valid.
- SPID chance `18!` is valid deterministic chance.
- One framework's wildcard or delimiter syntax never authorizes the same token
  in another framework.
- A log's parser exception must be mapped to the actual field before editing.
- A hook target outside an expected executable section proves an invalid target,
  not the identity of the conflicting DLL.
- Community Shaders feature descriptors are version-sensitive and must be
  checked at the exact deployed path for the installed release.
