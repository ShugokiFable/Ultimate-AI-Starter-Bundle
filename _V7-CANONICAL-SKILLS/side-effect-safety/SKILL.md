---
name: side-effect-safety
description: Use when work may write to external systems, perform destructive operations, publish, migrate, delete, send, push, or broadly modify files.
---

# Side-Effect Safety

## Core rule
Before an **irreversible** or externally visible action, verify intent, target, **scope**, prerequisites, and **rollback**.

## Gate
1. Identify exactly what state changes and where.
2. Read current state immediately before the write.
3. Narrow the operation to the minimum target set.
4. Preserve recoverable state: backup, branch, snapshot, transaction, or export.
5. Validate required preconditions and authorization.
6. Execute once; do not blindly retry ambiguous writes.
7. Read back the resulting state and verify it matches intent.

If a write returns an uncertain result, perform a read-only verification before retrying. Duplicate emails, releases, PRs, payments, or config blocks are usually caused by treating “timeout” as “nothing happened”.

Prefer reversible staging before irreversible publication.
