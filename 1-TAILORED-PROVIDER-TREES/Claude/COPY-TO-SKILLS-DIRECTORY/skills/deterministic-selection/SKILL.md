---
name: deterministic-selection
description: Use when code chooses among multiple files, providers, releases, candidates, records, plugins, matches, or equally valid options and repeatability matters.
---

# Deterministic Selection

## Core rule
Never let filesystem/API enumeration **order** become an undocumented decision rule.

Define explicit ranking keys and a stable **tie-break**: semantic version, priority, timestamp plus name, provider score plus slug, or another contract-relevant identity. Normalize inputs before comparison and make the final choice **deterministic** across machines and reruns.

When "first result" is intended, prove the upstream API guarantees ordering; otherwise sort locally. Log or return the chosen identity when selection affects correctness, cost, or reproducibility.

Test equal-primary-key cases, different casing, missing metadata, and reordered input. A selection algorithm should return the same answer when the candidate set is identical but iteration order changes.
