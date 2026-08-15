# Ultimate AI Starter Bundle v6.8.2

**Ultimate multi-provider AI starter kit** - not a Skyrim-only pack.

Install skills, MCP servers, plugins, and offline tools for:

- **Claude Code**, **Codex**, **Grok**, **Kimi**, **Hermes**
- Code graph memory, context compression, browser/scrape MCPs
- Optional deep **Skyrim SE/AE** modding stack (houseCARL, Spooky, Forge, frameworks)

Skyrim is a major included domain. The pack is also a general "good start" for serious AI-assisted development.


## AI preamble (`AIO-INSTRUCTION.txt`)

The operating contract to paste into any provider's custom-instructions box.
~614 tokens, sized deliberately: it rides on every request, so every line has to
earn its cost.

- **Finish the job, not the sentence** — the request is the goal, not the
  checklist; docs, version and cleanup are part of shipping
- Read for intent, not wording; no yes-man; correct a wrong premise
- **Verify, don't assume** — use the tool that would settle it; ask if none
  exists; assume only as a last resort and label it
- Never invent a fact, API, path, version or command
- An explicit evidence order: runtime output > tool verdict > docs > recall
- Report what you did *not* do, and never call partial work finished
- Spend tokens like they're the user's; no routine confidence footer

**How to use**

1. Keep the file at the pack root (`AIO-INSTRUCTION.txt`).
2. Copy it into your workspace, **or** paste into provider custom instructions, **or** open a session with:

```text
Follow AIO-INSTRUCTION.txt for every complex or factual request.
```

Same content is also stored as `AIO Instruction.txt`.

## Quick start

**Windows**

1. Clone or download this repo (or unzip the release).
2. Double-click `INSTALL-V6-AIO.bat`, or run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\INSTALL-V6-AIO.ps1
```

3. Fully restart your AI app(s).

### Common options

```powershell
.\INSTALL-V6-AIO.ps1 -Providers Grok,Claude
.\INSTALL-V6-AIO.ps1 -Mode OnlineLatest
.\INSTALL-V6-AIO.ps1 -WithExtras
.\INSTALL-V6-AIO.ps1 -SkillsOnly
.\INSTALL-V6-AIO.ps1 -ToolsOnly
.\INSTALL-V6-AIO.ps1 -WorkspaceRoot "D:\My\AI-Workspace"
```

| Mode | Behavior |
|------|----------|
| `BundledFirst` (default) | Use `BUNDLED-TOOLS\offline`, fall back to GitHub |
| `OnlineLatest` | Always fetch latest GitHub releases |
| `BundledOnly` | Offline zips only (no network) |

## What gets installed

- **Provider skills** — 88 skills per AI (Claude, Codex, Grok, Kimi, Hermes), all generated from one canonical tree
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
_V6-CANONICAL-SKILLS/              maintainer master skills
INSTALL-V6-AIO.ps1 / .bat          master installer
START-HERE.txt                     short human guide
```

## Docs

- [START-HERE.txt](START-HERE.txt)
- [V6-AIO-GUIDE.md](V6-AIO-GUIDE.md)
- [V6.8.2-CHANGELOG.md](V6.8.2-CHANGELOG.md)
- [V6.8.1-CHANGELOG.md](V6.8.1-CHANGELOG.md)
- [V6.8-CHANGELOG.md](V6.8-CHANGELOG.md)
- [V6.5-CHANGELOG.md](V6.5-CHANGELOG.md)
- [BOOTSTRAP.txt](BOOTSTRAP.txt)
- [V6-CHANGELOG.md](V6-CHANGELOG.md)
- [BUNDLED-TOOLS/THIRD-PARTY-NOTICES.md](BUNDLED-TOOLS/THIRD-PARTY-NOTICES.md)
- [WHICH-AI-SHOULD-I-USE-FOR-SKYRIM.md](WHICH-AI-SHOULD-I-USE-FOR-SKYRIM.md)
- Historical: [V5-CHANGELOG.md](V5-CHANGELOG.md), [V5-INTEGRATION-AUDIT.md](V5-INTEGRATION-AUDIT.md), [RELEASE-NOTES-v5.2.2.md](RELEASE-NOTES-v5.2.2.md), [V4.3-CLAUDE-REVIEW-AUDIT.md](V4.3-CLAUDE-REVIEW-AUDIT.md), [V4.2-LOG-REGRESSION-AUDIT.md](V4.2-LOG-REGRESSION-AUDIT.md)

