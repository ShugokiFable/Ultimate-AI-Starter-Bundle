---
name: skyrim-distr-kid-validation
description: Cross-framework static and semantic validation for SPID, KID, SkyPatcher, and BOS output.
compatibility: Windows 10/11; Skyrim Special Edition or Anniversary Edition; exact installed framework version must be verified
metadata:
  version: 4.3.0
  updated: '2026-07-22'
  library: overseer-skyrim-agent-skills
  error_registry_revision: 4.3.0
  final_pack_version: 4.3.0
---

# Framework configuration validation

This skill validates SPID, KID, BOS, SkyPatcher, and source-locked CDF rules.

## Commands

```text
python scripts\lint_framework_configs.py <files-or-directories>
python scripts\verify_framework_truth.py
python ..\skyrim-base-object-swapper\scripts\audit_bos_configs.py <bos-directory>
python ..\skyrim-container-distribution\scripts\lint_cdf_json.py <json>
```

## Contract coverage

### SPID

- standard, `Death<Type>`, `ExclusiveGroup`, and linked key families;
- key-specific field layouts;
- one-to-seven normal fields and one-to-four linked fields;
- field-aware LevelFilters, TraitFilters, count/index, and Chance;
- trailing semicolon comments;
- `Weapon =` rejection while `Item =` remains valid.

### KID

- ordinary `Keyword` two-to-five fields;
- required human-readable type for ordinary rows;
- record signatures and blank ordinary types rejected;
- special `ExclusiveGroup` grammar;
- trailing semicolon comments.

### BOS

- section and field count;
- transform/property/chance grammar;
- whitespace inside invocations rejected by both the general linter and the BOS auditor;
- duplicate targets reported without inventing a semantic winner.

## Validator disagreement protocol

A published config is evidence, not proof. A validator result is also evidence,
not proof. When the linter conflicts with the exact parser, accepted runtime log,
or a known-positive deployed behavior:

1. do not rewrite the mod merely to satisfy the linter;
2. reproduce the disagreement with the exact line;
3. inspect the parser/version and runtime log;
4. mark the validator finding as disputed;
5. repair the validator first when its contract is wrong;
6. add the real line as a production-path regression fixture.

A claimed regression test is insufficient when it tests a helper that the actual
CLI/auditor never calls. `verify_framework_truth.py` executes the production
entry points against production-shaped fixtures.

## Limits

Static validation cannot prove form resolution, semantic BOS coordinates,
intended actor selection, hook safety, or in-game behavior.
