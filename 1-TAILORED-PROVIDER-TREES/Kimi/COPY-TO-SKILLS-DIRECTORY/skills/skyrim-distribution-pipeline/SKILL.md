---
name: skyrim-distribution-pipeline
description: Bulk-generate, normalize, and audit large SPID, KID, SkyPatcher, or related runtime configuration sets from resolved
  plugin data. Use for hundreds of rows or cross-plugin distributions.
compatibility: Windows 10/11; Skyrim Special Edition or Anniversary Edition; PowerShell and Python 3 when bundled scripts
  are used
metadata:
  version: 4.3.0
  updated: '2026-07-22'
  library: overseer-skyrim-agent-skills
  error_registry_revision: 4.3.0
---

# Distribution pipeline

This skill owns bulk generation and cross-framework audit. Exact syntax belongs
to each dedicated framework skill.

## Inputs

- exact installed framework versions;
- source plugins and deployed load-order manifest;
- resolved source plugin, local FormID, EditorID, record type, and intended filters;
- written balance/classification policy;
- known-good parser examples;
- expected parsed, rejected, unresolved, and skipped counts.

## Typed pipeline

1. Extract source records with a typed parser.
2. Store a typed intermediate CSV/JSON manifest.
3. Validate one positive and one negative target per source plugin.
4. Map the desired record class to the framework's actual key:
   - SPID inventory forms, including weapons and staves: `Item` or generic `Form`;
   - never manufacture `Weapon =` merely because the source record is WEAP.
5. Generate deterministically.
6. Run the dedicated linter before deployment.
7. Resolve every exact form against a deployed-plugin manifest.
8. Compare source manifest count, generated count, parser accepted count,
   rejected count, unresolved count, and intended exclusions.
9. Fail release when an entire generated feature family is rejected or resolves
   zero targets.
10. Inspect runtime logs after deployment.

## Framework separation

- SPID `*`/`/`/`,` meanings are field-specific.
- FLM permits special `*FormList`, `#Group`, and `#Collection` forms.
- CDF JSON `add` uses exact forms and does not inherit FLM wildcard syntax.
- BOS alphabetical priority is not semantic conflict resolution.
- SkyPatcher operation names and paths remain category/version-specific.

Never copy punctuation or selector conventions between frameworks because they
look similar.

## Bulk-change gate

A mass replacement such as `Weapon =` to `Item =` is permitted only after:

1. proving the old key is unsupported in the target SPID parser;
2. confirming every affected row intends inventory-form distribution;
3. validating representative forms from every source plugin;
4. writing a reversible diff;
5. rerunning parser and runtime logs;
6. reconciling accepted/rejected counts exactly.

## Stale dependency handling

Classify unresolved rows:

- hard requirement missing;
- conditional requirement missing;
- optional integration absent;
- stale config left after mod removal;
- typo or wrong local FormID/EditorID.

Do not delete hundreds of rows merely to quiet logs. Preserve useful optional
integrations when their guard conditions are correct. Remove or repair dead rows
in the owning source when their target can never resolve in the intended build.

## Commands

```text
scripts\audit_configs.py <tree>
..\skyrim-distr-kid-validation\scripts\lint_framework_configs.py <tree>
..\skyrim-container-distribution\scripts\lint_cdf_json.py <tree>
..\skyrim-runtime-log-forensics\scripts\analyze_runtime_logs.py <logs>
```
