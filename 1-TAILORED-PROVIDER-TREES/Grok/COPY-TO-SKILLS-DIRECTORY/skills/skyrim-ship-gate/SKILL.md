---
name: skyrim-ship-gate
description: Mandatory final validation gate for a Skyrim mod release tree or archive. Use after implementation and FOMOD
  work, before calling a mod finished or ready for Nexus.
compatibility: Windows 10/11; Skyrim Special Edition or Anniversary Edition; PowerShell and Python 3 when bundled scripts
  are used
metadata:
  version: 4.3.0
  updated: '2026-07-22'
  library: overseer-skyrim-agent-skills
  error_registry_revision: 4.3.0
---

# Skyrim ship gate

## Required gates

1. **Version gate:** active version, changelog, and ownership are correct.
2. **Diff gate:** no unrelated or deployed files were modified.
3. **Plugin gate:** run `forge plugin-info` and `skyrim-plugin-authoring/scripts/audit_plugin_headers.py` for every plugin. Header success is structural only.
4. **Papyrus gate:** changed scripts compile and packaged PEX files match the current build.
5. **Runtime-config gate:** structural and semantic audits pass; installed framework versions are recorded.
6. **Native gate:** every supported DLL target builds and its dependencies are inspected.
7. **Asset gate:** referenced paths exist and generated outputs are identified.
8. **FOMOD gate:** XML parses and referenced sources exist.
9. **Archive gate:** run `scripts/validate_release_tree.py`; inspect the final root manually.
10. **Disclosure gate:** list in-game or GUI tests that were not performed.

## Target-aware plugin gate

Accept HEDR `1.70` or `1.71` when it matches the declared runtime/backport target. Reject an unexplained mismatch, not either value in isolation. Apply the legacy `0x800-0xFFF` or extended light-ID policy accordingly.

## Completion report

```text
INPUTS: required_files=present|missing | attachments=present|missing
MEMORY CHECK: entries=... applied=...
AUTHORITY: installed=... parent=... active=... RESULT=PASS|FAIL
VERSION GATE: prior=... active=... copied_files=... changelog=YES|NO RESULT=PASS|FAIL
EXACT BUILD/COMPILE: command=... dependencies=... RESULT=PASS|FAIL|UNBUILT|N/A
FRAMEWORK VALIDATION: evidence=... RESULT=PASS|FAIL|N/A
SEMANTIC TEST: symptom/player-visible result=... RESULT=PASS|FAIL|UNTESTED
SHIP GATE: command=... RESULT=PASS|FAIL|N/A
FINAL ARCHIVE: path=... sha256=... version_strings=PASS|FAIL|N/A
RUNTIME STATUS: user-confirmed-runtime | runtime-evidenced | tool-validated | assistant-claimed | contradicted
SSEEDIT/CK: not launched
UNRESOLVED: none | exact remaining risks
```

## Evidence-derived release gates

Add these mandatory lines to the verdict:

```text
AUTHORITY: installed=... parent=... active=... RESULT=PASS|FAIL
EXACT BUILD: command=... dependencies=... RESULT=PASS|FAIL|UNBUILT|N/A
SEMANTIC TEST: user symptom/player-visible behavior RESULT=PASS|FAIL|UNTESTED
FINAL ARCHIVE: path=... sha256=... version_strings=PASS|FAIL
```

A parser pass, compile pass, or loader discovery cannot substitute for semantic/runtime evidence. Exclude developer-only artifacts unless the release explicitly includes a separate symbols package.


## V4 plugin master gate

For every generated or changed plugin:

- audit HEDR, ESL flag, record form versions, local-ID mode, master indices, and HEDR count;
- fail extended local IDs below 0x800 unless HEDR is 1.71 and `Skyrim.esm` is first master;
- when master files are available, pass `--master-root` and validate 1.71 dependency compatibility plus transitive master ordering;
- do not call a plugin runtime-valid from header checks alone.

## V4 framework gate

Run the framework linter for every `_KID.ini`, `_DISTR.ini`, `_SWAP.ini`, or SkyPatcher tree. Run the CDF JSON linter for Container Distribution Framework rules. Confirm suffixes, supported keys, field-specific grammar, category placement, exact resolved forms, and runtime logs.

Mandatory regression fixtures include:

- SPID `Weapon =` rejected and `Item =` accepted;
- SPID `65/` rejected while `-C/-D` and `18!` remain accepted;
- eight SPID sections rejected;
- comma TraitFilters rejected;
- BOS whitespace inside transform arguments rejected;
- CDF wildcard-like `add` strings rejected;
- manager bookkeeping markers rejected from release trees.


## Runtime-log reconciliation gate

For every shipped runtime framework, record:

```text
files_discovered
rows_or_rules_read
rows_or_rules_accepted
rows_or_rules_rejected
unresolved_forms
optional_rules_skipped
features_disabled
conflicts_reported
```

A release fails when an intended feature family has zero accepted rows, every
target is unresolved, or its required feature descriptor is disabled.

## Manager-bookkeeping gate

Public and deployable archives must not contain:

```text
__folder_managed_by_vortex
__folder_managed_by_vortex.json
meta.ini
*.meta
```

Fix the source package and redeploy. Do not treat deletion from live `Data` as a
release fix.

## Validator integrity gate

Before changing a shipping config because a linter failed:

- compare the finding against the exact installed parser and runtime log;
- treat publication as evidence, not authority;
- do not modify runtime-accepted data solely to make a validator green;
- require a production-path fixture that invokes the same CLI/auditor used by the ship gate;
- fail the skill pack when a documented mandatory check is absent from the actual production tool.

Mandatory V4.3 fixtures include:

- BOS auditor detects `rotR(147.9, 355.9, 82.7)`;
- SPID accepts `ExclusiveGroup`, `DeathItem`, and linked key families;
- SPID/KID trailing semicolon comments do not corrupt fields;
- KID accepts its special `ExclusiveGroup` key;
- ordinary KID blank types and record signatures remain rejected under KID 4.0.6.
