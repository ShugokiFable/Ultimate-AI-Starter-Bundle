# Roblox-authored Assistant skills as specialist accelerators

Roblox documents built-in Assistant skills maintained by Roblox. When the official
Studio MCP exposes the `skill` capability, these can act like domain sub-agents for
Hermes/Claude/Codex.

## Route by problem

| Need | Prefer |
|---|---|
| exact API/current docs | `rbx-docs-search` or RobloxForge `rb_docs_search` |
| runtime bug/state | `rbx-debug` |
| unit tests | `rbx-unit-test` |
| phone/tablet/console UI | `rbx-device-simulator-lua` |
| CPU/GPU/frame spikes | `rbx-perf-profiling` |
| memory/render/scene audit | `rbx-scene-analysis` |

## Usage policy

1. Discover whether the `skill` tool and named skill are actually available.
2. Use the specialized skill for the hard part.
3. Use normal Studio tools to implement fixes.
4. Re-test with runtime evidence.
5. Do not load every skill "just in case."

## Fallbacks

- docs skill unavailable -> RobloxForge local creator-docs cache
- debug skill unavailable -> playtest + Output + targeted temporary diagnostics
- device skill unavailable -> available Studio device emulator/manual evidence
- perf skill unavailable -> MicroProfiler/Stats evidence that the current tool surface can actually expose
- scene analysis unavailable -> targeted hierarchy/property/instance-count audit

Never claim use of a Roblox-authored skill unless the current Studio instance exposed it.
