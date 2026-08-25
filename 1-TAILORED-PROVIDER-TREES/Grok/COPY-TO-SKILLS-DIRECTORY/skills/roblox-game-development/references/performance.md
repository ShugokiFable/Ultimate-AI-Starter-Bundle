# Roblox performance — measure first

Roblox performance problems span script CPU, rendering, physics, memory, network,
and streaming. Optimize the measured bottleneck.

## Common script traps

- expensive work every frame,
- repeatedly walking large descendant trees,
- deep clone/serialization of huge tables,
- high-frequency remotes,
- unbounded spawned tasks,
- connection leaks,
- expensive NPC decisions at render frequency.

Use slower decision ticks for AI when possible and interpolate presentation.

## Scene traps

- excessive unique meshes/materials/textures,
- huge particle counts,
- many unanchored physics assemblies,
- unnecessary collisions/touches,
- large always-replicated worlds,
- duplicated assets.

## Network

Send semantic state changes, not every visual detail.
Do not fire reliable remotes every frame for effects that can be derived locally.

## Streaming

Large experiences should evaluate instance streaming. Client code must tolerate
objects being absent/unstreamed and avoid assuming the entire Workspace exists locally.

## Built-in specialist

If available through Studio's `skill` tool:
- `rbx-perf-profiling` for MicroProfiler evidence
- `rbx-scene-analysis` for scene/memory/rendering composition

## Procedure

1. reproduce lag/stutter,
2. capture profiler/scene evidence,
3. identify dominant subsystem,
4. fix one dominant issue,
5. recapture evidence,
6. compare before/after.

"Use fewer parts" is not a performance analysis.
