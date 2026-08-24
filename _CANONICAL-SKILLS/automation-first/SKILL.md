---
name: automation-first
description: Use when a workflow asks the user to copy, edit, approve, restart, configure, repair, or verify steps that software may be able to perform.
---

# Automation First

## Core rule
Every required **manual step** is a potential failure point. **Automate** deterministic setup and verification when the platform provides a safe interface.

## Decision
Automate when the action is deterministic, scoped, reversible or verifiable, and supported by a CLI/API/config contract. Preserve an explicit **fallback** only for capabilities that truly cannot be automated safely.

Good automation:
- detects existing state;
- preserves user config;
- is idempotent;
- checks exit codes;
- verifies the result;
- fails with an actionable reason.

Bad automation guesses undocumented schemas, disables security globally, or hides failures behind warnings.

Documentation should describe what automation did and how to recover—not offload routine machine work back to the user. If a fresh install still says “now manually edit/copy this”, treat it as an engineering gap and investigate first.
