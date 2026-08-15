---
name: skyrim-code-review
description: Read-only Skyrim-specific correctness and maintainability review for Papyrus, native code, plugin tooling, runtime-patching
  configs, installers, and release scripts. Use when the user asks for a review or hostile audit; do not edit unless asked.
compatibility: Windows 10/11; Skyrim Special Edition or Anniversary Edition; PowerShell and Python 3 when bundled scripts
  are used
metadata:
  version: 4.3.0
  updated: '2026-07-22'
  library: overseer-skyrim-agent-skills
  error_registry_revision: 4.3.0
  final_pack_version: 4.3.0
---

# Skyrim code and configuration review

## Review priorities

1. Correctness and data integrity.
2. Safety of file writes and rollback behavior.
3. API, ABI, runtime, and save compatibility.
4. Error handling, diagnostics, and observability.
5. Concurrency, ownership, lifetime, and resource management.
6. Performance proportional to the actual hot path.
7. Maintainability: cohesion, naming, duplication, boundaries, and testability.
8. Release behavior and upgrade path.

## Method

- Read the task and architecture before judging individual lines.
- Trace inputs through transformations to outputs.
- Identify assumptions and verify them against code or documentation.
- Separate confirmed defects from risks and stylistic preferences.
- Include file and line references.
- Prefer a small number of load-bearing findings over a landfill of cosmetic notes.

## Severity

- **Critical:** corruption, crash, security issue, irreversible write, broken release.
- **High:** common incorrect behavior, major compatibility defect, missing validation.
- **Medium:** edge-case bug, difficult maintenance, misleading diagnostics.
- **Low:** localized clarity or consistency issue.

Finish with a prioritized fix order and the tests required to close each finding.

## Parser-field review

When reviewing SPID, KID, BOS, CDF, FLM, SkyPatcher, or similar configurations:

- map each row into its framework-specific fields;
- verify the key before reviewing the value;
- do not use whole-line delimiter searches as syntax verdicts;
- check parser error messages against the parser stage that emits them;
- identify rules that parse but resolve zero targets;
- distinguish optional no-ops from broken required features;
- run the dedicated validators and inspect runtime logs.

Specifically reject SPID `Weapon =`, incomplete LevelFilters such as `65/`,
comma TraitFilters, and more than seven value sections.
