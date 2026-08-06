# Ultimate AI Starter Bundle - changelog

**Rename (v5.2.0 branding):** this pack is no longer titled "Skyrim AI only".
It is the **Ultimate AI Starter Bundle** - multi-provider AI toolkit with an
optional deep Skyrim SE/AE stack. Repo/folder names may still say V5 for history.

Date: 2026-07-31  
Base: Skyrim-AI-FINAL-MANUAL-INSTALL-v4.3.0

## Goals

1. Integrate new AI/Skyrim tools into the skill pack for every supported provider.
2. Keep paths portable: discover tools or recommend install — never require the pack author's drive letters.
3. Preserve V4.3 registry, validators, and safety laws.

## Added skill families

### houseCARL ecosystem
- `housecarl` (multi-provider discovery + MCP notes)
- `mutagen-reference`, `papyrus-reference`, `papyrus-optimization`
- `spid-authoring`, `kid-authoring`, `skypatcher-authoring`, `oar-authoring`
- `dialogue-authoring`, `facegen-diagnostics`, `biped-slot-reference`
- `bulk-record-jobs`, `skse-plugin-authoring`, `tool-output-awareness`

### Spooky's AutoMod Toolkit
- `spookys-automod-toolkit` (root + references from toolkit docs)
- Module skills: `skyrim-esp`, `skyrim-papyrus`, `skyrim-mcm`, `skyrim-nif`, `skyrim-archive`, `skyrim-audio`, `skyrim-skse`

### AI coding utilities
- `codebase-memory` (DeusData MCP + Grok wiring notes)
- `headroom` (context compression MCP)
- `using-superpowers` + Superpowers process skills (brainstorming, systematic-debugging, TDD, plans, verification, …)
- `ponytail` + ponytail-review/audit/debt/gain/help
- `codeburn` (local token/cost analytics)

### Pack orchestration
- `ai-tooling-stack` — when to use which tool
- `tool-discovery` + `scripts/discover_tools.ps1`
- `skyrim-forge` refreshed from live skill (no machine-specific INSTALLATION.json shipped)

## Pack root additions

- `TOOLS/discover_tools.ps1`
- `TOOLS/Fix-Grok-Codebase-Memory-Direct.ps1` (portable; discovers exe)
- `TOOLS/MCP-CONFIG-EXAMPLES.toml.txt`
- `TOOLS/RECOMMENDED-INSTALLS.md`
- `_V5-CANONICAL-SKILLS/` master tree used to fan out to providers
- `V5-CHANGELOG.md`, `V5-INTEGRATION-AUDIT.md`

## Router / instructions

- `skyrim-tool-router` rewritten for V5 routes (houseCARL, Spooky, MCP utils).
- All `AGENTS.md` / `CLAUDE.md` gain **V5 tooling laws**.
- `START-HERE.txt`, `WINDOWS-PATH-MAP.md` updated.
- Provider `COPY-MAP.md` files note MCP + discovery steps.

## Counts

- V4.3 tailored skills per provider: **34**
- V5 skills per provider: **~82**
- Provider skill roots updated: **10** (5 tailored + 5 generic)

## Non-goals / intentional limits

- Does not redistribute houseCARL or Spooky **binaries** (licensing + size); skills + install guidance only.
- Does not embed Bethesda script headers.
- Does not assume MO2 path; user must set instance.
- Superpowers/Ponytail plugins remain optional; markdown skills work standalone.
- CodeBurn is optional analytics, not a mod compiler.

## Upgrade from v4.3.0

1. Keep v4.3 folder as backup.
2. Copy V5 provider skills over the old skills directory (overwrite).
3. Refresh workspace `AGENTS.md` / `CLAUDE.md`.
4. Run `TOOLS\discover_tools.ps1` and install anything you want from MISSING.
5. Re-register MCP servers; fully restart each AI app.

## V5.0.0 add-on — houseCARL auto setup

