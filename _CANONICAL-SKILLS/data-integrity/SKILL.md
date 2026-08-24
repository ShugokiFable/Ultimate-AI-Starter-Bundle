---
name: data-integrity
description: Use when writing manifests, databases, JSON/YAML/TOML, caches, indexes, save files, generated reports, or other persisted state.
---

# Data Integrity

## Core rule
Persisted state needs validated **serialization**, safe writes, and post-write verification.

## Contract
Parse/validate input before mutation. Write to a temporary sibling and use an **atomic** replace when supported. Preserve the original until the replacement is known-good. Re-open and **validate** the result against schema/invariants after writing.

For multi-file state, define ordering or a transaction marker so interruption cannot leave a believable half-update. For manifests/checksums, generate from final bytes and verify every entry. For caches, make corruption recoverable by rebuilding rather than propagating bad data.

Do not equate “write() returned” with durable correctness. Consider disk-full, interrupted process, encoding errors, duplicate keys, partial JSON, stale cache, and concurrent writers.
