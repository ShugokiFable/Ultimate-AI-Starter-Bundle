---
name: unreal-mod-frameworks
description: Unreal Engine 4/5 mods via UE4SS, Lua and C++ hooks, generated SDKs, reflection, and packaged pak/utoc content - Palworld, Satisfactory, XCOM 2, and generic Unreal targets.
---

# Unreal Engine mod development

Read `game-modding` -> `references/MODDING-LAWS.md` before the first write:
version snapshot, evidence ladder, and the never-invent rules apply here too.

Start with `references/OVERVIEW.md` for the shared toolchain, then the
specific reference below.

| Target | Reference |
|---|---|
| Palworld | `references/palworld.md` |
| Satisfactory | `references/satisfactory-sml.md` |
| XCOM 2 / War of the Chosen | `references/xcom2.md` |

Resolve the exact game build, loader, mappings, and framework versions before
implementing. Never invent an API, hook, signature, ID, or asset path.
