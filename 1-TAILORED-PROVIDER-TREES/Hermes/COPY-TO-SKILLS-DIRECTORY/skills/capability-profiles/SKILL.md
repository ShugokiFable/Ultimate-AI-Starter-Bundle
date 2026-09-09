---
name: capability-profiles
description: Use when a task needs a capability the connected MCP servers do not cover (game-specific Forge tools, browser debugging, symbol-level code navigation, Blender, Godot, Unity), when deciding whether to add an MCP server, when a server is configured but shows no tools, when a session feels slow and MCP tool schemas are the suspected cause, or when choosing the smallest capability that can produce the evidence a task actually needs.
---

# Capability profiles

The right number of connected MCP servers is **the fewest that can do the
task**, and it changes per project. This pack ships the rest as profiles that
are off until something needs them.

## Installed is not enabled

Installed means files exist on disk. Configured means a provider entry exists.
Active means the provider accepted its scope/trust and connected successfully.
Callable means the needed tool survived filters and permissions.
Do not treat any one of these as proof of the next.

A skill's description has an index cost; its body is usually loaded on demand.
MCP behavior is host-dependent. Claude Code supports deferred Tool Search;
Codex and Hermes support individual-tool filters. Full advertised schemas are
NOT automatically loaded or billed on every turn.

## Measure the right thing

`TOOLS\Measure-McpSchemaCost.ps1` measures advertised compact UTF-8 schema bytes.
Its bytes/4 figure is a schema-token estimate, not actual tokenization, prompt
usage, cached tokens or billing. Tool results and discovery metadata have their
own costs. Compare the same serialization and use provider usage for real cost.

Historical houseCARL 1.9.0 measurements (sum of per-tool bytes, not array framing):

| set | tools | schema bytes | bytes/4 estimate |
|---|---:|---:|---:|
| Full | 45 | 167,072 | 41,768 |
| Lean | 42 | 125,476 | 31,369 |
| ReadOnly | 27 | 70,418 | 17,604 |

Three tools account for 41,596 bytes: tool count is not a reliable size proxy.
Never average a full server's bytes to price a subset. Measure the selected set
or report it unmeasured. Legacy JSON fields named `tokens_per_turn` retain
schema estimates for compatibility; they are not billing evidence.

## Narrow the tools using native support

- Codex: `enabled_tools` allowlist and `disabled_tools` denylist on the server
  entry; the denylist applies after the allowlist. Verified with native Codex
  0.152.0 discovery, filtered registration and a harmless call, without inference.
- Hermes: `tools.include` / `tools.exclude`; a custom filter survives normal
  reinstallation. `TOOLS\Migrate-HermesProfiles.ps1 -SkyrimToolset ReadOnly -Apply`
  explicitly selects the packaged set; `Full` removes the filter.
- Claude Code: prefer native Tool Search when supported by the active
  model/deployment. Do not force it on an unsupported proxy.
- Grok/Kimi: use the narrowest supported scope and server-native toolset flags;
  do not assume they implement Codex or Hermes filter keys.

An allowlist does not admit newly added tools; a denylist normally does.
A tool named ReadOnly is not an OS security boundary: still inspect the actual
operation, target and permissions.

## The always-on three

`context7`, `github`, and `headroom` are the small core. Keep optional servers
scoped to task evidence. Windows desktop control stays off by default.
`sequential-thinking` remains opt-in (`reasoning`, no auto-detection markers):
its historical 4,590 schema bytes are not evidence of better answers.

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

Hermes has a smaller native topology: `default` is the always-on three, `code`
adds codebase-memory, `roblox` adds the official Roblox Studio MCP, and `skyrim`
adds houseCARL. Use `hermes -p code` in a code repository; its ~5,994 schema-token
estimate is not a bill, and its servers are absent from ordinary Hermes sessions.
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

| provider | mechanism |
|---|---|
| Claude Code | `projects["<abs path>"].mcpServers` in `~/.claude.json` (local scope) |
| Grok | `<project>\.grok\config.toml` |
| Codex | `<project>\.codex\config.toml`, loaded only for a trusted project |
| Kimi | no project scope established; skip unless `-Global` is explicit |
| Hermes | native named homes via `-p default/code/roblox/skyrim`, not project-path scope |

Use `TOOLS\Set-McpProfile.ps1 -Auto -Path <project> -Providers Codex` for matching
Codex profiles. The installer never grants trust. Restart and run
`codex mcp list --json` from that project to verify effective configuration.
A successful file write is not activation proof. Keep machine-specific project
config out of Git. `-Global` is an explicit wider scope, never a silent fallback.

## Configured but no tools?

Check the scope, Codex trust, disabled flags/filters, binary path, package pin,
host application, and restart status before recommending another install.

`TOOLS\Test-McpHandshake.ps1 -Provider Codex -Path <project> -RequireMatch`
uses native Codex discovery, then checks stdio command/args with a real
`initialize` -> `tools/list`. For other providers it reads the pack's config
shape. This is a transport smoke test using the current shell environment, not
full provider parity: config env/cwd and tool filters are not replayed. It does
not prove authentication, model selection, tool execution or billed usage.

Sources: [Codex MCP](https://learn.chatgpt.com/docs/extend/mcp?surface=cli),
[Claude Tool Search](https://code.claude.com/docs/en/mcp#scale-with-mcp-tool-search).

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
