# Grok MCP Troubleshooting

Measured 2026-08-15/16 against grok-cli **1.0.4** on Windows 11, using
`~/.grok/logs/unified.jsonl` and repeated `grok -p` runs.

**Correction history matters here.** v7.3.0/v7.3.1 shipped six rules written
while the problem was open; two were wrong and one shipped a harmful script.
v7.4.0/v7.4.1 then claimed Grok "never attaches MCP tools" — **also wrong**, and
corrected in v7.4.2. All three mistakes came from the same habit: inferring a
cause from a plausible story or a single counter instead of testing the thing
itself. The corrections are kept in place rather than quietly edited out.

---

## Read the turn phases before believing any theory

`%USERPROFILE%\.grok\logs\unified.jsonl` decomposes every turn:

```text
  0.66s  prompt received
 10.66s  shell.task_wake.gate_cleared     {"reason":"user_intake"}           +10.003s
 30.66s  shell.task_wake.gate_cleared     {"reason":"queued_user_promotion"} +19.997s
 65.66s  shell.turn.tool_prep_done        {"tool_count":26,"mcp_wait_ms":34887}
 67.71s  shell.turn.inference_done        {"model_elapsed_ms":2048}
127.74s  shell.handle_prompt.done                                            +60.037s
```

97 seconds of turn, **2.0 seconds of model**. Stalls landing on 10.003s,
19.997s and 60.037s are timeouts expiring, not work happening.

---

## Cause 1 — Grok runs Claude Code's hooks (real; fix stands)

Grok's Claude compatibility loads `~/.claude/settings.json` hooks **and** every
enabled plugin's `hooks/hooks.json` — 14 entries from 6 sources on this machine.
Grok's docs state hook layers "are read from every layer and combined
additively: a lower-priority layer can add hooks but never removes or replaces
another layer's block", so the compat cell is the only lever.

Measured: the two `Stop` hooks at `timeout: 30` cost **60.037s** per turn.
`inference_done` → `handle_prompt.done` dropped to **22ms** with the cell off.

```toml
# ~/.grok/config.toml
[compat.claude]
hooks = false
```

Claude Code keeps every hook. Only Grok stops running them.

### The underlying bug, fixed in `TOOLS/hooks/`

Both gates called `sys.stdin.read()`, which waits for EOF. Grok spawns hooks
without closing their stdin, so each hook burned its full timeout. Both files
declare *"fail open: a broken gate must never be able to stop work"* as design
rule 3 — a blocking read breaks that rule.

Three passes, and the first two are the instructive part:

1. Daemon thread + timed join — **still hung**: a daemon thread parked inside
   `sys.stdin`'s `BufferedReader` holds that object's lock, and CPython's
   shutdown blocks finalising it.
2. `os.read()` on the raw fd + `os._exit()` — `--pre` returned at 2.1s, `--stop`
   still hung.
3. A minimal repro found the real interaction: **a thread parked on fd 0 plus a
   child that inherits stdin deadlocks on Windows** — 161ms with no reader, >12s
   with one, 2158ms once the child got `stdin=DEVNULL`. `--pre` returns before
   touching git; `--stop` shells out to it.

Now 2.2s worst case with stdin open, unchanged 141–230ms otherwise.

---

## Cause 2 — too many MCP servers wedges startup (the real MCP limit)

**MCP works in Grok.** Verified end to end: Grok called
`housecarl__housecarl_load_order_status` and returned *2994 active plugins,
profile Default*, and `codebase-memory-mcp__list_projects` returning *45
projects*. Real data from real servers.

The constraint is **how many servers you register**, and it is sharp:

| Servers | `mcp_wait_ms` | Turn | Result |
|---|---|---|---|
| 1 | 0 | 2.5s | fine |
| 3 (local exes) | 0 | 5.2s | fine |
| 5 (3 local + github + context7) | 0 | 7.6–7.9s | **fine** |
| 7 | ~34 900 | — | process never exits |
| 8 | ~34 900 | — | process never exits |

