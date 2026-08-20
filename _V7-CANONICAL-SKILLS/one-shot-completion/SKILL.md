---
name: one-shot-completion
description: Use when the user asks for a finished result, end-to-end fix, “do it all”, or a task with implied deliverables.
---

# One-Shot Completion

## Core rule
Translate the goal into explicit **acceptance criteria** before acting, including **implied deliverables** a reasonable user expects but did not spell out.

## Contract
Build a short requirement ledger: requested outputs, implied outputs, constraints, failure conditions, and proof for each. Execute against that ledger rather than stopping at the first plausible result.

Before finalizing:
- verify every criterion with direct evidence;
- open/run the actual deliverable when possible;
- check sibling surfaces affected by the same change;
- remove manual cleanup that can be automated;
- state any criterion that remains unverified.

Do not substitute activity for completion. “Code written”, “tests added”, and “looks right” are intermediate states unless they are the requested result.

## Failure pattern
Weak agents often satisfy the literal noun but miss installation, packaging, entrypoints, docs, error paths, or validation. Treat those as implied deliverables whenever the user asked for something ready to use.
