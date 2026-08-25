---
name: game-modding
description: Modding any game other than Skyrim - Cyberpunk 2077, Baldur's Gate 3, Factorio, Terraria, Arma 3, DayZ, Project Zomboid, Garry's Mod, No Man's Sky, Witcher 3, Bannerlord, Space Engineers, and 20 more, plus the cross-game workflow, packaging, crash, and release rules.
---

# Modding any game other than Skyrim

Read `references/MODDING-LAWS.md` before the first write. It is not optional:
it carries the version-snapshot workflow, the evidence ladder, and the
never-invent rules that every game below depends on.

For Skyrim use the `skyrim-*` skills instead -- they are deeper and this
skill deliberately does not duplicate them.

## Pick the family first

| Game family | Skill |
|---|---|
| Minecraft Java | `minecraft-modding` |
| Paradox grand strategy | `paradox-modding` |
| Unity / BepInEx / Harmony | `unity-mod-frameworks` |
| Unreal Engine / UE4SS | `unreal-mod-frameworks` |
| Fallout 4, Starfield | `bethesda-creation-modding` |
| Roblox | `roblox-game-development` |
| Saints Row 3/4 | `saints-row-modding` |

## Games covered here

| Game | Reference |
|---|---|
| Cyberpunk 2077 | `references/cyberpunk2077.md` |
| The Witcher 3 | `references/witcher3-redkit.md` |
| Baldur's Gate 3 | `references/baldurs-gate3.md` |
| Divinity: Original Sin 2 | `references/divinity-original-sin2.md` |
| Factorio | `references/factorio.md` |
| Terraria | `references/terraria-tmodloader.md` |
| Project Zomboid | `references/project-zomboid.md` |
| Don't Starve Together | `references/dont-starve-together.md` |
| Noita | `references/noita.md` |
| Garry's Mod | `references/garrys-mod.md` |
| Slay the Spire | `references/slay-the-spire.md` |
| Barotrauma | `references/barotrauma.md` |
| Cities: Skylines II | `references/cities-skylines2.md` |
| BeamNG.drive | `references/beamng.md` |
| Arma 3 | `references/arma3.md` |
| DayZ | `references/dayz.md` |
| Space Engineers | `references/space-engineers.md` |
| Mount & Blade II: Bannerlord | `references/bannerlord.md` |
| No Man's Sky | `references/no-mans-sky.md` |

If the game is not listed, read `references/game-mod-unknown-game-fallback.md`
and do not guess an API.

## Cross-game workflow

| Task | Reference |
|---|---|
| Start a new mod or major feature | `references/game-mod-development.md` |
| Repair, modernize, or extend an existing mod | `references/game-mod-reworking.md` |
| The game or loader is unfamiliar | `references/game-mod-unknown-game-fallback.md` |
| Resolve a version-sensitive fact from installed truth | `references/game-mod-facts.md` |
| Cross-game error registry and lessons | `references/game-mod-memory.md` |
| Versioned workspace and rollback | `references/game-mod-versioned-workspace.md` |
| Read-only review of mod source | `references/game-mod-code-review.md` |
| Final release gate | `references/game-mod-ship-gate.md` |

## Engineering

| Task | Reference |
|---|---|
| Native / managed runtime plugins, loaders, hooks | `references/game-mod-native-plugin.md` |
| Data, reflection, script, config, runtime patches | `references/game-mod-runtime-patching.md` |
| Textures, meshes, materials, animation, audio, UI | `references/game-mod-assets.md` |
| Roots, manifests, dependencies, optional branches | `references/game-mod-packaging.md` |
| Dependency graph, load order, patch precedence | `references/game-mod-load-order-compatibility.md` |
| Startup failures, crashes, loader and script errors | `references/game-mod-crash-diagnostics.md` |
| CPU, GPU, memory, I/O, startup cost | `references/game-mod-performance-profiling.md` |

The cross-game error registry is `references/ERROR-REGISTRY.json`; read it
before substantial repair, packaging, or release work.
