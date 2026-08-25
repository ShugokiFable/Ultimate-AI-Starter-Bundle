---
name: paradox-modding
description: Paradox grand strategy mods - Stellaris, Crusader Kings III, Hearts of Iron IV, Europa Universalis IV, Victoria 3, and the shared Clausewitz/Jomini script, localisation, and descriptor rules.
---

# Paradox Clausewitz / Jomini mod development

Read `game-modding` -> `references/MODDING-LAWS.md` before the first write:
version snapshot, evidence ladder, and the never-invent rules apply here too.

Start with `references/OVERVIEW.md` for the shared toolchain, then the
specific reference below.

| Target | Reference |
|---|---|
| Stellaris | `references/stellaris.md` |
| Crusader Kings III | `references/ck3.md` |
| Hearts of Iron IV | `references/hoi4.md` |
| Europa Universalis IV | `references/eu4.md` |
| Victoria 3 | `references/victoria3.md` |

Resolve the exact game build, loader, mappings, and framework versions before
implementing. Never invent an API, hook, signature, ID, or asset path.