- `TOOLS\Setup-HouseCarl.ps1` — one-shot MO2 detection or Vortex shim build
- `TOOLS\housecarl\houseCARL-Vortex-shim-setup.pdf` — shim design reference
- `TOOLS\housecarl\README.md` — operator guide
- `housecarl\scripts\Setup-HouseCarl.ps1` copied into every provider skill tree
- Env + Grok MCP wiring + `%LOCALAPPDATA%\houseCARL-data\v5-setup-state.json`
- `discover_tools.ps1` reports `housecarl-instance` (MO2-INSTANCE | VORTEX-SHIM)

## V5.0.0 AIO layer

- `INSTALL-V5-AIO.ps1` / `INSTALL-V5-AIO.bat` — one-shot skills + tools + MCP + houseCARL setup
- `BUNDLED-TOOLS\offline\` — houseCARL, Spooky, codebase-memory, Headroom wheel, Superpowers, Ponytail
- `BUNDLED-TOOLS\plugins\` — ready Superpowers + Ponytail trees
- `BUNDLED-TOOLS\CATALOG.json` — GitHub repos + install rules
- `TOOLS\Update-From-GitHub.ps1` — releases/latest fetch
- `TOOLS\Ensure-Tools.ps1` — agent/user repair helper
- `TOOLS\V5-Common.ps1` — shared installer library
- `V5-AIO-GUIDE.md` — user + AI contract

## v5.0.0 post-publish hotfix (codebase-memory safety)

Date: 2026-07-31

### What went wrong
The AIO installer used `robocopy` to force-extract `codebase-memory-mcp` into
`%LOCALAPPDATA%\Programs\codebase-memory-mcp` even when the MCP was already
installed and running. A locked binary + aggressive MCP rewires could break
Grok/Codex/Claude wiring and force a manual reinstall + `Fix-Grok-Codebase-Memory-Direct.ps1`.

### Fixes in this pack
1. **Keep existing install**: if `codebase-memory-mcp.exe` is already discoverable
   (prefer `Programs\codebase-memory-mcp\`), the installer **does not overwrite** it.
2. **Locked-file guard**: `Copy-V5RoboSafe` / `Test-V5FileLocked` refuse to replace
   a running MCP binary.
3. **Grok MCP upsert is idempotent**: `-SkipIfPresent` leaves a correct
   `codebase-memory-mcp` (and other) block alone so housecarl/headroom/forge are
   not stripped by a partial rewrite.
4. **Canonical path**: wire always prefers
   `%LOCALAPPDATA%\Programs\codebase-memory-mcp\codebase-memory-mcp.exe`
   over any `.local\bin` shim.
5. **Fix-Grok script**: same prefer-Programs + no-touch-if-correct behavior.

### Manual recovery (if CBM is broken again)
```powershell
cd "$env:LOCALAPPDATA\Programs\codebase-memory-mcp"
# Ultimate AI Starter Bundle - changelog

**Rename (v5.2.0 branding):** this pack is no longer titled "Skyrim AI only".
It is the **Ultimate AI Starter Bundle** - multi-provider AI toolkit with an
optional deep Skyrim SE/AE stack. Repo/folder names may still say V5 for history.
powershell -ExecutionPolicy Bypass -File .\Fix-Grok-Codebase-Memory-Direct.ps1
```
Then fully restart Grok and confirm `/mcp` shows codebase-memory-mcp.

## v5.0.1 Codebase-memory safety hotfix

Date: 2026-07-31

### Problem
The AIO installer used robocopy to force-extract codebase-memory-mcp into
`%LOCALAPPDATA%\Programs\codebase-memory-mcp` even when MCP was already
installed and running. A locked binary plus aggressive MCP rewires could
break Grok/Codex/Claude wiring and force manual reinstall +
`Fix-Grok-Codebase-Memory-Direct.ps1`.

### Fixes
1. **Keep existing install**: if `codebase-memory-mcp.exe` is already
   discoverable (prefer `Programs\codebase-memory-mcp\`), installer does not overwrite it.
2. **Locked-file guard**: `Copy-V5RoboSafe` / `Test-V5FileLocked` refuse to replace a running MCP binary.
3. **Grok MCP upsert is idempotent**: `-SkipIfPresent` leaves a correct
   `codebase-memory-mcp` (and other) block alone so housecarl/headroom/forge
   are not stripped by a partial rewrite.
4. **Canonical path**: wire always prefers
   `%LOCALAPPDATA%\Programs\codebase-memory-mcp\codebase-memory-mcp.exe`
   over any `.local\bin` shim.
5. **Fix-Grok script**: same prefer-Programs + no-touch-if-correct behavior.

### Manual recovery (if CBM broken again)
```powershell
cd "$env:LOCALAPPDATA\Programs\codebase-memory-mcp"
# Ultimate AI Starter Bundle - changelog

