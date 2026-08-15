# Skyrim SE/AE plugin invariants

## Header and FormID modes

### Legacy-compatible mode

- HEDR `1.70`.
- ESL-flagged ESP flag `0x200` when applicable.
- New light-plugin local FormIDs: `0x800` through `0xFFF`.

### Extended FormID mode

- HEDR `1.71`.
- New light-plugin local FormIDs: `0x001` through `0xFFF`; `0x000` remains reserved.
- **A module that actually uses the extended range below `0x800` must list the Game Master, `Skyrim.esm`, as its first master.**
- A dependent module that uses a HEDR `1.71` master must itself use HEDR `1.71` when the extended-range records can be referenced or overridden.
- The complete transitive master chain must be present and ordered before the direct master that requires it.

Overrides retain the source record's FormID and are not judged as newly allocated local IDs.

## Target decision

- Do not normalize every historical plugin to 1.71.
- Use 1.70 for legacy runtime compatibility unless the declared target/backport supports 1.71.
- Use 1.71 when low light IDs are allocated or a 1.71 dependency requires it.
- Record the runtime, Creation Kit/toolchain, and BEES/backport requirement.

## Record structure

- New Skyrim SE/AE records normally use form version `44`; preserve legitimate historical records unless conversion is intentional.
- HEDR record/group count, master indices, master ordering, and serialized links must be parser-validated.
- A header pass does not prove VMAD, navmesh, dialogue, facegen, quest, or runtime correctness.
- ESM/ESL/ESP flags are semantic decisions, not cosmetic file-extension choices.

## Master rules

- `Skyrim.esm` is the Game Master for Skyrim SE/AE.
- Extended-range output without `Skyrim.esm` first is a ship-blocking error.
- Do not remove a required up-chain master merely because the plugin contains no obvious direct record header from it.
- Resolve all plugin-qualified FormIDs and verify every master index.
