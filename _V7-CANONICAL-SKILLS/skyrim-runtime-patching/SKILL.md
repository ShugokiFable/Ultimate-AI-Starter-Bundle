---
name: skyrim-runtime-patching
description: Route Skyrim runtime patching to dedicated SPID, KID, SkyPatcher, BOS, FLM, CDF, and OAR authorities. This skill
  is an overview, not a second executable syntax manual.
compatibility: Windows 10/11; Skyrim Special Edition or Anniversary Edition; PowerShell and Python 3 when bundled scripts
  are used
metadata:
  version: 4.3.0
  updated: '2026-07-22'
  library: overseer-skyrim-agent-skills
  error_registry_revision: 4.3.0
  final_pack_version: 4.3.0
---

# Runtime patching router

Load `skyrim-frameworks-index`, then the dedicated syntax owner:

- `kid-authoring`
- `spid-authoring`
- `skyrim-skypatcher`
- `skyrim-base-object-swapper`
- `skyrim-distr-kid-validation` for generated output

FLM, CDF, OAR, and other frameworks remain version-sensitive. Verify their installed documentation and known-working examples before generating syntax.

Do not place copy-paste SPID, KID, SkyPatcher, or BOS grammar in this overview. This prevents the router and dedicated skills from drifting into competing dialects.


## Additional routing

- CDF JSON container/vendor authoring: `skyrim-container-distribution`
- framework or SKSE log interpretation: `skyrim-runtime-log-forensics`
- FLM exact syntax and collections: verify installed FLM documentation; do not
  import FLM `*` or `#` selectors into CDF, SPID, or SkyPatcher
- Community Shaders feature-load errors: `skyrim-runtime-log-forensics` plus
  `skyrim-assets-pbr`
