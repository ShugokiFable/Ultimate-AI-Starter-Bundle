---
name: contradiction-detection
description: Use when documentation, tests, configs, user requirements, source code, runtime behavior, or external sources disagree about the same fact.
---

# Contradiction Detection

## Core rule
Two incompatible claims cannot both remain silently true.

When you find a **conflict**, name the exact propositions and identify their **authority**: runtime behavior, executable source, schema, official docs, generated artifacts, comments, memory, or user instruction. Prefer the source that actually governs the behavior, but check freshness and scope.

Then **reconcile** the system: fix stale derived copies, tests, docs, or configuration so future agents do not rediscover the same contradiction. If the conflict cannot yet be resolved, mark the disputed fact unknown and avoid building dependent conclusions on it.

Search sibling surfaces after a contradiction caused by duplicated state; one stale version string often means several more exist.
