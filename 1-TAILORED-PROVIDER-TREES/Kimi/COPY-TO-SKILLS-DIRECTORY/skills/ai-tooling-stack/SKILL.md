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

## What each tool COSTS (read before the cheat-sheet)

An MCP server's tool schemas are serialized into the prompt on **every turn of
every session**, whether you call it or not. A CLI costs **nothing** until you
run it, and then only the command and its output. That difference dwarfs any
preference between two tools that can both do the job.

Measured with `TOOLS\Measure-McpSchemaCost.ps1` (real `initialize` ->
`tools/list`), houseCARL 1.9.0 and Skyrim Forge 6.0.0:

| tool | surface | standing cost |
|---|---|---|
| **Skyrim Forge** | 52 subcommands, **CLI** (`forge <cmd>`) | **0 tokens** |
| Skyrim Forge as MCP | the same 52 tools | ~4,372 tokens/turn |
| **Spooky's AutoMod** | CLI with `--json` | **0 tokens** |
| **houseCARL** | 45 tools, **MCP only -- no CLI** | ~41,768 tokens/turn (Full) |
| houseCARL `Lean` | 42 tools | ~31,369 tokens/turn |
| houseCARL `ReadOnly` | 27 tools | ~17,604 tokens/turn |

**Forge has SEVEN more tools than houseCARL and, run as a CLI, costs nothing.**
Every Forge MCP tool has a CLI twin: `forge plugin-build`, `forge record-query`,
`forge papyrus-compile`, `forge fomod-build`, `forge release-build`,
`forge lint`, `forge doctor`. Check `forge --help` before assuming otherwise.

### The rule

1. **Can Forge's CLI do it? Use the CLI.** Free, and it is the typed,
   validated path this pack prefers anyway.
2. **Can Spooky's CLI do it? Use the CLI.** Same reason.
3. **Only houseCARL answers "what wins in MY load order".** Live MO2 truth,
   conflict trees, VFS asset resolution and keyless Nexus lookup have no CLI
   anywhere. That is what its schema is being paid for -- use it for that, and
   route the rest to a CLI.

### Two mistakes this table exists to prevent

- **"Prefer the cheaper MCP server."** Preferring a cheaper server you have
  already registered saves nothing: you pay both schemas every turn regardless
  of which one gets called. The saving comes from **not registering** the
  expensive one, or from registering fewer of its tools -- never from
  preferring around it at call time.
- **"Fewer tools means cheaper."** Ranking by tool count puts Forge (52) ahead
  of houseCARL (45) as the thing to cut. That is backwards by an order of
  magnitude. Count bytes; see `capability-profiles`.

On Hermes specifically, MCP is billed per token on your own key, and Hermes is
the one provider that can register a **subset** of a server's tools
(`tools.include` / `tools.exclude`). The `skyrim` profile ships houseCARL's
`Lean` set; `TOOLS\Migrate-HermesProfiles.ps1 -SkyrimToolset ReadOnly -Apply`
takes it to 27 tools when the session is diagnosis rather than authoring.

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
