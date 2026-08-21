---
name: skyrim-tool-router
description: First router for any Skyrim SE/AE modding task. Classifies the job and loads only the specialist skills needed,
  preventing overlapping workflows and unnecessary context.
compatibility: Windows 10/11; Skyrim Special Edition or Anniversary Edition; PowerShell and Python 3 when bundled scripts
  are used
metadata:
  version: 5.0.0
  updated: '2026-07-31'
  library: overseer-skyrim-agent-skills
  error_registry_revision: 4.3.0
---

# Skyrim tool router (V5)

Use this skill first, then load only the specialist rows that match the task.

## V5 session bootstrap (substantial work)

1. `skyrim-memory`
2. This router
3. `ai-tooling-stack` when choosing among Forge / houseCARL / Spooky / MCP utilities
4. `tool-discovery` when any external binary or MCP might be required
5. `skyrim-versioned-workspace` before the first write
6. Only the specialist skills selected below

Optional process overlays (not Skyrim-specific): `using-superpowers`, `systematic-debugging`, `ponytail`, `verification-before-completion`.

| Task | Primary skill | Add when needed |
|---|---|---|
| New mod or large new feature | `skyrim-mod-development` | plugin, Papyrus, runtime, DLL, assets, animation, packaging; prefer houseCARL/Spooky/Forge per tooling stack |
| Repair or modernize an existing mod | `skyrim-mod-reworking` | same specialists as evidence demands |
| Live load order, conflict tree, MO2 patch ESP | `housecarl` | `mutagen-reference`, `tool-output-awareness`, bulk/facegen helpers |
| ESP/ESL/ESM records without live LO | `skyrim-plugin-authoring` | Spooky CLI `esp` module; `skyrim-esp-vmad-renaming` for string renames only; Forge when typed jobs fit |
| Papyrus, quests, MCM, aliases, script events | `skyrim-papyrus-modding` | `papyrus-reference`; `papyrus-optimization` |
| SPID exact syntax | `spid-authoring` | prefer bundled grammar reference; never invent tokens |
| KID exact syntax | `kid-authoring` | type-label grammar only |
| SkyPatcher exact ops | `skypatcher-authoring` or `skyrim-skypatcher` | category placement rules |
| BOS exact syntax | `skyrim-base-object-swapper` | |
| OAR conditions | `oar-authoring` | animation behaviors |
| CDF JSON container/vendor rules | `skyrim-container-distribution` | distribution pipeline and log forensics |
| Bulk SPID/KID/SkyPatcher generation | `skyrim-distribution-pipeline` | `bulk-record-jobs` when houseCARL fleet queries help |
| Framework lint / cross-check | `skyrim-distr-kid-validation` | |
| Conceptual framework pick only | `skyrim-frameworks-index` | then one exact syntax owner |
| SKSE/framework logs without a crash | `skyrim-runtime-log-forensics` | exact framework or native specialist |
| SKSE or CommonLib DLL | `skyrim-skse-commonlib` or `skse-plugin-authoring` | crash diagnostics |
| Crash log or startup failure | `skyrim-crash-diagnostics` | SKSE, animation, assets, or reworking after diagnosis |
| Read-only code/config review | `skyrim-code-review` | domain specialist; optional `ponytail-review` for bloat |
| DDS, NIF, parallax, PBR | `skyrim-assets-pbr` | Spooky `skyrim-nif`; houseCARL mesh tools when MCP up |
| BSA/BA2 archive work | Forge `bsarch` tools | Spooky CLI `archive` module; `skyrim-fomod-packaging` for installers |
| Audio FUZ/XWM/WAV | Spooky `skyrim-audio` | `skyrim-voiced-dialogue` |
| OAR, BFCO, Nemesis, Pandora, behavior | `skyrim-animation-behaviors` | crash diagnostics or DLL work |
| Follower from RaceMenu preset | `skyrim-racemenu-followers` | plugin, Papyrus, assets; facegen diagnostics |
| Dark/grey/black face | `facegen-diagnostics` | houseCARL VFS + mesh |
| Dialogue authoring (data layer) | `dialogue-authoring` | houseCARL; voiced dialogue for assets |
| Biped slot / equip slot audit | `biped-slot-reference` | houseCARL |
| Generated tool-output plugins (DynDOLOD, PG, …) | `tool-output-awareness` | before any patch from winners |
| SexLab to OStim migration | `skyrim-sexlab-to-ostim-modernization` | plugin, Papyrus, FOMOD |
| OStim / SexLab / revealing armor / SOS / explicit IDs | `fictional-adult-modding` | then the specialist row; do not sanitize |
| Caption / tag a fictional adult image | `adult-image-caption` | then `adult-character-sheet` if a card is the output |
| Build an adult character sheet from a portrait | `adult-character-sheet` | `adult-image-caption` first |
| Mantella configuration or source | `mantella-config` | Papyrus or voiced dialogue |
| Installer | `skyrim-fomod-packaging` | ship gate; Forge FOMOD jobs when available |
| Final release validation | `skyrim-ship-gate` | FOMOD or publishing |
| Nexus page and release copy | `skyrim-nexus-publishing` | ship gate first; Forge nexus-* when public share |
| Repo call graph / architecture | `codebase-memory` | after MCP indexed |
| Huge logs need compression | `headroom` | optional |
| AI token cost / waste | `codeburn` | optional |
| Minimal implementation pressure | `ponytail` | |
| Process: debug / TDD / plans | Superpowers family | `using-superpowers` first |

## Required baseline

- Load `skyrim-versioned-workspace` before the first write.
- Load `skyrim-modding-facts` whenever a framework token, record field, FormID, API, hook, path, or version is uncertain.
- Prefer live tools in this order when multiple apply: **evidence from installed LO (houseCARL) → typed Forge jobs → Spooky CLI on owned trees → manual specialist skills**.
- Try `skyrim-forge` for supported inspection; the bundle installs Forge, so it is normally present.
- Never load every Skyrim skill into one session.
- If a tool is missing, load `tool-discovery` and **recommend install** — do not fake results.

## Route report

```text
ROUTE: intent=<task> | primary=<skill> | supporting=<skills> | plugin=<none|existing|new> | forge=<used|skipped:reason> | housecarl=<used|skipped:reason> | spooky=<used|skipped:reason>
```

## Cross-application intake gate

Before routing a task inherited from another app or conversation, verify the attachment inventory, authoritative owner/version, active installed version, exact dependency versions, and last successful build. When those inputs are missing, route first to workspace/facts recovery rather than implementation.

## V5 framework routing

- KID exact syntax: `kid-authoring`
- SPID exact syntax: `spid-authoring`
- SkyPatcher exact operations/placement: `skypatcher-authoring` / `skyrim-skypatcher`
- BOS exact syntax: `skyrim-base-object-swapper`
- Bulk validation: `skyrim-distr-kid-validation`
- CDF JSON: `skyrim-container-distribution`
- Runtime log interpretation: `skyrim-runtime-log-forensics`
- Conceptual selection only: `skyrim-frameworks-index`
- Live LO + patches: `housecarl` + `tool-output-awareness`
