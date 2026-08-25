---
name: capability-profiles
description: Use when a task needs a capability the connected MCP servers do not cover (game-specific Forge tools, browser debugging, symbol-level code navigation, Blender, Godot, Unity), when deciding whether to add an MCP server, when a server is configured but shows no tools, when a session feels slow and MCP tool schemas are the suspected cause, or when choosing the smallest capability that can produce the evidence a task actually needs.
---

# Capability profiles

The right number of connected MCP servers is **the fewest that can do the
task**, and it changes per project. This pack ships the rest as profiles that
are off until something needs them.

## Why servers are not like skills

A skill costs nothing until its description matches. Its body is loaded on
demand. Measured in this pack: the 146 SKILL.md files are ~163,000 tokens,
while the name-and-description index the agent actually reads is ~6,900.

**MCP tool schemas have no such discount.** Every tool of every connected server
is in context on every turn, in every session, whether or not the task is
related. Measured on a real machine with `TOOLS\Test-McpHandshake.ps1`:

```
housecarl  45   skyrim-forge  52   github  45   firecrawl  25
codebase-memory 15   headroom 3   context7 2   sequential-thinking 1
                                          = 188 tool schemas, every turn
```

That is the budget. Spend it on what the task uses.

**Count bytes, not tools.** The same servers by serialized schema size —
`TOOLS\Measure-McpSchemaCost.ps1`, real `initialize` → `tools/list`:

```
houseCARL 1.9.0      45 tools  167,072 bytes  ~41,768 tokens/turn
firecrawl 3.24.0     25 tools   36,321 bytes   ~9,080 tokens/turn
skyrim-forge 6.0.0   52 tools   17,488 bytes   ~4,372 tokens/turn
context7              2 tools    5,124 bytes   ~1,281 tokens/turn
sequential-thinking   1 tool     4,590 bytes   ~1,148 tokens/turn
```

Read the first and third rows together. **Skyrim Forge has SEVEN more tools
than houseCARL and costs a tenth of the context.** Ranking these by tool count
puts Forge first in line to be cut, which is backwards by an order of
magnitude. houseCARL's schemas carry deep nested record objects — three tools
(`bulk_create`, `create_record`, `bulk_apply`) are 41,596 bytes between them,
more than the whole of Forge — while Forge's are typed and narrow at ~336 bytes
each.

One tool cost as much as two. A tool count tells you almost nothing about what
a server charges you.

houseCARL at ~41,768 tokens is roughly **21% of a 200k context window gone
before the first user message**. That is not an argument for removing it: live
MO2 load-order truth, conflict trees and keyless Nexus lookup have no cheaper
substitute, and guessing at load order is the failure this pack exists to
prevent. It is an argument for *scope* — it belongs in the `skyrim` profile and
Hermes' `skyrim` home, never in the always-on core. Numbers:
`BUNDLED-TOOLS/capability-records/game-mcp-schema-cost.json`.

### The unit below a server: individual tools

**Hermes can filter a server down to named tools; the others cannot.**

```yaml
mcp_servers:
  housecarl:
    tools:
      exclude: [housecarl_bulk_create, housecarl_create_record, housecarl_bulk_apply]
      # or include: [...] for a strict allowlist. fnmatch globs work in both.
```

Enforced at tool **registration** (`tools/mcp_tool.py`, on both the live
discovery and schema-cache paths), so a filtered tool's schema never reaches the
model. `hermes mcp configure <server>` writes this interactively.

Two facts that decide which form to use:

| | behaviour when the server adds a tool upstream | use for |
|---|---|---|
| `exclude` | the new tool IS registered | trimming a few known-huge tools |
| `include` | the new tool is NOT registered | a set with a promise to keep, e.g. "nothing writes" |

Measured on houseCARL 1.9.0, and shipped as named sets in `CATALOG.json`:

```
Full      45 tools  167,072 bytes  ~41,768 tok/turn
Lean      42 tools  125,476 bytes  ~31,369 tok/turn   -25%   (default)
ReadOnly  27 tools   70,418 bytes  ~17,604 tok/turn   -58%
```

Lean drops three tools and 25% of the cost, because schema size is wildly
uneven: `bulk_create`, `create_record` and `bulk_apply` carry full nested record
objects and are 41,596 bytes between them.

**Never estimate a filtered cost by averaging.** `active_tools × (bytes ÷
tools)` gives ~38,983 for the Lean set, which measures 31,369 — a 3.7× error in
the saving, presented as a number. Measure the filtered set, or say unmeasured.

```powershell
TOOLS\Migrate-HermesProfiles.ps1 -SkyrimToolset ReadOnly -Apply   # -58%
TOOLS\Migrate-HermesProfiles.ps1 -SkyrimToolset Full -Apply       # remove the filter
hermes -p skyrim mcp configure housecarl                          # pick by hand
```

