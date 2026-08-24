---
name: supply-chain-verification
description: Use when downloading, vendoring, executing, updating, or redistributing third-party binaries, scripts, packages, actions, plugins, models, or archives.
---

# Supply-Chain Verification

## Core rule
Third-party bytes need known **provenance** before they become trusted build or install inputs.

Prefer official release channels and pinned immutable versions. Record source URL/repository, version/commit, expected **hash**, and licensing/redistribution constraints where relevant. Verify a published cryptographic **signature** when the upstream provides one; otherwise verify checksums from an independent authoritative channel when possible.

Avoid unpinned `latest` in reproducible release paths. If runtime update checks intentionally use latest, resolve it to an immutable identity before execution and record what was chosen.

Scan archives for unexpected executable content, path traversal, and nested secrets. A successful download only proves transport, not authenticity or compatibility.
