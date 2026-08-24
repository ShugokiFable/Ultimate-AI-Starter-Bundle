---
name: assumption-audit
description: Use when a plan relies on guessed paths, versions, APIs, user state, defaults, environment behavior, or undocumented facts.
---

# Assumption Audit

## Core rule
Every material **assumption** must become a verified fact, an explicit inference, or an **unknown** before it can support an irreversible decision.

## Audit
List assumptions that could change correctness: path existence, provider behavior, version semantics, file format, permissions, network availability, user intent, current branch, generated state, and external service status.

For each:
- **verify** from the authoritative source when cheap;
- isolate it behind a runtime check when environment-dependent;
- provide a safe fallback when absence is expected;
- state it as unknown when it cannot be proved.

Prioritize assumptions by blast radius, not by convenience. A guessed path used in one log line matters less than a guessed path written into five provider configs.

## Then route it
Naming an assumption is half the job; the other half is the cheapest thing that settles it. `research-verification` for an external or version-specific fact, `visual-verification` for anything about appearance, `systematic-debugging` for a failure, `observability-first` when nothing in the system can currently answer the question at all, `capability-routing` when the assumption is that you have to build something to find out.

## Red flag
If the sentence “this should exist/work because it usually does” appears in your reasoning, turn it into a check.