**Rename (v5.2.0 branding):** this pack is no longer titled "Skyrim AI only".
It is the **Ultimate AI Starter Bundle** - multi-provider AI toolkit with an
optional deep Skyrim SE/AE stack. Repo/folder names may still say V5 for history.
powershell -ExecutionPolicy Bypass -File .\Fix-Grok-Codebase-Memory-Direct.ps1
```
Then fully restart Grok and confirm `/mcp` shows codebase-memory-mcp.


## v5.0.2 Headroom Grok durable wrap (APPLY on install)

Date: 2026-07-31

### Problem
For Grok, Headroom **MCP** (`headroom_compress` / `retrieve` / `stats`) is not enough.
Automatic context compression requires Grok **API traffic** to route through the
Headroom **proxy** (`GROK_MODELS_BASE_URL` -> `http://127.0.0.1:8787/...`).

Earlier AIO only **checked** wrap / optionally started an existing deploy.
A **fresh** machine did **not** get durable wrap the way a working author
machine does after `headroom install apply` + live proxy.

### Fix (fresh install now wraps Grok)
`INSTALL-V5-AIO.ps1` (Grok provider, default) runs `TOOLS\Ensure-Headroom-Grok.ps1`
which **applies**:

1. `headroom install apply --preset persistent-task --providers manual --target grok_build`
2. User env `GROK_MODELS_BASE_URL` and `GROK_MODEL_GROK_BUILD_BASE_URL` -> `http://127.0.0.1:8787/v1` (if unset)
3. `headroom install start` when proxy is down
4. Idempotent `[mcp_servers.headroom]` in `%USERPROFILE%\.grok\config.toml`

Idempotent on already-wrapped machines: skips apply when deploy targets already
include `grok` / `grok_build`; never kills a healthy proxy or live wrap session.

### Manual
```powershell
.\TOOLS\Ensure-Headroom-Grok.ps1
.\TOOLS\Ensure-Headroom-Grok.ps1 -CheckOnly
```

### Still separate
codebase-memory binary path stays `%LOCALAPPDATA%\Programs\codebase-memory-mcp\`
(see v5.0.1). Headroom wrap does not replace CBM; both are required for
"codebase works under Grok with compression."

## v5.1.0 Headroom MCP-only for Grok + extras (BREAKING vs v5.0.2 wrap)

Date: 2026-07-31

### Why v5.0.2 was wrong for most Grok users
v5.0.2 auto-applied `headroom install apply` and set `GROK_MODELS_BASE_URL` to the local
Headroom proxy. That only works with **XAI_API_KEY** (api.x.ai).

A normal **Grok subscription / OIDC** login uses `https://cli-chat-proxy.grok.com`.
Headroom cannot forward that path, so wrapping produces:
- model catalog empty -> UI shows **"unknown"**
- chat **401** Unauthorized through `http://127.0.0.1:8787/...`

### Fix (default now)
- `TOOLS\Ensure-Headroom-Grok.ps1` is **auth-aware**:
  - OIDC/session: **MCP only** + auto **-Repair** if a wrap is detected
  - XAI_API_KEY: durable wrap only with explicit `-Wrap`
- `INSTALL-V5-AIO.ps1` registers Headroom MCP and **never** reroutes Grok inference by default
- PowerShell: do not ship `function grok { headroom wrap grok }`

