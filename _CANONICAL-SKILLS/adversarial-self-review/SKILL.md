---
name: adversarial-self-review
description: Use when finalizing a complex answer, implementation, diagnosis, migration, or release where an initially plausible result could hide a costly mistake.
---

# Adversarial Self-Review

## Core rule
Try to **falsify** your conclusion instead of only collecting support for it.

Before completion, ask: what concrete observation would prove this wrong? Search for at least one plausible **counterexample**: stale version, alternate call path, empty input, different shell, retry, upgrade state, partial failure, or hidden consumer.

Re-read the strongest **evidence**, not your own summary of it. Check whether the tests could pass while the real requirement is still broken. Distinguish absence of evidence from evidence of absence.

Do not turn review into endless skepticism. Once the high-impact failure hypotheses have been tested or ruled out with direct evidence, stop and report remaining uncertainty explicitly.
