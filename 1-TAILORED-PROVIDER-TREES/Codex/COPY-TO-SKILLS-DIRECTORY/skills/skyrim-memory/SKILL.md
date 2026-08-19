---
name: skyrim-memory
description: Consult the Claude Code Skyrim evidence registry before substantial mod work so previously observed failures
  are not repeated.
when_to_use: Before substantial Skyrim creation, repair, debugging, packaging, publishing, plugin, Papyrus, runtime-patching,
  follower, OStim, or DLL work
metadata:
  version: 5.0.0
  provider: codex
  updated: '2026-07-31'
  architecture: self-contained-skill-references
  provider_pack_version: 1.0.0
  base_library: Skyrim-Agent-Skills-v6
  error_registry_revision: 4.3.0
  final_pack_version: 5.0.0
---

# Skyrim evidence registry

The error registry and technical lessons are bundled inside this skill:

```text
skyrim-memory\references\
```

There is no separate memory directory to install.

## Start

1. Read `references/GLOBAL-LESSONS.md`.
2. Search `references/ERROR-REGISTRY.json` by task tags and symptoms.
3. Read only matching entries and the relevant validation sections.
4. Check the active project's `CURRENT.txt`, `CHANGELOG`, `STATE.md`, and known-good records.
5. Apply the evidence ladder.

## Evidence ladder

1. `user-confirmed-runtime`
2. `runtime-evidenced`
3. `tool-validated`
4. `assistant-claimed`
5. `contradicted`

Conversation text alone is not validation. Promote technical lessons only when
supported by actual artifacts, user feedback, build output, parser results, or
runtime behavior.

## Registry scope

- `shared-cross-provider` entries apply to every supported AI application.
- `provider-specific` entries apply only to Claude.
- Do not reinterpret another provider's entry as a failure of this provider.

## Project-local learning

Write proposed lessons to:

```text
<Project>\MEMORY\CANDIDATES.md
```

Do not rewrite the bundled registry automatically. Promotion requires
`references/MEMORY-PROMOTION-PROTOCOL.md`.