### New optional extras (`-WithExtras`)
Non-overlapping third-party skills/MCP (see CATALOG scope notes):
- code-review-skill (awesome-skills) - generic languages only
- obsidian-skills (kepano) - vault/docs, not Skyrim records
- claude-mem (thedotmack) - Claude Code cross-session memory only
- playwright-mcp - browser automation for CLIs without a built-in browser
- firecrawl-mcp - web scrape (not Nexus; houseCARL owns Nexus)
- perplexity-mcp - needs PERPLEXITY_API_KEY

```powershell
.\INSTALL-V5-AIO.ps1 -WithExtras
.\TOOLS\Ensure-Headroom-Grok.ps1 -Repair   # if Grok shows unknown after v5.0.2
```

### Upgrade from v5.0.2
```powershell
.\TOOLS\Ensure-Headroom-Grok.ps1 -Repair
# Ultimate AI Starter Bundle - changelog

**Rename (v5.2.0 branding):** this pack is no longer titled "Skyrim AI only".
It is the **Ultimate AI Starter Bundle** - multi-provider AI toolkit with an
optional deep Skyrim SE/AE stack. Repo/folder names may still say V5 for history.
.\INSTALL-V5-AIO.ps1 -WithExtras
```

## v5.2.0 — Headroom MCP-only for Grok + extras (supersedes bad v5.0.2 wrap)

Date: 2026-07-31

### Baselines
- **GitHub before this release:** `v5.0.2` on main (tag) auto-wrapped Grok inference through Headroom.
- That broke **subscription / OIDC** Grok logins (model **"unknown"**, chat **401**).
- This release is the finished fix that was started on the local `v5-main` worktree (Claude incomplete, completed here).

### Breaking change vs v5.0.2
Default install **does NOT** set `GROK_MODELS_BASE_URL` or run `headroom install apply` for Grok.

| Grok auth | Headroom mode |
|-----------|----------------|
| Subscription / OIDC (`cli-chat-proxy.grok.com`) | **MCP tools only** (compress/retrieve/stats) |
| `XAI_API_KEY` (api.x.ai) | Optional inference wrap: `Ensure-Headroom-Grok.ps1 -Wrap` |

### Repair if you already ran v5.0.2
```powershell
.\TOOLS\Ensure-Headroom-Grok.ps1 -Repair
# Ultimate AI Starter Bundle - changelog

**Rename (v5.2.0 branding):** this pack is no longer titled "Skyrim AI only".
It is the **Ultimate AI Starter Bundle** - multi-provider AI toolkit with an
optional deep Skyrim SE/AE stack. Repo/folder names may still say V5 for history.
grok
```

### New optional extras (`-WithExtras`)
| Component | Scope |
|-----------|--------|
| code-review-skill | Generic languages (not Skyrim-specific review) |
| obsidian-skills | Vault/docs markdown only |
| claude-mem | **Claude Code ONLY** — needs **Bun**; conversation memory, not codebase-memory |
| playwright-mcp | Browser automation for CLIs without built-in browser |
| firecrawl-mcp | Web scrape (not Nexus — houseCARL owns Nexus) |
| perplexity-mcp | Needs `PERPLEXITY_API_KEY` |

### Still from earlier hotfixes
- v5.0.1: never overwrite live codebase-memory-mcp binary
- Headroom + CBM are complementary, not replacements

### Install
```powershell
.\INSTALL-V5-AIO.ps1
.\INSTALL-V5-AIO.ps1 -WithExtras
```

## v5.2.1 Codebase-memory UI / auto_index safety

Date: 2026-07-31

### Problem
`codebase-memory-mcp --ui=true` / `install.ps1 --ui` enables the HTTP
"Codebase Discovery" UI (port 9749). On Windows this frequently pops
**Select an app to open...** dialogs and confuses agents.

Some install notes / Auto.txt also set `auto_index true`.

