---
name: shell-boundary-safety
description: Use when commands cross batch, PowerShell, cmd, Bash, native executable, subprocess, quoting, environment, or exit-code boundaries.
---

# Shell Boundary Safety

Shell boundaries change parsing and quoting rules. Treat every transition as an interface contract.

## Contract

1. Know which shell parses each layer and which process receives the final argv.
2. Preserve arguments containing spaces, Unicode, quotes, commas, wildcards, and leading dashes.
3. Do not construct command lines by string concatenation when an argv/argument-list API exists.
4. Capture and propagate the real child **exit code**; success text is not proof.
5. Refresh environment/PATH when an installer modifies it during the same process.
6. Account for Windows PowerShell 5.1 `-File` quirks, including switch/array serialization.
7. Test from a path containing spaces and Unicode.

When invoking another shell, verify behavior at the receiving boundary, not just the caller's source string.
