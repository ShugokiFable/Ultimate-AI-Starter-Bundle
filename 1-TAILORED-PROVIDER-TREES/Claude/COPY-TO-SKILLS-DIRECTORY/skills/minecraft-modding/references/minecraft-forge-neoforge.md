# Forge / NeoForge

Forge and NeoForge are related ecosystems, not interchangeable import namespaces.

## Verify

- exact loader branch and Minecraft version;
- ForgeGradle or NeoGradle/toolchain version;
- official/Mojang/Parchment mappings;
- mod metadata and dependency ranges;
- event bus and lifecycle;
- registries and deferred registration;
- sides and distribution safety;
- networking;
- Forge capabilities versus NeoForge data attachments or current equivalents;
- access transformers;
- configuration system;
- data generation and GameTest support.

Do not mechanically replace package names to port between Forge and NeoForge.
Compare official porting notes and source for the target release.

Primary sources:

- https://docs.minecraftforge.net/
- https://docs.neoforged.net/