### Fix
- Document and enforce: `auto_index=false`, `auto_watch=false`, `--ui=false`
- MCP wiring is stdio only (exe path, no UI args) for all providers
- Skills no longer recommend `install.ps1 --ui`
- Codex SessionStart "Code discovery" echo hooks removed on affected machines
- Index via `index_repository` tool on demand only

## v5.2.2 Headroom scheduled-task console-flash fix

Date: 2026-08-01

### Problem
Old Headroom `persistent-task` deployments could leave `headroom-*` Scheduled
Tasks after their deployment manifest or `ensure-headroom.cmd` was removed.
The previous cleanup checked only `Actions.Execute`, so a task using
`cmd.exe /c <missing-script>` looked valid because `cmd.exe` still existed.
Cleanup also ran only inside the Grok repair path.

### Fix
- Inspect Headroom script paths embedded in Scheduled Task arguments.
- Treat a default Headroom deploy task without its manifest as orphaned.
- Run cleanup during every normal setup before checking for `headroom.exe`.
- Disable a stale task when unregistering it is denied, preventing further
  blink-and-vanish console windows.
- Preserve valid tasks whose target and deployment manifest still exist.
- Add a PowerShell regression test for all three cases.

## v5.2.3 codebase-memory dashboard guidance fix

Date: 2026-08-06

### Problem
The pack shipped two contradictory instructions for the same setting.
Skills and `START-HERE.txt` said to **never** enable the codebase-memory HTTP
UI and to run `codebase-memory-mcp --ui=false`, while the Grok `config.toml`
this same pack writes warned *not* to pass `--ui=false` because it would kill
the dashboard for the other AI apps.

The Grok comment was the correct one. `--ui` and `--port` are **persisted into
the codebase-memory-mcp config itself**, not into a per-agent MCP entry, so a
single `--ui=false` from any one provider silently disables the dashboard for
every other provider on the next restart. Following the old instruction turned
off a working, loopback-only feature pack-wide, and made the dashboard appear
to vanish at random.

The "Select an app / Codebase Discovery" Windows dialog that motivated the
original warning comes from running the upstream `install.ps1 --ui`, not from
the dashboard itself.

### Fix
- Rewrite the `codebase-memory` skill UI section for all five providers
  (10 provider copies + `_V5-CANONICAL-SKILLS`, 11 files total).
- Supersede the earlier `--ui=false` guidance: it is no longer a required default.
- State that `--ui` / `--port` are global, shared, persisted settings and must
  never appear in MCP `args`; `args = []` stays correct for every provider.
- Document the toggle as an out-of-band, one-time command, and give the
  dashboard URL <http://127.0.0.1:9749/> (loopback only).
- Keep `auto_index=false` and `auto_watch=false` as required defaults; indexing
  stays manual via `index_repository`.
- Retain the `install.ps1 --ui` warning, correctly scoped to the installer flag.
- Correct `START-HERE.txt`, which also still carried a stale V5.2.0 title.

## v5.2.4 dashboard keep-alive

Date: 2026-08-06

### Problem
v5.2.3 correctly established that `--ui` and `--port` are global, persisted
state and must not appear in MCP `args`, but it stopped short of explaining how
to keep the dashboard running. That left a real gap: following v5.2.3 exactly,
the dashboard still appears to work and then vanish.

The HTTP dashboard is served **by a codebase-memory-mcp process**, and that
process exits as soon as its stdin closes. A server spawned by an MCP client
serves the dashboard only while that client stays attached, so the page dies
whenever the AI app restarts or disconnects.

### Fix
- Document the standalone keep-alive host that ships beside the exe,
  `Start-codebase-memory-UI.bat`, which holds stdin open so the dashboard
  survives independently of any AI app.
- Note that port 9749 has a single binder, so exactly one UI host should run.
- Confirm MCP clients keep `args = []` and coexist with that host: verified
  the standalone host serving http://127.0.0.1:9749/ while MCP tool calls
  continued to succeed.
- Applied to all 11 `codebase-memory` skill copies and `START-HERE.txt`.
