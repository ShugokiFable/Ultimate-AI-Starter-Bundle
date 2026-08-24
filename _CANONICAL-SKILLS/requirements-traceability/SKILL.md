---
name: requirements-traceability
description: Use when implementing a multi-part request, specification, migration, release, audit, or acceptance-test-driven task.
---

# Requirements Traceability

## Core rule
Every material **requirement** needs a mapped implementation location and independent **evidence**.

## Trace table
Track: requirement → owning file/component → test/gate → artifact/runtime proof → status. Include negative requirements (“must not overwrite config”, “must not require manual setup”) and platform constraints.

Before completion, walk the table line by line. Test suites provide **coverage** only for requirements they actually assert; a green suite does not prove an omitted requirement.

When scope changes, update the table first so new work cannot disappear into prose. When a requirement cannot be verified in the current environment, mark it explicitly pending and name the exact gate that would prove it.

Use this skill to prevent “we implemented the main thing” from becoming a substitute for the full user request.