## AI contract

Skills teach **portable discovery**. Paths are resolved from env vars, `LOCALAPPDATA`, and `PATH` — never hardcoded drive letters or usernames.

If a tool is missing, the AI should recommend `INSTALL-V6-AIO.ps1`, `Ensure-Tools.ps1`, or `Update-From-GitHub.ps1` — not invent paths or fake MCP results.

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

## What's new in v6.8.2

Stop Assuming. Agents have a filesystem, Firecrawl, and a code index, and still
answer from memory. v6.8.2 adds a control, not another reminder:

- **Assumption gate** — refuses a drive that does not exist on this machine,
  another user's home hardcoded into a script, and unread remote content piped
  into a shell. Same installer as the completeness gate. Precise, cheap, fail
  open, self-tested before it is wired.
- **Hermes installer routed through the tool.** v6.8.1 documented `hermes
  config path` and then still wrote to `~/.hermes/config.yaml`. Now
  `hermes_wire.py` asks the executable and merges YAML instead of appending.
- **The pack gates itself.** `VERSION.txt` + `CHANGELOG.md` are the files the
  completeness gate actually reads.
- **Verify-first AIO-INSTRUCTION** (rules 4/5/9). Token budget held.
- **`TOOLS/Build-Toolbelt.ps1`** writes a machine-local inventory of MCP
  servers and CLIs that actually exist.
- **MCP pins refreshed** (`context7@4.0.2`, `sequential-thinking@2026.7.4`)
  after a broken npx cache shipped as "installed".

Full detail in [V6.8.2-CHANGELOG.md](V6.8.2-CHANGELOG.md).

## What's new in v6.8.1

v6.8.0 said the completeness gate was on five providers. It was on **two**.
Fixed by using each provider's real mechanism, verified against its own docs or
CLI: Codex loads hooks from **plugins** (now installed as a local-marketplace
plugin), Hermes uses a `hooks:` block in the config path `HERMES_HOME` resolves
to — *not* the one its docs name — and **Kimi has no hook system at all**, so
that file is removed rather than left looking installed.

Hermes also gained the three MCP servers it was missing.

Two consent prompts remain, by design: Codex asks once to trust the plugin, and
Hermes needs `hermes --accept-hooks` once. Forging either would mean writing a
security consent record on your behalf.

Full detail in [V6.8.1-CHANGELOG.md](V6.8.1-CHANGELOG.md).

## What's new in v6.8.0

Three MCP servers chosen for one-shot accuracy, and two tools brought current.

- **`TOOLS/Add-Reasoning-MCPs.ps1`** wires **context7** (live library/API docs —
  stops invented signatures), **sequential-thinking** (explicit decomposition)
  and the official **github** server (releases, PRs, CI status) into Claude,
  Grok, Codex and Kimi. npx-based, majors pinned, keys optional.
- **codebase-memory-mcp 0.9.0 → 0.10.5**, **Headroom 0.33.0 → 0.35.0**, verified
  against upstream checksums.
- Fixed both installers writing a **UTF-8 BOM** into JSON configs —
  `Set-Content -Encoding utf8` emits one on PowerShell 5.1, and a strict JSON
  reader rejects the file. The exact bug v6.0 exists to prevent.

Full detail in [V6.8-CHANGELOG.md](V6.8-CHANGELOG.md).

## What's new in v6.5.0

Agents are literal. Told "push the fix", they push the fix and never touch the
README, because nobody asked. Every provider's prompt already says "be
thorough", so v6.5 stops asking and adds a control instead.

