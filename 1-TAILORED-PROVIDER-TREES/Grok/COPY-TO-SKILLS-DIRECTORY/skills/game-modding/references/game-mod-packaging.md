# Roots, manifests, dependencies, optional branches

Validate the final archive for package roots, manifests, loader layout, secrets,
caches, source correspondence, dependencies, optional components, upgrade,
uninstall, checksums, and version labels.


## Non-negotiable laws

- Never edit a deployed game directory, active mod-manager staging folder, save, profile, or framework installation as the project source.
- Resolve the exact game build, storefront, runtime, loader, framework versions, dependency graph, and packaging format before implementation.
- Never invent API names, hook signatures, offsets, asset identifiers, manifest keys, paths, serialization fields, or compiler syntax.
- Prefer official documentation, upstream source, exact installed files, generated SDKs, and known-good local examples.
- A build or parser pass is not runtime proof.
- Preserve the previous working version and make the new version reproducible.
- Record every command, changed file, validation result, unresolved risk, and runtime status.
