---
name: coding-discipline
description: Operating contract for changing code, scripts, configuration, or build files. Use before implementation work;
  do not use as a domain-specific Skyrim syntax guide.
compatibility: Windows 10/11; Skyrim Special Edition or Anniversary Edition; PowerShell and Python 3 when bundled scripts
  are used
metadata:
  version: 4.3.0
  updated: '2026-07-22'
  library: overseer-skyrim-agent-skills
  provider: grok
  provider_pack_version: 1.0.0
  base_library: Skyrim-Agent-Skills-v6
  error_registry_revision: 4.3.0
  final_pack_version: 4.3.0
when_to_use: Use for operating contract for changing code, scripts, configuration, or build files.
---

# Coding discipline

## Before editing

1. Read the nearest task, state, environment, and agent instruction files.
2. Establish the writable root and treat all deployed inputs as read-only.
3. Inspect the smallest relevant file set before proposing architecture.
4. Write a plan first when the change is broad, risky, cross-file, or poorly specified.
5. Define a measurable completion condition and the commands that will prove it.

## During implementation

- Make one coherent change at a time.
- Preserve unrelated formatting and behavior.
- Prefer typed parsers, structured libraries, and tested transforms over regex or byte surgery.
- Keep generated output separate from source.
- Redirect large command output to a report file and summarize it.
- Stop when a required fact cannot be verified. Do not hide uncertainty behind confident prose.
- Checkpoint after each phase so a failed attempt can be reverted cleanly.

## Validation

- Review the diff, not only the final files.
- Run syntax checks, builds, tests, validators, and package inspection relevant to the task.
- Exercise failure paths and boundary cases.
- Never claim a command ran unless its output was observed.
- Report remaining risks explicitly.

## Context efficiency

- Use targeted search instead of recursive reading of unrelated folders.
- Do not repeatedly reload unchanged large files.
- Persist decisions in project files, then compact or start a fresh session at a milestone.
- Use subagents only for independent exploration, audit, or testing. One owner edits a tightly coupled system.

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

Keep each change set narrow, reversible, and linked to an explicit requirement or defect.

## Usage and milestone discipline

Create the smallest buildable artifact early. Compile and checkpoint after each coherent milestone. Stop spawning subagents once the evidence is sufficient. Keep `STATE.md` current with exact paths, uncommitted changes, the last successful command, failures, and the next command.
