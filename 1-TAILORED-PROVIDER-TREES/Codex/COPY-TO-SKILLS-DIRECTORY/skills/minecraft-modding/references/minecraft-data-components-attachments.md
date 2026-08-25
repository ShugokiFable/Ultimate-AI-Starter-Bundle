# Data components and attachments

Possible systems vary by loader and version:

- vanilla data components and codecs;
- Fabric Data Attachment API;
- Cardinal Components API;
- Forge capabilities;
- NeoForge data attachments;
- Curios, Trinkets, or Accessories data owned by those APIs;
- saved data, entity data, block-entity data, chunk data, and world data.

For each field, define owner, lifetime, default, serialization codec, sync
direction, cloning/death behavior, dimension transfer, migration, and removal.

Never mix several ownership systems for the same data without an explicit
adapter and migration plan.

Primary references:

- https://docs.fabricmc.net/develop/data-attachments
- https://docs.minecraftforge.net/en/latest/datastorage/capabilities/
- https://docs.neoforged.net/
- https://wiki.fabricmc.net/community:library_mods
