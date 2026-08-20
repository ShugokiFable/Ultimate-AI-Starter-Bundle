# State

- Active version: 5.2.0
- Parent: v5.1.5 at 1e9f645
- Authoritative owner: `https://github.com/ShugokiFable/SkyrimForge`, branch
  `main`
- Preserved installed releases: `Skyrim-Forge-5.1.3`, `Skyrim-Forge-5.1.4`
- 5.1.5 MCP symptom: Claude Code 2026-07-28 listed Forge tools then rejected
  every `tools/call` (`missing required resultType`). List/read had the field;
  `tools/call` did not. Fixed by always naming complete tool results.
- Original MCP symptom: `forge_papyrus_compile` appeared in `tools/list` but
  had no dispatch case, so every call failed as an unknown tool
- Provider symptom: Kimi and Hermes were reported as skill-only even though
  both installed clients support MCP
- Provider-home symptom: Hermes skills defaulted to `%USERPROFILE%\.hermes`,
  but the installed application uses `%LOCALAPPDATA%\hermes`
- Shared runtime: `.venv\Scripts\python.exe`; no provider-specific environment
- Kimi approach: preserve all existing `mcpServers`, replace only
  `skyrim-forge`, then run `kimi doctor`
- Hermes approach: use `hermes mcp add` and require
  `hermes mcp test skyrim-forge`
- Targeted regressions: PASS, including byte-exact Kimi rollback on failure
- Full repository validation: PASS, 151 tests
- Native helpers: rebuilt reproducibly with pinned Go 1.23.2 for Windows x64
  and Linux x64
- 5.1.1 release audit: Hermes' `mcp add` cancelled at its tool-enable prompt
  while returning exit code zero; `mcp test` also returned zero for a missing
  server. Both conditions require explicit output validation.
- 5.1.2 real-client probe: PASS. Hermes persisted the Forge MCP entry and
  discovered all 52 tools after the explicit confirmation.
- 5.1.2 release workflow failure reproduced: publication attempted to create a
  release that already existed. The workflow now refreshes existing assets.
- 5.1.2 installed-runtime failure reproduced: `.venv\Scripts\python.exe`
  existed but its base Python was gone. The installer now executes and repairs
  an unusable environment instead of treating file presence as health.
- Target deployment folder: `Skyrim-Forge-5.1.3`; older folders remain rollback
  copies and must not be mistaken for the active user-level pointer.
- Runtime boundary: Skyrim gameplay and third-party GUI behavior remain outside
  this bridge-only release
