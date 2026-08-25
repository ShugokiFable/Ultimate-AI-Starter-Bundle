# Cross-game error registry and lessons

The registry is embedded in `references/`.

Read `GLOBAL-LESSONS.md`, search `ERROR-REGISTRY.json`, and load only relevant
entries.


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


## Evidence ladder

1. `user-confirmed-runtime`
2. `runtime-evidenced`
3. `tool-validated`
4. `assistant-claimed`
5. `contradicted`

Write candidate lessons to the active project's `MEMORY/CANDIDATES.md`.
