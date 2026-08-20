---
name: context-compaction-fidelity
description: Use when long-running work requires summarization, compaction, handoff, or context reduction without losing requirements or state.
---

# Context Compaction Fidelity

A shorter context is useful only if it preserves the facts needed to finish correctly.

## Compaction contract

Before discarding detail, preserve:

- user goals, acceptance criteria, constraints, and explicit non-goals;
- exact identifiers, versions, paths, commands, hashes, names, and external references;
- completed work and the evidence that proved it;
- current failures, unresolved questions, blockers, and hypotheses;
- irreversible actions already taken or still requiring approval;
- next executable steps.

Separate verified facts from inferences. Never convert uncertainty into certainty while summarizing.

After compaction, test fidelity by asking: **Could a fresh agent resume without rereading discarded context or repeating completed work?** If not, restore the missing state before continuing.
