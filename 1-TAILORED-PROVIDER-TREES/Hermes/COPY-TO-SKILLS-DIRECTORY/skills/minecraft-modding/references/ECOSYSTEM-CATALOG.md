# Minecraft Java ecosystem catalog

This is a routing catalog, not a compatibility guarantee.

## Loaders and core APIs

- Fabric Loader and Fabric API
- Forge
- NeoForge
- Quilt Loader, Quilt Standard Libraries, and Quilted Fabric API

## Build, mappings, and bytecode

- Fabric Loom
- ForgeGradle
- NeoGradle and current NeoForge tooling
- Quilt tooling
- official/Mojang mappings
- Yarn
- Parchment
- SpongePowered Mixin
- MixinExtras
- access wideners
- access transformers

## Cross-loader architecture

- Architectury API
- loader-specific platform modules
- common source sets
- project-specific multiloader templates

## Persistent and attached data

- vanilla data components and codecs
- Fabric Data Attachment API
- Cardinal Components
- Forge capabilities
- NeoForge data attachments
- SavedData and equivalent persistent stores

## Common optional integration categories

- JEI, REI, EMI
- Cloth Config, YACL, Mod Menu
- Curios, Trinkets, Accessories
- GeckoLib
- Patchouli
- TerraBlender
- KubeJS and CraftTweaker
- Registrate
- Balm, Bookshelf, Moonlight, Puzzles Lib, Resourceful Lib, Porting Lib
- Kotlin language adapters when the project is actually Kotlin-based

For every dependency, inspect the upstream repository and release metadata for
the exact Minecraft and loader version.
