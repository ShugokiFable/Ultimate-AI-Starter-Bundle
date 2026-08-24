---
name: state-resumption
description: Use when resuming interrupted, long-running, multi-session, compacted, or partially completed work.
---

# State Resumption

## Core rule
Do not resume from conversational memory alone. **Reconstruct** the work from repository state, **actual files**, artifacts, logs, and tests.

## Resume ledger
Maintain a tiny **ledger** with:
- goal and current acceptance criteria;
- current branch/revision and dirty files;
- completed changes with proof;
- failing/remaining gates;
- generated artifacts and exact paths;
- external state already changed;
- next smallest safe action.

On resume, verify the ledger against disk/git before trusting it. If a claimed file or build no longer exists, treat it as lost work and rebuild rather than reporting it as present.

## Compression discipline
Before context compaction or handoff, update the ledger with facts, not narrative. Keep volatile logs out; preserve only commands, outcomes, hashes, decisions, and blockers needed to continue deterministically.
