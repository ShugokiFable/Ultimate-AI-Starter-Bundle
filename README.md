# Ultimate AI Starter Bundle v7.5.1

**Ultimate multi-provider AI starter kit** - not a Skyrim-only pack.

Install skills, MCP servers, plugins, and offline tools for:

- **Claude Code**, **Codex**, **Grok**, **Kimi**, **Hermes**
- Code graph memory (with the indexing discipline that keeps it small), context compression, browser/scrape MCPs
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
- **Adult fiction is in scope** — do fictional-adult mod work; do not sanitize
  explicit IDs; still refuse child, age-ambiguous, and real-person sexual content
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

## SOUL + AIO for every agent (v7.5.0)

The preamble is now **installed automatically**, not pasted by hand:

- `4-PREAMBLES/SOUL.md` — the operator's own soul config (unrestricted, no
  yes-man, truth-seeking process, output format), shipped verbatim
- `4-PREAMBLES/SOUL-UNIVERSAL.md` — same content, identity-neutral, wired
  into agents that are not Hermes
- `4-PREAMBLES/MANUAL-PASTE.txt` — for web UIs (ChatGPT/Gemini) that have no
  instruction file: paste it into the custom-instructions box

`INSTALL-V7-AIO.ps1` appends SOUL-UNIVERSAL + `AIO-INSTRUCTION.txt` to
Claude Code (`~/.claude/CLAUDE.md`), Codex (`~/.codex/AGENTS.md`), Kimi
(`~/.kimi-code/AGENTS.md`) and Grok (`~/.grok/AGENTS.md`, its global-rules
file), and copies the verbatim soul into Hermes' home (`SOUL.md`). Idempotent
and backup-first; `-SkipPreamble` opts out. Full map:
`4-PREAMBLES/README.md`.

## Quick start

**Fresh machine, nothing installed - one command:**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/ShugokiFable/Ultimate-AI-Starter-Bundle/main/INSTALL-REMOTE.ps1 | iex"
```

Downloads the latest release, extracts to `%LOCALAPPDATA%\Ultimate-AI-Starter-Bundle`,
and runs the full installer (skills, tools, MCP servers, gates, SOUL + AIO
preamble). With parameters:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "& ([scriptblock]::Create((irm https://raw.githubusercontent.com/ShugokiFable/Ultimate-AI-Starter-Bundle/main/INSTALL-REMOTE.ps1))) -Providers Claude,Grok -Tag v7.5.0"
```

Or double-click `INSTALL-REMOTE.bat`. Re-running is a no-op.

**Windows (bundle already on disk)**

