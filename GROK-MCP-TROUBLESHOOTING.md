# Grok MCP Troubleshooting

Measured 2026-08-15/16 against grok-cli **1.0.4** on Windows 11, using
`~/.grok/logs/unified.jsonl` and repeated `grok -p` runs.

**Read this first if you are coming from v7.3.0/v7.3.1.** Those releases
documented six rules written while the problem was still open. Two of them were
wrong, and one shipped a script that killed other applications' MCP servers.
They are corrected below and the reasoning is kept, because the *way* they went
wrong is the useful part: every one of them was inferred from a plausible story
instead of from a measurement that separated cause from correlation.

---

## Read the turn phases before believing any theory

`%USERPROFILE%\.grok\logs\unified.jsonl` decomposes every turn. One `grok -p
"Reply with the single word: OK"` gives you the whole picture:

```text
  0.66s  prompt received
 10.66s  shell.task_wake.gate_cleared     {"reason":"user_intake"}          +10.003s
 30.66s  shell.task_wake.gate_cleared     {"reason":"queued_user_promotion"} +19.997s
 30.77s  shell.handle_prompt.start
 65.66s  shell.turn.tool_prep_done        {"tool_count":26,"mcp_wait_ms":34887}
 67.71s  shell.turn.inference_done        {"model_elapsed_ms":2048}
127.74s  shell.handle_prompt.done                                           +60.037s
```

97 seconds of turn. **2.0 seconds of model.** Everything else is the harness,
and the round numbers give it away: stalls that land on 10.003s, 19.997s and
60.037s are timeouts expiring, not work happening.

Two independent causes, each confirmed by A/B:

| Change | Turn time |
|---|---|
| baseline | 97s (and often no reply at all) |
| `[compat.claude] hooks = false` | 68s — kills the 60.037s post-inference stall |
| `[compat.claude] mcps = false` | 3.7s — kills the 10s + 20s + 35s pre-inference stall |
| both | **2.1–4.9s** |

---

## Cause 1 — Grok runs Claude Code's hooks, and they are not built for it

Grok's Claude compatibility loads `~/.claude/settings.json` hooks *and* every
enabled plugin's `hooks/hooks.json`. On this machine that is **14 hook entries
from 6 sources**. Grok's own docs state hook layers "are read from every layer
and combined additively: a lower-priority layer can add hooks but never removes
or replaces another layer's block" — so there is no way to un-inherit them from
the Grok side except the compat cell.

The measured cost was the two `Stop` hooks at `timeout: 30` each: `inference_done`
→ `handle_prompt.done` took **60.037s**, and dropped to **22ms** with the cell off.

```toml
# ~/.grok/config.toml
[compat.claude]
hooks = false
```

Claude Code keeps every hook. Only Grok stops running them.

### The underlying bug, fixed in `TOOLS/hooks/`

Both gates called `sys.stdin.read()`, which waits for EOF. Grok spawns hooks
without closing their stdin, so the read never returned and each hook burned its
full timeout. Both files declare *"fail open: a broken gate must never be able to
stop work"* as design rule 3 — a blocking read breaks that rule.

Fixing it took three passes, and the first two are worth recording:

1. Moved the read to a daemon thread with a 2s join. **Still hung** — a daemon
   thread parked inside `sys.stdin`'s `BufferedReader` holds that object's lock,
   and CPython's shutdown blocks finalising it.
2. Switched to `os.read()` on the raw fd and exited via `os._exit()`. `--pre` now
   returned at 2.1s, but `--stop` still hung.
3. `--pre` returns before touching git; `--stop` shells out to it. A minimal
   repro isolated the real interaction: **a thread parked on fd 0 plus a child
   that inherits stdin deadlocks on Windows** — 161ms with no reader, >12s with
   one, 2158ms once the child got `stdin=DEVNULL`.

Result: worst case **2.2s** with stdin open (was an indefinite hang), unchanged
**141–230ms** for hosts that close stdin properly, both self-tests passing, and
the block decision still firing. Any host that leaves stdin open is now safe.

---

## Cause 2 — Grok 1.0.4 never attaches MCP tools at all

This is the finding that makes the rest moot. Across **every single turn ever
recorded in the log — 12 of them**, spanning interactive and headless sessions,
8 servers and 0 servers, `~/.claude.json` and native `[mcp_servers]`:

```text
tool_count = 26     (unchanged, always)
```

