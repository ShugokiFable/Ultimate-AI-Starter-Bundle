---
name: test-oracle-quality
description: Use when a test passes but may be checking the wrong signal, mocks its own assumption, snapshots unstable output, or cannot distinguish correct behavior from a broken implementation.
---

# Test Oracle Quality

## Core rule
A test is valuable only if its **oracle** fails when the user-visible contract is wrong.

Before trusting a green test, name one realistic production defect that should make it fail. If the test would still pass, strengthen the observation boundary. Prefer final state, parsed output, exit status, hashes, or real protocol behavior over "mock was called".

Watch for **false positive** tests: empty loops, skipped assertions, broad exception swallowing, fixtures that reproduce the implementation bug, or mocks that encode an invented API.

For critical regressions, perform a temporary **mutation** or revert of the fix and confirm the test turns red, then restore and rerun green. A test that never demonstrated failure is weak evidence.
