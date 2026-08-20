---
name: minimal-reproducer
description: Use when a bug is intermittent, complex, cross-layer, or buried in a large application and the causal input or boundary is not yet isolated.
---

# Minimal Reproducer

## Core rule
Reduce the failure until one controlled **variable** explains the difference between working and broken behavior.

Start from the real failing path and build the **smallest** case that can still **reproduce** the symptom. Remove unrelated files, plugins, configuration, data, and timing assumptions one at a time. Preserve the real boundary that may be causal: the actual parser, shell, serializer, protocol, or filesystem behavior.

Once minimal, vary one factor at a time and record the outcome. A reproducer that fails for a different reason is not useful.

Keep the final case as a regression fixture when practical; it should make the bug cheap to understand and impossible to reintroduce silently.
