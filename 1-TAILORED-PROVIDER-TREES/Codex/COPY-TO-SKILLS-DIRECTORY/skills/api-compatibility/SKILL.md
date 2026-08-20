---
name: api-compatibility
description: Use when changing commands, schemas, APIs, protocols, config formats, plugin interfaces, or behavior consumed by other components.
---

# API Compatibility

## Core rule
Treat every external interface as a **contract** with one or more **consumer** versions.

## Contract
Enumerate observable inputs, outputs, error codes, defaults, side effects, ordering, and version negotiation. Preserve **backward** behavior unless a breaking change is intentional and versioned.

For a compatibility change, test at least: current producer/current consumer, new producer/old supported consumer, old supported producer/new consumer, unsupported versions, unknown fields, and missing optional fields.

Prefer additive changes and capability negotiation over silent semantic changes. Make incompatible combinations fail clearly rather than partially working.

When two repositories must “work in harmony”, encode the supported range in a machine-readable handshake and test both accepted and rejected neighbors. Documentation alone is not a compatibility boundary.
