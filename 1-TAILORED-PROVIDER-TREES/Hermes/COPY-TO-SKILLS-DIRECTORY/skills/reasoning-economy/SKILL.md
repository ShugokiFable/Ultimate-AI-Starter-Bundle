---
name: reasoning-economy
description: Use when work is expensive, long-context, retry-prone, irreversible, or billed heavily for repeated input/output.
---

# Reasoning Economy

## Core rule
Spend reasoning where it prevents **rework**. Cheap thought before a risky action is usually cheaper than repeated tool calls, repeated prompts, and repair rounds.

## Practice
- Build a compact factual **state ledger** once; update it instead of re-explaining history.
- Keep stable instructions and reference material stable so provider **cache** prefixes can be reused.
- Read only the files/sections needed for the current decision; search before opening huge trees.
- Batch independent reads, but do not batch dependent writes.
- Before irreversible or high-rework actions, explicitly check assumptions, acceptance criteria, and rollback.
- Prefer one strong diagnostic experiment over many speculative edits.
- Compress old volatile tool output while preserving decisions, errors, hashes, and user constraints.

Reasoning economy does not mean “think less”. It means minimize total cost to a correct result: reasoning + input + output + tool calls + retries + user correction cycles.
