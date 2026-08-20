# Plugin invariants

Forge-created Skyrim SE/AE plugins use TES4 HEDR 1.71 and form version 44. ESPFE output uses record flag `0x200` and local FormIDs from `0x800` through `0xFFF`.

The built-in writer creates new KYWD, GLOB, FLST, and OTFT records only. It does not edit NAVM, CELL, WRLD, LAND, QUST, DIAL, INFO, SCEN, or arbitrary VMAD structures.

A successful Forge reopen is structural evidence, not independent xEdit or runtime evidence.
