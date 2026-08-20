---
name: partial-success-accounting
description: Use when a batch, installer, migration, fan-out, provider sweep, or multi-resource action can succeed for some targets and fail for others.
---

# Partial Success Accounting

## Core rule
A mixed outcome is **partial**, not success and not total failure.

Track per-item **status** using stable identities: succeeded, failed, skipped-by-policy, unavailable, or not attempted. Keep the causal error for every **failure** and do not collapse several errors into the last one observed.

At the end, reconcile counts against the requested target set. Global success requires every required target to satisfy its acceptance state; optional skips must be explicitly allowed by policy.

On retry, operate only on unresolved targets unless repeating successful work is proven idempotent. Never print a single green DONE banner when a required provider, file, check, or artifact is still red.
