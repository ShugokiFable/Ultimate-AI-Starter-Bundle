# Post-rename MCP path sweep (do not trust your own summary)

Learned on Skyrim-Forge `Skyrim-Forge-5.1.6` → `Skyrim-Forge` (2026-08-20):
claimed "all 8 configs updated", but **Claude Desktop (Store app)** and
**Kimi** still pinned the dead path. The user caught it. Two surfaces get
missed because they're not in the mental model: the Store-app desktop config
(the app does NOT read `~/.claude.json`) and Kimi's `mcp.json`.

## All surfaces that can pin a tool's absolute path

| Surface | File |
|---|---|
| Claude Code | `~/.claude.json` → `mcpServers` |
| **Claude Desktop app** | `claude_desktop_config.json` — glob `%LOCALAPPDATA%\Packages\Claude_*\LocalCache\Roaming\Claude\` (Store install; package folder is hash-suffixed, never hardcode) or `%APPDATA%\Claude\` (normal install) |
| Codex | `~/.codex/config.toml` |
| Grok | `~/.grok/config.toml` → `[mcp_servers.<name>]` (the bundle disables Claude MCP compatibility; inspect both files only on machines that re-enabled it) |
| Kimi | `~/.kimi-code/mcp.json` |
| Hermes | `%LOCALAPPDATA%\hermes\config.yaml` → `mcp_servers` |
| Skill roots | every provider's `~/.<provider>/skills/<tool>/INSTALLATION.json` (Claude, Codex, Grok, Kimi, Hermes) |

## The sweep (run BEFORE claiming success)

```bash
grep -rl '<OLD-TOOL-NAME>' \
  ~/.claude.json \
  ~/.kimi-code/mcp.json \
  ~/.codex/config.toml \
  ~/.grok/config.toml \
  ~/AppData/Local/hermes/config.yaml \
  "$(ls -d ~/AppData/Local/Packages/Claude_*/LocalCache/Roaming/Claude/claude_desktop_config.json 2>/dev/null)" \
  2>/dev/null
# plus: for s in claude codex grok kimi hermes; do
#   grep -l '<OLD-TOOL-NAME>' ~/.$s/skills/*/INSTALLATION.json 2>/dev/null
# done
```

Zero matches = done. Any match = patch that config (backup first, JSON/TOML
schema-aware rewrite, verify `grep -c` returns 0 after).

## Bundle's auto-repair tool

`TOOLS/Repair-McpPaths.ps1` (Ultimate-AI-Starter-Bundle) now:
- scans **6** configs incl. the Claude Desktop Store config (globbed, not
  hardcoded — package folder is hash-suffixed);
- `Resolve-LivePath` falls back to a **bare-stem sibling** when no
  version-stamped folder exists (the "renamed to drop the version suffix"
  pattern) — previously it reported "DEAD (no replacement found)" for an
  unversioned folder;
- run `-Quiet` for a one-line verdict: `All MCP command paths resolve.`

Also fixed in the same session: venv `.pth` — renaming a tool folder breaks
`site-packages/*_local.pth` (records old absolute path); rewrite the single
path line. And: dead husk folders left by in-place installer renames
(`Skyrim-Forge-5.1.6` holding only an empty `Workspaces/`) are safe to delete
after verifying the live folder boots (`python -m <pkg> version`).
