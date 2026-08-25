# Native / managed runtime plugins, loaders, hooks

Pin executable build, architecture, loader, SDK/generated headers, ABI/compiler
runtime, managed runtime, addresses/signatures, and dependencies.

Never invent offsets or signatures. Prefer stable IDs, supported APIs, generated
SDKs, and address libraries. Validate init, shutdown, reload, error paths,
thread ownership, and unsupported-build failure.


## Non-negotiable laws

- Never edit a deployed game directory, active mod-manager staging folder, save, profile, or framework installation as the project source.
- Resolve the exact game build, storefront, runtime, loader, framework versions, dependency graph, and packaging format before implementation.
- Never invent API names, hook signatures, offsets, asset identifiers, manifest keys, paths, serialization fields, or compiler syntax.
- Prefer official documentation, upstream source, exact installed files, generated SDKs, and known-good local examples.
- A build or parser pass is not runtime proof.
- Preserve the previous working version and make the new version reproducible.
- Record every command, changed file, validation result, unresolved risk, and runtime status.
