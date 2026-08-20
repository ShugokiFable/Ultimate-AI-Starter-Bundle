---
name: migration-rollback
description: Use when moving user data/config, renaming install roots, changing schemas, upgrading persisted state, or replacing existing installations.
---

# Migration Rollback

## Core rule
A **migration** is incomplete without a tested **rollback** or a proven forward-repair path.

## Contract
Before mutation, detect exact source version/state and create a recoverable **backup** of user-owned data. Make migration idempotent and record its applied version. Verify the new state before deleting or abandoning the old state.

Test: clean old state → migrate → verify; rerun migration; interrupted/partial migration; already-new state; unsupported-old state; rollback after a post-migration failure.

Never infer that a folder can be deleted because a copy command returned success. Compare critical counts/hashes/schema and keep the old state until verification completes.

For irreversible schema migrations, provide a tested export/restore path and clearly block downgrade when safe rollback is impossible.
