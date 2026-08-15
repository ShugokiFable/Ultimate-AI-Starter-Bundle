---
name: codebase-memory
description: Use the codebase knowledge graph for structural code queries. Triggers on: explore the codebase, understand the architecture, what functions exist, show me the structure, who calls this function, what does X call, trace the call chain, find callers of, show dependencies, impact analysis, dead code, unused functions, high fan-out, refactor candidates, code quality audit, graph query syntax, Cypher query examples, edge types, how to use search_graph.
---

# Codebase Memory — Knowledge Graph Tools

Graph tools return precise structural results in ~500 tokens vs ~80K for grep.

## Quick Decision Matrix

| Question | Tool call |
|----------|----------|
| Who calls X? | `trace_path(direction="inbound")` |
| What does X call? | `trace_path(direction="outbound")` |
| Full call context | `trace_path(direction="both")` |
| Find by name pattern | `search_graph(name_pattern="...")` |
| Dead code | `search_graph(max_degree=0, exclude_entry_points=true)` |
| Cross-service edges | `query_graph` with Cypher |
| Impact of local changes | `detect_changes()` |
| Risk-classified trace | `trace_path(risk_labels=true)` |
| Text search | `search_code` or Grep |

## Exploration Workflow
1. `list_projects` — check if project is indexed
2. `get_graph_schema` — understand node/edge types
3. `search_graph(label="Function", name_pattern=".*Pattern.*")` — find code
4. `get_code_snippet(qualified_name="project.path.FuncName")` — read source

## Tracing Workflow
1. `search_graph(name_pattern=".*FuncName.*")` — discover exact name
2. `trace_path(function_name="FuncName", direction="both", depth=3)` — trace
3. `detect_changes()` — map git diff to affected symbols

## Quality Analysis
- Dead code: `search_graph(max_degree=0, exclude_entry_points=true)`
- High fan-out: `search_graph(min_degree=10, relationship="CALLS", direction="outbound")`
- High fan-in: `search_graph(min_degree=10, relationship="CALLS", direction="inbound")`

## 14 MCP Tools
`index_repository`, `index_status`, `list_projects`, `delete_project`,
`search_graph`, `search_code`, `trace_path`, `detect_changes`,
`query_graph`, `get_graph_schema`, `get_code_snippet`, `get_architecture`,
`manage_adr`, `ingest_traces`

## Edge Types
CALLS, HTTP_CALLS, ASYNC_CALLS, IMPORTS, DEFINES, DEFINES_METHOD,
HANDLES, IMPLEMENTS, OVERRIDE, USAGE, FILE_CHANGES_WITH,
CONTAINS_FILE, CONTAINS_FOLDER, CONTAINS_PACKAGE

## Cypher Examples (for query_graph)
```
MATCH (a)-[r:HTTP_CALLS]->(b) RETURN a.name, b.name, r.url_path, r.confidence LIMIT 20
MATCH (f:Function) WHERE f.name =~ '.*Handler.*' RETURN f.name, f.file_path
MATCH (a)-[r:CALLS]->(b) WHERE a.name = 'main' RETURN b.name
```

## Gotchas
1. `search_graph(relationship="HTTP_CALLS")` filters nodes by degree — use `query_graph` with Cypher to see actual edges.
2. `query_graph` has a 200-row cap — use `search_graph` with degree filters for counting.
3. `trace_path` needs exact names — use `search_graph(name_pattern=...)` first.
4. `direction="outbound"` misses cross-service callers — use `direction="both"`.
5. Results default to 10 per page — check `has_more` and use `offset`.

---

## V5 install + multi-provider wiring

Upstream: https://github.com/DeusData/codebase-memory-mcp

### Resolve binary

1. `$env:CODEBASE_MEMORY_MCP`
2. `%LOCALAPPDATA%\Programs\codebase-memory-mcp\codebase-memory-mcp.exe`
3. `tool-discovery`

Verify: `codebase-memory-mcp.exe --version`

### Install (MCP stdio; the HTTP dashboard is optional and global)

```powershell
Invoke-WebRequest -Uri https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.ps1 -OutFile install.ps1
Unblock-File .\install.ps1
.\install.ps1
# Run install.ps1 WITHOUT --ui. That installer flag is what triggers the Windows
# "Select an app to open..." / "Codebase Discovery" dialog - not the dashboard itself.
```

**Required defaults for this pack (do not turn these on unless the user asks):**

```powershell
codebase-memory-mcp config set auto_index false
codebase-memory-mcp config set auto_watch false
```

### The dashboard (`--ui`, `--port`) is GLOBAL, shared state

`--ui` and `--port` are **persisted into the tool's own config**, not into any one agent's
MCP entry. Every agent shares a single setting. Passing `--ui=false` from one provider
therefore turns the dashboard off for **all** of them on the next restart. This is the
single most common way the dashboard "randomly" disappears.

- **Never put `--ui` or `--port` in MCP `args`.** Keep `args = []` in every provider config.
- Toggle it once, out of band:

```powershell
codebase-memory-mcp --ui=true     # enable dashboard (persisted globally)
codebase-memory-mcp --ui=false    # disable dashboard (persisted globally)
codebase-memory-mcp --port=9749   # change port (persisted globally)
```

- Dashboard: <http://127.0.0.1:9749/> (graph, stats, ADRs). It is served by the
  codebase-memory-mcp process itself and binds to loopback only.

### Keeping the dashboard up

The dashboard is served **by a codebase-memory-mcp process**, and that process exits as soon
as its stdin closes. A server started by an MCP client therefore serves the dashboard only
while that client is attached - the page goes dead the moment the client disconnects or the
app restarts. This is why the dashboard seems to work and then vanish for no reason.

For a dashboard that stays up, run one standalone keep-alive host, which holds stdin open:

```powershell
& "$env:LOCALAPPDATA\Programs\codebase-memory-mcp\Start-codebase-memory-UI.bat"
```

Run **one** UI host only - port 9749 has a single binder. MCP clients keep `args = []` and
coexist with that host normally; they never need to own the dashboard themselves. Verified:
the standalone host serves <http://127.0.0.1:9749/> while MCP tool calls keep working.

Indexing is still manual either way: agents call `index_repository` when needed. The
dashboard only visualizes what is already indexed; it never triggers an index.

### Grok Build MCP block (example — edit path)

```toml
[mcp_servers.codebase-memory-mcp]
command = "C:/Users/<YOU>/AppData/Local/Programs/codebase-memory-mcp/codebase-memory-mcp.exe"
args = []
enabled = true
startup_timeout_sec = 90
tool_timeout_sec = 6000
```

Pack helper (edit paths first): `TOOLS/Fix-Grok-Codebase-Memory-Direct.ps1`

### If MCP tools are missing

- Recommend install + provider MCP registration + full restart
- Fallback: ordinary search/grep tools; do not fake graph results

### Usage reminder

Prefer graph tools for structural questions (callers, callees, dead code). Index the repo first (`index_repository` / project list) when empty.
