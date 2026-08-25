# Resolve a version-sensitive fact from installed truth

Evidence order:

1. Active project environment and lock files.
2. Exact installed binaries, source, generated SDK, logs, or metadata.
3. Official framework docs and upstream source for that version.
4. Official game modding docs.
5. Known-good local mods, read-only.
6. Community examples only when primary evidence is unavailable.

Record evidence and version scope in `VALIDATION.md`.


## Non-negotiable laws

- Never edit a deployed game directory, active mod-manager staging folder, save, profile, or framework installation as the project source.
- Resolve the exact game build, storefront, runtime, loader, framework versions, dependency graph, and packaging format before implementation.
- Never invent API names, hook signatures, offsets, asset identifiers, manifest keys, paths, serialization fields, or compiler syntax.
- Prefer official documentation, upstream source, exact installed files, generated SDKs, and known-good local examples.
- A build or parser pass is not runtime proof.
- Preserve the previous working version and make the new version reproducible.
- Record every command, changed file, validation result, unresolved risk, and runtime status.
