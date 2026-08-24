---
name: failure-injection-testing
description: Use when software installs, updates, migrates, downloads, writes files, invokes networks, or crosses boundaries where partial failure could corrupt state.
---

# Failure Injection Testing

Happy-path tests do not prove recovery behavior. Deliberately exercise realistic failures before shipping destructive or stateful automation.

## Minimum matrix

Inject at least the relevant cases:

- network timeout, truncated download, and unavailable dependency;
- permission denied / read-only destination;
- malformed or unexpected input;
- disk/write failure or partial extraction;
- child-process nonzero exit;
- interruption between backup and commit;
- retry after a partial previous run.

For each injection, require a clear nonzero failure, preserved prior state, actionable diagnostics, and a safe retry path. Verify temporary files and processes are cleaned up.

Never weaken production checks merely to make an injected failure pass.
