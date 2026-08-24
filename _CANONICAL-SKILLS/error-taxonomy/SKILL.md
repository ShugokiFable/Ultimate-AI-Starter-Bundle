---
name: error-taxonomy
description: Use when failures from APIs, subprocesses, installers, parsers, providers, networks, or validation are being retried, surfaced, grouped, or mapped to recovery actions.
---

# Error Taxonomy

## Core rule
Recovery should depend on what kind of failure occurred, not on a generic catch-all.

Classify errors into actionable groups such as **transient** transport/capacity, **permanent** input/unsupported-operation, authentication/authorization, **configuration** or missing dependency, data corruption, invariant violation, and internal defect.

Preserve the original error/exit code and enough structured context to diagnose it. Map each category to an explicit policy: retry, fallback, repair, rollback, ask for credentials, or fail immediately.

Do not retry syntax errors, invalid API parameters, or deterministic incompatibility. Do not treat every timeout as transient if the child may still be running. Unknown errors should remain unknown and fail conservatively until evidence supports a category.
