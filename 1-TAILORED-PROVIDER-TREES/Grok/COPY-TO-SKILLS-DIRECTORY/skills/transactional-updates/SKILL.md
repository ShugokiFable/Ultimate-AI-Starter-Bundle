---
name: transactional-updates
description: Use when an operation changes multiple files, registrations, database rows, configs, versions, or external resources that must not be left half-updated.
---

# Transactional Updates

## Core rule
A multi-step update needs an explicit commit boundary.

Validate prerequisites first. Snapshot or **backup** user-owned state that may need restoration. Prepare replacements in temporary locations, verify them, then publish using an **atomic** replace or the closest platform-supported equivalent.

For multiple resources, define the order and a transaction marker so recovery can distinguish old, staged, and committed states. Do not announce success before the final **commit** and read-back verification.

If a later step fails, roll back only what this operation owns; never overwrite newer external changes with a stale backup. If full rollback is impossible, record the partial state precisely and make rerun/resume deterministic.
