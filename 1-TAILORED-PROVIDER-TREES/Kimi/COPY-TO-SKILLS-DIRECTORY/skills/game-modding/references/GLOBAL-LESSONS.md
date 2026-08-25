# Multi-game global lessons

1. Parent versions are immutable.
2. Every update starts with a full semantic-version snapshot.
3. Exact installed versions outrank examples and model memory.
4. Similar engines do not make game APIs interchangeable.
5. Build, loader, semantic, save, multiplayer, and runtime gates are separate.
6. One writer owns each coupled artifact.
7. Source and release must correspond.
8. Native AI memory is not a substitute for project records.


## Non-negotiable laws

- Never edit a deployed game directory, active mod-manager staging folder, save, profile, or framework installation as the project source.
- Resolve the exact game build, storefront, runtime, loader, framework versions, dependency graph, and packaging format before implementation.
- Never invent API names, hook signatures, offsets, asset identifiers, manifest keys, paths, serialization fields, or compiler syntax.
- Prefer official documentation, upstream source, exact installed files, generated SDKs, and known-good local examples.
- A build or parser pass is not runtime proof.
- Preserve the previous working version and make the new version reproducible.
- Record every command, changed file, validation result, unresolved risk, and runtime status.