A hand-picked filter survives re-installs: the migrator fills the field when it
is absent and never overwrites it, unless `-SkyrimToolset` is passed explicitly.

For Claude, Codex, Grok and Kimi the whole server is still the unit. There, the
answer is a project-scoped profile, not a smaller server.

## Installed is not enabled

Two different things, and conflating them is what made the first cut of this
router expensive:

| | means | costs |
|---|---|---|
| **installed** | the executable exists on disk | disk, nothing else |
| **enabled** | an MCP entry is registered in a provider config | its tool schemas, every turn of every session that config covers |

`Set-McpProfile.ps1` will install a missing tool when it can, and still leave it
disabled everywhere except the project that asked for it. "Serena is installed"
is not a reason to expect `find_symbol` in this session.

## The always-on three

`context7`, `github`, and `headroom` are wired globally because they apply to
every task: current API docs instead of recalled signatures, verified pushes
instead of hoped-for ones, and context compression that pays for itself.
Everything else is a profile. The general router uses project scope; Hermes
uses its native named homes for `roblox` and `skyrim` because it has profiles
but no project-path MCP scope.

`sequential-thinking` was the third until 7.9.7 measured it: 1 tool, but a
4,590-byte schema — ~1,148 tokens on every turn of every session, as much as
context7's two tools, for a structured scratchpad rather than a capability.
It is the opt-in `reasoning` profile now, with no detection markers so `-Auto`
can never reach it.

This is the one number to keep in view when judging any server: **tools is the
wrong unit, bytes is the right one.** Measure before arguing about it —
`TOOLS\Measure-McpSchemaCost.ps1 -Command 'npx -y <package>'` runs the real
`initialize` → `tools/list` and prints per-tool bytes.

## Profiles

| profile | gives you | needs |
|---|---|---|
| `game-skyrim` | Skyrim Forge typed mod engineering | installed bundled Forge |
| `game-skyrim-load-order` | houseCARL against a real MO2 instance/Vortex shim | `HOUSECARL_MCP` + instance env |
| `game-roblox` | Roblox Forge analysis, planning, review, receipts | discovered Roblox Forge checkout |
| `game-saints-row` | Saints Row assets, XTBL, builds, dependency checks | discovered Saints Row Forge checkout |
| `code-intel` | codebase-memory graph + Serena LSP symbol navigation/edits | installed graph server; uv for Serena |
| `web` | Chrome DevTools: console, network, performance traces, live DOM; shadcn registry | Google Chrome |
| `engine-blender` | live Blender scene control | Blender + its addon running |
| `engine-godot` | run projects, read scene trees, capture runtime errors | `GODOT_PATH` |
| `engine-unity` | live Unity editor control | the Unity package installed in that project |

`code-intel` was called `code-deep` before 7.9.6. The old id still resolves.

Hermes has a smaller native topology: `default` is the always-on three,
`roblox` adds the official Roblox Studio MCP, and `skyrim` adds houseCARL.
The Skyrim toolset still includes all three specialists: houseCARL through the
profile MCP, Skyrim Forge through its skill/CLI, and Spooky's AutoMod through
the routed specialist skills/CLI. Forge's MCP is opt-in compatibility, not a
default profile member.

The `cloud` profile (Supabase) was withdrawn in 7.9.7: it was the only profile
here that needed an account and a personal access token, against this pack's
default of free, local, keyless and no signup. A machine that had it enabled
gets it un-registered on the next run — only the entries this pack created; a
Supabase server you configured yourself is untouched.

```powershell
TOOLS\Set-McpProfile.ps1 -List                    # what exists, what is ready, what is on where
TOOLS\Set-McpProfile.ps1 -Detect -Path <project>  # what this project implies
TOOLS\Set-McpProfile.ps1 -Auto   -Path <project>  # detect and wire, for that project only
TOOLS\Set-McpProfile.ps1 -Disable code-intel      # give the context back, everywhere it was on
TOOLS\Migrate-HermesProfiles.ps1                  # dry-run native Hermes topology
TOOLS\Migrate-HermesProfiles.ps1 -Apply           # backup, migrate, verify
```

`-Auto` writes a profile only when the project shows its markers **and** the
machine satisfies its requirements. A profile it cannot run is skipped with the
reason printed.

## What "project-scoped" means per provider

Not every CLI has the concept. Where one does not, this pack does **not**
quietly register the server machine-wide instead — that is the cost the whole
router exists to avoid:

