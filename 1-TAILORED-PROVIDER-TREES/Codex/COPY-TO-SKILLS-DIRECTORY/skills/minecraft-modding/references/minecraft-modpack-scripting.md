# Modpack scripting

First decide whether the change belongs in:

- vanilla data/resource pack;
- KubeJS;
- CraftTweaker;
- loader-specific configuration;
- a real Java mod.

Pin the Minecraft, loader, script framework, and addon versions. Validate load
phases, startup/server/client script roots, recipe IDs, tags, event names,
reload behavior, dedicated server, and pack update migration.

Do not copy scripts from a different Minecraft generation without checking the
current event and wrapper APIs.

Primary sources:

- https://github.com/KubeJS-Mods/KubeJS
- https://github.com/CraftTweaker/CraftTweaker