**Six or more wedges it.** Not a specific server — dropping headroom from the 8
did not help, and every server is individually healthy: probed cold outside
Grok, `housecarl 0.32s/45`, `skyrim-forge 0.16s/52`, `headroom 0.86s/3`,
`codebase-memory 1.07s/15`, `mcp-search 0.16s/14`, `github 0.96s/26`,
`firecrawl 1.37s/25`, `context7 1.27s/2`, `sequential-thinking 1.07s/1` — 183
tools, none slower than 1.4s.

**Keep Grok at five MCP servers or fewer.** Put the ones you actually use there;
the rest stay in Claude Code and Hermes, which have no such limit.

### `tool_count: 26` is normal — do not read anything into it

This is what v7.4.0 got wrong. From Grok's own README:

| `search_tool` | Discover available integration tools (MCP) |
| `use_tool` | Call an integration tool discovered via `search_tool` |

**Grok deliberately never injects MCP tools into the tool list.** It ships those
two built-ins and discovers MCP tools on demand, to save context. So
`tool_count` stays at 26 (the built-in count) whether you have 8 servers or
none, and `shell.tool.exec_done {"tool_name":"search_tool"}` is what a working
MCP call looks like. v7.4.0 read a constant as evidence and concluded MCP was
dead. It is not.

### `[compat.claude] mcps = false` + native sections

Set the cell off and declare servers natively. This keeps Grok off the
`~/.claude.json` import path (which drags in every Claude Code plugin's MCP,
pushing you over the limit) while your chosen servers still work:

```toml
[compat.claude]
hooks = false
mcps = false

[mcp_servers.housecarl]
command = "C:/.../housecarl-mcp.exe"
args = []
```

---

## Corrections to earlier releases

### ~~v7.4.0: "Grok 1.0.4 never attaches MCP tools"~~ — WRONG

`tool_count: 26` is the built-in count by design; MCP is reached through
`search_tool`/`use_tool`. Verified by actually invoking tools on two different
servers. The real limit is server count (≥6 wedges startup).

### ~~Rule 1 — never add `[mcp_servers]` to `~/.grok/config.toml`~~ — WRONG

Native sections work and persist; `grok inspect` reports them as
`source: configToml`. The original "sections disappeared" observation was
misattributed, most likely to a `grok update --force-reinstall` in the same
window.

### ~~Rule 6 — orphan fleets; run `Clean-Grok-MCP-Orphans.ps1`~~ — WRONG AND HARMFUL

The "orphaned Grok MCP fleet" was **Claude Code's own running servers** —
children of `claude.exe`, with no Grok process alive. The script matched on
process name only, with no parent check, and its sole guard was "no grok.exe
running", so it killed every houseCARL, codebase-memory, headroom, Forge and
npx MCP server on the machine. **Removed in v7.4.0. Delete any copy you made.**

### Rules 2–5 — kept, demoted to hygiene

True and worth doing, but none was the softlock: pin npx servers; run headroom
through the PYTHONPATH-stripping launcher (a 3.11 `PYTHONPATH` kills the 3.12
`headroom.exe` on `click`); check port 9749 when codebase-memory reports
unavailable; don't force-kill MCP children under a live session.

---

## Diagnosis cheat-sheet

| Check | Command / file |
|---|---|
| harness or model? | `mcp_wait_ms` vs `model_elapsed_ms` in `unified.jsonl` — round numbers mean timeouts |
| MCP startup wedged? | `mcp_wait_ms` near 34 900 means you are over the server limit — drop to ≤5 |
| is MCP actually working? | `grok --always-approve -p "use search_tool then use_tool to call <tool>"` — **test a real call, never infer from `tool_count`** |
| what does Grok load? | `grok inspect --json` → `hooks`, `skills`, `mcpServers[].source`, `externalCompat.cells` |
| single server healthy? | pipe `initialize` + `tools/list` into its command; healthy = reply < 1.5s |
| whose child is that process? | `Get-CimInstance Win32_Process`, check `ParentProcessId` — **never match on name alone** |

> `grok inspect` lists what was *discovered on disk*, not what is *active*: it
> still reports 14 hooks and 9 MCP servers with both compat cells off. Trust the
> turn log, and trust an actual tool call over any counter.
