---
name: check-work
description: Post-change verification workflow. Use after implementation to independently inspect diffs, run the real build
  and validators, and decide whether the requested artifact is actually complete.
compatibility: Windows 10/11; Skyrim Special Edition or Anniversary Edition; PowerShell and Python 3 when bundled scripts
  are used
metadata:
  version: 4.3.0
  updated: '2026-07-22'
  library: overseer-skyrim-agent-skills
  error_registry_revision: 4.3.0
---

# Check work

This skill verifies completed work. It does not replace implementation planning or domain-specific validation.

## Procedure

1. Re-read the task's stated completion criteria.
2. Inspect the complete diff and list every modified, added, removed, or generated file.
3. Look for scope creep, accidental rewrites, placeholder content, stale copies, and missing artifacts.
4. Run the project-defined build, compiler, test, linter, and package validators.
5. Verify the built artifact rather than assuming source success implies release success.
6. Compare public interfaces, paths, record IDs, configuration names, and archive layout against the prior version.
7. Check negative cases: missing dependency, malformed input, empty result, duplicate entry, unsupported runtime, and interrupted execution where relevant.
8. Write results to `VALIDATION.md` with exact commands and exit codes.

## Independent review

Use one read-only reviewer when it adds value with only the task, diff, and validation evidence. Do not ask several agents to edit the same files. The implementation owner decides and applies fixes.

## Verdict format

```text
SCOPE: PASS|FAIL
DIFF REVIEW: PASS|FAIL
BUILD/COMPILE: PASS|FAIL|N/A
TESTS/VALIDATORS: PASS|FAIL|N/A
PACKAGE INSPECTION: PASS|FAIL|N/A
UNRESOLVED: none | exact issues
FINAL: PASS|FAIL
```

A partial or skipped check cannot be reported as a pass.

## Evidence-derived exact-verification gate

- A review that changed code must run the exact clean project build or report `UNBUILT`.
- Compile against pinned local dependencies, not a nearby template or broad dependency tree.
- Validate the final ZIP/DLL/plugin rather than the working directory.
- Add semantic tests for the actual user symptom and player-visible behavior.
- Check whether every required input and attachment is actually present.
- Record final archive SHA-256 and public version-string consistency.

## Runtime-framework proof

For generated or edited runtime configs, require:

- exact framework/version;
- source-locked grammar;
- linter result;
- parser/runtime log accepted and rejected counts;
- unresolved target count;
- one positive and one negative semantic test.

A file existing in `Data` or a game reaching the main menu is not proof that a
runtime rule loaded.
