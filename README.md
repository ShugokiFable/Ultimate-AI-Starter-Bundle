# Ultimate AI Starter Bundle v7.9.9.9

**Ultimate multi-provider AI starter kit** - not a Skyrim-only pack.

Install skills, MCP servers, plugins, and offline tools for:

- **Claude Code**, **Codex**, **Grok**, **Kimi**, **Hermes**
- Code graph memory (with the indexing discipline that keeps it small), context compression, browser/scrape MCPs
- Optional deep **Skyrim SE/AE** modding stack (houseCARL, Spooky, Forge, frameworks)

Skyrim is a major included domain. The pack is also a general "good start" for serious AI-assisted development.

---

## ⚡ NEW TO AI CLI TOOLS? Read this first: installed ≠ enabled

One distinction explains almost everything about how this pack behaves:

| State | What it means | What it costs you |
|---|---|---|
| **INSTALLED** | The tool exists on disk | Disk space only. **Zero** effect on your AI chats. |
| **ENABLED** | Registered in a provider's config | Its tool descriptions ride along inside **every message you send, in every chat, forever** — related to your task or not. |

The 146 **skills** are the opposite deal: they all sit installed and cost nearly nothing until one actually matches your task. MCP servers get **no such discount** — measured in this pack, the heaviest server (houseCARL) burns ~17,000 tokens *every single turn*, and enabling the entire catalog would cost ~40,000+ tokens/turn before you've typed a word. That's why the installer enables almost nothing.

### What's ON after install

Exactly three servers, everywhere: `context7` (library docs), `github` (repo access — zero-config for new users), `headroom` (context compression). Total: ~3,700 tokens/turn. Everything else is **parked**: installed, harmless, invisible, free.

### There is NO auto-disable. No timer. No expiry.

If your AI enables something to do a job — say, the Roblox Studio server during a game jam, or houseCARL to debug a mod load order — **it stays on across restarts and chats until a human turns it off.** That is deliberate: nothing will silently rip tools out from under a running project, and nothing will silently bill you either — the switch is visible and yours. Done with it? Park it in one line:

```powershell
# Hermes (then restart the app)
hermes config set mcp_servers.<name>.enabled false   # true to re-enable

# Claude Code
claude mcp remove <name>          # claude mcp add ... to bring it back

# Codex / Grok / Kimi — open the provider's config file and set enabled=false,
# comment the entry out, or delete it. Restore the same way.
```

Not sure what's on, or what a task actually needs?

```powershell
powershell -ExecutionPolicy Bypass -File TOOLS\Set-McpProfile.ps1 -List            # see profiles & state
powershell -ExecutionPolicy Bypass -File TOOLS\Set-McpProfile.ps1 -Auto -Path C:\code\my-app   # enable just what THIS project needs
```

Rule of thumb: **enable for the job, park it after** — or just leave the small stuff on and never think about it again. The pack's agents know this too: the `capability-profiles` skill tells them to flip servers on and off themselves as tasks come and go.

---

## AI preamble (`AIO-INSTRUCTION.txt`)

Compact variants for smaller hosts: `PROMPTS/AIO-INSTRUCTION-COMPACT-CORE-v1.0.md` and `PROMPTS/AIO-INSTRUCTION-WEB-CORE-v1.0.md`.

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


## SOUL + AIO for every agent (v7.5.0)

The preamble is now **installed automatically**, not pasted by hand:

- `3-PREAMBLES/SOUL.md` - the operator's own soul config (unrestricted, no
  yes-man, truth-seeking process, output format), shipped verbatim and
  identity-neutral: it names no provider, so it is safe in all five
- `3-PREAMBLES/MANUAL-PASTE.txt` — for web UIs (ChatGPT/Gemini) that have no
  instruction file: paste it into the custom-instructions box

`INSTALL-V7-AIO.ps1` appends `SOUL.md` + `AIO-INSTRUCTION.txt` to
Claude Code (`~/.claude/CLAUDE.md`), Codex (`~/.codex/AGENTS.md`), Kimi
(`~/.kimi-code/AGENTS.md`) and Grok (`~/.grok/AGENTS.md`, its global-rules
file), and copies the verbatim soul into Hermes' home (`SOUL.md`). Idempotent
and backup-first; `-SkipPreamble` opts out. Full map:
`3-PREAMBLES/README.md`.

## Quick start

**Fresh machine, nothing installed - one command:**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/ShugokiFable/Ultimate-AI-Starter-Bundle/main/INSTALL-REMOTE.ps1 | iex"
```

Downloads the latest release, extracts to `%LOCALAPPDATA%\Ultimate-AI-Starter-Bundle`,
and runs the full installer (skills, tools, MCP servers, gates, SOUL + AIO
preamble). With parameters:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "& ([scriptblock]::Create((irm https://raw.githubusercontent.com/ShugokiFable/Ultimate-AI-Starter-Bundle/main/INSTALL-REMOTE.ps1))) -Providers Claude,Grok"
```

Or double-click `INSTALL-REMOTE.bat`. Re-running is a no-op.

