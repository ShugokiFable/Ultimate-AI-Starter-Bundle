---
name: fallback-degradation
description: Use when software automatically switches providers, models, algorithms, parsers, tools, cached data, compatibility modes, or optional components after a failure.
---

# Fallback Degradation

## Core rule
A **fallback** is safe only when its reduced **capability** is explicit and acceptable for the requirement.

For each fallback, define which outputs/invariants it can and cannot preserve. Trigger it only for classified failures it is meant to handle. A fallback must not be **silent** when it changes quality, safety, data freshness, determinism, tool access, context length, or cost in a material way.

Verify the fallback path independently; the primary path's tests do not cover it. When the primary recovers, avoid oscillation or inconsistent state across one workflow.

If no fallback can satisfy a required contract, fail clearly instead of producing a plausible-looking lower-quality result and calling the task complete.
