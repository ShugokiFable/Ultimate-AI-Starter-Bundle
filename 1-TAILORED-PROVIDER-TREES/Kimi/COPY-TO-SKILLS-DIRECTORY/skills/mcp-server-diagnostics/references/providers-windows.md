# MCP config per provider (Windows, verified 2026-08)

| Client | Config file | Section | Test command | Notes |
|---|---|---|---|---|
| Hermes | `%LOCALAPPDATA%\hermes\config.yaml` (from `hermes config path`) | `mcp_servers:` | `hermes mcp test <name>` | `args: []` for local stdio tools; safe YAML merge (backup first) since `hermes mcp add` needs a TTY |
| Claude Code | `~/.claude.json` | `mcpServers` | — | The SHARED source other clients import |
| Codex | `~/.codex/config.toml` | `[mcp_servers.<name>]` | — | Supports `startup_timeout_sec` |
| Kimi | `~/.kimi-code/mcp.json` | nested server objects | — | — |
| Grok | `~/.grok/config.toml` | `[mcp_servers.<name>]` | `grok mcp list --json` | **User TOML beats the compat import from `~/.claude.json`.** Grok's own list may show `[]` while sessions still import 8 servers from claude.json — define servers explicitly in the TOML to take control. |

## Grok specifics

- Default `startup_timeout_sec = 30` per server; env overrides: `GROK_MCP_STARTUP_TIMEOUT_SECS` (seconds) or Claude-compatible `MCP_TIMEOUT` (milliseconds).
- Per-server stderr: `~/.grok/logs/mcp/<name>.stderr.log` (touched per session; healthy npx shows `npm notice run ...`; empty = instant death).
- `grok -p` headless single-turn is unreliable for verification (shell gate + OIDC auth-refresh stalls produce no output). Prefer `grok mcp list --json` + manual spawn probes.
- Grok keeps `permission_mode`/`ui` settings in the same TOML; append `[mcp_servers.*]` sections at the end, back up first.

## The provider-runtime venv trap (Forge case study)

Skyrim Forge 5.0.2 → 5.1.0 created the 5.1.0 venv FROM the 5.0.2 venv, whose base was the Codex runtime python (`pyvenv.cfg home = C:\Users\<u>\.cache\codex-runtimes\...`). Deleting the Codex runtime killed BOTH venvs; `python -m skyrim_forge mcp` printed `No Python at '...codex-runtimes...'` and Grok hung at session start.

- Diagnosis: `cat <root>/.venv/pyvenv.cfg` — if `home =` points into a cache dir, it's a zombie.
- Repair (zero-dep package): `py -3.12 -m venv "<root>/.venv"` then `"<root>/.venv/Scripts/python.exe" -m pip install "<root>"`.
- Editable installs can fail on custom build backends without PEP 660 (`build_editable` hook) — fall back to plain `pip install <root>` (Forge's local `forge_build_backend` needs no network).
- After repair: always re-verify with the JSON-RPC initialize probe; a clean `initialize` + `tools/list` response is the bar.

## Firecrawl cold-start case study

Unpinned `npx -y firecrawl-mcp` + lost npm cache + heavy machine load (re-index storm) = cold fetch > 30s → Grok killed it before first output (0-byte stderr). User memory: it "always started quick" — true, because the cache was warm; fresh sessions do NOT refetch, only cold caches do. Fix: pin (`firecrawl-mcp@3.24.0`) + `startup_timeout_sec = 120` + warm the cache once manually. Verified fast spawn afterward (~2s).
