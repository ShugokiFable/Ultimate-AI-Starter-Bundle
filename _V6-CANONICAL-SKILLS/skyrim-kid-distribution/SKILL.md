---
name: skyrim-kid-distribution
description: Author and validate current Keyword Item Distributor configuration with one official type-label grammar.
compatibility: Windows 10/11; Skyrim Special Edition or Anniversary Edition; exact installed framework version must be verified
metadata:
  version: 4.3.0
  updated: '2026-07-22'
  library: overseer-skyrim-agent-skills
  error_registry_revision: 4.3.0
  final_pack_version: 4.3.0
---

# Keyword Item Distributor

This skill owns copy-paste KID grammar for pinned KID `4.0.6`, source commit
`895df224d4964dc9723460038eb533bfff06d860`.

## Ordinary Keyword rows

```ini
Keyword = KeywordFormOrEditorID|Record Type|Filters|Traits|Chance
```

There are five possible value positions. An ordinary usable `Keyword` row needs
both the keyword target and a human-readable type in field 2. Trailing optional
positions may be omitted.

Accepted type labels are exactly:

```text
Armor Weapon Ammo Magic Effect Potion Scroll Location Ingredient Book Misc Item
Key Soul Gem Spell Activator Flora Furniture Race Talking Activator Enchantment
```

The parser performs an exact lookup against those labels. Record signatures such
as `WEAP`, `ARMO`, `MGEF`, and `SPEL` resolve to `kNone` and the row is skipped.
A blank type position in an ordinary `Keyword` row likewise leaves the type at
`kNone`; it is not a supported shorthand.

## KID ExclusiveGroup

KID also has a separate special key:

```ini
ExclusiveGroup = GroupName|KeywordFormA,KeywordFormB,-ExcludedKeyword
```

This row does not have an ordinary type position. Do not confuse a valid
`ExclusiveGroup` row with an ordinary `Keyword` row that has a blank type.

## Comments

Offline validation must strip runtime-accepted trailing semicolon comments before
splitting fields.

## Validation

Verify the exact installed KID version, run the framework linter, and inspect
`po3_KeywordItemDistributor.log`. Test one intended positive and one intended
negative form. Do not copy SPID trait grammar into KID.
