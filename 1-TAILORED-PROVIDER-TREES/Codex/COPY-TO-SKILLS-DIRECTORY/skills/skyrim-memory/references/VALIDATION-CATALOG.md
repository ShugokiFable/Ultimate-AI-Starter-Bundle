# Validation Catalog

Use only the gates relevant to the task, but report which were run.

## Package and FOMOD

- Parse `ModuleConfig.xml` and `info.xml`.
- Validate schema element order and required attributes.
- Enumerate every installer branch and verify source/destination paths.
- Ensure optional choices remain present.
- Inspect the final ZIP root and payload.
- Compare release inventory against the prior known-good package.
- Confirm the ZIP contains the newest built files, not stale copies.

## Plugin

- Confirm target runtime/toolchain matrix.
- Verify masters, flags, header version, record count, and local FormID policy.
- Detect duplicate FormIDs and unresolved references.
- Parse all changed record families deeply enough to validate subrecord order.
- Validate VMAD object formats and property types.
- Validate `.seq` generation from actual start-game-enabled quests.
- Run the configured plugin gate against both loose plugin and final archive.
- Keep runtime status separate from structural status.

## Papyrus and MCM

- Compile against real parent sources where possible.
- Confirm PEX timestamps/hashes correspond to final PSC.
- Verify no compile-only stubs ship.
- Validate MCM Helper JSON types, page definitions, option IDs, and bindings.
- Test first-run, existing save, reset, uninstall, and dependency-missing paths.

## Runtime patching

- Verify exact framework version and scan directory.
- Parse every generated row/config.
- Resolve plugin-qualified references.
- Check duplicate, contradictory, and unreachable rules.
- Expand representative target sets and inspect false positives.
- Preserve deterministic ordering and formatting.

## Native DLL

- Configure and build from a clean tree.
- Confirm architecture, runtime library, exports, dependencies, and supported
  Skyrim/SKSE/CommonLib matrix.
- Check logs for load failures.
- Provide a minimal runtime test and rollback plan.

## Appearance/followers

- Test apply-before-summon and summon-before-apply.
- Test reset/dismiss and verify the player is never moved to a temp cell.
- Test high-poly head, FaceGen/tint, tattoos, body presets, dynamic normal maps,
  sex/voice/race mappings, save/reload, and 3D unload/reload.

## Evidence-derived mandatory gates

- `EXACT BUILD`: clean build against pinned local dependencies or explicit `UNBUILT`.
- `RUNTIME-SHAPED TEST`: real path/dependency/lifetime conditions reproduced where applicable.
- `SEMANTIC`: player-visible behavior and selector/condition meaning tested.
- `FINAL ARCHIVE`: inventory, public version strings, and SHA-256 recorded.
