---
name: ci-convergence
description: Use when a task may push commits, wait on CI, tag, publish, or declare a release complete.
---

# CI Convergence

## Core rule
A local green run is not release evidence. The authoritative unit is the **pushed SHA** and every required check attached to that exact SHA.

## Contract
1. Record the pushed SHA immediately after push.
2. Enumerate required checks for that SHA; never substitute “latest run”.
3. Wait while any required check is queued or running. **Pending is not success.**
4. Require every required check to reach a terminal successful state.
5. If one fails, inspect its log, fix the causal defect, push a new SHA, and restart convergence from step 1.
6. Tag, publish, or end the task only after the exact release SHA is terminal-green.

For a release, verify the tag resolves to the same green SHA and verify the uploaded artifacts after publication.

## Stop conditions
Do not release on cancelled, skipped-when-required, missing, unknown, pending, or stale checks. If the CI system cannot prove which SHA it tested, report that as unverified rather than inferring success.
