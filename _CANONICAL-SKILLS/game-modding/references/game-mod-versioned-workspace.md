# Versioned workspace and rollback

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


## Completion report

```text
VERSION GATE
project=...
owner=...
parent=...
active=...
bump=patch|minor|major
copied_files=...
changelog_started=YES|NO
version_record=YES|NO
previous_snapshot_untouched=YES|NO
RESULT=PASS|FAIL
```

Use `scripts/new_version.py` to create the snapshot and
`scripts/validate_project.py` to verify the structure.
