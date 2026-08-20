---
name: source-of-truth
description: Use when the same fact appears in multiple files, configs, generated reports, caches, docs, or external systems.
---

# Source of Truth

## Core rule
For each important fact, name one **authority**. Everything else is **derived** or observational.

## Contract
Document the authoritative source for versions, schemas, generated manifests, configuration ownership, release SHA, dependency pins, and compatibility ranges. Generate downstream copies when practical; otherwise gate them against the authority.

When two surfaces disagree, do not average or choose the convenient one. Determine which is authoritative and explain whether the other is stale, generated incorrectly, or represents a different scope.

Caches and generated reports must never silently become authoritative merely because they are easier to read.

## Drift control
Add a verification step that detects **drift** between the authority and every required derived surface. Regenerate derived files last, after all source edits are complete.
