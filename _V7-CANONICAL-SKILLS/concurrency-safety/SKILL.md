---
name: concurrency-safety
description: Use when work can overlap across threads, processes, agents, hooks, async tasks, parallel builds, or shared mutable files/state.
---

# Concurrency Safety

## Core rule
Shared state plus overlapping execution creates a **race** unless ownership and ordering are explicit.

## Contract
Identify shared mutable resources and decide whether they require a **lock**, transaction, immutable snapshot, queue, unique workspace, or compare-and-swap/version check. Keep critical sections small and never hold locks around arbitrary external callbacks when avoidable.

Make operations **idempotent** where retries or duplicate delivery can occur. Use unique temp/output names for parallel work. Test two writers/readers deliberately; timing-dependent bugs rarely appear in single-threaded tests.

For agentic work, isolate branches/worktrees and prevent two agents from editing the same file without coordination. For installers, protect config read-modify-write from concurrent runs or detect and abort.

A passing sequential test is not evidence of concurrency safety.
