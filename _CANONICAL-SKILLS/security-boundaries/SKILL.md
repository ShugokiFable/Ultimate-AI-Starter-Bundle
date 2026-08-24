---
name: security-boundaries
description: Use when code executes commands, installs hooks/plugins, handles untrusted input, writes outside a workspace, or crosses privilege/network boundaries.
---

# Security Boundaries

## Core rule
Identify each **trust boundary** explicitly and apply **least privilege** at that boundary.

## Contract
Treat downloaded content, repository files from unknown origins, generated shell text, archive members, plugin hooks, environment variables, and user-supplied paths as **untrusted** until validated for the operation being performed.

Prefer argument arrays over shell interpolation; validate archive paths; constrain write roots; avoid privilege elevation unless required; verify signatures/hashes for bootstrapped executables when feasible; preserve provider trust prompts unless the user has explicitly opted into the exact automation being installed.

Do not disable dangerous-command approval globally to remove one setup prompt. Scope consent to the known component or one installer process.

Security checks are part of correctness: a “working” installer that can overwrite arbitrary paths or silently trust future third-party hooks is not near-perfect.
