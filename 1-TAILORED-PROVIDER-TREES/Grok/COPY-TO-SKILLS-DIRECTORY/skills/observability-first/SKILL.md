---
name: observability-first
description: Use when debugging production-like failures, long workflows, installers, background processes, external integrations, or hard-to-reproduce state - and when WRITING any app, CLI, service, installer, game or script, so its next failure produces evidence instead of a mystery.
---

# Observability First

## Core rule
If a failure cannot be reconstructed from **logs** and state, add enough observability before guessing at fixes.

## Diagnostic contract
Capture a stable **correlation** identifier for one run/task where multiple processes or services participate. Log timestamps, version/revision, command/action, target, key state transitions, exit codes, retries, and bounded error detail. Preserve machine-readable reports for doctors and CI.

Never log secrets or huge payloads by default. Prefer structured summaries plus paths to full artifacts. Distinguish warnings from release-blocking failures.

A **diagnostic** should answer: what was attempted, with which version/config, what state existed before, where it failed, and what state remained after.

Observability is not noisy printing. Every emitted field should shorten root-cause time or prove an acceptance criterion.

## Software you write

The same rule applies before there is a failure. Anything you build that runs -- an app, CLI, service, installer, game, background worker -- should be able to explain its own next failure without a second debugging session to add logging.

Scale to the project. A ten-line utility needs no logging framework; a multi-stage tool needs a **run** identifier tying its events together.

Baseline worth emitting: startup with version/build, the configuration actually resolved, each external dependency that failed and why, an actionable message rather than a bare exception class, a stack trace for the unexpected, child-process exits, clean shutdown, and the exit code. Where a durable log is written, print its path.

What not to emit: whole payloads, request bodies, file contents, per-iteration chatter, or anything from `secret-hygiene`. A field that cannot help reproduce, localise or explain a failure is cost with no return.

When existing evidence is not enough to explain a failure, add **targeted** instrumentation, reproduce once, then use what it produced -- rather than editing speculative fixes and re-running. `systematic-debugging` owns the isolation loop itself.
