---
name: compatibility-matrix
description: Use when behavior depends on combinations of operating system, shell, architecture, runtime, model/provider, API revision, application version, or optional dependency.
---

# Compatibility Matrix

## Core rule
Compatibility is a **matrix**, not a single version number.

List the dimensions that can change behavior: **platform**, architecture, shell, runtime/tool version, provider/model, protocol/schema version, and relevant optional components. Mark each combination supported, unsupported, or unverified.

Choose representative high-risk intersections for automated tests, especially the oldest supported runtime and newest protocol/dependency. Do not extrapolate a Linux/Python pass to Windows PowerShell or one provider's MCP schema to another.

Keep compatibility claims tied to evidence and update the matrix when a boundary changes. If a combination is not exercised, say unverified instead of compatible by assumption.
