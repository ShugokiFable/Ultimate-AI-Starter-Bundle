---
name: skyrim-frameworks-index
description: Conceptual framework selector for Skyrim runtime patching. Routes to one authoritative syntax owner per framework
  and prevents conflicting dialects.
compatibility: Windows 10/11; Skyrim Special Edition or Anniversary Edition; exact installed framework version must be verified
metadata:
  version: 4.3.0
  updated: '2026-07-22'
  library: overseer-skyrim-agent-skills
  error_registry_revision: 4.3.0
  final_pack_version: 4.3.0
---

# Skyrim frameworks index

This is a conceptual router. It does not own executable syntax.

## Authority order

1. Exact installed framework version, bundled documentation, parser DLL/source, and bundled working examples.
2. Authoritative upstream source or documentation matching that installed version.
3. The source-locked dedicated framework skill in this library.
4. Known-working local configuration files, read-only and version-identified.
5. This index.
6. Historical prompt libraries, integration plans, old guides, and remembered syntax.

A dedicated skill never outranks the actual parser. When evidence proves a skill wrong, fix the skill and its validator rather than rewriting working mods to match stale prose.

## Routing

| Goal | Primary mechanism | Syntax owner |
|---|---|---|
| Add keywords to records | KID | `kid-authoring` |
| Distribute forms to NPCs | SPID | `spid-authoring` |
| Patch supported record fields at runtime | SkyPatcher | `skyrim-skypatcher` |
| Swap base objects/references or supported properties | BOS | `skyrim-base-object-swapper` |
| Generate/audit large distributions | deterministic generator | `skyrim-distribution-pipeline` + `skyrim-distr-kid-validation` |
| CDF JSON container/vendor rules | Container Distribution Framework | `skyrim-container-distribution` |
| Interpret framework/SKSE logs | source-aware log forensics | `skyrim-runtime-log-forensics` |
| New settings menu | MCM Helper | `skyrim-papyrus-modding` |
| Legacy SkyUI MCM maintenance | SKI_ConfigBase | `skyrim-papyrus-modding` |
| Simple JSON/form persistence | PapyrusUtil | `skyrim-papyrus-modding/references/papyrusutil.md` |
| Nested/dynamic structured data | JContainers | `skyrim-papyrus-modding/references/jcontainers.md` |
| Unsupported operation | ESPFE, Papyrus, patcher, or DLL | `skyrim-plugin-authoring`, `skyrim-papyrus-modding`, or `skyrim-skse-commonlib` |

## Locked current decisions

- **SPID 7.3.x:** supported keys do not include `Weapon`; inventory objects use `Item` or generic `Form`. Level range endpoints must both exist. TraitFilters split on `/`, `D/-D` are valid, and Chance may end in `!`.
- **KID 4.0.6:** use human-readable type labels. Trailing optional fields may be omitted.
- **BOS 3.4.1:** use pipe-delimited entries under current sections including `[Forms]`, `[References]`, `[Transforms]`, and `[Properties]`.
- **SkyPatcher 6.4.2:** category placement is mandatory and operation names are category/version-specific.
- **MCM:** MCM Helper is the normal new-menu route; SKI_ConfigBase remains a legacy maintenance route.

The historical integration plan's comma-based SPID-trait decision is superseded by the current parser source. Historical documents are evidence leads, not executable syntax authorities.


## Cross-framework punctuation warning

A token valid in one framework is not portable:

- FLM `*FormList` expands a FormList;
- CDF `add: ["*Claw"]` is not a wildcard query in the pinned parser;
- SPID `/` may mean a level range in LevelFilters or trait combination in
  TraitFilters;
- BOS commas inside transform functions are not SPID filter separators.

Route first, then parse by the selected framework and exact field.
