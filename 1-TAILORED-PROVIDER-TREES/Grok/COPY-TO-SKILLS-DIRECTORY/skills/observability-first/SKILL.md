---
name: observability-first
description: Use when debugging production-like failures, long workflows, installers, background processes, external integrations, or hard-to-reproduce state.
---

# Observability First

## Core rule
If a failure cannot be reconstructed from **logs** and state, add enough observability before guessing at fixes.

## Diagnostic contract
Capture a stable **correlation** identifier for one run/task where multiple processes or services participate. Log timestamps, version/revision, command/action, target, key state transitions, exit codes, retries, and bounded error detail. Preserve machine-readable reports for doctors and CI.

Never log secrets or huge payloads by default. Prefer structured summaries plus paths to full artifacts. Distinguish warnings from release-blocking failures.

A **diagnostic** should answer: what was attempted, with which version/config, what state existed before, where it failed, and what state remained after.

Observability is not noisy printing. Every emitted field should shorten root-cause time or prove an acceptance criterion.
