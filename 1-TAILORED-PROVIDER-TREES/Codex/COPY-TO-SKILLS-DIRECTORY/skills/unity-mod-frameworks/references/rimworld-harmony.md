# RimWorld

RimWorld is approachable, but its XML, Verse, Harmony, load order, and save
serialization still require version-specific care.

## Framework map

- `About/About.xml`, package IDs, dependencies, incompatibilities, and load order;
- game-version folders and supported versions;
- XML Defs, PatchOperations, languages, textures, sounds, and assemblies;
- Verse and RimWorld managed assemblies;
- Harmony patches;
- DefOf initialization;
- save serialization through Scribe;
- settings and Mod classes;
- optional frameworks such as HugsLib, Vanilla Expanded Framework, Vehicle
  Framework, Multiplayer API, and others only when the project explicitly uses
  them.

## Required tests

- clean game with only dependencies;
- intended load order;
- existing save;
- new colony;
- mod disabled after save backup;
- optional frameworks absent/present;
- every supported game version folder.

Never patch generated or deployed workshop copies as the source project.

Primary references:

- https://rimworldwiki.com/wiki/Modding
- https://rimworldwiki.com/wiki/Modding_Tutorials
- https://github.com/pardeike/Harmony
