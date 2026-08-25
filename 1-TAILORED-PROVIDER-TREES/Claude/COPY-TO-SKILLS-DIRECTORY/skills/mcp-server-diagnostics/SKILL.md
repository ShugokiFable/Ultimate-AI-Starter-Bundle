---
name: mcp-server-diagnostics
description: MCP server hangs, fails, or reads unavailable - handshake checks, provider CLI differences on Windows, path and launcher faults, and per-provider registration repair.
---

# MCP Server Diagnostics

## When to Use

- A client (Grok, Claude Code, Codex, Kimi, Hermes) hangs at session start, "does not reply", or reports an MCP server unavailable
- A server that "used to work" now fails to start or connect
- You changed something (tool update, cleanup, uninstall) and MCP broke after

## Diagnosis Ladder (fastest evidence first)

1. **Client-side evidence.** Find the client's per-server logs before theorizing:
   - Grok: `~/.grok/logs/mcp/<server>.stderr.log` (one file per server; a healthy npx spawn shows `npm notice run ...`; an empty file with a fresh mtime means the process died before printing)
   - Also `~/.grok/logs/unified.jsonl` (`session.create.*` carries `mcp_server_count`)
   - Ask the user what the client UI shows (`/mcps` in Grok). Zero output + "unavailable" ≠ slow start — it is usually an instant death.
2. **Reproduce the spawn manually.** Run the exact configured command with a JSON-RPC `initialize` probe and a timeout:
   `printf '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"probe","version":"1"}}}\n' | timeout 25 <command>`
   Must return JSON, not hang. Also probe `tools/list`.
3. **Check the config the client actually uses.** Precedence differs per client — see `references/providers-windows.md`.
4. **Look for the classic killers** (below), then apply the matching fix.

## Classic Killers & Fixes

| Symptom | Cause | Fix |
|---|---|---|
| Client hangs at start; server stderr empty | Server's interpreter is dead — e.g. a venv whose `pyvenv.cfg home` points into a **deleted provider runtime cache** (`~/.cache/codex-runtimes/...`) | Rebuild the venv from a STABLE interpreter (`py -3.12 -m venv <root>/.venv`), reinstall the package, verify with the initialize probe. Never build venvs from provider runtime pythons. |
| npx server "unavailable", 0-byte stderr | Unpinned `npx -y <pkg>` cold-resolves the latest package; a cold fetch past the client's **30s default startup timeout** kills it silently | Pin the version (`<pkg>@x.y.z`) AND raise `startup_timeout_sec` (Grok default 30; per-server key, or `GROK_MCP_STARTUP_TIMEOUT_SECS` / `MCP_TIMEOUT`) |
| 429 "Too Many Requests" when registering/queueing | Server rate-limits bursts (e.g. codebase-memory `/api/index` accepts only a few queue slots) | Sequential submission + backoff, one at a time, confirm each before the next. Never fire a 40-way parallel burst. |
| Port bind / "single binder" | Two hosts serving one port (e.g. codebase-memory UI on 9749) | Run ONE keep-alive host only. |

## Pitfalls

- **Do not conflate "fresh client session" with "cold package cache".** A warm npx cache starts in ~2s every time; users remember that and will push back if you imply the timeout is the normal startup time. The timeout is an invisible kill-switch that only bites on a genuinely cold fetch.
- Calibrate root-cause confidence. If the user says "it used to be quick" and your theory doesn't match, re-check evidence (logs, cache state) before restating — their memory of behavior is usually accurate.
- An empty stderr log is itself evidence: nothing printed = died before first output (spawn failure), not slow output.
- Verify with the client's own test command where it exists (`hermes mcp test <name>`, `grok mcp list --json`), and remember config changes need a client restart.
- Per-provider config locations, precedence, and env knobs: `references/providers-windows.md`.
- codebase-memory UI/HTTP API quirks (slot-status list, RPC allowlist, re-register recipe): `references/codebase-memory-ops.md`.
