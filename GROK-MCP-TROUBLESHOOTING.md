# Grok MCP Troubleshooting

Measured 2026-08-15/16 against grok-cli **1.0.4** on Windows 11, using
`~/.grok/logs/unified.jsonl` and repeated `grok -p` runs.

**Correction history matters here.** v7.3.0/v7.3.1 shipped six rules written
while the problem was open; two were wrong and one shipped a harmful script.
v7.4.0/v7.4.1 then claimed Grok "never attaches MCP tools" — **also wrong**,
corrected in v7.4.2. v7.4.2 then put the server limit at five — **also wrong**,
corrected in v7.4.3: the limit is seven *running*, and a plugin-provided server
you never configured is quietly using one. Four mistakes, one habit: inferring
from something adjacent instead of testing the thing itself. The corrections are
kept in place rather than quietly edited out.

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

The constraint is **how many servers end up running**, and it is a hard cliff:

| Servers running | `mcp_wait_ms` | Turn | Result |
|---|---|---|---|
| 2–7 | 0 | 2.5–8.2s | fine |
| 8 | ~34 900 | — | process never exits |

**Seven running is fine. Eight wedges.** Composition is irrelevant: five
different 6-configured sets all passed and four different 7-configured sets all
failed, including sets that swapped every member. Every server is individually
healthy — probed cold outside Grok: `housecarl 0.32s/45`,
`skyrim-forge 0.16s/52`, `headroom 0.86s/3`, `codebase-memory 1.07s/15`,
`mcp-search 0.16s/14`, `github 0.96s/26`, `firecrawl 1.37s/25`,
`context7 1.27s/2`, `sequential-thinking 1.07s/1` — 183 tools, none over 1.4s.

### Count the free-rider: your budget is one less than you think

**`[compat.claude] mcps = false` does not stop plugin-provided MCP servers.**
Every enabled Claude Code plugin with a `.mcp.json` still loads. On this machine
that is `mcp-search` from claude-mem, and it silently occupies a slot.

Proof — same 7 configured servers, only difference is whether claude-mem's
`.mcp.json` is present:

```text
7 configured + mcp-search  -> 8 running -> WEDGED
7 configured, mcp-search hidden -> 7 running -> OK, 7.3s
```

So with claude-mem installed you get **6 configured servers**, not 7. Confirm
what is actually running by counting grok's direct children during a turn:

```powershell
Get-CimInstance Win32_Process -Filter "ParentProcessId=<grok pid>"
```

Each stdio server appears as one child (`cmd.exe` wrapper for npx ones), plus a
`conhost.exe` that is not a server.

**Keep Grok at six configured MCP servers** while any MCP-providing Claude
plugin is enabled — seven if you disable them. Everything else stays in Claude
Code and Hermes, which have no such limit.

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
servers. The real limit is how many servers **run** (8 wedges), and enabled
Claude plugins add servers that never appear in `config.toml`.

### ~~v7.4.2: "keep Grok at five MCP servers or fewer"~~ — WRONG

Five was never tested against six. Five different 6-configured sets all pass;
the cliff is at **8 running**, and `mcp-search` from the claude-mem plugin was
silently occupying a slot the whole time. Budget is 6 configured with an
MCP-providing plugin enabled, 7 without.

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
| MCP startup wedged? | `mcp_wait_ms` near 34 900 means 8+ servers are running — drop to 6 configured |
| is MCP actually working? | `grok --always-approve -p "use search_tool then use_tool to call <tool>"` — **test a real call, never infer from `tool_count`** |
| what does Grok load? | `grok inspect --json` → `hooks`, `skills`, `mcpServers[].source`, `externalCompat.cells` |
| single server healthy? | pipe `initialize` + `tools/list` into its command; healthy = reply < 1.5s |
| whose child is that process? | `Get-CimInstance Win32_Process`, check `ParentProcessId` — **never match on name alone** |

> `grok inspect` lists what was *discovered on disk*, not what is *active*: it
> still reports 14 hooks and 9 MCP servers with both compat cells off. Trust the
> turn log, and trust an actual tool call over any counter.

## Hook "failed with exit code 1: At line:1 char:65" on every tool use (v7.6.4)

`global/ultimate-bundle:pre_tool_use[N].hooks[0]` failing with
`At line:1 char:65` is a PowerShell *parse* error, not a gate verdict: Grok
executes hook commands through PowerShell, and the pre-7.6.4 wiring wrote
cmd-style commands (`"python" "script.py" --pre`). A quoted command followed
by arguments is invalid PowerShell without the call operator; char 65 is where
the second quoted string begins.

Fix shipped in v7.6.4: `TOOLS/Install-Completeness-Gate.ps1` writes Grok's
`~/.grok/hooks/ultimate-bundle.json` with the `& ` call-operator prefix
(Claude keeps the cmd form — cmd.exe chokes on a leading `&`). Re-run
`Install-Completeness-Gate.ps1 -Providers Grok` to rewrite the file, then
restart Grok.
