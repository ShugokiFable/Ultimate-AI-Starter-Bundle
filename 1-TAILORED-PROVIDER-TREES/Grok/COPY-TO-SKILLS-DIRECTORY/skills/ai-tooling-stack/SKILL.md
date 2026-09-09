---
name: ai-tooling-stack
description: Map of Skyrim + AI coding tools (Forge, houseCARL, Spooky, codebase-memory, Headroom, Superpowers, Ponytail, CodeBurn). Load to choose tools, wire MCP, or recommend installs when missing.
metadata:
  version: 5.0.0
---

# AI tooling stack

This skill is the **cross-tool index**. Exact syntax lives in specialist skills. Paths are discovered via `tool-discovery` — never assumed.

## Always-on baseline (Skyrim work)

1. `skyrim-memory`
2. `skyrim-tool-router`
3. `tool-discovery` when any external binary/MCP might be needed
4. `skyrim-versioned-workspace` before first write

## Tool roles (do not collapse these)

| Tool | Role | Skill(s) | If missing |
|---|---|---|---|
| **Skyrim Forge** | Typed automation broker: doctor, capabilities, Papyrus compile pipeline, FOMOD, release/nexus gates, tool-resolve | `skyrim-forge` | Bundle-managed; the AIO installs it. Continue with narrower tools if absent |
| **houseCARL** | Live MO2 load-order MCP: true winners, conflict trees, reviewable patch ESPs, Nexus keyless lookup, VFS assets | `housecarl` + mutagen/spid/kid/skypatcher authoring helpers | Recommend houseCARL-Setup + .NET 9 pair + MCP register |
| **Spooky's AutoMod Toolkit** | CLI for ESP/Papyrus/MCM/NIF/BSA/audio/SKSE project workflows with `--json` | `spookys-automod-toolkit` + `skyrim-plugin-authoring` | Recommend toolkit release + .NET 8 SDK |
| **codebase-memory-mcp** | Knowledge-graph code navigation (call graphs, impact) | `codebase-memory` | Recommend DeusData install + MCP wire |
| **Headroom** | Context compression / retrieve / session stats MCP | `headroom` | Optional; recommend pip install when context thrash is real |
| **Superpowers** | Process discipline (debug, TDD, plans, verification) | `using-superpowers` + family | Bundled skill text works; plugin optional |
| **Ponytail** | Minimal-diff / anti-over-engineering mode | `ponytail` + family | Bundled skill text works; plugin optional |
| **CodeBurn** | Local AI token/cost analytics | `codeburn` | Optional `npx codeburn` |

## Capability and schema overhead

Prefer an existing CLI when it fully answers the task. A dormant CLI adds
**0 tokens of MCP schema**; commands, instructions and output still consume
context when used. houseCARL is **MCP only -- no CLI**, and provides live
MO2 load-order evidence that an offline plugin reader cannot replace.

Historical schema estimates, not per-turn bills: Forge MCP 52 tools / 17,488
bytes / ~4,372 tokens (bytes/4); houseCARL Full 45 tools / 167,072 bytes /
~41,768; Lean 125,476 bytes / ~31,369; ReadOnly 70,418 bytes / ~17,604.
Tool count alone is a poor size proxy.

**Preferring a cheaper server you have already connected does not guarantee
lower usage.** Scope, native filtering, deferred discovery, caching and actual
calls decide what enters context. Start by **not registering** irrelevant
servers. Codex supports `enabled_tools` / `disabled_tools`; Hermes supports
`tools.include` / `tools.exclude`; Claude Code supports deferred Tool Search.
Do not buy a new router for a capability already native to the provider.

Use Forge CLI for typed engineering, Spooky CLI for its specialist workflows,
and houseCARL for live load-order truth, conflict trees, VFS and keyless Nexus.
See `capability-profiles` for setup and measurement boundaries.

## Decision cheat-sheet

| User need | Prefer |
|---|---|
| "What wins this FormID in MY list?" | houseCARL - nothing else can answer it |
| "Typed release / FOMOD / nexus policy / doctor" | Forge **CLI** (`forge release-build`, `forge doctor`) |
| "Create ESL + quest + compile papyrus from CLI" | Spooky, or Forge CLI - both free |
| "Read a record / query a plugin off disk" | Forge CLI `record-query` / `plugin-info` before houseCARL |
| "Build or validate a patch plugin from a plan" | Forge CLI `plugin-build` / `plugin-plan-validate` |
| "Edit what the LIVE load order resolves to" | houseCARL - Forge has no view of MO2 |
| "SPID/KID/SkyPatcher line syntax" | `*-authoring` / dedicated V4 syntax skills — never invent |
| "Who calls this function in the repo?" | codebase-memory |
| "Context is huge / compress this log" | headroom |
| "Stop over-engineering" | ponytail |
| "How much did this AI session cost?" | codeburn |
| "Bug / plan / verify before done" | superpowers process skills |

## Provider adaptation

- **Claude Code:** houseCARL ships as a Claude plugin; Superpowers/Ponytail/Headroom often install as plugins. Skills in this pack still work as plain `SKILL.md`.
- **Grok Build:** register MCP servers in `%USERPROFILE%\.grok\config.toml`. Use pack script `TOOLS\Fix-Grok-Codebase-Memory-Direct.ps1` only after editing the exe path. Skills go in `%USERPROFILE%\.grok\skills`.
- **Codex:** user skills in `%USERPROFILE%\.agents\skills`; `%CODEX_HOME%\skills` is legacy-only. MCP per Codex docs. houseCARL may ship a `codex\` skill stub — still require MCP binary.
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

## AIO installer (pack)

New users and missing-tool recovery:

```powershell
# Pack root
.\INSTALL-AIO.ps1
.\INSTALL-AIO.ps1 -Mode OnlineLatest
.\TOOLS\Ensure-Tools.ps1
.\TOOLS\Update-From-GitHub.ps1
```

Offline snapshots live in `BUNDLED-TOOLS\offline\`. Component registry: `BUNDLED-TOOLS\CATALOG.json`.
After MCP changes the user must **fully restart** the AI application.
