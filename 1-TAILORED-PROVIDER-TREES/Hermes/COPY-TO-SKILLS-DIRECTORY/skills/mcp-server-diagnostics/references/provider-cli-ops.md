# Provider CLI and MCP operations on Windows

Operating and debugging the multi-provider AI tooling stack on this Windows machine:
Claude Code, Codex, Grok CLI, Kimi, Hermes, and their MCP servers (houseCARL,
skyrim-forge, codebase-memory, headroom, firecrawl, context7, and github).

## When to Use

- An AI provider "hangs", "won't reply", or shows MCP servers as unavailable
- A new MCP server or tool needs to be wired into one or all providers
- A provider CLI misbehaves after an install, upgrade, or cleanup
- The Ultimate-AI-Starter-Bundle needs a version bump + GitHub release
- codebase-memory dashboard or indexing misbehaves

## Workflow law (user-corrected, twice)

**Evidence order: direct measurement > runtime logs > the user's observed history > theory.**
The user's "it used to work and was quick" is evidence — when a symptom starts
after a change, revert-test that change FIRST instead of inventing a latency theory.
Never present a mechanism as fact until a probe or log line confirms it.

## Provider MCP config map (bundle defaults)

| Provider | Config file | Notes |
|---|---|---|
| Claude Code | `~/.claude.json` → `mcpServers` | Upstream Grok can import this, but the bundle disables that compatibility cell and wires Grok natively |
| **Claude Desktop app** | `claude_desktop_config.json` — normal install `%APPDATA%\Claude\`, **Store/MSIX install `%LOCALAPPDATA%\Packages\Claude_*\LocalCache\Roaming\Claude\`** | The app does NOT read `~/.claude.json` for its own MCP; code/cowork sessions run a bundled Claude Code that does. Schema: `command`/`args`/`env`, no `type`. Write BOTH files for CLI + app coverage |
| Codex | `~/.codex/config.toml` → `[mcp_servers.X]` | `startup_timeout_sec` supported |
| Kimi | `~/.kimi-code/mcp.json` | JSON, walk for entries |
| Hermes | `hermes config path` → `config.yaml` `mcp_servers` | safe YAML merge, never hand-edit blindly |
| Grok | `~/.grok/config.toml` → `[mcp_servers.<name>]` | Native sections persist. The bundle sets `[compat.claude] mcps = false`, so discovered Claude entries are not active |

All `npx`-based servers must be **version-pinned** in every config
(`firecrawl-mcp@3.24.0`, `@upstash/context7-mcp@4.0.4`,
`@modelcontextprotocol/server-sequential-thinking@2026.7.4`). GitHub is the
bundle's official versioned binary, not an npm reference server. Unpinned npx
entries cold-resolve on first spawn and can blow past a 30s startup timeout.

## Verification protocol (do this BEFORE touching config)

For any "server unavailable" report, spawn each configured server standalone
and time `initialize` + `tools/list` — use the bundle's
`TOOLS\Test-McpHandshake.ps1` or this skill's `scripts/probe_mcp_servers.py`.
A server that dies instantly (0-byte stderr log) or hangs is the culprit;
"unavailable" can also be collateral of one wedged server blocking the
client's tool enumeration.

Per-server stderr logs: `~/.grok/logs/mcp/<name>.stderr.log` (empty file =
spawned but produced nothing = suspicious; healthy npx servers print npm
notices). Grok turn timing: `~/.grok/logs/unified.jsonl` — a turn that stalls
shows `shell.turn.tool_prep_done {mcp_wait_ms: N}`; large `mcp_wait_ms` =
tool prep stall, NOT a model problem (model inference itself is ~2s).

## Top failure modes (with fixes)

1. **PYTHONPATH poison** — the Hermes desktop exports its venv (Py3.11)
   site-packages; any Py3.12 tool spawned from that environment crashes on
   import (`click`, `pydantic_core`, ...). Fix: launcher script that strips
   `PYTHONPATH` (`%LOCALAPPDATA%\<your-tools-root>\headroom-mcp-launch.py`),
   wired as the MCP command.
2. **Venv built from a provider runtime cache** (`~/.cache/codex-runtimes/...`)
   — dies when the cache is deleted; MCP clients hang at startup. Fix: rebuild
   the venv with a stable interpreter + `pip install <root>` (skyrim-forge has
   zero deps and a local build backend).
3. **Zombie probe processes hold locks** — killing an MCP server mid-session
   wedges the client pipeline; a killed probe can leave a child holding a lock
   that hangs the next real spawn (housecarl `tools/list` stuck). Kill strays
   before diagnosing, and never kill a provider's live children while it runs.
4. **codebase-memory daemon death** — MCP sessions log
   `version_cohort.claimed_unheld` and hang; the daemon re-claims on next
   spawn (port 9749). See `references/codebase-memory-mcp.md`.
5. **Renaming a tool install folder breaks its venv** — a venv's
   `site-packages/*_local.pth` records the OLD absolute path; after renaming
   (e.g. `Skyrim-Forge-5.1.6` → `Skyrim-Forge`) the module import fails
   (`module not found` in `sys.path` points at the dead path). Fix: rewrite
   the `.pth` to the new path. MCP configs (`~/.claude.json`, `config.toml`,
   skill `INSTALLATION.json` roots) all pin the old path too — update every
   provider config after any folder rename.
6. **Manifest/CRLF CI trap (SkyrimForge)** — `MANIFEST.json` hashes must
   match a clean CI checkout. Local working trees with CRLF text (or a
   rebuilt binary) produce a manifest that fails CI + the
   `test_manifest_verifies_against_the_delivered_tree` test. Fix in repo:
   `manifest()` hashes `git_normalized()` bytes (LF for text, raw for
   `.ps1`/`.bat`/binaries detected by magic bytes). NEVER regenerate the
   manifest from a dirty/CRLF tree, and never let build outputs (`dist2/`,
   `dist3/`) get tracked — they're gitignored only as `dist/`.

## References

- `references/windows-mcp-spawn-pitfalls.md` — PYTHONPATH, venv traps, npx pinning, shell quirks (MSYS taskkill/`$_`/Popen)
- `references/grok-cli.md` — config-manager rewrites, compat import, logs, `/mcps`, `-p` quirks, tool-prep stalls
- `references/codebase-memory-mcp.md` — daemon/cohort, UI RPC lockdown (issue #1663), `/api/index` slots, re-registration
- `references/bundle-release-protocol.md` — bumping + releasing Ultimate-AI-Starter-Bundle (6 version-string spots, MANIFEST-last ordering, tag/release recreate, fresh-install invariants)

## Scripts

- `scripts/probe_mcp_servers.py` — timed standalone initialize+tools/list probe for any server list