- **Completeness gate** (`TOOLS/Install-Completeness-Gate.ps1`) — a `PreToolUse`
  hook that refuses a push, and a `Stop` hook that refuses to end the turn, while
  a release is internally inconsistent: version bumped with no changelog entry, a
  README still declaring the old version, uncommitted source left behind. Named
  specifics, not nagging. Installs into Grok, Claude, Codex, Kimi and Hermes.
  Silent unless the current commit changed a version declaration; fails open;
  self-tested before it is wired.
- **AIO-INSTRUCTION rewritten** around "finish the job, not the sentence", and
  made *cheaper* — 614 tokens versus 640.
- **BOOTSTRAP.txt** — one paste that makes a fresh agent install and verify the
  whole bundle itself.

Full detail in [V6.5-CHANGELOG.md](V6.5-CHANGELOG.md).

## What's new in v6.0.0

v6 is a **correctness release**. Full detail in [V6-CHANGELOG.md](V6-CHANGELOG.md).

- **7 skills per install had no usable description.** A UTF-8 BOM before the
  opening `---` of a `SKILL.md` stops a strict YAML reader from ever opening the
  frontmatter, so the `description` is lost — and the description is the only
  thing an agent matches on when deciding whether to load a skill. The skill is
  installed, listed, and invisible. Two of the seven were `skyrim-memory` and
  `skyrim-tool-router`, the skills the instructions say to load *first*.
- **The inverse rule, found while fixing that one.** A `.ps1` **needs** its BOM:
  PowerShell 5.1 decodes a BOM-less file as ANSI, and one em dash then breaks
  the parse. v6 classifies by execution target — skills are normalised, Windows
  scripts are copied byte-for-byte.
- **Canonical rebuilt from a working install**, which had drifted ahead of the
  bundle: 3 missing validator scripts, corrected `codebase-memory` guidance, and
  6 uncaptured extras skills. All 10 provider trees are now *generated* from it.
- **Evidence registry 70 → 85 entries**, each tied to a real failure.
- **New skill `mcp-protocol-2026`** for the stateless 2026-07-28 MCP revision.
- **Superpowers 6.3.0**, **Ponytail 4.9.0**; offline assets re-fetched and
  hash-verified.
- **Grok + Headroom:** MCP only by default. Do **not** wrap subscription Grok
  through Headroom (the v5.0.2 bug: model "unknown" / 401). Repair with
  `.\TOOLS\Ensure-Headroom-Grok.ps1 -Repair`.
- **Extras:** `.\INSTALL-V6-AIO.ps1 -WithExtras` (claude-mem is Claude Code only
  and needs Bun).

## Gates (new in v6)

```powershell
python TOOLS\audit_skills.py <skills-dir>
powershell -NoProfile -ExecutionPolicy Bypass -File .\TESTS\Test-V6-Pack.ps1
python TOOLS\install_live_skills.py _V6-CANONICAL-SKILLS --check
```

v5.2.5's registry had *already warned* that BOM/encoding drift breaks
valid-looking files, and v5.2.5 shipped BOMs anyway. A warning in a document is
not a control; these are. `Test-V6-Pack.ps1` checks every skill tree, parses
every shipped `.ps1`, verifies offline-asset hashes, and sanity-checks the
registry.

## Known limitations

- 19 skills exceed the tier-1/tier-2 context budget (22 warnings). They work;
  they are not free. Trimming is deferred, not done.
- Everything here is **tool-validated** — gates pass, scripts parse, hashes
  verify, and the BOM fix is confirmed live in a provider's own skill listing.
  The installer has **not** been run end-to-end on a clean machine as part of
  this build.

## Version

**v6.8.1** — 2026-08-15. Based on v6.8.0.

## License

Pack documentation and original installer scripts are provided as-is for
personal and community use. Third-party tools inside `BUNDLED-TOOLS` keep their
own licenses (see [BUNDLED-TOOLS/THIRD-PARTY-NOTICES.md](BUNDLED-TOOLS/THIRD-PARTY-NOTICES.md)).
