---
name: condition-based-waiting
description: Use when completion depends on asynchronous jobs, CI checks, processes, files, services, or other state that changes over time.
---

# Condition-Based Waiting

Wait for the **condition**, not an arbitrary sleep duration.

## Pattern

1. Identify the observable success, failure, and terminal states.
2. Poll the authoritative state at a reasonable interval.
3. Stop immediately on success or a terminal failure.
4. Set a bounded timeout and report the last observed state when it expires.
5. For CI or remote jobs, bind polling to the exact run/commit/job identifier so a newer unrelated run cannot satisfy the wait.
6. After terminal success, verify the expected artifact/output exists before continuing.

A fixed sleep is acceptable only when the system exposes no observable progress signal. Never treat timeout as success.
