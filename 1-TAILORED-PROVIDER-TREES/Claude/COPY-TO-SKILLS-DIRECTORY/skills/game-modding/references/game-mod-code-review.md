# Read-only review of mod source

Review version pinning, APIs/hooks, lifecycle, threading, networking, save
migration, reflection/binary fragility, assets, package roots, config
compatibility, hot paths, and release/source drift.

Remain read-only unless fixes are explicitly authorized. Rank findings by crash,
save corruption, desync, silent data loss, regression, and packaging severity.


## Non-negotiable laws

- Never edit a deployed game directory, active mod-manager staging folder, save, profile, or framework installation as the project source.
- Resolve the exact game build, storefront, runtime, loader, framework versions, dependency graph, and packaging format before implementation.
- Never invent API names, hook signatures, offsets, asset identifiers, manifest keys, paths, serialization fields, or compiler syntax.
- Prefer official documentation, upstream source, exact installed files, generated SDKs, and known-good local examples.
- A build or parser pass is not runtime proof.
- Preserve the previous working version and make the new version reproducible.
- Record every command, changed file, validation result, unresolved risk, and runtime status.
