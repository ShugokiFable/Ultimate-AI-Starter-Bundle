# Skyrim modernization master prompt

Modernize the supplied Skyrim mod under the V4 Skyrim skill rules.

Use `<WorkspaceRoot>`, `<ToolsRoot>`, and `<GameRoot>` placeholders. Inspect the active environment before selecting dependencies. Classify the result as a compatibility patch, modernization, replacement, or successor. Preserve the original concept and installer choices unless a documented design decision changes them.

Prefer the least conflict-heavy mechanism that correctly represents the behavior. Route through `skyrim-frameworks-index` and the dedicated KID, SPID, SkyPatcher, BOS, Papyrus, plugin, or native skill. Do not force a runtime framework into an unsupported operation.

For plugins, enforce legacy versus extended FormID mode, `Skyrim.esm` first-master requirements, complete master chains, HEDR, form version, ESL flag, record counts, links, VMAD, and package contents. Agents do not claim xEdit or Creation Kit GUI results.

Return the audit, architecture, requirements, permissions ledger, implementation, generated files, compatibility matrix, validation results, remaining tests, release tree, changelog, and final archive hash.
