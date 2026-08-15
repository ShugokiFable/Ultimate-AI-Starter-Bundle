# Memory Promotion Protocol

## Purpose

Prevent one model's confident but incorrect conclusion from becoming a permanent
rule for all four agents.

## Promotion workflow

1. Capture a candidate lesson in the active project's
   `MEMORY/CANDIDATES.md`.
2. Attach:
   - project and version;
   - exact symptom;
   - changed files;
   - commands and validators run;
   - before/after evidence;
   - user or tester confirmation;
   - framework/runtime versions.
3. Assign an evidence status from `GLOBAL-LESSONS.md`.
4. Promote to the global error registry only when:
   - the lesson is cross-project;
   - it is supported by tool evidence or user/runtime confirmation;
   - it does not conflict with version-specific documentation;
   - no later feedback contradicts it.
5. When contradicted:
   - mark the old entry `superseded` or `contradicted`;
   - link the replacement entry;
   - never leave both as equally active instructions.

## Never promote

- assistant final-message claims;
- speculative diagnoses;
- temporary local paths;
- unverified FormIDs or offsets;
- one project's balance values;
- framework syntax without a version/evidence source;
- conclusions from a build that later crashed;
- explicit content from private transcripts when a technical summary is enough.
