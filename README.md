# Ultimate AI Starter Bundle v5.2.0

**Ultimate multi-provider AI starter kit** - not a Skyrim-only pack.

**Simply download and extract and point your ai agent to the extracted folder and say: Install all non overlapping skills, plugins and tool you may use from my ai starter bundle https://github.com/ShugokiFable/Ultimate-AI-Starter-Bundle im pretty sure you are already connected to the mcp codebase index but make sure you are and you know how to use it.**

Make sure you have all skills that are newer also like if you have old skills or old stuff that contradicts remove it

you keep asking windows to open codebase discovery thingy so yeah stop making this shit pop up on my screen. other ai's I used use it with MCP

Install skills, MCP servers, plugins, and offline tools for:

- **Claude Code**, **Codex**, **Grok**, **Kimi**, **Hermes**
- Code graph memory, context compression, browser/scrape MCPs
- Optional deep **Skyrim SE/AE** modding stack (houseCARL, Spooky, Forge, frameworks)

Skyrim is a major included domain. The pack is also a general "good start" for serious AI-assisted development.

## Quick start

**Windows**

1. Clone or download this repo (or unzip the release).
2. Double-click `INSTALL-V5-AIO.bat`, or run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\INSTALL-V5-AIO.ps1
```

3. Fully restart your AI app(s).

### Common options

```powershell
.\INSTALL-V5-AIO.ps1 -Providers Grok,Claude
.\INSTALL-V5-AIO.ps1 -Mode OnlineLatest
.\INSTALL-V5-AIO.ps1 -WithExtras
.\INSTALL-V5-AIO.ps1 -SkillsOnly
.\INSTALL-V5-AIO.ps1 -ToolsOnly
.\INSTALL-V5-AIO.ps1 -WorkspaceRoot "D:\My\AI-Workspace"
```

| Mode | Behavior |
|------|----------|
| `BundledFirst` (default) | Use `BUNDLED-TOOLS\offline`, fall back to GitHub |
| `OnlineLatest` | Always fetch latest GitHub releases |
| `BundledOnly` | Offline zips only (no network) |

## What gets installed

- **Provider skills** — ~82 skills per AI (Claude, Codex, Grok, Kimi, Hermes)
- **houseCARL** MCP + MO2 instance or Vortex shim setup
- **Spooky's AutoMod Toolkit**
- **codebase-memory-mcp**
- **Headroom** (context compression, registered as an MCP server — see [Headroom + Grok](#headroom--grok))
- **Superpowers** + **Ponytail** plugins/skills
- **CodeBurn** (optional, via npm/npx)
- Grok MCP wiring + portable tool discovery

### Not bundled

**Skyrim Forge** is not redistributed. Install it yourself and set `SKYRIM_FORGE_ROOT`, or place `INSTALLATION.json` beside the `skyrim-forge` skill.

## Update tools later

```powershell
.\TOOLS\Update-From-GitHub.ps1
.\TOOLS\Update-From-GitHub.ps1 -Components housecarl,codebase-memory -UpdateCatalogOffline
.\TOOLS\Ensure-Tools.ps1
.\TOOLS\Setup-HouseCarl.ps1
```

## Layout

```text
1-RECOMMENDED-SEPARATE-TAILORED/   per-AI tailored skill trees
2-OPTIONAL-SHARED-GENERIC/         shared generic trees
BUNDLED-TOOLS/offline/             shipped tool zips/wheels
BUNDLED-TOOLS/plugins/             Superpowers + Ponytail
BUNDLED-TOOLS/CATALOG.json         component registry
COPY-TO-YOUR-WORKSPACE/
TOOLS/                             installers and discovery scripts
_V5-CANONICAL-SKILLS/              maintainer master skills
INSTALL-V5-AIO.ps1 / .bat          master installer
START-HERE.txt                     short human guide
```

## Docs

- [START-HERE.txt](START-HERE.txt)
- [V5-AIO-GUIDE.md](V5-AIO-GUIDE.md)
- [V5-CHANGELOG.md](V5-CHANGELOG.md)
- [V5-INTEGRATION-AUDIT.md](V5-INTEGRATION-AUDIT.md)
- [BUNDLED-TOOLS/THIRD-PARTY-NOTICES.md](BUNDLED-TOOLS/THIRD-PARTY-NOTICES.md)
- [WHICH-AI-SHOULD-I-USE-FOR-SKYRIM.md](WHICH-AI-SHOULD-I-USE-FOR-SKYRIM.md)

## AI contract

Skills teach **portable discovery**. Paths are resolved from env vars, `LOCALAPPDATA`, and `PATH` — never hardcoded drive letters or usernames.

If a tool is missing, the AI should recommend `INSTALL-V5-AIO.ps1`, `Ensure-Tools.ps1`, or `Update-From-GitHub.ps1` — not invent paths or fake MCP results.

## Third-party components

Bundled offline artifacts and plugins retain their upstream licenses. See [BUNDLED-TOOLS/THIRD-PARTY-NOTICES.md](BUNDLED-TOOLS/THIRD-PARTY-NOTICES.md).

Notable upstream projects:

| Component | Upstream |
|-----------|----------|
| houseCARL | https://github.com/Avick3110/houseCARL |
| Spooky's AutoMod Toolkit | https://github.com/SpookyPirate/spookys-automod-toolkit |
| codebase-memory-mcp | https://github.com/DeusData/codebase-memory-mcp |
| Headroom | https://github.com/headroomlabs-ai/headroom |
| Superpowers | https://github.com/obra/superpowers |
| Ponytail | https://github.com/DietrichGebert/ponytail |
| CodeBurn | https://github.com/getagentseal/codeburn |

Do not re-upload third-party binaries to Nexus as your own work. Keep attribution. Prefer `TOOLS\Update-From-GitHub.ps1` for newer versions.

## Headroom + Grok

**The installer registers Headroom as an MCP server for Grok. It does not route
Grok inference through Headroom, and neither should you.**

Headroom's Grok proxy forwards to `https://api.x.ai` and authenticates with
`XAI_API_KEY`. A Grok **subscription** login (the normal one) uses
`https://cli-chat-proxy.grok.com` instead, which Headroom cannot forward.
Wrapping such an account breaks Grok:

