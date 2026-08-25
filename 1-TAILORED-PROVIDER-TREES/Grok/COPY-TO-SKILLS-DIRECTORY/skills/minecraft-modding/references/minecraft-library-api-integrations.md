# Library and API integrations

## Categories to inspect

### Configuration and menus

- loader-native config systems;
- Cloth Config;
- YetAnotherConfigLib;
- Mod Menu;
- other version-specific config screens.

### Recipe and item viewers

- JEI;
- REI;
- EMI.

These are viewer/plugin APIs, not recipe-authoring replacements.

### Accessories and equipment slots

- Curios;
- Trinkets;
- Accessories.

### Guide books and documentation

- Patchouli and loader/version-specific alternatives.

### Shared utility libraries

- Architectury;
- Balm;
- Bookshelf;
- Moonlight;
- Puzzles Lib;
- Resourceful Lib;
- Registrate;
- Porting Lib;
- other project-specific libraries.

## Rules

- Treat every integration as optional unless the mod intentionally requires it.
- Isolate adapters so the core mod loads when the optional API is absent.
- Never load client-only viewer/config classes on a dedicated server.
- Pin exact Maven coordinates and licenses from the upstream project.
- Avoid adding a large library for one trivial helper.

Representative primary repositories:

- https://github.com/mezz/JustEnoughItems
- https://github.com/shedaniel/RoughlyEnoughItems
- https://github.com/emilyploszaj/emi
- https://github.com/shedaniel/cloth-config
- https://github.com/illusivesoulworks/curios
- https://github.com/emilyploszaj/trinkets
- https://github.com/wisp-forest/accessories
- https://github.com/Fuzss/puzzles-lib
