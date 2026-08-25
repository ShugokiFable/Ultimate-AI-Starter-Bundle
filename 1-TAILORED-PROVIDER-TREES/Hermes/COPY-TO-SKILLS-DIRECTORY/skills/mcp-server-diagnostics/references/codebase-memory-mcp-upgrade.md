# codebase-memory-mcp: Windows binary upgrade (verified 0.10.5 → 0.10.8)

Data survives upgrades — graphs live in `%USERPROFILE%\.cache\codebase-memory-mcp\`,
NOT next to the exe. Verified: after swap, `52 projects, 165,982 nodes` reported
byte-identical to pre-upgrade.

## Procedure

1. **Check current version**: `<install>\codebase-memory-mcp.exe --version`
   (install root: `%LOCALAPPDATA%\Programs\codebase-memory-mcp\`).
2. **Check upstream** (no browser needed — Firecrawl may be unconfigured):
   ```bash
   curl -s https://api.github.com/repos/DeusData/codebase-memory-mcp/releases?per_page=5
   ```
   Release notes are the source of truth for what changed; the dashboard-tiles issue
   #1663 was STILL OPEN in v0.10.8 — do not promise an upgrade fixes it.
3. **Kill ALL running instances first.** A running exe is locked on Windows;
   replacing it fails with `PermissionError: [Errno 13]`. In git-bash,
   `taskkill //F //IM name.exe` breaks (MSYS mangles `//F` into a bad flag). Use:
   ```bash
   powershell -NoProfile -Command "Stop-Process -Name codebase-memory-mcp -Force"
   ```
   This kills MCP-spawned instances AND the UI host; the next MCP call cold-spawns
   the new binary automatically.
4. **Back up the old exe** before overwriting:
   `copy codebase-memory-mcp.exe codebase-memory-mcp.exe.bak-<oldver>`
5. **Grab the release zip** — asset name `codebase-memory-mcp-windows-amd64.zip`,
   which contains `codebase-memory-mcp.exe`, `install.ps1`, LICENSE, notices.
   Extract just the exe over the install dir (python zipfile works).
6. **Restart the UI host DETACHED.** A foreground or `timeout 10 ... --ui=true` run
   dies with the shell and the port vanishes. The exe spawns a daemon child that
   actually holds port 9749 (log line `version_cohort.claimed_unheld` is NORMAL here).
   Working launch:
   ```bash
   powershell -NoProfile -Command "Start-Process -FilePath 'C:\Users\<YOU>\AppData\Local\Programs\codebase-memory-mcp\codebase-memory-mcp.exe' -ArgumentList '--ui=true' -WorkingDirectory 'C:\Users\<YOU>\AppData\Local\Programs\codebase-memory-mcp'"
   ```
   (`cmd //c start` from git-bash did NOT keep it alive; Start-Process did.)
7. **Verify**: `--version` shows new build; `netstat -ano | grep 9749.*LISTEN`;
   then RPC totals (see pagination note below).

## v0.10.8+ list_projects is PAGINATED (upstream #1181)

The lean default caps at 50 projects and omits per-project `nodes`/`edges` —
parsing it throws `KeyError: 'nodes'`. Pass the full-view args:

```bash
curl -s -X POST http://127.0.0.1:9749/rpc -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"list_projects","arguments":{"include_details":true,"limit":100}}}'
```

Same for PowerShell: `Invoke-RestMethod` with the same body. This ALSO means the
user-owned `codebase-memory` skill's old dashboard-honesty snippet (no
`include_details`) is stale on 0.10.8+.
