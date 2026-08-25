# Final release gate

```text
VERSION SNAPSHOT: PASS|FAIL
SOURCE INVENTORY: PASS|FAIL
BUILD: PASS|FAIL|N/A
FRAMEWORK VALIDATION: PASS|FAIL|N/A
ASSET VALIDATION: PASS|FAIL|N/A
DEPENDENCY GRAPH: PASS|FAIL
PACKAGE ROOTS: PASS|FAIL
UPGRADE/UNINSTALL: PASS|FAIL
SAVE/MULTIPLAYER: PASS|FAIL|UNTESTED
RUNTIME STATUS: user-confirmed-runtime | runtime-evidenced | tool-validated | assistant-claimed | contradicted
UNRESOLVED: none | exact risks
```

Never collapse `UNTESTED` into `PASS`.


## Non-negotiable laws

- Never edit a deployed game directory, active mod-manager staging folder, save, profile, or framework installation as the project source.
- Resolve the exact game build, storefront, runtime, loader, framework versions, dependency graph, and packaging format before implementation.
- Never invent API names, hook signatures, offsets, asset identifiers, manifest keys, paths, serialization fields, or compiler syntax.
- Prefer official documentation, upstream source, exact installed files, generated SDKs, and known-good local examples.
- A build or parser pass is not runtime proof.
- Preserve the previous working version and make the new version reproducible.
- Record every command, changed file, validation result, unresolved risk, and runtime status.
