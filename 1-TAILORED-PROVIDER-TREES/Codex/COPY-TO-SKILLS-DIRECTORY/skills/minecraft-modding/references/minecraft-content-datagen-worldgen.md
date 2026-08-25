# Content, data generation, worldgen

Use deterministic data generation for registries, models, blockstates, tags,
recipes, loot tables, advancements, language files, and other generated assets.

## Worldgen

Pin the target version's codec/schema and determine whether the feature belongs
in vanilla data packs, loader APIs, TerraBlender, or custom code. Validate seeds,
server generation, upgrade of existing worlds, biome-source interactions,
datapack reload, and generated-resource completeness.

Never hand-edit generated output without updating its source generator.

Primary references:

- https://docs.fabricmc.net/develop/
- https://docs.minecraftforge.net/
- https://docs.neoforged.net/
- https://github.com/Glitchfiend/TerraBlender
