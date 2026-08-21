---
name: capability-profiles
description: Use when a task needs a capability the connected MCP servers do not cover (browser debugging, symbol-level code navigation, Blender, Godot, Unity, Supabase), when deciding whether to add an MCP server, when a server is configured but shows no tools, or when a session feels slow and MCP tool schemas are the suspected cause.
---

# Capability profiles

The right number of connected MCP servers is **the fewest that can do the
task**, and it changes per project. This pack ships the rest as profiles that
are off until something needs them.

## Why servers are not like skills

A skill costs nothing until its description matches. Its body is loaded on
demand. Measured in this pack: 144 skill bodies are ~154,000 tokens, while the
name-and-description index the agent actually reads is ~5,500.

**MCP tool schemas have no such discount.** Every tool of every connected server
is in context on every turn, in every session, whether or not the task is
related. Measured on a real machine with `TOOLS\Test-McpHandshake.ps1`:

```
housecarl  45   skyrim-forge  52   github  45   firecrawl  25
codebase-memory 15   headroom 3   context7 2   sequential-thinking 1
                                          = 188 tool schemas, every turn
```

That is the budget. Spend it on what the task uses.

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

`context7`, `sequential-thinking` and `github` are wired globally because they
apply to every task: current API docs instead of recalled signatures, explicit
decomposition, and the ability to verify a push rather than hope. Everything
else is a profile, and every profile is **project-scoped**.

## Profiles

| profile | gives you | needs |
|---|---|---|
| `code-intel` | Serena: LSP-accurate find-symbol, find-referencing-symbols, symbol-level edits | uv (auto-installs) |
| `web` | Chrome DevTools: console, network, performance traces, live DOM; shadcn registry | Google Chrome |
| `cloud` | Supabase schema, migrations, logs (read-only by default) | `SUPABASE_ACCESS_TOKEN` |
| `engine-blender` | live Blender scene control | Blender + its addon running |
| `engine-godot` | run projects, read scene trees, capture runtime errors | `GODOT_PATH` |
| `engine-unity` | live Unity editor control | the Unity package installed in that project |

`code-intel` was called `code-deep` before 7.9.6. The old id still resolves.

```powershell
TOOLS\Set-McpProfile.ps1 -List                    # what exists, what is ready, what is on where
TOOLS\Set-McpProfile.ps1 -Detect -Path <project>  # what this project implies
TOOLS\Set-McpProfile.ps1 -Auto   -Path <project>  # detect and wire, for that project only
TOOLS\Set-McpProfile.ps1 -Disable code-intel      # give the context back, everywhere it was on
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
| Hermes | none. One config file, no scope option. |

For the last three the server is skipped and the reason is printed.
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
machine-wide only              188 tool schemas every turn
+ code-intel for this project  209   (serena [project]  21 tools)
```

Those 21 are paid by that project and by nothing else. For the "wrong project"
cause, `Set-McpProfile.ps1 -List` prints which project each profile is on for.

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

Report what you did not enable and why. A profile left off on purpose is a
decision; a profile left off silently is a missing capability nobody knows about.
