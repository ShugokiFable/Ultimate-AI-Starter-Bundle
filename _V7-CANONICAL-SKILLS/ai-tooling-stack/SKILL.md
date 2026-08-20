---
name: ai-tooling-stack
description: V5 map of Skyrim + AI coding tools (Forge, houseCARL, Spooky, codebase-memory, Headroom, Superpowers, Ponytail, CodeBurn). Load to choose tools, wire MCP, or recommend installs when missing.
metadata:
  version: 5.0.0
  final_pack_version: 5.0.0
---

# AI tooling stack (V5)

This skill is the **cross-tool index**. Exact syntax lives in specialist skills. Paths are discovered via `tool-discovery` — never assumed.

## Always-on baseline (Skyrim work)

1. `skyrim-memory`
2. `skyrim-tool-router` (updated for V5)
3. `tool-discovery` when any external binary/MCP might be needed
4. `skyrim-versioned-workspace` before first write

## Tool roles (do not collapse these)

| Tool | Role | Skill(s) | If missing |
|---|---|---|---|
| **Skyrim Forge** | Typed automation broker: doctor, capabilities, Papyrus compile pipeline, FOMOD, release/nexus gates, tool-resolve | `skyrim-forge`, `skyrim-forge-bridge` | Recommend Forge install; continue with narrower tools |
| **houseCARL** | Live MO2 load-order MCP: true winners, conflict trees, reviewable patch ESPs, Nexus keyless lookup, VFS assets | `housecarl` + mutagen/spid/kid/skypatcher authoring helpers | Recommend houseCARL-Setup + .NET 9 pair + MCP register |
| **Spooky's AutoMod Toolkit** | CLI for ESP/Papyrus/MCM/NIF/BSA/audio/SKSE project workflows with `--json` | `spookys-automod-toolkit` + `skyrim-plugin-authoring` | Recommend toolkit release + .NET 8 SDK |
| **codebase-memory-mcp** | Knowledge-graph code navigation (call graphs, impact) | `codebase-memory` | Recommend DeusData install + MCP wire |
| **Headroom** | Context compression / retrieve / session stats MCP | `headroom` | Optional; recommend pip install when context thrash is real |
| **Superpowers** | Process discipline (debug, TDD, plans, verification) | `using-superpowers` + family | Bundled skill text works; plugin optional |
| **Ponytail** | Minimal-diff / anti-over-engineering mode | `ponytail` + family | Bundled skill text works; plugin optional |
| **CodeBurn** | Local AI token/cost analytics | `codeburn` | Optional `npx codeburn` |

## Decision cheat-sheet

| User need | Prefer |
|---|---|
| "What wins this FormID in MY list?" | houseCARL |
| "Typed release / FOMOD / nexus policy / doctor" | Forge |
| "Create ESL + quest + compile papyrus from CLI" | Spooky (or Forge if capability ready) |
| "SPID/KID/SkyPatcher line syntax" | `*-authoring` / dedicated V4 syntax skills — never invent |
| "Who calls this function in the repo?" | codebase-memory |
| "Context is huge / compress this log" | headroom |
| "Stop over-engineering" | ponytail |
| "How much did this AI session cost?" | codeburn |
| "Bug / plan / verify before done" | superpowers process skills |

## Provider adaptation

- **Claude Code:** houseCARL ships as a Claude plugin; Superpowers/Ponytail/Headroom often install as plugins. Skills in this pack still work as plain `SKILL.md`.
- **Grok Build:** register MCP servers in `%USERPROFILE%\.grok\config.toml`. Use pack script `TOOLS\Fix-Grok-Codebase-Memory-Direct.ps1` only after editing the exe path. Skills go in `%USERPROFILE%\.grok\skills`.
- **Codex:** skills in `%CODEX_HOME%\skills`; MCP per Codex docs. houseCARL may ship a `codex\` skill stub — still require MCP binary.
- **Kimi / Hermes / others:** copy provider-native skills; wire MCP if the harness supports it; otherwise say MCP unavailable and use CLI fallbacks.

## Hard rules

- Missing tool → recommend install with verify command; continue with fallback when safe.
- Never claim houseCARL/Forge results without the tool actually responding.
- Never launch xEdit/CK GUI.
- Game Data / MO2 staging / saves remain read-only except via explicit owned project outputs.
- houseCARL patches are new MO2 mods to review — originals untouched (default lane).
- Tool outputs (DynDOLOD, ParallaxGen, Reqtificator, …) must not be frozen into hand patches — see `tool-output-awareness`.

## Session tool report (optional once per session)

```text
TOOLS: forge=<found|missing> housecarl=<found|missing|mcp-down> spooky=<found|missing> codebase-memory=<found|missing|mcp-down> headroom=<found|missing> codeburn=<found|missing> mo2=<set|unset>
```

## houseCARL first-time / Vortex

Never leave houseCARL "almost installed." Run pack automation:

```text
TOOLS\Setup-HouseCarl.ps1
```

- MO2 users → instance auto-detected or `-Mo2Instance`
- Vortex users → shim auto-built at `%LOCALAPPDATA%\houseCARL-Shim`
- Then full AI restart

---

## V5 AIO installer (pack)

New users and missing-tool recovery:

```powershell
# Pack root
.\INSTALL-V7-AIO.ps1
.\INSTALL-V7-AIO.ps1 -Mode OnlineLatest
.\TOOLS\Ensure-Tools.ps1
.\TOOLS\Update-From-GitHub.ps1
```

Offline snapshots live in `BUNDLED-TOOLS\offline\`. Component registry: `BUNDLED-TOOLS\CATALOG.json`.
After MCP changes the user must **fully restart** the AI application.
