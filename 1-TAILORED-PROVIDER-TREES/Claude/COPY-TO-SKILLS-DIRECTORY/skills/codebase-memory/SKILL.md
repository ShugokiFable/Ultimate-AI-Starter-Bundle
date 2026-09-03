---
name: codebase-memory
description: Use when exploring a codebase graph, tracing callers/dependencies, finding structure or dead code, or indexing/re-indexing codebase-memory.
---

# Codebase Memory — Knowledge Graph Tools

Graph tools return precise structural results in ~500 tokens vs ~80K for grep.

**Two halves to this skill.** Querying (below) is easy. **Indexing is where it goes
wrong** — a careless `index_repository` on a Skyrim mod tree produces a 200,000-node
graph of animation files that costs tokens on every query and answers nothing. Read
"Indexing discipline" before your first `index_repository` on any repo.

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
| Did the graph cover the source tree? | `check_index_coverage()` |
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

## 15 MCP Tools
`index_repository`, `index_status`, `list_projects`, `delete_project`,
`search_graph`, `search_code`, `trace_path`, `detect_changes`,
`query_graph`, `get_graph_schema`, `get_code_snippet`, `get_architecture`, `check_index_coverage`,
`manage_adr`, `ingest_traces`

Measured on 0.10.8 (2026-09-03): 23,974 schema bytes, about 5,994 tokens on
every turn while connected. Use Claude/Grok project scope or Hermes' native
`code` profile; do not register it globally just because the executable exists.

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

## Query Gotchas
1. `search_graph(relationship="HTTP_CALLS")` filters nodes by degree — use `query_graph` with Cypher to see actual edges.
2. `query_graph` has a 200-row cap — use `search_graph` with degree filters for counting.
3. `trace_path` needs exact names — use `search_graph(name_pattern=...)` first.
4. `direction="outbound"` misses cross-service callers — use `direction="both"`.
5. Results default to 10 per page — check `has_more` and use `offset`.

---

# Indexing discipline

## What this tool cannot parse

**Papyrus (`.psc`) is never indexed.** There is no tree-sitter grammar for it. Worse,
the indexer also skips directories named `scripts/` via a built-in skip-list — exactly
where Skyrim keeps `Scripts/Source/*.psc`. Verified on a real project: 309 `.psc` files,
and `get_architecture(aspects=["languages"])` reported PHP/YAML/JS/Python and no Papyrus.

Consequences you must respect:

- **Never** answer a Papyrus question with `search_graph` / `search_code` / `trace_path`.
  Use Grep plus the `papyrus-reference` skill.
- A Papyrus-only mod indexing to 2–50 nodes is **correct, not broken**. Do not "fix" it
  by loosening ignores; you will only add asset noise.
- The graph is genuinely useful for C, C++, C#, Python, TypeScript/JS, Go, PHP, Ruby,
  and for file/document structure. That covers SKSE plugins and your tooling — not
  Papyrus mod logic.

## `.cbmignore` matching is CASE-SENSITIVE

This is the single easiest way to silently ship a bloated index. `meshes/` does **not**
match `Meshes/`. Skyrim conventionally capitalizes `Meshes`, `Textures`, `Sound`,
`Interface`. A lowercase-only ignore list leaks entire asset trees into the graph.

Real case: a mod leaked 236 JSON files from a capitalized `Meshes` directory and carried
18,067 nodes for 13 source files, until both cases were listed.

**Always write both cases.** Use the shipped template rather than hand-rolling:
`COPY-TO-YOUR-WORKSPACE/_PROJECT-TEMPLATE/.cbmignore`, or generate and verify with
`TOOLS/Setup-CodebaseMemory-Index.ps1`.

## The four bloat sources

| Source | What it looks like | Fix |
|--------|--------------------|-----|
| Vendored dependencies | 3,471 of a project's 3,964 headers sat in `extern/` (CommonLibSSE) | ignore `extern/ external/ vcpkg_installed/ node_modules/ build/ dist/ obj/` |
| Version snapshots indexed N times | one project kept 34 full copies of itself, another 23 | keep only the `CURRENT.txt` version; ignore the rest |
| Binary assets counted as nodes | an anim/mesh tree alone was 235,567 nodes | ignore `Meshes/ Textures/ Sound/ *.nif *.hkx *.dds *.esp *.pex *.bsa` (both cases) |
| Vendored single-header libs | `SKSEMenuFramework.h` produced ~2,400 of 2,648 "functions", duplicated per patch folder | ignore the header by filename |

Measured effect of applying all four across a 45-project index:
**~570,000 nodes → 54,553**, while covering *more* projects.

## Versioned workspaces (`skyrim-versioned-workspace`)

A mod project root holds many `Mod Name X.Y.Z/` snapshots. Indexing them all multiplies
every file by the snapshot count. Resolve the active one from `CURRENT.txt` and ignore
the others.

**Do not blindly exclude every older snapshot.** Where the active version is a *packaged
release*, the source often lives only in an older folder. Before excluding, check that
the version you keep actually contains source; if it has none (or no compiled-language
source at all) keep the snapshot that does, and record why.

Observed real exceptions — the active version shipped as a package and the source lived
in an older snapshot:

- active `1.0.8` had zero C++; `1.0.0` held the only 13 source files
- active `1.5.1` had zero code files; `-1.5.1-source` held them
- active `0.8.5` had 2 source files; `0.7.0` held 45

`TOOLS/Setup-CodebaseMemory-Index.ps1` implements this check.

## Never index

