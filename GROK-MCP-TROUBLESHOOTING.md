# Grok MCP Troubleshooting

Field-tested 2026-08-15 against grok-cli 1.0.4 on Windows. Every entry below caused
real sessions to hang or report MCP servers as unavailable.

---

## Symptom: Grok "hangs" — no reply to a prompt

**Check the log before assuming anything.** `%USERPROFILE%\.grok\logs\unified.jsonl`
records every phase of a turn:

```text
shell.turn.tool_prep_done   {"mcp_wait_ms": 34932, ...}   <- the stall, if any
shell.turn.inference_start
shell.turn.inference_done   {"model_elapsed_ms": 2134}    <- the model itself
```

- If `mcp_wait_ms` is tens of seconds and `inference_done` follows within ~2s:
  **the model is fine — the stall is MCP tool enumeration.** The turn completes;
  cancelling at ~30s kills it one second before the reply streams.
- The model backend answers in ~1-2s when called directly
  (`https://cli-chat-proxy.grok.com/v1/responses`, Bearer = the `key` field of
  the scope entry in `~/.grok/auth.json`).
- Fastest end-to-end check: `grok -p "say ok"` (headless single-turn) and watch
  the log tail.

## Rule 1 — never add `[mcp_servers]` sections to `~/.grok/config.toml`

Grok's config manager **rewrites config.toml and drops user-added MCP sections**
(observed in 1.0.4; sections added at 19:45 were gone by 20:16). The churn also
wedged sessions. Keep all Grok MCP config in the **compat source**
(`~/.claude.json` → `mcpServers`); Grok imports it at session start and does not
own it. `grok mcp list --json` shows only user-scope entries — `[]` is correct.

## Rule 2 — pin every npx server

Unpinned `npx -y <pkg>` re-resolves the registry on each spawn. A cold fetch
past the 30s startup timeout kills the server **before it prints anything**
(0-byte stderr in `~/.grok/logs/mcp/`). Verified pins:

```text
firecrawl-mcp                                  @3.24.0
@modelcontextprotocol/server-github            @2025.4.8
@upstash/context7-mcp                          @4.0.2
@modelcontextprotocol/server-sequential-thinking @2026.7.4
```

## Rule 3 — headroom must run through the PYTHONPATH-stripping launcher

If the host exports `PYTHONPATH` at a different Python version (the Hermes
desktop exports its 3.11 venv), headroom.exe (Python 3.12) crashes on import —
traceback shows `click` loading from the venv's 3.11 site-packages. The server
dies instantly and Grok's tools enumeration never completes. Wire:

```json
"headroom": {
  "command": "<HERMES_HOME>/hermes-agent/venv/Scripts/python.exe",
  "args": ["<state-dir>/tools/headroom-mcp-launch.py"]
}
```

Same trap class as the Forge venv issue (v7.2.1): any Python-3.12 tool dies
under a 3.11 `PYTHONPATH`.

## Rule 4 — codebase-memory daemon keep-alive

The daemon (and its dashboard on 9749) exits when its console closes. The next
MCP spawn then **cold-boots the daemon** — a ~30s stall on the first turn, and
the spawn logs `version_cohort.claimed_unheld` while it waits. Run
`Start-codebase-memory-UI.bat` as a persistent host (one host only), and treat
port 9749 not listening as the first thing to check when cbm is "unavailable".

## Rule 5 — never kill MCP server processes under a live session

Force-killing a server child (even a stuck one) wedges Grok's pipeline:
`/mcps` spins on loading, and prompts log `prompt.enqueue` but never reach the
model. Restart Grok after touching any server process.

## Rule 6 — Grok's server children survive shell close (orphan fleets)

Windows does not kill child processes when the parent dies. Closing a Grok
shell — especially after a softlock — leaves the whole MCP fleet running.
The next session spawns a second fleet that collides with the first:
housecarl waits on its own MO2 lock, codebase-memory on its cohort slot, and
`tools/list` hangs mid-handler → softlock, `/mcps` stuck on loading.

**Fix:** run `TOOLS\Clean-Grok-MCP-Orphans.ps1` after any crashed/softlocked
session (it refuses to run while Grok is alive and keeps the daemon on the UI
port), then start Grok fresh.

## Diagnosis cheat-sheet

| Check | Command / file |
|---|---|
| user-scope servers | `grok mcp list --json` (expect `[]` with compat import) |
| per-server spawn output | `~/.grok/logs/mcp/<name>.stderr.log` — 0 bytes + "unavailable" = died before any output |
| turn phases | grep `mcp_wait_ms`, `inference_done`, `session.create` in `unified.jsonl` |
| standalone server probe | pipe `initialize` + `tools/list` JSON-RPC into each configured command; healthy = tools/list in < 2s |
| model/API health | POST to `cli-chat-proxy.grok.com/v1/responses` with the auth.json `key` |
