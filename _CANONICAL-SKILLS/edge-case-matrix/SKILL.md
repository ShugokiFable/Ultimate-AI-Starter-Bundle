---
name: edge-case-matrix
description: Use when changing parsers, installers, APIs, inputs, file handling, state machines, or code with many boundary conditions.
---

# Edge Case Matrix

## Core rule
Derive tests from input dimensions, not from whatever examples happen to be in front of you.

## Minimum matrix
For each relevant **boundary**, consider: normal, **empty**, missing/null, one item, many items, minimum/maximum, invalid type, **malformed** syntax, duplicate values, reordered values, spaces/Unicode, old/new version, permission failure, timeout, partial state, and rerun.

Use pairwise combinations when dimensions multiply; reserve full Cartesian coverage for small high-risk state spaces.

For stateful operations, include interruption between steps and recovery from partially written state. For parsers, include unknown future fields. For installers, include already-installed and broken-installed cases.

The goal is not maximal test count. It is to identify qualitatively different failure classes before users do.