| Path | Why |
|------|-----|
| Mod-manager staging (Vortex/MO2 `mods/`) | thousands of asset folders, ~90,000 nodes, stale after every mod change. `houseCARL` already answers installed-mod and conflict questions from live truth. |
| Game `Data` as sole authority | the manager deploys it; use the owner project |
| Tool install trees, `WindowsApps`, `C:\WINDOWS\System32` | noise, never project memory |
| Agent session dumps under `.claude` / `.grok` | not authority |
| Bundled reference corpora (large `corpus.json`, `*.jsonl`) | served through skills; one 6.43 MB corpus alone cost ~15,000 nodes |
| A thin whole-workspace root graph | prefer one graph per owner project |
| `auto_index` stays OFF | verified trap: one MCP handshake from a scratch directory indexed `%TEMP%` as its own project within seconds. Indexing is a deliberate act. |

## Secrets and hostile filenames

- **Exclude `.env` and `.env.*` everywhere.** A graph is queryable; API keys and bot
  tokens must not enter it. The template does this.
- **A file literally named `nul` breaks the indexer.** It is a reserved Windows device
  name; `index_repository` fails with a bare "Pipeline failed" and no useful log. Such
  files come from a botched `... > nul` redirect. Delete the stray file (verify the
  content first — it is junk) and the project indexes normally.
- If an index fails with "Pipeline failed", suspect a reserved name (`nul`, `con`,
  `aux`, `prn`, `com1`) before you suspect the repo.

## Indexing procedure

```text
index_repository(repo_path=<owner project root>, mode=moderate, name=<stable-slug>)
```

1. Write `.cbmignore` at the project root **before** the first index.
2. Index the **owner project root**, one graph per project, with a stable `name=` slug.
3. Read the response: `excluded` proves your ignores fired; `not_indexed_files` shows
   what was dropped and why (`cbmignore`, `gitignore`, `skip-list`, `ignored-suffix`).
4. **Sanity-check the node count against the file count.** 18,000 nodes from 13 source
   files means something leaked. Investigate before moving on.
5. Verify with a real query, not just a node count:
   `get_architecture(aspects=["languages"])` — if the languages you expect are missing,
   your ignores are wrong (or the language is unparsed, see Papyrus above).

MCP only — never `Start-Process` the exe, never pass `--ui` in MCP `args`.
Re-indexing is idempotent; run it again after large structural changes.

## Reading the dashboard honestly

The Projects tab's **NODES / EDGES tiles read 0** even on a healthy index. As of
v0.10.5 the HTTP UI RPC allowlist permits only `list_projects`; the SPA's per-project
`get_graph_schema` calls are rejected with 403 `UI RPC method is not allowed`, so the
tiles sum zero (upstream issue #1663). MCP-tool access is unaffected — verify via
`list_projects` below. Only the PROJECTS tile is a real total. This is cosmetic;
**do not diagnose it as data loss.**

Confirm real totals from the same endpoint the UI calls:

```powershell
$r = Invoke-RestMethod -Uri http://127.0.0.1:9749/rpc -Method Post -ContentType 'application/json' -Body '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"list_projects","arguments":{}}}'
$p = ($r.result.content[0].text | ConvertFrom-Json).projects
"{0} projects, {1} nodes, {2} edges" -f $p.Count, ($p | Measure-Object nodes -Sum).Sum, ($p | Measure-Object edges -Sum).Sum
```

Per-project health uses **`?name=`**, not `?project=` (the latter returns 400):
`http://127.0.0.1:9749/api/project-health?name=<Project>`

In PowerShell, `curl` is an alias for `Invoke-WebRequest` and does **not** accept
`-H` / `-d`. Use `Invoke-RestMethod` as above.

### Working fix on this machine (v7.9.8.5 field note)

`%LOCALAPPDATA%\Ultimate-AI-Starter-Bundle\tools\cbm-dashboard-plus.py` is a same-origin loopback
proxy on **http://127.0.0.1:9751/** serving the stock dashboard plus injected real
totals, per-project nodes/edges and language badges — it exists precisely because of
#1663. Prefer it for human dashboarding; autostarts at login. Upstream rejects any
foreign-origin page reading those endpoints (DNS-rebinding defense), which is why the
fix must be same-origin rather than a userscript.

### Issue #1764: do not trust its root cause

The idle-CPU burn (~0.6 core per idle client on Windows) was attributed upstream to two
10 ms maintenance observers walking the file-lock path. That attribution **failed an A/B
repro**: a geometric-backoff patch of exactly those observers was built from source with
no improvement over stock while idle, and the burn reproduces only on roughly half of
spawns, always as one hot thread. Treat #1764 as unsolved and unattributed; do not cite
the observer theory or claim any shipped fix.

## The index has no backup

Project graphs live under `%USERPROFILE%\.cache\codebase-memory-mcp\`. Deleting a project
from the dashboard is immediate and unrecoverable — there is no undo and no automatic
backup. What makes a rebuild cheap is a **written registry** of what was indexed and why.

Keep one (the `skyrim-memory` vault does this at
`locations/CODEBASE-MEMORY-PROJECTS.md`) recording per project: MCP name, root path,
node count, and the "not indexed / why" table. Refresh it after bulk index or delete.
Optionally set `persistence=true` on `index_repository` to write a shareable
`.codebase-memory/graph.db.zst` artifact into the project.

---

## Install + multi-provider wiring

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

**Cold-daemon stall:** if the daemon is down (port 9749 not listening), the next MCP spawn
cold-boots it and the first turn can stall ~30s; the spawn logs
`version_cohort.claimed_unheld` while waiting. Keep the host bat running at login to avoid
the per-boot penalty. If a client reports cbm "unavailable", check the port first.

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

Prefer graph tools for structural questions (callers, callees, dead code). Index the repo
first when the project list is empty — and write `.cbmignore` before you do.
