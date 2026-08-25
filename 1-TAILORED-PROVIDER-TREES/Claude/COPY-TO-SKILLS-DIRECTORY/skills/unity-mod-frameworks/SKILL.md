---
name: unity-mod-frameworks
description: Unity game mods via BepInEx, Harmony, MonoMod, IL2CPP or Mono - RimWorld, Valheim, Subnautica, Lethal Company, Risk of Rain 2, Stardew Valley, Oxygen Not Included, Kerbal Space Program, and generic Unity targets.
---

# Unity / BepInEx / Harmony mod development

Read `game-modding` -> `references/MODDING-LAWS.md` before the first write:
version snapshot, evidence ladder, and the never-invent rules apply here too.

Start with `references/OVERVIEW.md` for the shared toolchain, then the
specific reference below.

| Target | Reference |
|---|---|
| RimWorld | `references/rimworld-harmony.md` |
| Valheim | `references/valheim-jotunn.md` |
| Subnautica | `references/subnautica-nautilus.md` |
| Lethal Company | `references/lethal-company.md` |
| Risk of Rain 2 | `references/risk-of-rain2.md` |
| Stardew Valley | `references/stardew-valley.md` |
| Oxygen Not Included | `references/oxygen-not-included.md` |
| Kerbal Space Program 1 | `references/kerbal-space-program.md` |
| Harmony patch order and safety (cross-game) | `references/dotnet-harmony-patching.md` |

Resolve the exact game build, loader, mappings, and framework versions before
implementing. Never invent an API, hook, signature, ID, or asset path.