26 is Grok's built-in count: it is identical with zero MCP servers configured.
**Not one MCP tool ever reached the model**, while `mcp_wait_ms: ~34900` was
charged to the first turn of every session.

The servers are not the problem. Probed cold, outside Grok:

```text
housecarl 0.32s/45   skyrim-forge 0.16s/52   headroom 0.86s/3
codebase-memory 1.07s/15   mcp-search 0.16s/14   github 0.96s/26
firecrawl 1.37s/25   context7 1.27s/2   sequential-thinking 1.07s/1
```

All 9 healthy, 183 tools, none slower than 1.4s. The stall also scales with
server *count*, not with any particular server — 1 server gives `mcp_wait_ms: 0`
and a 2.5s turn; 8 give 35s and a 37–97s turn.

So MCP in Grok is currently **pure cost**. Until a build ships where
`tool_count` exceeds 26:

```toml
[compat.claude]
mcps = false
```

Keep the server definitions commented in `config.toml` so re-enabling is one
edit. Your MCP tools still work normally in Claude Code and Hermes.

---

## Corrections to v7.3.0 / v7.3.1

### ~~Rule 1 — never add `[mcp_servers]` to `~/.grok/config.toml`~~ — WRONG

Native `[mcp_servers.*]` sections were added, survived repeated `grok` runs and
`grok inspect` reported them as `source: configToml`. The README documents them
as first-class. The original observation (sections "gone by 20:16") was real but
was attributed to the wrong actor — most likely a `grok update --force-reinstall`
run in the same window, not a routine config rewrite.

### ~~Rule 6 — orphan fleets; run `Clean-Grok-MCP-Orphans.ps1`~~ — WRONG AND HARMFUL

The "orphaned Grok MCP fleet" was **Claude Code's own running MCP servers**. The
processes were children of `claude.exe`, and no Grok process was alive at the
time. The script matched on process name only — every `housecarl-mcp.exe`,
`codebase-memory-mcp.exe`, headroom/forge `python.exe` and `_npx` `node.exe` on
the machine — with no parent check, and its only guard was "no grok.exe running".
Running it while Claude Code or Hermes was open killed their servers.

**`TOOLS/Clean-Grok-MCP-Orphans.ps1` is removed in v7.4.0.** If you copied it
anywhere, delete it. Windows genuinely does not kill children when a parent dies,
but that was never the softlock, and process-name matching is not a safe way to
find one app's children.

### Rules 2–5 — kept, demoted to hygiene

Still true and still worth doing, but none of them was the softlock:

- **Pin every npx server.** Unpinned `npx -y` re-resolves on each spawn. Good
  hygiene; verified pins are `firecrawl-mcp@3.24.0`,
  `@modelcontextprotocol/server-github@2025.4.8`, `@upstash/context7-mcp@4.0.2`,
  `@modelcontextprotocol/server-sequential-thinking@2026.7.4`.
- **Headroom needs the PYTHONPATH-stripping launcher.** Real: a host exporting a
  3.11 `PYTHONPATH` makes the 3.12 `headroom.exe` die importing `click`. Same
  trap class as the Forge venv issue (v7.2.1).
- **codebase-memory daemon.** Port 9749 not listening is worth checking when cbm
  reports unavailable; `version_cohort.claimed_unheld` in its stderr means the
  daemon died and is re-electing.
- **Never force-kill MCP children under a live session.** Restart the client
  instead.

---

## Diagnosis cheat-sheet

| Check | Command / file |
|---|---|
| is the harness or the model slow? | `mcp_wait_ms` and `model_elapsed_ms` in `unified.jsonl` — round numbers mean timeouts |
| are MCP tools reaching the model? | `tool_count` in `shell.turn.tool_prep_done`; **26 means none are** |
| what does Grok actually load? | `grok inspect --json` → `hooks`, `skills`, `mcpServers[].source`, `externalCompat.cells` |
| is a specific server healthy? | pipe `initialize` + `tools/list` into its command directly; healthy = reply < 1.5s |
| whose child is that process? | `Get-CimInstance Win32_Process` and check `ParentProcessId` — **never match on name alone** |
| end-to-end timing | `grok -p "Reply with the single word: OK"`, wall-clock it |

> `grok inspect` lists what was *discovered* on disk, not what is *active*: it
> still reports 14 hooks and 9 MCP servers with both compat cells off. Trust the
> turn timings in the log over the inspect counts.
