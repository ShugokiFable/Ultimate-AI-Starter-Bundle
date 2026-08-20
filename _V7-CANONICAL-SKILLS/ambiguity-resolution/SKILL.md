---
name: ambiguity-resolution
description: Use when a requirement, error, API, name, or observed behavior has multiple plausible interpretations that would lead to different actions.
---

# Ambiguity Resolution

## Core rule
Do not silently choose among materially different meanings.

Identify each **ambiguity**, then ask whether it is **material**: would choosing the wrong interpretation change files, cost, safety, compatibility, or the delivered result? If not, choose the simplest reasonable reading and state it only when useful. If it is material, resolve it from authoritative context, source, existing state, or a focused experiment before acting.

Keep an explicit **assumption** only when the ambiguity cannot be resolved and progress is still safe. Make that assumption falsifiable and avoid irreversible work that depends on it.

When user intent is clear from prior context, do not manufacture ambiguity as an excuse to stop. The goal is fewer wrong branches, not more questions.
