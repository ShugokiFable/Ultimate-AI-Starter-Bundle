# Roblox API and documentation lookup

Use when you need CURRENT Roblox API facts rather than recalled ones: service
behavior, Luau syntax, method signatures, deprecations, and limits.

Resolve against primary sources before implementing:

- https://create.roblox.com/docs - engine, API reference, Luau
- https://create.roblox.com/docs/reference/engine - class and service reference

Facts that go stale fastest, so look them up every time:

- `DataStoreService` limits, retry and `UpdateAsync` semantics
- `ProcessReceipt` correctness and idempotency requirements
- `RemoteEvent` / `RemoteFunction` trust boundaries and rate limits
- `TweenService` easing and completion behavior
- Streaming-enabled replication and instance lifetime
- Task scheduler and `task.*` versus deprecated `wait`/`spawn`

Never invent a class, property, method, enum, or limit. If the documentation does
not state it, verify inside Studio with the official Roblox Studio MCP.
