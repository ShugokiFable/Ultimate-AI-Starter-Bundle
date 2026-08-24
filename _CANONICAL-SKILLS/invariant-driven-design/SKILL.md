---
name: invariant-driven-design
description: Use when designing or changing stateful systems, installers, serializers, concurrent code, workflows, or APIs whose correctness depends on facts always remaining true.
---

# Invariant-Driven Design

## Core rule
Define what must always remain true before choosing implementation details.

Write each important **invariant** as a checkable statement: one active registration per provider, manifest hashes match final bytes, a failed install never prints success, user config survives repair, or a lock has one owner.

Place enforcement at the narrowest **boundary** where invalid state can enter or leave. Tests should attempt a direct **violation** and prove it is rejected or repaired.

Prefer a small number of strong invariants over many procedural reminders. If correctness requires every caller to remember five steps in order, move those steps behind an interface or automated gate that preserves the invariant by construction.
