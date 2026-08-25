# Roblox persistence

Use persistence only when the game loop actually needs it.

## Core rules

- `DataStoreService` is server-side.
- Treat load/save failures as normal operational events.
- Use `pcall`/error-aware retry policy.
- Prefer `UpdateAsync` when multiple servers may modify the same logical value.
- Keep a versioned schema for meaningful player data.
- Validate/sanitize before saving.
- Do not persist arbitrary client-provided tables.
- Do not write on every coin tick.

## Studio safety

Roblox documents an important trap: Studio API access can touch the same data as
the live experience. Do **not** casually enable Studio DataStore access against a
production universe. Use a separate test version/universe or deliberate test keys.

## Suggested data shape

Keep one player profile with explicit version and bounded fields:

- schema version
- progression
- inventory identifiers/counts
- settings
- timestamps needed for offline/time systems

Avoid serializing transient Instances or giant nested runtime objects.

## Save strategy

Typical triggers:
- periodic checkpoint at a reasonable interval,
- important irreversible transaction after server validation,
- `PlayerRemoving`,
- server shutdown via `BindToClose` with bounded time.

Never promise a save succeeded until the call actually succeeded.

## Migrations

When schema changes:
1. read old version,
2. validate,
3. migrate in memory,
4. write new version safely,
5. keep migration deterministic and testable.

## Temporary/global state

For frequently changing temporary cross-server state, evaluate MemoryStore rather
than abusing persistent DataStores. Verify current quotas/semantics from official docs.

## Third-party profile libraries

Do not hardcode one community library as eternal truth. If a project already uses
a profile/session-locking library, follow it. Otherwise research current maintenance
and tradeoffs before introducing a dependency.
