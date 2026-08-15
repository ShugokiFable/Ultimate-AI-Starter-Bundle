
# Runtime log casebook

## SPID rejected staff distributions

Observed shape:

```text
Failed to parse entry [Weapon = ...]: Unsupported form type Weapon
```

Verdict: the key is invalid for current SPID. A WEAP record is still distributed
with `Item =` or `Form =`. Validate the target forms before a deterministic
mass replacement.

## SPID numeric conversion failure

Observed shape:

```text
Perk = Form|ActorTypeNPC||65/|-C/-D||18!
```

Field map:

1. distributable form
2. StringFilters
3. FormFilters
4. LevelFilters = `65/`
5. TraitFilters = `-C/-D`
6. index/count
7. Chance = `18!`

`65/` is malformed because the maximum endpoint is empty. `-C/-D` and `18!`
are valid. Restore the intended exact level or complete range.

## Eight-field faction row

An eight-field SPID row is invalid. Fixing only the extra pipe can still leave
comma-separated traits or contradictory intent. A filename such as `MaleOnly`
combined with `F` is an intent conflict, not merely punctuation. Confirm whether
the target is male or female before rewriting the row.

## Hook target outside `.text`

Treat this as a safe feature abort. Possible classes include wrong runtime,
wrong relocation, stale vtable index, already-modified slot, or a pointer owned
by another module. Determine the actual owner before assigning blame.

## Community Shaders feature disabled

Inspect:

```text
Data\Shaders\Features\<Feature>.ini
```

Check deployed winner, feature version, core/optional status, and the preset's
requirements. An override log line does not supersede an earlier disabled state.

## Missing HKX

Classify paths:

- custom actor/creature path: locate the owning mod and archive;
- vanilla character path: inspect behavior generator inputs/outputs and asset
  ownership;
- paired animation: verify both participants and behavior registration.

## BOS conflict

Alphabetical priority answers which config wins, not which config is correct.
Inspect reference identity, worldspace/cell, qualifiers, and expected coordinates.

## Mod-manager marker parsed as config

Remove the marker from the source/staging package and redeploy. Do not blindly
delete files from the live game directory.

## Stale dependency references

Unresolved optional integrations are dead rows, not automatically fatal. A
required feature whose every target is unresolved is broken. Report both scopes.
