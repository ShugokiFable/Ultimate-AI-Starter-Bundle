# Fabric / Quilt

## Verify

- Minecraft, Java, loader, Fabric API/QSL/QFAPI versions;
- Loom or Quilt Gradle plugin version;
- mappings and namespace;
- `fabric.mod.json` or Quilt metadata;
- entrypoints and environment;
- access wideners;
- mixin configs and refmaps;
- client/server source separation;
- nested JARs and dependency declarations.

Fabric events commonly provide compatibility-friendly alternatives to direct
Mixins, but not every game behavior has an event. Quilt can consume much of the
Fabric ecosystem, while Quilt-specific APIs and documentation must still be
checked for the exact version.

Primary sources:

- https://docs.fabricmc.net/
- https://github.com/FabricMC/fabric
- https://wiki.quiltmc.org/
- https://quiltmc.org/
