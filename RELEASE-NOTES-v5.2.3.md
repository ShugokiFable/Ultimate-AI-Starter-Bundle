# Ultimate AI Starter Bundle v5.2.3

## Fixed

- Removes the instruction to disable the codebase-memory HTTP dashboard. `--ui=false` is no longer a required default for this pack.
- Documents `--ui` and `--port` as **global, persisted** settings stored in the codebase-memory-mcp config itself, shared by every wired AI app — not per-agent MCP options.
- States the rule that follows from that: never put `--ui` or `--port` in MCP `args`. `args = []` remains correct for Claude, Codex, Grok, Kimi, and Hermes.
- Documents the dashboard URL <http://127.0.0.1:9749/> (graph, stats, ADRs; bound to loopback only) and the out-of-band toggle commands.
- Rewrites the `codebase-memory` skill UI section across all 11 copies (5 providers x 2 layouts, plus `_V5-CANONICAL-SKILLS`).
- Rescopes the `install.ps1 --ui` warning to the installer flag that actually causes the Windows "Select an app / Codebase Discovery" dialog.
- Corrects `START-HERE.txt`, which still carried a stale `V5.2.0` title.

## Root cause

The pack shipped two contradictory instructions for one setting. The skills and `START-HERE.txt` said to never enable the HTTP UI and to run `codebase-memory-mcp --ui=false`. The Grok `config.toml` that this same installer writes said the opposite — do *not* pass `--ui=false`, because it would kill the dashboard for the other AI apps.

The Grok comment was right. `--ui` and `--port` persist into codebase-memory-mcp's own configuration rather than into any one agent's MCP entry, so a single `--ui=false` from one provider disables the dashboard for all of them on the next restart. Users following the documented default were switching off a working, loopback-only feature pack-wide, and seeing the dashboard disappear for no visible reason.

The Windows "Select an app / Codebase Discovery" dialog that motivated the original warning is caused by running the upstream `install.ps1 --ui`, not by the dashboard.

## Unchanged

`auto_index=false` and `auto_watch=false` remain required defaults. Indexing is still manual through the `index_repository` tool; the dashboard only visualizes an existing index and never triggers one.
