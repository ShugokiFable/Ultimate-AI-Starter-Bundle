# Grok MCP: the 8-server cliff and the disabled list (verified 2026-08-19)

## Corrected belief (the old "never edit config.toml" note was wrong)

Native `[mcp_servers.*]` sections in `~/.grok/config.toml` **persist and load**
(`grok mcp list` reads them; `grok inspect --json` shows source `configToml`).
`[compat.claude] mcps = false` blocks the `~/.claude.json` import at RUNTIME,
but `grok inspect` still lists claudeJson-sourced servers as *discovered* —
discovery ≠ active. The bundle's `TOOLS/MCP-CONFIG-EXAMPLES.toml.txt` says the
same ("the older 'grok rewrites them' note was wrong").

## The 8-running-server cliff (hard wedge)

- 8 running MCP servers = Grok wedges: `mcp_wait_ms` ~34,900, process never
  exits, no reply. 7 fine. Authoritative doc: bundle
  `GROK-MCP-TROUBLESHOOTING.md` (v7.4.3 corrections).
- Running count = configured `[mcp_servers.*]` + **plugin-provided servers**.
  claude-mem's `mcp-search` loads via Claude-code plugin compat even with
  `mcps = false` — it is the classic free-rider. It is deadweight under Grok:
  `[compat.claude] hooks = false` means claude-mem's capture hooks never run,
  so mcp-search points at a DB Grok never writes to.
- Budgets: **7 configured** once the plugin server is disabled, **6 while it
  loads**.
- Evidence, fastest first:
  - `~/.grok/logs/unified.jsonl`: `session.create.*` ctx carries
    `mcp_server_count` (over the cliff = wedge), `shell.turn.tool_prep_done`
    carries `mcp_wait_ms` (large = tool-prep stall, not model latency).
  - `grok inspect --json` → `mcpServers[]` with `source` per server:
    `configToml` | `claudeJson` (discovery-only when mcps=false) | `plugin`
    (carries `plugin_name`).
  - `~/.grok/logs/mcp/<name>.stderr.log` per server.

## Fixes

- Disable a plugin/compat server for Grok ONLY (Claude Code keeps it):
  `grok mcp disable <name>` → persists `disabled_mcp_servers = [...]` in
  `~/.grok/config.toml`; known names include plugin and `.mcp.json` servers.
  `grok mcp enable <name>` reverses. Unknown names exit 1.
- Or trim `[mcp_servers.*]` to 6. On this machine the working 7 are:
  housecarl, skyrim-forge, codebase-memory-mcp, firecrawl-mcp, context7,
  github, headroom.
- Any config edit: verify with a REAL one-shot call, never `tool_count`:
  `grok --always-approve -p "use search_tool to discover MCP tools, then use_tool to call <server>__<tool>"`.
  A completed reply = healthy. ~20-50s, exits 0.

## Zombie MCP server cleanup (stale version after an upgrade)

Before killing a stale server process (e.g. an old Forge version still running
under a gateway): prove the broker talks to the NEW server by calling the MCP
tool yourself (e.g. `forge_version` returns the new version). Only then is the
old one dead weight and safe to `taskkill /PID <pid> /F` (single slash — MSYS
path conversion is off on this box; `//PID` is rejected). Windows lets you
delete a running executable's folder, so kill first, then delete.
