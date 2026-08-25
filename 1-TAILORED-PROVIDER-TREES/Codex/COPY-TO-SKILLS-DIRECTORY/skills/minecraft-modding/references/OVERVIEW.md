# Minecraft Java mod development

Minecraft modding is a matrix, not one API.

## Resolve first

- Minecraft version, including whether the project uses the newer calendar-style
  version line or an older `1.x` line;
- Java version;
- loader and loader version;
- mappings namespace;
- Gradle plugin and build tool versions;
- client, dedicated server, or both;
- required and optional library mods;
- whether the project is single-loader or multiloader;
- source-set and generated-resource layout.

## Loader routing

| Target | Load these specialists |
|---|---|
| Fabric | `minecraft-fabric-quilt-modding` |
| Quilt | `minecraft-fabric-quilt-modding`, with Quilt/QSL verification |
| Forge | `minecraft-forge-neoforge-modding`, Forge branch |
| NeoForge | `minecraft-forge-neoforge-modding`, NeoForge branch |
| Several loaders | `minecraft-multiloader-architectury` |
| Mixins or private access | `minecraft-mixins-access-control` |
| Saved or synced data | `minecraft-data-components-attachments` |
| Packets and dedicated server | `minecraft-networking-persistence` |
| Registries, tags, recipes, loot, data generation | `minecraft-content-datagen-worldgen` |
| Models, renderers, animation | `minecraft-rendering-animation` |
| Config, mod menu, recipe viewer, accessories | `minecraft-library-api-integrations` |
| KubeJS/CraftTweaker/modpack scripts | `minecraft-modpack-scripting` |
| Porting and release | `minecraft-testing-porting-release` |

## Common ecosystem categories

The exact library list is version and loader dependent. Common categories
include Fabric API, Forge APIs, NeoForge APIs, Quilt APIs, Architectury,
SpongePowered Mixin, MixinExtras, Parchment mappings, Cardinal Components,
loader-native attachments/capabilities, Curios, Trinkets, Accessories, Cloth
Config, YACL, Mod Menu, GeckoLib, JEI, REI, EMI, Patchouli, TerraBlender,
KubeJS, CraftTweaker, Registrate, Balm, Bookshelf, Moonlight, Puzzles Lib,
Resourceful Lib, and other library mods.

A familiar name is not proof that the requested Minecraft and loader version is
supported. Inspect the exact project release, Gradle coordinates, license,
side requirements, and API source.
