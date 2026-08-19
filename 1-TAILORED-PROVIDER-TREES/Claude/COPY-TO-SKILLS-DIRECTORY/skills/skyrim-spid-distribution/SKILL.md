---
name: skyrim-spid-distribution
description: Author and validate current SPID 7.3 distributions, filtering, traits, and NPC-target semantics.
compatibility: Windows 10/11; Skyrim Special Edition or Anniversary Edition; exact installed framework version must be verified
metadata:
  version: 4.3.0
  updated: '2026-07-22'
  library: overseer-skyrim-agent-skills
  error_registry_revision: 4.3.0
  final_pack_version: 4.3.0
---

# SPID distribution

This skill is the sole active owner of copy-paste SPID `_DISTR.ini` grammar.

## Source lock

Pinned to `powerof3/Spell-Perk-Item-Distributor` commit
`e5ef32b99ecb277778644f4deae0ac04851ca614`. The exact installed parser and its
runtime log outrank this skill.

## Key families

### Standard and on-death distribution

Base types:

```text
Form Spell Perk Item Shout LevSpell Package Outfit Keyword Faction SleepOutfit Skin
```

Valid examples include:

```ini
Item = 0x800~Items.esp|...
FinalOutfit = 0x800~Outfits.esp|...
DeathItem = 0x801~Items.esp|...
FinalDeathOutfit = 0x801~Outfits.esp|...
```

`Death<Type>` uses the normal seven-field distribution layout but applies on
death. The optional `Final` modifier is meaningful only for Outfit.

There is no `Weapon` distribution key. Weapons, staves, armor, and other
inventory objects use `Item =` or deliberate generic `Form =` inference.

### Exclusive groups

```ini
ExclusiveGroup = GroupName|FormFilterA,FormFilterB,-ExcludedForm
```

This is a real SPID key with its own two-field layout. Do not parse it as a
normal distribution row.

### Linked distribution

Current linked keys follow:

```text
[Global]Linked[Final][Death]<Type>
```

Example:

```ini
GlobalLinkedFinalDeathOutfit = OutfitForm|ParentFormFilters|IndexOrCount|Chance
```

Linked rows have four possible value fields, not seven. A parent Form Filter is
required.

## Normal seven-field layout

```ini
Type = DistributableForm|StringFilters|FormFilters|LevelFilters|TraitFilters|IndexOrCount|Chance
```

Trailing positions may be omitted. Interior omissions still need pipes.

### LevelFilters

- exact actor level: `65`
- actor-level range: `25/100`
- skill filter: `14(10)` or `14(10/50)`
- weighted skill filter: `w14(10/50)`

`65/` and `/100` are malformed.

### TraitFilters

The parser splits TraitFilters on `/`.

```text
M -F F -M U -U S -S C -C L -L T -T D -D
```

`-C/-D` is valid. Comma-combined traits are not equivalent.

### Chance

Numeric, optionally followed by one deterministic `!`. `18!` is valid.

## Comments

SPID uses an INI parser. Trailing semicolon comments seen in accepted runtime
rows must be removed before field validation by offline tools:

```ini
DeathItem = 0x800~Loot.esp|ActorTypeNPC||||1|100 ; explanation
```

Do not rewrite an accepted shipping row merely because an offline linter failed
to strip its comment.

## Validation

Run both:

```text
python skyrim-distr-kid-validation\scripts\lint_framework_configs.py <configs>
python skyrim-distr-kid-validation\scripts\verify_framework_truth.py
```

Then inspect the actual SPID log for discovered, accepted, rejected, and
unresolved rows. A published mod is not automatically correct, but a linter that
contradicts the pinned parser or runtime acceptance must be quarantined before
any config is edited.
