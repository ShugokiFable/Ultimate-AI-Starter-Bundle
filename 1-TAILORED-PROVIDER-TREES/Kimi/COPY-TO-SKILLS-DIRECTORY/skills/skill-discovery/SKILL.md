---
name: skill-discovery
description: Find current agent skills when the user asks whether a skill, plugin, workflow, auto-setup, fetcher, or reusable capability already exists. Search the public skills catalog without telemetry, then review provenance, license, overlap, and scripts before recommending or adopting anything. Never install directly into bundle-managed provider skill directories.
metadata:
  version: 1.0.0
  upstream_cli: https://github.com/vercel-labs/skills/tree/v1.5.23
---

# Skill discovery without skill-tree drift

Use the included wrapper for the first search. It pins `skills@1.5.23`, disables its telemetry and
audit calls, and only exposes the non-mutating `find` command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <skill-base-dir>\scripts\find-skills.ps1 "frontend accessibility"
```

An optional `-Owner anthropics` narrows results. Search once with all required criteria together;
broaden only if it returns nothing.

Discovery is not approval. For a promising result:

1. Open the source repository and resolve an immutable release, tag, commit, or package version.
2. Verify the license, exact bytes/hash when an asset exists, runtime requirements, install scripts,
   telemetry/network behavior, writes, hooks, credentials, and overlap with installed capabilities.
3. Run it in an isolated home or fixture before touching provider state.
4. For this bundle, promote accepted files through `_CANONICAL-SKILLS` and provider fanout. Never run
   `skills add`, `skills update`, `skills remove`, or `skills experimental_sync` against live homes;
   they create a second writer for the same skill trees.
5. If the candidate is useful but redundant, risky, unlicensed, mutable-only, or untested, record the
   decision instead of installing it.

The catalog's install counts are discovery hints, not security or quality evidence.
