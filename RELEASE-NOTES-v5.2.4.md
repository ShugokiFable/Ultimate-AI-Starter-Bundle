# Ultimate AI Starter Bundle v5.2.4

Follow-up to v5.2.3. That release got the rule right but left out the part that makes it usable.

## Fixed

- Documents how to keep the codebase-memory dashboard running. The page is served **by a codebase-memory-mcp process**, and that process exits as soon as its stdin closes — so a server spawned by an AI app serves the dashboard only while that app stays attached.
- Adds the standalone keep-alive host that ships beside the exe, `Start-codebase-memory-UI.bat`, which holds stdin open so the dashboard survives independently of any AI app.
- Notes that port 9749 has a single binder, so exactly one UI host should run.
- Confirms MCP clients keep `args = []` and coexist with that host.
- Applied to all 11 `codebase-memory` skill copies and `START-HERE.txt`.

## Why this was needed

v5.2.3 correctly identified `--ui` and `--port` as global, persisted state that must never appear in MCP `args`. But following v5.2.3 exactly, the dashboard still appears to work and then vanish — because nothing was holding it open. The missing half was the keep-alive host.

## Verified

The standalone host serving <http://127.0.0.1:9749/> while codebase-memory MCP tool calls continued to succeed against the same index — dashboard and MCP clients coexist.

## Unchanged from v5.2.3

`--ui` / `--port` remain global and persisted; keep them out of MCP `args`. `auto_index=false` and `auto_watch=false` remain required defaults, and indexing stays manual through `index_repository`.
