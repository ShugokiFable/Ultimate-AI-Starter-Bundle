---
name: minecraft-modding
description: Minecraft Java mod development - Fabric, Forge, NeoForge, Quilt, multiloader, mixins, data generation, worldgen, networking, rendering, modpack scripting, porting across game and loader versions.
---

# Minecraft Java mod development

Read `game-modding` -> `references/MODDING-LAWS.md` before the first write:
version snapshot, evidence ladder, and the never-invent rules apply here too.

Start with `references/OVERVIEW.md` for the shared toolchain, then the
specific reference below.

| Target | Reference |
|---|---|
| Fabric / Quilt | `references/minecraft-fabric-quilt.md` |
| Forge / NeoForge | `references/minecraft-forge-neoforge.md` |
| Multiloader / Architectury | `references/minecraft-multiloader-architectury.md` |
| Mixins and access control | `references/minecraft-mixins-access-control.md` |
| Content, data generation, worldgen | `references/minecraft-content-datagen-worldgen.md` |
| Data components and attachments | `references/minecraft-data-components-attachments.md` |
| Networking and persistence | `references/minecraft-networking-persistence.md` |
| Rendering and animation | `references/minecraft-rendering-animation.md` |
| Library and API integrations | `references/minecraft-library-api-integrations.md` |
| Modpack scripting | `references/minecraft-modpack-scripting.md` |
| Testing, porting, release | `references/minecraft-testing-porting-release.md` |

Resolve the exact game build, loader, mappings, and framework versions before
implementing. Never invent an API, hook, signature, ID, or asset path.
