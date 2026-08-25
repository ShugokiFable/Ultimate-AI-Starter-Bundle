# The game or loader is unfamiliar

Detect executable architecture, engine, managed/native runtime, asset containers,
existing loaders, mod directories, official tooling, storefront, anti-cheat,
multiplayer constraints, and update cadence.

Choose the smallest supported path: official SDK, data/config mod, script
framework, managed plugin, native plugin, cooked asset package, or no safe path.
When evidence is missing, stop at research/design instead of shipping guessed files.


## Non-negotiable laws

- Never edit a deployed game directory, active mod-manager staging folder, save, profile, or framework installation as the project source.
- Resolve the exact game build, storefront, runtime, loader, framework versions, dependency graph, and packaging format before implementation.
- Never invent API names, hook signatures, offsets, asset identifiers, manifest keys, paths, serialization fields, or compiler syntax.
- Prefer official documentation, upstream source, exact installed files, generated SDKs, and known-good local examples.
- A build or parser pass is not runtime proof.
- Preserve the previous working version and make the new version reproducible.
- Record every command, changed file, validation result, unresolved risk, and runtime status.