1. Double-click `INSTALL-V7-AIO.bat`, or run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\INSTALL-V7-AIO.ps1
```

3. Fully restart your AI app(s).

### Common options

```powershell
.\INSTALL-V7-AIO.ps1 -Providers Grok,Claude
.\INSTALL-V7-AIO.ps1 -Mode OnlineLatest
.\INSTALL-V7-AIO.ps1 -WithExtras
.\INSTALL-V7-AIO.ps1 -SkillsOnly
.\INSTALL-V7-AIO.ps1 -ToolsOnly
.\INSTALL-V7-AIO.ps1 -WorkspaceRoot "D:\My\AI-Workspace"
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
- **codebase-memory-mcp** — plus the v7 index scope tooling (`.cbmignore` project template + `TOOLS/Setup-CodebaseMemory-Index.ps1`) so the graph indexes source, not asset trees
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
COPY-TO-YOUR-WORKSPACE/            workspace files + _PROJECT-TEMPLATE (incl. .cbmignore)
0-UNRESTRAINT-PACKS/               no-holds prompt library (v6.9.2)
4-PREAMBLES/                      SOUL + AIO preamble for every agent (v7.5.0)
TOOLS/                             installers and discovery scripts
TOOLS/Setup-CodebaseMemory-Index.ps1   index scope generator (v7.0.0+)
_V7-CANONICAL-SKILLS/              maintainer master skills
INSTALL-V7-AIO.ps1 / .bat          master installer
START-HERE.txt                     short human guide
```

## Docs

- [START-HERE.txt](START-HERE.txt)
- [V7-AIO-GUIDE.md](V7-AIO-GUIDE.md)
- [V7.5.1-CHANGELOG.md](V7.5.1-CHANGELOG.md)
- [V7.5.0-CHANGELOG.md](V7.5.0-CHANGELOG.md)
- [V7.2.0-CHANGELOG.md](V7.2.0-CHANGELOG.md)
- [V7.0.0-CHANGELOG.md](V7.0.0-CHANGELOG.md)
- [V6.9.3-CHANGELOG.md](V6.9.3-CHANGELOG.md)
- [V6.9.2-CHANGELOG.md](V6.9.2-CHANGELOG.md)
- [V6.9.1-CHANGELOG.md](V6.9.1-CHANGELOG.md)
- [V6.9.0-CHANGELOG.md](V6.9.0-CHANGELOG.md)
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

If a tool is missing, the AI should recommend `INSTALL-V7-AIO.ps1`, `Ensure-Tools.ps1`, or `Update-From-GitHub.ps1` — not invent paths or fake MCP results.

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

## What's new in v7.5.1

The installer ran end-to-end on a real machine for the first time and three
bugs surfaced, all fixed: the Grok compat-cells rewrite could eat every
`[mcp_servers.*]` block after `[compat.claude]` on re-runs; Headroom's pip
step died on PATH pythons without pip (and on pip's stderr); and gates /
reasoning-MCP wiring silently no-op'd on multi-provider installs. Full
details in [V7.5.1-CHANGELOG.md](V7.5.1-CHANGELOG.md).

## What's new in v7.5.0

- **`4-PREAMBLES/`** — SOUL for every agent: the operator's soul config
  (verbatim), an identity-neutral universal soul, and a manual-paste file for
  web UIs. The installer now wires SOUL + the AIO operating contract into
  Claude Code, Codex, Kimi, Grok and Hermes automatically (idempotent,
  backup-first, `-SkipPreamble` to opt out).
- **One command from zero** — `INSTALL-REMOTE.ps1` / `.bat`: downloads the
  latest release, extracts it under `%LOCALAPPDATA%\Ultimate-AI-Starter-Bundle`
  and runs the full installer. Releases now carry a zip asset.
- **Hermes home catalog fix** — `%LOCALAPPDATA%\hermes` (was `~/.hermes`,
  which silently missed the real home).
- **`BOOTSTRAP.txt`** now bootstraps from GitHub when the bundle is absent.

## What's new in v7.3.0

- **`GROK-MCP-TROUBLESHOOTING.md`** — the full Grok-hang forensics: turn-phase log
  reading, 5 field-tested rules (no MCP sections in grok config.toml, pin every npx
  server, headroom via launcher, cbm daemon keep-alive, never kill servers mid-session),
  diagnosis cheat-sheet. Model stalls were tool-prep, not the model.
- MCP examples: github pin + "pin every npx" rule.
- `codebase-memory` skill: cold-daemon stall note.

## What's new in v7.2.2

- Firecrawl MCP example pinned (`firecrawl-mcp@3.24.0`) — unpinned npx cold-resolves
  and can exceed Grok's 30s startup timeout; doc + explanation added.
- `codebase-memory` skill: dashboard tiles can read 0 on v0.10.5 (UI-RPC lockdown,
  upstream #1663) — documented with the correct verification path.

## What's new in v7.2.1

- `skyrim-forge` skill updated for Forge 5.x (no more 4.2 pin) and now documents the
  **provider-runtime venv trap**: venvs built from `~/.cache/codex-runtimes/...` die
  when that cache is deleted, hanging every MCP client at startup. Repair recipe included.
- No pack-structure changes.

## What's new in v7.2.0

v7.0.0 shipped the indexing discipline but left two maintainer-tooling defects as
*documented workarounds*. A workaround that depends on someone remembering two manual
steps is a deferred bug — the fanout trap was hit again within the session that
documented it. v7.2.0 makes the tooling enforce it.

- **`fanout_providers.py` no longer widens scope.** A `SCOPED` map keeps
  `unrestraint-packs` Hermes-only (493 files for Hermes, 492 elsewhere) and prints what
  it withheld. Canonical still holds the skill so it stays maintained in one place.
- **`fanout_providers.py` preserves line endings.** It used to rewrite CRLF sources to
  LF on every run, which matters because `.gitattributes` sets `* -text` so
  `MANIFEST.json` hashes verify against a clean clone. A full fanout run now leaves
  `git status` completely clean; before, it dirtied 12 files and created 8 directories.
- **`install_live_skills.py` stopped making useless backups.** It backed up *before*
  knowing whether anything would change, so a no-op run still copied ~53 MB per provider
  (13 stacked trees / ~692 MB observed). It now probes first and says
  `backup: skipped (nothing changed)`.
- **V6→V7 rename completed** for live artifacts: `_V7-CANONICAL-SKILLS/`,
  `INSTALL-V7-AIO.ps1/.bat`, `V7-AIO-GUIDE.md`, `TESTS/Test-V7-Pack.ps1`,
  `TOOLS/V7-Common.ps1`, `v7-registry-*.json`. Historical changelogs keep their
  V4/V5/V6 names — they describe the past accurately.

## What's new in v7.0.0

Indexing discipline for `codebase-memory-mcp`. Previous versions documented how to
*query* the graph and said nothing about how to *build* one — so agents indexed whole
mod trees and produced graphs that cost tokens on every call and answered nothing.

- `codebase-memory` skill rewritten with an **Indexing discipline** half: the four
  bloat sources, what the tool cannot parse, never-index paths, and verification.
- **`.cbmignore` matching is case-sensitive** — `meshes/` does not match `Meshes/`,
  and Skyrim capitalizes its asset folders. Every asset rule now ships in both cases.
- **Papyrus (`.psc`) is never parsed**, and `scripts/` is skipped by a built-in
  skip-list. A script-only mod indexing to a handful of nodes is correct, not broken.
  Use Grep + `papyrus-reference` for Papyrus.
- New `COPY-TO-YOUR-WORKSPACE/_PROJECT-TEMPLATE/.cbmignore` — correct scope from
  the moment a project is created.
- New `TOOLS/Setup-CodebaseMemory-Index.ps1` — generates `.cbmignore` per project,
  resolves the active version from `CURRENT.txt`, and detects the **source-carrier
  exception** (an active version that ships as a package while the only copy of the
  source sits in an older snapshot). Dry-run by default.
- Secrets (`.env`, `.env.*`) excluded from every generated scope; a graph is queryable.
- Documented two failure modes that produce useless bug reports: a stray file named
  `nul` makes `index_repository` fail with a bare "Pipeline failed", and the
  dashboard's NODES/EDGES tiles read **0** on a perfectly healthy index.

Applied to a real 45-project index, these rules took it from ~570,000 nodes to
**54,553** while covering more projects than before.

## What's new in v6.9.3

- Hermes `unrestraint-packs` skill (routes to the prompt library) in both Hermes trees + canonical skills.
- Codex CLI reinstalled fresh (0.147.0); all providers verified live with the V6.9.2 block.
- Stale backups, duplicate skill trees, and scratch purged from every provider home.

## What's new in v6.9.2

- `0-UNRESTRAINT-PACKS/` — the no-holds prompt library: operator Fun stuff kit
  (AIO, Story, Websim, Vision caption kit, Tags), Spiritual-Spell-Red-Teaming,
  UltraBr3aks, tuxsharxsec jailbreaks, claude-fable red-team corpus, Tavern presets.
- V6.9.2 unrestraint block wired into Claude Code / Codex / Kimi / Grok workspace
  instruction files (backups kept).
- Start at `0-UNRESTRAINT-PACKS/README.md`.

## What's new in v6.9.1

Useful Fun stuff techniques, not the jail collections:

- `adult-image-caption` and `adult-character-sheet`
- Jailbreak GitHub kits were **not** imported

Full detail in [V6.9.1-CHANGELOG.md](V6.9.1-CHANGELOG.md).

## What's new in v6.9.0

One-shot coverage for fictional-adult game-modding, not a jailbreak layer.

- **AIO rule 11** — do the OStim / SexLab / explicit-ID work; do not sanitize;
  still refuse child, age-ambiguous, and real-person sexual content
- **`fictional-adult-modding` skill** + router row so agents stop treating
  legal adult-mod work as out of policy
- **Tools already current** (checked 2026-08-15 against GitHub/npm). No bump.
- Jail pastes stay out of the installed contract. `PROMPTS/README.md` says why.

Full detail in [V6.9.0-CHANGELOG.md](V6.9.0-CHANGELOG.md).

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
- **Extras:** `.\INSTALL-V7-AIO.ps1 -WithExtras` (claude-mem is Claude Code only
  and needs Bun).

## Gates (new in v6)

```powershell
python TOOLS\audit_skills.py <skills-dir>
powershell -NoProfile -ExecutionPolicy Bypass -File .\TESTS\Test-V7-Pack.ps1
python TOOLS\install_live_skills.py _V7-CANONICAL-SKILLS --check
```

v5.2.5's registry had *already warned* that BOM/encoding drift breaks
valid-looking files, and v5.2.5 shipped BOMs anyway. A warning in a document is
not a control; these are. `Test-V7-Pack.ps1` checks every skill tree, parses
every shipped `.ps1`, verifies offline-asset hashes, and sanity-checks the
registry.

## Known limitations

- 19 skills exceed the tier-1/tier-2 context budget (22 warnings). They work;
  they are not free. Trimming is deferred, not done.
- **The knowledge graph cannot read Papyrus.** `codebase-memory-mcp` has no
  `.psc` parser and skips `scripts/` via a built-in skip-list, so Skyrim mod
  logic never enters the graph no matter how you configure it. The graph covers
  C/C++/C#/Python/TS/Go/PHP and file structure — SKSE plugins and tooling, not
  Papyrus. Use Grep + the `papyrus-reference` skill there.
- `unrestraint-packs` is kept Hermes-only by a hardcoded `SCOPED` map in
  `TOOLS/fanout_providers.py`. The mechanism works, but nothing validates that the
  map matches intent — a wrong entry would be as silent as the bug it replaced.
- Everything here is **tool-validated** — gates pass, scripts parse, hashes
  verify, and the BOM fix is confirmed live in a provider's own skill listing.
  The installer has **not** been run end-to-end on a clean machine as part of
  this build. The v7.5.0 preamble wiring was sandbox-tested (fresh file,
  existing file, BOM file, re-run replace); the remote bootstrap download
  and extract path was exercised against a local archive.

## Version

**v7.5.1** — 2026-08-16. Based on v7.5.0.

## License

Pack documentation and original installer scripts are provided as-is for
personal and community use. Third-party tools inside `BUNDLED-TOOLS` keep their
own licenses (see [BUNDLED-TOOLS/THIRD-PARTY-NOTICES.md](BUNDLED-TOOLS/THIRD-PARTY-NOTICES.md)).
