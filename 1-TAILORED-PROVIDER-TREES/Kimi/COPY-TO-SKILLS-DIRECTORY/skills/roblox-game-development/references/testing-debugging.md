# Roblox testing and debugging

## Evidence-first bug loop

1. Reproduce the exact behavior.
2. Read Output / error text.
3. Identify script, line, state, or event path.
4. Inspect the actual source/state.
5. Form one concrete hypothesis.
6. Apply the smallest useful fix.
7. Re-run the same scenario.
8. Remove temporary debug spam.
9. Verify nearby regression risks.

Do not replace three scripts because one nil error appeared.

## Roblox built-in Assistant skills

The current Studio Assistant documents Roblox-maintained skills. If the official
Studio MCP exposes the `skill` tool, use these specialized capabilities when they
fit instead of manually reinventing them:

- `rbx-debug` — breakpoints, call stacks, locals/thread state.
- `rbx-unit-test` — framework detection and Luau unit-test workflow.
- `rbx-device-simulator-lua` — device presets/orientation/UI capture.
- `rbx-perf-profiling` — MicroProfiler interpretation.
- `rbx-scene-analysis` — scene/memory/rendering health.
- `rbx-docs-search` — authoritative Roblox docs.

Always discover current availability; names/capabilities can change.

## Unit testing policy

Use existing project framework first.

Current useful options include:
- Roblox/Jest Roblox (Roblox-maintained read-only mirror / internal lineage),
- jsdotlua/jest-lua community continuation,
- a tiny built-in harness for small pure modules.

TestEZ is historically common but archived; do not install it as the automatic modern default.

Unit-test:
- pure calculations,
- inventory/economy rules,
- state machines,
- validation,
- serialization/migrations.

Playtest:
- character motion,
- physics,
- UI interaction,
- remotes,
- spawn/respawn,
- NPC behavior,
- camera,
- networked gameplay.

## Source-controlled automation

For Rojo projects, `rojo-rbx/run-in-roblox` can run a place/model/script inside
Studio and pipe output to stdout/stderr. It is useful for deterministic CI-style
Studio tests when the project shape fits it.

Do not install it for a Studio-native prototype unless automation justifies it.

## Completion

A gameplay fix is complete only when the failing scenario is exercised in the
final state and the expected result is observed.
