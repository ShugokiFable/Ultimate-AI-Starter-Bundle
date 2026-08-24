---
name: skyrim-base-object-swapper
description: Author current Skyrim Base Object Swapper sectioned pipe syntax and validate version-sensitive swaps.
compatibility: Windows 10/11; Skyrim Special Edition or Anniversary Edition; exact installed framework version must be verified
metadata:
  version: 4.3.0
  updated: '2026-07-22'
  library: overseer-skyrim-agent-skills
  error_registry_revision: 4.3.0
---

# Base Object Swapper

This skill owns Skyrim BOS `3.4.1` sectioned pipe grammar.

## Sections and entries

```ini
[Forms]
OriginalBase|SwapBase|PropertyOverrides|Chance

[References]
OriginalReference|SwapBase|PropertyOverrides|Chance

[Transforms]
OriginalBaseOrReference|PropertyOverrides|Chance

[Properties]
OriginalBaseOrReference|PropertyOverrides|Chance
```

Condition-qualified section headers are supported. Do not introduce a competing
`Base = Swap` dialect.

## Transform grammar

Function invocations must remain contiguous:

```text
rotR(147.9,355.9,82.7)       valid
rotR(147.9, 355.9, 82.7)     parser-breaking in the locked grammar
```

The second shape can be split into tokens, producing log messages such as
`failed to process rotR(147.9`, `355.9`, and `82.7)`.

## Conflict law

The last config alphabetically wins. That identifies priority, not semantic
correctness. Resolve the actual reference, cell/worldspace, qualifiers, patch
intent, and expected transform before renaming or deleting a config.

## Mandatory validation

Run both tools:

```text
python ..\skyrim-distr-kid-validation\scripts\lint_framework_configs.py <directory>
python scripts\audit_bos_configs.py <directory>
```

`audit_bos_configs.py` must report both duplicate targets and whitespace-split
transform/property invocations. Its self-test includes the production-shaped
`rotR(147.9, 355.9, 82.7)` failure.
