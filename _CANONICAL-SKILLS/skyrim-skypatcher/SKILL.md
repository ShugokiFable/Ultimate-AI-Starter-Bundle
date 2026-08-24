---
name: skyrim-skypatcher
description: Route and validate SkyPatcher category placement and installed-version operations without inventing keys.
compatibility: Windows 10/11; Skyrim Special Edition or Anniversary Edition; exact installed framework version must be verified
metadata:
  version: 4.3.0
  updated: '2026-07-22'
  library: overseer-skyrim-agent-skills
  error_registry_revision: 4.3.0
---

# SkyPatcher

This skill owns SkyPatcher placement and safety policy. Executable field names remain version-sensitive and must be verified against the installed SkyPatcher documentation or source.

## Directory contract

SkyPatcher configurations belong beneath a category directory:

```text
Data\SKSE\Plugins\SkyPatcher\<category>\<mod-or-feature>\<config>.ini
```

Examples of categories include `npc`, `weapon`, `armor`, `race`, `spell`, `leveledList`, and other directories supported by the installed version. A configuration left directly in the SkyPatcher root is treated as a likely silent ignore.

## Line contract

SkyPatcher files commonly use colon-separated `key=value` operations. Do not invent a key from a similar patcher or an old guide.

## NPC safety

- Do not invent `itemsRemove`. Current versions/examples may expose operations such as `objectsToRemove`, but exact behavior must be confirmed against the installed NPC patcher before use.
- Do not force confidence, aggression, assistance, morality, or combat behavior merely to “normalize” NPCs. Such edits require explicit user intent and compatibility analysis.
- Appearance copies must account for facegen, skin, head parts, templates, and load-order behavior.
- Inventory, outfit, leveled-spell, and package operations are distinct. Select the operation that matches the installed version.

## Validation

- Category directory exists and matches the patcher type.
- Every key appears in current installed documentation/source or a known-working local file.
- Every form resolves to the intended plugin and record.
- No contradictory add/remove operation exists on the same target without an ordering plan.
- One known-positive and one known-negative target are checked.
- Runtime logs are inspected after user testing.
