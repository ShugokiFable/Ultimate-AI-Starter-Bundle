---
name: dependency-capability-check
description: Use when a task depends on runtimes, CLIs, SDKs, APIs, provider features, plugins, or platform-specific behavior.
---

# Dependency Capability Check

## Core rule
A tool name is not a **capability** guarantee. Verify the executable/API and exact **version** before selecting a workflow.

## Contract
For each critical dependency:
- discover the real executable/endpoint;
- query version/capabilities directly;
- verify required subcommands, flags, schemas, protocols, or runtime packs;
- account for platform differences;
- prefer pinned or bounded versions for release-critical behavior.

If the preferred capability is absent, choose an automatic **fallback** that leaves the result functional. Only ask the user for a manual step when no safe automatable path exists.

Do not infer availability from a directory, registry key, package name, or documentation alone. A stale installation can exist without a working executable; a CLI can exist without the required feature.

## Evidence
Record what capability was tested, how it was tested, and the observed version/result.
