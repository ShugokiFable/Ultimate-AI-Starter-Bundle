---
name: regression-sweep
description: Use when a bug was fixed or shared behavior, schemas, helpers, installers, or cross-provider integrations changed and sibling regressions may exist.
---

# Regression Sweep

## Core rule
A bug rarely lives alone when it comes from a shared **changed boundary**. After the direct regression turns green, search for **sibling** paths with the same pattern.

## Sweep
1. Name the underlying failure class, not only the symptom.
2. Search callers, copies, provider variants, serializers, docs snippets, tests, and generated artifacts for the same construct.
3. Add a **regression** test that fails when the causal defect returns.
4. Test adjacent inputs: empty, multiple values, spaces/Unicode, old/new versions, absent dependencies, and reruns.
5. Re-run the broad gate after sibling fixes.

Examples: one ANSI-decoding read implies searching every PowerShell read-modify-write; one stale version string implies checking every declared version surface; one bad subprocess argument shape implies checking all sibling child-process calls.

Do not “fix everything similar” blindly—confirm the shared cause before editing.
