---
name: config-preservation
description: Use when reading, merging, editing, migrating, or generating user-owned JSON, YAML, TOML, INI, or settings files.
---

# Config Preservation

## Core rule
User configuration is data, not a template target. **Merge** only the keys you own and preserve everything else.

## Safe update contract
- Read using the file’s real encoding; prefer explicit UTF-8 for modern configs.
- Parse before changing.
- **Backup** the original bytes before a destructive rewrite.
- Modify the smallest owned subtree.
- Serialize to a temporary sibling file when possible, then atomically replace.
- Parse the result again and verify the owned values.
- Preserve or deliberately normalize line endings/encoding only when the format contract allows it.
- On any failed write/verification, restore the original bytes.

A successful write requires a verified **round-trip**, not merely a zero exception.

Never replace a live config wholesale with a developer-machine template. Never delete unknown keys because the local schema does not recognize them.
