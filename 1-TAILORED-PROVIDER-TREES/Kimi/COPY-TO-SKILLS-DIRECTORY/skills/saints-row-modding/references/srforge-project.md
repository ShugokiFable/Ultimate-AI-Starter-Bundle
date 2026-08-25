# srforge project state

Repo: `S:\Apps\Saints Row Tools\SaintsRowForge` · public: github.com/ShugokiFable/SaintsRowForge (MIT)
Installed copy: `%LOCALAPPDATA%\SaintsRowForge` — run from there; refresh with
`powershell -File Update.ps1` from repo root (robocopy /MIR).
Releases v0.1.0 + v0.2.0 with source-zip assets; CI runs the test suite on every push.

## Status: SHIPPED (2026-08-22)

- Real-install validated: doctor sees both Steam installs
  (`S:\SteamLibrary\steamapps\common\Saints Row {the Third,IV}`);
  SRTT indexed ~21k files, SRIV ~23k; E2E mod build verified on real weapons.xtbl.
- Formats: vpp.py (v0A read/write), vpp06.py (SRTT native reader+writer),
  asm.py (0x0B/0x0C byte-perfect vs vanilla asm_pc), xtbl.py (multi-tag dup
  elements handled, mixed-content text preserved), strings.py, crc.py,
  lua.py (static lint only).
- Mod manager: `srforge merge --game sriv ModA/ ModB/` — three-way XTBL
  merge vs pristine vanilla; additions unioned, distinct edits coexist,
  same-field conflicts logged in merge-report.json (later-listed mod wins),
  non-table collisions flagged. Verified on real SRIV data (4 edits applied,
  2 additions unioned, 1 true conflict caught).
- MCP server: mcp_server/server.py — 13 stdio JSON-RPC tools incl.
  sr_knowledge_search. NOT registered globally anywhere (token cost);
  launch on demand.
- Knowledge layer: knowledge/*.md + SOURCES.json;
  `python %LOCALAPPDATA%\SaintsRowForge\scripts\KnowledgeSearch.py "<topic>"`.
- Tests: python tests/run_tests.py → 18 checks green.
- Installers: Install.ps1 / Update.ps1 use robocopy /MIR (stale code dies).

## Known limits (honest)

No PEG/CPEG texture, mesh, audio, or workshop code — capability matrix
reports `unsupported`. TJ BuildPackfile can't target SRTT (use native writer).
Runtime behavior always needs an in-game test; receipts say verified_static.

## Session setup

```bash
export SRFORGE_GAME_SRTT="S:\SteamLibrary\steamapps\common\Saints Row the Third"
export SRFORGE_GAME_SRIV="S:\SteamLibrary\steamapps\common\Saints Row IV"
```

## Possible next (only when asked)

- Real multi-mod merge once user's Downloads mod packs return (TTDIS etc.).
- PEG/mesh adapters via SRIV SDK crunchers (provenance-gated) if textures wanted.
- Auto-release CI workflow on tags.
