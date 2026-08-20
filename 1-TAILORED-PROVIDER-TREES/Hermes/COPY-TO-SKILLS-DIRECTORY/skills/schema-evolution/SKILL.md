---
name: schema-evolution
description: Use when JSON, YAML, TOML, databases, APIs, manifests, messages, configs, or persisted objects change shape across versions.
---

# Schema Evolution

## Core rule
A **schema** change is a compatibility event even when the code diff is small.

Define old and new shapes, defaults for added fields, treatment of unknown fields, and whether readers/writers remain **backward** compatible. Provide a versioned **migration** when persisted data cannot be read directly.

Test at least: current writer→current reader, previous supported writer→current reader, current writer→older consumer when backward output is promised, missing optional fields, unknown future fields, and malformed input.

Preserve user-owned unknown data when round-tripping configs unless the schema explicitly forbids it. Never silently reinterpret an old field with a new meaning; migrate deliberately and record the schema version used.