| provider | mechanism |
|---|---|
| Claude Code | `projects["<abs path>"].mcpServers` in `~/.claude.json` — where `claude mcp add --scope local` writes. No file in your repo, no trust prompt. |
| Grok | `<project>\.grok\config.toml` — `grok mcp add -s project`. This one *is* a file in the project. |
| Codex | none. A project `.codex/config.toml` is ignored. |
| Kimi | none found; it reads `%USERPROFILE%\.kimi-code\mcp.json`. |
| Hermes | native named homes/configs (`default`, `roblox`, `skyrim`), selected with `-p` or the generated aliases; no project-path scope. |

For Codex and Kimi the MCP server is skipped and the reason is printed. The
matching game skill can still run an installed Forge through its CLI, so the
capability remains available without paying its schemas in every session.
`-Global` is the explicit opt-in, and it registers machine-wide — Serena then
gets `--project-from-cwd` rather than one baked path, so it follows the session
instead of activating one project everywhere.

## When a server is configured but shows no tools

This is the failure mode to recognize on sight, because the provider says
nothing about it. Every instance in this pack's history had one of five causes:

- the command does not exist (a version-stamped folder that was renamed)
- the package was withdrawn upstream (a valid name, a dead command)
- a backslash escaped twice too many, so the path parses to nothing
- `npx` without `-y`, blocking forever on an install prompt
- the entry is registered for a *different* project than the one you are in

Do not guess between them:

```powershell
TOOLS\Test-McpHandshake.ps1 -Provider Claude -Path <project>
```

It spawns each server exactly as the provider does and runs the real
`initialize` -> `tools/list` exchange. A server that answers is working; one
that does not gets a reason instead of a shrug.

**Pass `-Path`.** Without it the check reads the machine-wide config only, and
every capability profile is registered per project — so the servers most likely
to need this question asked are the ones it cannot see. With `-Path` it reports
what a session opened there would actually pay. Measured on the development
machine for this pack's own repository:

```
machine-wide before profiles   188 tool schemas every turn
+ code-intel for one project   209   (serena [project]  21 tools)
```

Those 21 are paid by that project and by nothing else. For the "wrong project"
cause, `Set-McpProfile.ps1 -List` prints which project each profile is on for.

## Pick the capability the evidence needs

A profile is not a subject area, it is a way of getting evidence. Turn on the
one that answers this question, not the set that looks related:

| task | what settles it |
|---|---|
| UI change, "make it look right" | run it, look at the rendered output — `web` for console/network/layout, plus `visual-verification` |
| CLI or parser bug | the failing input, the real output, the tests. No browser. |
| symbol-level refactor in a real codebase | `code-intel` |
| "which API does this library have now" | `research-verification` — installed `--help`, upstream, Context7. No Blender, no DevTools. |
| Blender / Godot / Unity work | that engine's profile, plus a render or capture if you can see it |
| Skyrim mod project | Hermes `skyrim` for houseCARL evidence; use Skyrim Forge and Spooky through their routed skills/CLIs unless Forge MCP compatibility is explicitly needed |
| Roblox project | Hermes `roblox` for the official Studio bridge; use RobloxForge through its skill/CLI |
| Saints Row project | `game-saints-row` when markers match; otherwise its installed CLI/skill |
| Skyrim crash | the crash log and the Skyrim diagnostic skills. Only reach outward if a version fact is genuinely unresolved. |

Do not enable Chrome DevTools to edit a README. Do not enable `shadcn` because a
`package.json` exists. Do not open a browser when a deterministic test answers
the question more cheaply.

This skill answers **which server to turn on**. For the other half — choosing
between a capability you already have and writing the thing yourself, and what
to do when the tool you picked fails — see `capability-routing`. The short
version: do not rebuild an installed capability with a weaker ad-hoc script,
and do not reach for machinery a file read would have finished.

## Before proposing a new MCP server

1. **Does a connected server already do it?** houseCARL reads Nexus keylessly;
   context7 has the current docs. Adding a second server for either is cost
   with no capability.
2. **Is it pinned?** `@latest` lets a server change its tool surface
   mid-session, and npx will reuse a broken cache. Pin the exact version.
3. **Can it be scoped?** The GitHub server has 20 toolsets; this pack loads five.
   Prefer a flag that narrows the surface over accepting all of it.
4. **Is it project-scoped or machine-wide?** If it is only useful inside one
   kind of project, it belongs in a profile, and the profile must be written
   where only that project sees it.
5. **Does it need a host application?** Blender, Unity, Godot and Unreal bridges
   talk to a plugin inside a running editor. Registering one with nothing to
   talk to produces a server that starts and answers nothing.
6. **Is upstream alive?** Check the last commit before vendoring a bridge into
   someone else's machine.
7. **Does it need an account, a key or a signup?** This pack's default is free,
   local and keyless. That is why Supabase was withdrawn rather than kept
   behind a token check.

Report what you did not enable and why. A profile left off on purpose is a
decision; a profile left off silently is a missing capability nobody knows about.
