---
name: roblox-game-development
description: Use when building, fixing, testing, or reviewing any Roblox game or Roblox Studio work - Roblox, Roblox Studio, Luau, obby, tycoon, simulator, Roblox UI, Roblox combat, DataStore, RemoteEvent, Roblox multiplayer, Studio MCP. Router skill; load the matching reference for the task.
---

# Roblox Game Development (RobloxForge)

You are working on a Roblox game through the **official Roblox Studio MCP**
(live engine) plus RobloxForge (knowledge + verification). Non-negotiables
first; references carry the detail.

## The loop (never skip steps)

```
rb_doctor / rb_capabilities   -> is Studio actually connected? (probe, don't assume)
inspect current place          -> search_game_tree / inspect_instance BEFORE writing anything
plan smallest vertical slice   -> one playable loop, not the whole game
implement                      -> server owns truth; client owns input/presentation
playtest via official MCP      -> start_stop_play, character_navigation, get_console_output
read console output            -> errors are data, fix them
screen_capture + INSPECT       -> only claim visual success if you actually looked
fix, re-run, THEN expand       -> vertical slice proven before adding systems
```

## Hard rules

1. **Vertical slices only.** Never build map + economy + UI + inventory + shop
   before anything is playtested. One loop, proven, then expand.
2. **Server owns truth.** Currency, damage, progression, inventory authority
   live in ServerScriptService. A client request is a *suggestion* the server
   validates. `RemoteEvent != authorization`.
3. **Probe, don't assume.** Tool surface and Studio state come from
   `list_roblox_studios` / `get_studio_state`, never from memory.
4. **"Scripts exist" is not "game works".** Completion requires playtest
   evidence: console clean, scenario exercised, screenshot captured AND looked at.
5. **Check `rb_capabilities` before playtesting.** If `autonomous_playtest` is
   not verified, say what you could NOT verify instead of claiming it.

## References (load only what the task needs)

- `references/studio-mcp.md` - tool map, argument quirks, subagent use
- `references/development-loop.md` - the vertical-slice method per genre
- `references/architecture.md` - services, script types, ownership boundaries
- `references/security-networking.md` - remotes, validation, exploit patterns
- `references/persistence.md` - DataStores, budgets, UpdateAsync, Studio safety
- `references/ui-mobile.md` - ScreenGui, safe area, input for touch
- `references/testing-debugging.md` - playtest scenarios, console triage
- `references/sharp-edges.md` - the traps that break AI-built games
- `references/game-design.md` - loop design: ACTION -> FEEDBACK -> REWARD -> REPEAT
- `references/performance.md` - MicroProfiler-first optimization, known traps
- `references/assets.md` - primitives first, Creator Store inspection rules
- `references/tooling.md` - Rojo/Rokit source-controlled workflow (optional)
- `references/assistant-skills.md` - routing to Roblox's built-in rbx-* skills

## When unsure about an API

Do not trust model memory. `rb_docs_search "TweenService:Create"` against the
official creator-docs cache, then `rb_docs_read` the hit. Current official
documentation beats your training data every time.
