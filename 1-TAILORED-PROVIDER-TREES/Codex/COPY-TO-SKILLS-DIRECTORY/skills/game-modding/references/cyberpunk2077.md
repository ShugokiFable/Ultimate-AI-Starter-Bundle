# Cyberpunk 2077

Treat Cyberpunk as an ecosystem:

- redscript
- RED4ext
- ArchiveXL
- TweakXL
- Codeware
- Cyber Engine Tweaks
- REDmod/archive packaging
- Deceptious Quest Core when explicitly required
- WolvenKit and REDmodding docs

Pin the game patch and every core dependency. Validate compile order, caches,
archive roots, TweakDB identifiers, native plugin versions, and optional
framework presence.

Primary sources:

- https://github.com/CDPR-Modding-Documentation/Cyberpunk-Modding-Docs
- https://github.com/WopsS/RED4ext
- https://github.com/jac3km4/redscript
- https://github.com/psiberx/cp2077-archive-xl
- https://github.com/psiberx/cp2077-tweak-xl
- https://github.com/psiberx/cp2077-codeware
- https://wiki.redmodding.org/


## Mandatory version snapshot before the first edit

Every new mod starts at a semantic version such as `1.0.0`. Every update creates a new sibling folder by fully copying the current snapshot.

```text
<OwnerRoot>\<Mod Name>\
├── CHANGELOG.md
├── CURRENT.txt
├── WORKSPACE_OWNERSHIP.md
├── <Mod Name> 1.0.0\
│   └── VERSION.md
├── <Mod Name> 1.0.1\
│   └── VERSION.md
└── <Mod Name> 1.1.0\
    └── VERSION.md
```

Before changing a file:

1. Read `CURRENT.txt`, `CHANGELOG.md`, and `WORKSPACE_OWNERSHIP.md`.
2. Choose the semantic bump: patch, minor, or major.
3. Fully duplicate the current snapshot into the new version folder.
4. Update `CURRENT.txt`.
5. Create or update the new snapshot's `VERSION.md`.
6. Start the new changelog entry with the AI application, model, reasoning mode, task, parent version, and intended files.
7. Edit only the new version.
8. Never mark a partial or failed copy as current.

The previous version remains untouched for rollback and binary comparison.



## Non-negotiable laws

- Never edit a deployed game directory, active mod-manager staging folder, save, profile, or framework installation as the project source.
- Resolve the exact game build, storefront, runtime, loader, framework versions, dependency graph, and packaging format before implementation.
- Never invent API names, hook signatures, offsets, asset identifiers, manifest keys, paths, serialization fields, or compiler syntax.
- Prefer official documentation, upstream source, exact installed files, generated SDKs, and known-good local examples.
- A build or parser pass is not runtime proof.
- Preserve the previous working version and make the new version reproducible.
- Record every command, changed file, validation result, unresolved risk, and runtime status.