```text
model catalog: all retries exhausted   ->  model selector shows "unknown"
Unauthorized (401) from http://127.0.0.1:8787/.../v1/chat/completions
```

grok-4.5 becomes unselectable. **v5.0 of this pack applied that wrap
automatically — that was the bug. v5.1 does not.**

### Grok shows an "unknown" model / grok-4.5 is gone

```powershell
.\TOOLS\Ensure-Headroom-Grok.ps1 -Repair
```

Then open a **new** PowerShell window and run `grok`. The repair clears the
`GROK_MODELS_BASE_URL` / `GROK_MODEL_GROK_BUILD_BASE_URL` env vars, renames any
`function grok` that calls `headroom wrap grok`, deletes a poisoned
`models_cache.json`, and tells you how to drop the durable deploy.

If a `~/.headroom/deploy/default/manifest.json` lists `grok` or `grok_build` in
`targets`, remove it — that deploy re-applies the breaking env vars on every
health check, so Grok re-breaks at logon:

```powershell
headroom install remove --profile default
```

### Other Ensure-Headroom-Grok modes

| Command | Effect |
|---|---|
| `.\TOOLS\Ensure-Headroom-Grok.ps1` | MCP registration, auth aware (what the installer runs) |
| `... -CheckOnly` | Report state, change nothing |
| `... -Repair` | Undo a v5.0 wrap |
| `... -Wrap` | Opt in to the inference proxy; **refuses without `XAI_API_KEY`** |

MCP mode gives Grok `headroom_compress` / `headroom_retrieve` /
`headroom_stats` — on-demand compression the agent calls deliberately. It is not
automatic traffic compression, and for a subscription account it is the only
mode that works.

## Version

**v5.1.0** — Headroom/Grok wrap made auth aware; extra skills and MCP servers added.
Based on `Skyrim-AI-FINAL-MANUAL-INSTALL-v5.0.0`.

## License

Pack documentation and original installer scripts are provided as-is for personal and community use. Third-party tools inside `BUNDLED-TOOLS` keep their own licenses (see notices file).

## Current release: v5.2.2

- **Windows console-flash fix:** stale `headroom-*` scheduled tasks are removed or disabled during normal setup, including missing `ensure-headroom.cmd` argument targets.

- **Grok + Headroom:** MCP only by default. Do **not** wrap subscription Grok through Headroom (that was the v5.0.2 bug: model "unknown" / 401).
- **Repair:** `.\TOOLS\Ensure-Headroom-Grok.ps1 -Repair`
- **Extras:** `.\INSTALL-V5-AIO.ps1 -WithExtras` (claude-mem is Claude Code only and needs Bun)
