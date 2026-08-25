---
name: saints-row-modding
description: Use for Saints Row 3/4 PC modding and the srforge workbench.
---

# Saints Row modding (SRTT + SRIV family)

Load `game-mod-memory` and `game-mod-versioned-workspace` before first write (router rules apply).

## Targets

| Game | Notes |
|---|---|
| Saints Row: The Third (original PC) | asm_pc version **0x0B** |
| Saints Row IV / Re-Elected | asm_pc version **0x0C**; Workshop SDK exists |
| Gat Out Of Hell | Shares SRIV formats (0x0C) |
| SRTT Remastered | DIFFERENT engine/build — NOT covered; do not pretend |

## Verified binary formats

Details + struct layouts: `references/formats.md`. Headlines:

- `.vpp_pc` / `.str2_pc` = Packfile **version 0x0A**: 0x28-byte header
  (descriptor `0x51890ACE`, header CRC over bytes 0x0C..0x28), 0x18-byte
  entries, 2-aligned name block, payload. Compressed+condensed archives are
  ONE zlib stream over all payloads in order.
- `.asm_pc` = Asset Assembler (`0xBEEFFEED`): 0x0B (SRTT) vs 0x0C (SRIV)
  differ by exactly ONE byte per container (compression_type). Repacking a
  str2 REQUIRES updating its ASM container: `PackfileBaseOffset`,
  `TotalCompressedPackfileReadSize`, per-primitive CPU/GPU sizes
  (gpu file = same name with `.cNNN` -> `.gNNN`). Missing/failed ASM update
  must FAIL the build, never ship silently.
- `.xtbl` = tab-indented XML; `<Name>` child TEXT is the record identity
  (attribute-based parsing breaks duplicates). Preserve comments/format.
- `le_strings` = header id `0xA84C7F73`; buckets hash&mask keyed by Volition
  CRC; UTF-16-LE NUL-terminated records.
- Volition CRC = standard CRC-32 table, init 0, no final xor, lowercase input.
- Load precedence: loose files > `patch_compressed.vpp_pc` >
  `patch_uncompressed.vpp_pc` > base vpps. Always resolve the winner before
  editing; editing the base copy when a patch exists = wasted/incorrect mod.

## Toolchain (provenance-verified)

- **ThomasJepp.SaintsRow rev133** (Minimaul) — extract/build packfiles,
  Stream2 (ASM<->XML), strings, soundbanks. License permits redistribution
  WITH credit + link back (keep license.txt). Pin:
  `https://minimaul.saintsrowmods.com/files/tools/releases/ThomasJepp.SaintsRow-rev133.7z`.
  Known regression: CustomizationItemClone fails on many items >rev121 —
  use rev121 for cloning.
  Full source zip (has tool Program.cs sources):
  `https://minimaul.saintsrowmods.com/files/tools/saintsrowmods-src.zip`.
- **Gibbed.Volition** — older SRTT-era alternative; community forks vary.
- **Zinyak's Cache of Wonders** — official Volition SRIV SDK:
  `https://github.com/volition-inc/Zinyaks-Cache-Of-Wonders`
  (peg_assemble/mesh/rig/texture crunchers, vPkg, FBX converter).
  NO license file -> acquisition-only, NEVER redistribute.
- SRIV Workshop mods support partial-table merging (ship only changed
  records) — prefer that shape for table mods.

### Hard-won gotchas

- `ThomasJepp.SaintsRow.BuildPackfile.exe` throws
  `NotImplementedException` for game `srtt` (supports sr2/sriv/srgooh only).
  For SRTT builds use a native writer (see srforge below) and validate by
  reopening with TJ ExtractPackfile (cross-tool validation).
- ALL ThomasJepp CLIs crash with `Console.BufferWidth` IOException when
  stdout is piped AND args fail parsing. Never rely on `--help`; call with
  real arguments only. Usage signatures live in the source zip's Program.cs.
- `Stream2.exe <file.asm_pc> update` refreshes ASM from sibling str2 files;
  actions: clean/toasm/toxml/update.
- Legacy FBX converter needs Python 2.6 + wxPython + FBX SDK 2014 — isolate
  or defer; classic MANUAL ACTION REQUIRED dependency.

## srforge workbench (this machine)

**Run from the installed copy**: `%LOCALAPPDATA%\SaintsRowForge` — source
repo `S:\Apps\Saints Row Tools\SaintsRowForge` (GitHub: ShugokiFable/SaintsRowForge,
releases v0.1/v0.2, CI-protected). After changing repo code refresh the
install: `powershell -File Update.ps1` from repo root (robocopy /MIR).

Session setup:
```bash
export SRFORGE_GAME_SRTT="S:\SteamLibrary\steamapps\common\Saints Row the Third"
export SRFORGE_GAME_SRIV="S:\SteamLibrary\steamapps\common\Saints Row IV"
```

- Native readers/writers: `src/srforge/formats/{vpp,vpp06,asm,xtbl,strings,crc,lua}.py`
  (SRTT=vpp06 native writer too; SRIV=vpp0A; round-trip tested).
- Core: workspace/transaction/receipts/toolbroker/discovery/index under
  `src/srforge/core/` (+ `merger.py`). Game dirs are read-only sources;
  mods build in workspaces; receipts record per-op old→new values.
- CLI (`src/srforge_cli.py`, `--json` everywhere): doctor, asset find/origin/
  extract, xtbl query/patch/diff, mod new/patch/diff/build, deps import,
  **merge** — cross-mod table merge:
  `srforge merge --game sriv ModA/ ModB/` → three-way union vs vanilla,
  conflicts logged in merge-report.json (later-listed mod wins), non-table
  collisions flagged.
- MCP server: `mcp_server/server.py` — 13 stdio JSON-RPC tools incl.
  `sr_knowledge_search`; NOT registered globally (token cost) — launch on demand.
- Knowledge layer: `python %LOCALAPPDATA%\SaintsRowForge\scripts\KnowledgeSearch.py "<topic>"`
  searches `knowledge/*.md` + SOURCES.json upstream map.
- Tests: `python tests/run_tests.py` (18 checks, synthetic fixtures).
- Inbox/vault: downloads → hashed → `tools_vault/` + manifest.json (sha256 pinned).

Project state and resume pointers: `references/srforge-project.md`.

## Workflow skeleton

1. `srforge doctor` — game found? tools ready? capability matrix truthful?
2. Index vanilla (precedence-aware) BEFORE any extraction.
3. Workspace per mod; extract winning copies only.
4. Structured edits (XTBL ops / Lua lint), never blind regex on packed data.
5. Rebuild str2 -> ASM update -> reopen-and-verify package (zero exit code
   is NOT success).
6. Semantic vanilla diff; unexpected collateral changes = FAIL the build.
7. Receipt with evidence level; runtime behavior always needs in-game test.