**Windows (bundle already on disk)**

1. Double-click **`START-HERE.bat`**. (`INSTALL-V7-AIO.bat` remains only as a legacy compatibility alias.) Or run:

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

- **Provider skills** — 146 skills per AI (Claude, Codex, Grok, Kimi, Hermes), all generated from one canonical tree. v7.8.0 added 57 focused cross-domain reasoning/reliability skills; v7.9.0 removed `skyrim-forge-bridge`, which documented a preview tool that no longer exists and told the agent the shipped Forge could not write plugin records.
- **houseCARL** MCP + MO2 instance or Vortex shim setup
- **Spooky's AutoMod Toolkit**
- **codebase-memory-mcp** — plus the v7 index scope tooling (`.cbmignore` project template + `TOOLS/Setup-CodebaseMemory-Index.ps1`) so the graph indexes source, not asset trees
- **Headroom** (context compression, registered as an MCP server — see [Headroom + Grok](#headroom--grok))
- **Superpowers** + **Ponytail** plugins/skills
- **CodeBurn** (optional, via npm/npx)
- Grok MCP wiring + portable tool discovery

### Skyrim Forge

**Skyrim Forge 6.0.0 is developed in this repository**, at `BUNDLED-TOOLS/skyrim-forge`. It is source, not a downloaded payload, so both release variants carry it in full and there is no separately released archive that can drift out of step with the installer that reads it -- which is exactly how v7.8.0 shipped an installer calling a contract field Forge never emitted. The AIO installs or repairs it into ONE versionless install root, migrating any version-stamped install onto it and preserving `Workspaces` and the virtualenv, wires supported selected-provider integrations, sets `SKYRIM_FORGE_ROOT`, and proves the result runs with `forge doctor` before the final success banner. Choose where it lands with `-ForgeRoot`; the default is `%LOCALAPPDATA%\Skyrim-Tools\Skyrim-Forge`.

## Update tools later

```powershell
.\TOOLS\Update-From-GitHub.ps1
.\TOOLS\Update-From-GitHub.ps1 -Components housecarl,codebase-memory -UpdateCatalogOffline
.\TOOLS\Ensure-Tools.ps1
.\TOOLS\Setup-HouseCarl.ps1
```

## Layout

```text
1-TAILORED-PROVIDER-TREES/   per-AI tailored skill trees
BUNDLED-TOOLS/offline/             shipped tool zips/wheels
BUNDLED-TOOLS/plugins/             Superpowers + Ponytail
BUNDLED-TOOLS/CATALOG.json         component registry
COPY-TO-YOUR-WORKSPACE/            workspace files + _PROJECT-TEMPLATE (incl. .cbmignore)
0-UNRESTRAINT-PACKS/               no-holds prompt library (v6.9.2)
3-PREAMBLES/                      SOUL + AIO preamble for every agent (v7.5.0)
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

## What's new

Recent releases first; full detail in `docs/history/V<ver>-CHANGELOG.md`.

### v7.9.9.1 — The always-on three

- **Machine-wide MCP profile flip executed.** Every provider surface
  (Hermes, Claude Code, Claude Desktop, Codex, Grok) now runs exactly
  three always-on servers — `context7`, `github`, `headroom`. Everything
  else (housecarl, skyrim-forge, codebase-memory, firecrawl,
  sequential-thinking, serena, playwright, roblox-studio, robloxforge)
  is registered but off by default, enabled per task by the
  `capability-profiles` skill via `Set-McpProfile.ps1`.
- `capability-profiles` canonical skill updated: "always-on two" is now
  "always-on three"; provider copies byte-identical.
- MANIFEST.json regenerated for the new hashes.

### v7.9.9 — Truthful capability routing

- **Every capability claim re-measured on a clean machine.** Hermes' keyless web
  ring was re-verified from an isolated home with all credentials scrubbed: five
  vendors, search and extract, no key — and the native extract really renders
  (3.1x more content than a plain fetch on a JS-heavy page).
- **Firecrawl MCP: 2 of 25 tools work keyless**, `extract` is deprecated, and
  `parse` needs a self-hosted URL. The catalog's old claim was wrong on two
  counts. It is generated now by `TOOLS/measure_mcp_capability.py`, which keeps
  *rate-limited* separate from *needs a key* — the daily-limit message
  recommends OAuth, and reading it as an auth failure inverts the conclusion.
- **Registration is a choice, not a side effect.** `-WithExtras` no longer
  registers firecrawl-mcp without a key: keyless it costs ~9,080 tokens every
  turn for two tools you already have. It is an npx server, so nothing is
  cached either way. `-RegisterKeylessExtras` overrides.
- **The doctor now reports capability state** — registered where, keyless tools,
  schema cost, and why something is deliberately off.
- **Codex:** shortening skill descriptions does *not* fit more into its index —
  measured. Entry count is the only lever, so nothing was trimmed and the doctor
  now names what is actually removable.

### v7.9.8.5 — cbm dashboard zeros: confirmed upstream, workaround shipped

- `codebase-memory` skill documents **issue #1663**: the web dashboard's
  NODES/EDGES zero-tiles are an upstream allowlist regression (0.10.5+), not
  your data — and ships the working shape of the fix (same-origin stats proxy).
- Warns that #1764's accepted idle-CPU root cause **failed an A/B repro**;
  do not trust it as solved.
- Version gate accepts 4-part point releases (`7.9.8.5`) without failing CI.

### v7.9.8 — Best tool wins: capability routing

- **`capability-routing`** — one new skill, added only after auditing six that
  might already have owned it. It answers *what is the hard part, and which
  available capability owns it* — and it cuts both ways: do not write a crawler
  when a rendered extractor exists, and do not launch a browser stack to read a
  static JSON file.
- **Escalate the class, don't tune the weak tool.** After two failures of the
  same shape — challenge page, empty JS shell, 403/429, extract that holds only
  the nav — change the class of tool instead of adding another header.
- **A fresh Hermes install no longer inherits five MCP servers** from a starter
  template that contradicted its own README. Root cause fixed, and the installer
  now refuses any template declaring live MCP entries or an `@latest` package.
- **Firecrawl stays native, on measurement.** Hermes' own keyless web ring does
  search and scrape with no key; `firecrawl-mcp` costs ~9,084 tokens every turn
  and keylessly offers nothing the native route lacks. Install it with
  `-WithExtras` when you have a key and need crawl/map/interact.
- **`TOOLS\Measure-McpSchemaCost.ps1`** — measure what a server costs before
  arguing about it. Tools is the wrong unit; bytes is the right one.
- `final_pack_version` removed from 37 skills. `VERSION.txt` is the authority.

### v7.9.7 — Stop assuming: evidence closure

- One new skill after auditing eleven existing ones: `visual-verification`. If
  appearance is part of the requirement, the **rendered output** is the evidence
  — not the DOM, the CSS, the scene tree or a passing test.
- It ships a **canary** rather than an instruction: an image whose contents are
  stored only as a hash, so a session can prove it actually sees pixels instead
  of claiming it. A failure is a reportable answer, not an error.
- `TESTS/evidence-scenarios/` — eight fixtures with rubrics for the behaviour
  itself: a rendered defect invisible in source, a grey box that is really a
  404, a crash whose log already names the cause, the same crash with nothing to
  read, a version-specific fact, a stable fact that must **not** trigger
  research, a screenshot without vision, and a secret in the environment.
- **Supabase withdrawn** — the only profile needing an account and a token. The
  migration un-registers only what this pack created.
- **Blender pinned to 1.8.3** and discovered from `%APPDATA%\Blender Foundation`
  instead of a maintainer's Steam drive. A contract now fails the build on any
  hardcoded drive letter or user directory in a shipped config.
- **sequential-thinking left the always-on core**: 1 tool, but a 4,587-byte
  schema — ~1,146 tokens every turn, as much as context7's two. Now the opt-in
  `reasoning` profile, never auto-enabled; existing machines are told, not
  edited.
- Codex reports "Exceeded skills context budget" at this many installed skills,
  which removes every description and breaks description-based routing there.
  Measured and reported by the doctor; not yet solved.

### v7.9.6 — Profiles scoped to a project

- 7.9.5 detected profiles per project and registered them per machine: every
  entry in `PROFILES.json` carried `"scope": "global"`, so enabling one for a
  single repository put its tool schemas into every session on the box. Fixed.
- Each profile is now written where only its project sees it — Claude Code's
  local scope in `~/.claude.json`, Grok's `<project>\.grok\config.toml`. Codex,
  Kimi and Hermes have no project-scoped MCP config, so they are skipped with
  the reason printed; `-Global` is the opt-in.
- `code-deep` is renamed `code-intel` (the old id still resolves), and Serena is
  told which project with `--project <path>`.
- `-List` distinguishes **installed** (on disk, free) from **enabled**
  (registered, costs context every turn) and prints which project each profile
  is on for.
- Six unrelated defects found while building it: a crash when `GetFolderPath`
  returned an empty string, a successful `uv` install treated as fatal because
  it writes to stderr, a `.bak` file dropped into the user's project on every
  install run, `-Disable` sweeping the current directory, and an unmounted drive
  killing the run through both `Test-Path` and `Join-Path`.

### v7.9.5 — Capability profiles

- Seven MCP servers added as **profiles**, not global registrations: Serena,
  Chrome DevTools, shadcn, Supabase, Blender, Godot, Unity. (7.9.5 still wrote
  them machine-wide once enabled; v7.9.6 scopes them to one project.)
- `TOOLS\Test-McpHandshake.ps1` proves a configured server actually answers, and
  reports what it costs: **188 tool schemas rode in context on every Claude turn**
  on the development machine before this release.
- `TOOLS\Set-McpProfile.ps1` wires a profile only when the project needs it and
  the machine can run it; anything else is skipped with the reason printed.
- Both MCP writers now share `TOOLS/V7-Mcp-Write.ps1`. Its new gate found two
  defects immediately, and the handshake probe found a third on a live config:
  Codex still held `@playwright/mcp@latest` with no `-y`, blocking npx forever.

### v7.9.2 — One repository + real Windows closure

- Skyrim Forge 6.0.0 is developed and shipped directly under `BUNDLED-TOOLS/skyrim-forge`; no separate Forge payload/release can drift from the bundle installer.
- `START-HERE.bat` is the canonical launcher and failures persist to `INSTALL-LAST.log` / `INSTALL-FAILED.txt`.
- Real Windows runs restored the missing Kimi/Hermes plugin helpers and exposed the final doctor's PowerShell 5.1 `$HOME` collision; both are release-regression tested.
- The final installed-state doctor uses `forge doctor` (`result: PASS`, `read_only_ready: true`) instead of the removed Forge 5.x bundle handshake, and its child-process diagnostics are replayed into the durable transcript.
- The `skyrim-forge` skill and all five provider copies now describe Forge 6.x and the versionless `SKYRIM_FORGE_ROOT` install.

### v7.9.0 — Forge install/layout repair

- Migrated Forge to one versionless live root and added `-ForgeRoot`.
- Removed the obsolete bridge skill and reduced the canonical set to 142 skills.
- Made the release contracts/version surfaces release-agnostic instead of hardcoding 7.8.0.

### v7.8.0 — One-shot reliability + fresh-Windows hardening

- 57 new focused generic reliability/reasoning skills (v7.8.0); 142 total per provider since v7.9.0 removed a skill describing an unshipped product.
- Fresh-Windows provider bootstrap, final installed-state doctor, deterministic UTF-8-safe release packaging, and fail-closed install/runtime gates.
- At v7.8.0, Skyrim Forge was still a separately versioned 5.2.x payload; v7.9.2 supersedes that design with the in-repository Forge 6.0.0 source tree.
- Hermes defaults are tuned for DeepSeek V4 Flash 0731: maximum main reasoning (`max`), explicit execution/completion/verification guards, 120k compaction threshold, 30% recent-tail preservation, cache-friendly pruning, 1-hour prompt-cache TTL, and reasoning-free mechanical compression.

### v7.7.9 — Installer respects existing installs; compression tuned

- The AIO keeps existing houseCARL/Spooky installs (`kept-existing`) instead
  of overwriting them when `HOUSECARL_MCP` / `SPOOKY_AUTOMOD_ROOT` point at
  valid roots — curated tool copies survive re-runs.
- Hermes starter config compacts earlier (threshold 0.14, leaner tail) with
  `in_place` + idle compaction enabled.

### v7.7.8 — Skill tree dedupe

Five dead module docs (lowercase `skill.md`, never loaded by any agent) and
two KID/SPID distribution twins that duplicated `kid-authoring` /
`spid-authoring` were pruned from the skill tree. The twins' validate
scripts and pinned authority references moved into the grammar owners;
`install_live_skills.py` now skips dirs without a `SKILL.md` so dead skills
can't propagate to provider homes again.

### v7.7.7 — Hermes keeps plugin skill copies

Hermes derives `/skill-name` slash commands and desktop autofill from the
skills dir, not from plugin registrations. The native-plugin dedupe
deleted the Superpowers/Ponytail copies there, so `/using-superpowers`
stopped autocompleting (`Unknown command`) after a restart. Hermes no
longer runs that dedupe, mirroring the Grok exemption from v7.7.5.

### v7.7.6 — Ensure-Headroom-Grok MCP cliff guard parses

`Ensure-Headroom-Grok.ps1` interpolated
`$((if($pluginActive){...}))` — the extra paren made Windows PowerShell
parse `(if ...)` as a command call, so the 7-server MCP cliff guard threw
(`if` not recognized) instead of printing its warning. Removed the
redundant paren; the guard reports `mcp-search plugin disabled.` cleanly.

### v7.7.5 — Grok Superpowers copies stay

Native-plugin dedupe deleted `~/.grok/skills/verification-before-completion`.
Grok loads that path; the TUI then shows the skill as failed with no
reason. Copies stay. One Superpowers *plugin* is still required.

### v7.7.4 — Starter `$HOME` abort, one Grok Superpowers, no Claude skill leak

`Install-Provider-Starter-Settings.ps1` assigned `$home`, which is a
PowerShell constant, so the whole starter-settings pass died. Renamed to
`$provHome`. Grok no longer installs a second local Superpowers clone next
to the official marketplace copy (that collision is the
`systematic-debugging` TUI error). `[compat.claude] skills = false` so
Grok does not load claude-mem skills or `mcp-search`.

### v7.7.3 — Portable provider settings + Forge layout

`INSTALL-V7-AIO.ps1` now installs starter `settings.json` / `config.toml` /
`config.yaml` for Claude, Codex, Grok, Kimi, and Hermes from
`1-TAILORED-PROVIDER-TREES\<Provider>\COPY-TO-PROVIDER-HOME`. Those templates
are machine-neutral. A live dump of one PC is refused. Existing homes are
not overwritten. Unrestraint stays in `0-UNRESTRAINT-PACKS` and in the
instruction files (`CLAUDE.md` / `AGENTS.md` / `SOUL.md`), not in settings.

Skyrim Forge 6.0.0 is installed and repaired by the v7.9.2 bundle under the
Skyrim tools layout. Do not create a second manual copy in Documents. Grok's
MCP registration still respects its running-server safety budget.

### v7.7.2 — Grok MCP cliff guard

`Ensure-Headroom-Grok.ps1` used to force headroom into `~/.grok/config.toml`;
with 7 servers already configured plus claude-mem's `mcp-search` plugin
server, Grok hit the documented 8-running-server wedge and stopped replying.
The script now refuses to register past the cliff, and Grok users disable the
plugin server with `grok mcp disable mcp-search` to free the slot.

### v7.6.7 — the root folders are numbered 0, 1, 2, 3 again
- Deleting `2-OPTIONAL-SHARED-GENERIC` in v7.6.6 left the root numbered
  0, 1, 3, 4. Renumbered: `2-OPTIONAL-MANUAL-OTHER-GAMES-MEGA-PACK` and
  `3-PREAMBLES` (was 4-). `1-RECOMMENDED-SEPARATE-TAILORED` became
  `1-TAILORED-PROVIDER-TREES` — with the generic tree gone, "recommended" was
  answering a question that no longer exists.
- Every live reference updated: installer, pack gate, fanout tool, manifest
  generator, .gitignore, BOOTSTRAP, guide, prompts and layout docs. Historical
  changelogs keep the names that were true then.
- Full detail in `docs/history/V7.6.7-CHANGELOG.md`.

### v7.6.6 — dead trees, dead models, and a live MCP health sweep
- `2-OPTIONAL-SHARED-GENERIC` is gone. The installer has only ever read
  `1-TAILORED-PROVIDER-TREES`, and the two trees were 97% byte-identical —
  40 MB of duplication that only existed to drift. `fanout_providers.py`, the
  pack gate and the layout docs now treat the tailored tree as the only one.
- `0-UNRESTRAINT-PACKS` cleaned: retired-generation jails out (Claude 3.7/4,
  GPT-5/5.1/5.2, Gemini 2.5-era, Grok 3), 25 md5-verified byte-identical
  duplicates collapsed to one canonical copy each (~470 KB), stale "current
  strongest" labels and a wrong "last updated" stamp fixed.
- The housecarl skill's inert `.mcp.json` template (a `${CLAUDE_PLUGIN_ROOT}`
  path that resolves nowhere) removed from all copies — the installer wires
  housecarl into each agent's real config; the template was a trap.
- Full MCP health sweep across all six agents: all 42 configured servers
  verified launchable. Found and fixed on the machine: Skyrim-Forge's venv
  `.pth` still pointed at the deleted 5.1.3 folder (its upgrader never updates
  it), which is why Hermes kept parking `skyrim-forge`.
- Full detail in `docs/history/V7.6.6-CHANGELOG.md`.

### v7.6.5 — a hook that can hang wedged the whole Grok session
- `assumption_gate`'s drive check probed every letter A-Z with `os.path.isdir`.
  A sleeping or disconnected network drive blocks that probe for *seconds per
  letter* — so the hook outlived Grok's 15s timeout, and Grok wedges when it
  has to kill a hook. Now reads the `GetLogicalDrives` bitmask (6ms, never
  touches a device; disconnected-but-mapped letters count as existing, the
  fail-open direction).
- Both gates gained a hard watchdog: armed before anything else runs, the
  process `os._exit(0)`s at 10s (pre) / 25s (stop) — under every host's
  timeout (Grok/Claude/Codex 15/30, Hermes 20/40). Whatever hangs, the host
  is never forced to kill the hook.
- Verified: stdin held open forever -> gate exits at 2s; bad drive still
  denied; all four providers' wired commands exit 0 with the fixed scripts.
- Full detail in `docs/history/V7.6.5-CHANGELOG.md`.

### v7.6.4 — Grok hook errors on every tool use
- Grok runs hook commands through PowerShell, and the gate installer wrote
  cmd-style `"python" "script.py" --pre` — a parse error without the `&` call
  operator (`At line:1 char:65`, twice per tool call). The gates never ran.
- `New-HookBlock` gained a `-CallOperator` switch; only Grok's block gets the
  `& ` prefix, because cmd.exe (Claude's shell) chokes on it. All four wired
  commands verified to parse and exit 0 in the exact form Grok receives.
- Full detail in `docs/history/V7.6.4-CHANGELOG.md`.

### v7.6.2 — the repair tool would have corrupted a config, and CI now exists
- `Repair-McpPaths` swapped paths as literal strings, but a JSON config stores
  every separator doubled — so the replacement came out at the wrong escaping
  level and would have made `mcp.json` unparseable. Caught by the tool's own
  dry-run default. Fixed, with three new gate assertions including a round trip.
- This repo now has CI: the pack gate on `windows-latest` under **Windows
  PowerShell 5.1** (not pwsh — 5.1's encoding behaviour is what the pack
  targets), MANIFEST hash verification, and a version-consistency check.
- Full detail in `docs/history/V7.6.2-CHANGELOG.md`.

### v7.6.1 — the other 25 places that read a file wrong
- v7.6.0 fixed one ANSI-decoding read; this sweeps the remaining 25 across 10
  files to `[IO.File]::ReadAllText`.
- One was a config-destroying bug that had not fired yet: `Add-Reasoning-MCPs`
  read `~/.claude.json`, round-tripped it through JSON and wrote it back —
  measured on the real file, all 26 em dashes destroyed. It only stayed dormant
  because the script skips writing when nothing needs adding.
- New gate section 7b fails the build if a bare `Get-Content -Raw` comes back,
  and was verified to actually fail rather than merely pass.
- Full detail in `docs/history/V7.6.1-CHANGELOG.md`.

### v7.6.0 — the preamble told four agents they were a fifth product
- `SOUL.md` opened with "You are Hermes Agent ... created by Nous Research", and
  that file is injected verbatim into Claude's `CLAUDE.md` and Codex/Kimi/Grok
  `AGENTS.md`. Since v7.5.0 four agents were being told they were a different
  vendor's product. The opening is now provider-neutral.
- The installer re-created mojibake on every run: it read the preambles with
  `Get-Content -Raw`, which on PS 5.1 decodes as Windows-1252, turning the three
  em dashes in `AIO-INSTRUCTION.txt` into `â€"`. v7.5.6 cleaned the files but
  not the code that rewrote them. Now `[IO.File]::ReadAllText`.
- The installer no longer pushes Grok past eight running MCP servers, which
  wedges `grok-cli` at startup. Adding `skyrim-forge` was unchecked and took a
  fresh install to 7 configured; it is now refused with the reason, overridable
  with `-GrokMcpBudget`.
- New `TOOLS/Repair-McpPaths.ps1` fixes MCP servers pointing at a version folder
  that no longer exists — found live: Claude was still on `Skyrim-Forge-5.1.0`
  after the 5.1.3 upgrade and its MCP was silently dead. Runs on every install.
- Full detail in `docs/history/V7.6.0-CHANGELOG.md`.

### v7.5.6 — native stderr is no longer a red error block (or a crash)
- New `Invoke-V5Native` helper: pip's "already satisfied" / pip-upgrade notice
  prints as plain text instead of a `RemoteException / NativeCommandError`
  block; `npm install -g`, `npx` installs, and `claude mcp add` can no longer
  be terminated by a stderr write under the script-wide `$ErrorActionPreference='Stop'`.
- Measured PS 5.1 gotcha: a function parameter named `$Args` silently breaks
  `$LASTEXITCODE` propagation — the helper avoids it on purpose.
- `playwright-mcp` no longer forces Google Chrome: set user env
  `PLAYWRIGHT_MCP_EXECUTABLE_PATH` to your browser exe (Opera GX, Brave,
  Vivaldi, ...) and the installer appends `--executable-path` to the MCP
  wiring. Verified live against Opera GX via CDP.
- Full detail in `docs/history/V7.5.6-CHANGELOG.md`.

### v7.5.5 — Hermes config.yaml wiring + complete "What's new"
- Your Hermes config (model routing, MCP, hooks) now ships in the tailored
  tree and the installer wires it into the Hermes home — backup-first,
  idempotent, `-SkipHermesConfig` to opt out.
- README "What's new" now lists **every** release (was missing 8); stale
  `CATALOG.json`/`VALIDATION.json` version metadata fixed.
- Full detail in `docs/history/V7.5.5-CHANGELOG.md`.

### v7.5.4 — unrestraint-packs is a common provider skill
- `unrestraint-packs` is no longer Hermes-scoped. The canonical source fans it
  out to **Claude, Codex, Grok, Kimi and Hermes** alike.
- Installer help/comments corrected to the measured Grok limit: **8 running MCP
  servers wedge grok-cli 1.0.4; 7 are safe** — budget 6 configured when a
  plugin supplies one.
- Existing Grok MCP config is untouched (operator-owned).

### v7.5.3 — houseCARL pointed at a path called "C"
- Single-MO2-instance machines hit a PowerShell array-unroll bug that persisted
  `SKYRIM_MO2_INSTANCE = C`. Forced array semantics + a guard that refuses an
  instance dir without `ModOrganizer.ini`.
- `CATALOG.json` pack version and `updated_utc` were 7 minor versions stale.
- Dangling changelog/AIO-file references left by the 7.5.2 declutter fixed.

### v7.5.2 — version drift, a pinned install tag, root clutter
- The documented remote install hard-pinned `-Tag v7.5.0`, freezing every
  documented install at 7.5.0. Pin removed (empty tag = latest release).
- Installer banner + internal version still said 7.5.0; both track the release.
- Duplicate `AIO Instruction.txt` removed; 26 per-version changelogs moved to
  `docs/history/` (root markdown drops 33 → 7). Nothing deleted.
- The release gate blocked its own commit (porcelain `XY` Y-column ignored);
  fixed and self-tested.

### v7.5.1 — three installer bugs, found by running it end-to-end
- Grok compat-cells rewrite could eat every `[mcp_servers.*]` block after
  `[compat.claude]` on re-runs.
- Headroom's pip step died on PATH pythons without pip and on pip's stderr.
- Gates/reasoning-MCP wiring silently no-op'd on multi-provider installs.

### v7.5.0 — SOUL for every agent + one-command install from zero
- **`3-PREAMBLES/`** — the operator's SOUL (verbatim), an identity-neutral
  universal SOUL, and a manual-paste file for web UIs. The installer wires
  SOUL + the AIO contract into Claude Code, Codex, Kimi, Grok and Hermes
  (idempotent, backup-first, `-SkipPreamble`).
- **One command from zero** — `INSTALL-REMOTE.ps1`/`.bat` downloads the latest
  release, extracts it and runs the full installer. Releases carry a zip asset.
- Hermes home catalog fix (`%LOCALAPPDATA%\hermes`, was `~/.hermes`);
  `BOOTSTRAP.txt` now bootstraps from GitHub.

### v7.4.3 — the real Grok limit: 8 running servers; a plugin was eating a slot
- Bound tested rather than assumed: every 6-server set OK (5.6–24.9s); **every
  7-server set wedged**. It is a count, not composition.
- The free-rider: enabled Claude plugins with `.mcp.json` load servers that are
  **invisible in `config.toml`** (`[compat.claude] mcps = false` doesn't stop
  them). 7 configured + mcp-search = 8 running = wedge.
- **The limit is 8 running; 7 is fine.** Local install moved to 6 servers.

### v7.4.2 — MCP does work in Grok; I read a constant as a signal
- `tool_count: 26` was never proof MCP was off — Grok deliberately uses
  `search_tool`/`use_tool` and never injects MCP tools. A direct tool call
  returned real data. **MCP works.**
- The stall is the **server-count limit** (≤5 fine, 7+ wedges).
- Wiring restored as an installer default (4 servers), `[compat.claude] mcps =
  false` kept for the right reason.

### v7.4.1 — the installer now applies the Grok fix
- New `Set-V5GrokCompatCells` writes `[compat.claude] hooks = false` / `mcps =
  false` into `~/.grok/config.toml`, backup-first, BOM-free (PS 5.1 `utf8`
  emits a BOM that breaks TOML parsing — caught by parsing the result).
- Grok MCP wiring made opt-in (`-WireGrokMcp`).

### v7.4.0 — the Grok softlock, actually measured
- **Two real causes.** (1) Grok runs Claude's hooks: 14 entries from 6 sources,
  two `Stop` hooks at `timeout:30` cost a measured **60.037s per turn** —
  `hooks = false` is the only lever. (2) A server-count stall (`mcp_wait_ms`
  ~34,900 on first turn). Turn time after both: **2.1–4.9s.**
- **Corrections:** Rule 1 (never touch `config.toml`) and Rule 6 (orphan fleets)
  were wrong; the cleanup tool that killed "orphans" was killing Claude Code's
  own servers and is **removed**. Rules 2–5 kept as hygiene.
- Hook gates could hang: `sys.stdin.read()` waits for EOF; fixed with a minimal
  repro of the Windows stdin deadlock. Worst case now 2.2s.

### v7.3.1 — orphan-fleet cleanup tool
> **Superseded by v7.4.0.** The orphan-fleet diagnosis was wrong (see v7.4.0);
> the tool shipped here was removed. Kept as a documented record.

### v7.3.0 — Grok softlock forensics
- **`GROK-MCP-TROUBLESHOOTING.md`** — turn-phase log reading, field-tested
  rules, diagnosis cheat-sheet. The hang was tool-prep, not the model.
- Pin-every-npx rule; `codebase-memory` cold-daemon note.

### v7.2.2
- Firecrawl MCP pinned (`firecrawl-mcp@3.24.0`) — unpinned npx cold-resolves
  and can exceed Grok's 30s startup timeout.
- `codebase-memory` dashboard 0-tile lockdown (v0.10.5 UI-RPC, upstream #1663)
  documented with the correct verification path.

### v7.2.1
- `skyrim-forge` updated for Forge 5.x and documents the **provider-runtime venv
  trap** (venvs built from a deleted Codex runtime cache die, hanging every MCP
  client at startup).

### v7.2.0
- `fanout_providers.py` no longer widens scope, preserves line endings;
  `install_live_skills.py` stops making useless ~53 MB backups. V6→V7 rename
  completed for all live artifacts.

### v7.0.0
- **Indexing discipline for `codebase-memory-mcp`**: four bloat sources,
  case-sensitive `.cbmignore`, Papyrus never parsed, secrets excluded. Applied
  to a real 45-project index: ~570,000 → **54,553 nodes**.

### v6.9.3
- Hermes `unrestraint-packs` skill in both trees + canonical; Codex reinstalled
  fresh; stale backups/duplicate trees purged.

### v6.9.2
- **`0-UNRESTRAINT-PACKS/`** — the no-holds prompt library (operator Fun-stuff
  kit, Spiritual-Spell-Red-Teaming, UltraBr3aks, tuxsharxsec, claude-fable
  corpus, Tavern presets). Block wired into all provider instruction files.
  Start at `0-UNRESTRAINT-PACKS/README.md`.

### v6.9.1
- `adult-image-caption` and `adult-character-sheet`; jailbreak GitHub kits not
  imported.

### v6.9.0
- AIO rule 11 (do the OStim/SexLab/legal-adult work, don't sanitize) +
  `fictional-adult-modding` skill.

### v6.8.2
- **Assumption gate** — refuses nonexistent drives, hardcoded foreign homes,
  unread remote content. Hermes wiring through the tool; pack gates itself;
  MCP pins refreshed.

### v6.8.1
- Completeness gate on **all five providers** using each one's real mechanism
  (Codex = plugin, Hermes = config `hooks:`, **Kimi has none and is removed**).
  Hermes gained 3 MCP servers.

### v6.8.0
- `Add-Reasoning-MCPs.ps1` (context7, sequential-thinking, github) into four
  providers; codebase-memory-mcp 0.9.0→0.10.5, Headroom 0.33→0.35. Fixed both
  installers writing a UTF-8 BOM into JSON configs.

### v6.5.0
- **Completeness gate** (refuses push/end-of-turn while release is internally
  inconsistent), wired into all five providers. AIO-INSTRUCTION rewritten and
  cheaper; `BOOTSTRAP.txt`.

### v6.0.0 — correctness release
- 7 skills installed but their descriptions never loaded (UTF-8 BOM before
  frontmatter); the inverse rule (`.ps1` needs its BOM) classified by execution
  target. Canonical rebuilt from a working install; evidence registry 70→85.

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
- `unrestraint-packs` is installed for every supported provider by the canonical
  fanout. The `SCOPED` map remains available for any future, genuinely
  provider-specific skill, but is intentionally empty in this release.
- Everything here is **tool-validated** — gates pass, scripts parse, hashes
  verify, and the BOM fix is confirmed live in a provider's own skill listing.
  A real Windows PowerShell 5.1 run on an existing installation reached every
  provider and Forge 6.0.0, then exposed two final-doctor defects that are fixed
  and regression-tested in v7.9.2. A completely clean Windows machine remains
  the authoritative GitHub Actions gate after push. The v7.5.0 preamble wiring
  was sandbox-tested (fresh file, existing file, BOM file, re-run replace); the
  remote bootstrap download and extract path was exercised against a local archive.

## Version

**v7.9.9.9** — 2026-08-23. Installer hotfix: Register-MCP.ps1 crashed under PowerShell 5.1 when a provider had no prior skyrim-forge registration (stderr redirect under Stop preference). Affects every fresh machine with a claude/grok/codex CLI.

**v7.9.9.1** — 2026-08-22. Based on v7.9.9; the capability-profile policy became the machine-wide default on every provider.

**v7.9.9** — 2026-08-22. Based on v7.9.8.5; capability claims re-measured on clean machines.

**v7.9.8.5** — 2026-08-22. Based on v7.9.8; cbm field lessons (#1663 workaround, #1764 root-cause doubt) and a version gate that accepts point releases.

**v7.9.8** — 2026-08-21. Based on v7.9.7; capability routing, and a fresh-install path that no longer contradicts the bundle's own decisions.

**v7.9.7** — 2026-08-21. Based on v7.9.6; evidence closure — visual verification, evidence scenarios, Supabase withdrawn, sequential-thinking demoted on measurement.

**v7.9.6** — 2026-08-21. Based on v7.9.5; capability profiles scoped to one project instead of the machine.

**v7.9.5** — 2026-08-21. Based on v7.9.2; capability profiles for seven MCP servers.

**v7.9.2** — 2026-08-20. Based on v7.9.0; merged Forge 6.0.0 and Windows installer/doctor closure.

**v7.9.0** — 2026-08-20. Based on v7.8.0.

**v7.8.0** — 2026-08-20. Based on v7.7.15.

**v7.7.15** — 2026-08-20. Based on v7.7.14.

**v7.7.9** — 2026-08-19. Based on v7.7.8.

**v7.7.8** — 2026-08-19. Based on v7.7.7.

**v7.7.7** — 2026-08-19. Based on v7.7.6.

**v7.7.6** — 2026-08-19. Based on v7.7.5.

**v7.7.5** — 2026-08-19. Based on v7.7.4.

**v7.7.4** — 2026-08-19. Based on v7.7.3.

**v7.7.3** — 2026-08-19. Based on v7.7.2.

**v7.7.2** — 2026-08-19. Based on v7.7.1.

## License

Pack documentation and original installer scripts are provided as-is for
personal and community use. Third-party tools inside `BUNDLED-TOOLS` keep their
own licenses (see [BUNDLED-TOOLS/THIRD-PARTY-NOTICES.md](BUNDLED-TOOLS/THIRD-PARTY-NOTICES.md)).
