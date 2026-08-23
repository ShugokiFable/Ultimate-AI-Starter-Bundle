## 7.9.9.3

- Default `AIO-INSTRUCTION.txt` upgraded to ULTIMATE GENERAL AIO - UABS MAX v6.0 (16-section operating contract).
- New compact opt-in variants under `PROMPTS/`: COMPACT-CORE v1.0 and WEB-CORE v1.0 for smaller/web-only hosts.
- `3-PREAMBLES/SOUL.md` stripped of a legacy DECOMPOSE tail that leaked into every stamped provider block.

## 7.9.9.2
- Installer python probe now rejects virtualenv interpreters for `--user` installs (headroom component failed under venv-first PATHs); verified by full AIO rerun.

Installer hotfix. Register-MCP.ps1 threw under Windows PowerShell 5.1 whenever
a provider had NO prior skyrim-forge registration: `mcp remove ... 2>$null`
turns the harmless "not found" stderr into a terminating error under Stop
preference. Every fresh machine with claude/grok/codex CLIs hit this at the
Forge step (INSTALL FAILED, exit 1). Fix: merge streams (`2>&1`) at all three
remove sites. Found by running the real AIO installer end-to-end against the
post-v7.9.9.1 dormant-MCP machine state.

# Changelog

This file exists so the completeness gate can see the current version on the
same commit that bumped `VERSION.txt`. Detail lives in the dated files.

## 7.9.9.1

Applied this pack's own capability-profiles policy on a real four-provider
machine (Hermes, Claude Code, Claude Desktop, Codex, Grok; Kimi uninstalled).
The policy was already written; the machine had drifted from it.

- **Always-on core is now three, not two:** `context7`, `github`, `headroom`.
  Headroom joins because three tiny schemas buy compression that pays rent.
- **Everything else disabled by default on every provider**: housecarl,
  skyrim-forge, codebase-memory-mcp, firecrawl-mcp, sequential-thinking,
  serena, playwright-mcp, roblox-studio, robloxforge (~200 tool schemas and
  ~10k tokens/turn recovered). Per-provider mechanics differ -- Hermes
  `enabled: false` keys; Grok explicit `enabled = false` (its default is ON);
  Codex non-core blocks commented out (no verified disable key); the Claude
  pair strip global entries into a sibling `mcp-catalog.json` with one-line
  re-enable instructions. SaintsRowForge stays deliberately unregistered:
  installed is not enabled.
- **Re-enable is per task, not per machine**: flip the one server back on
  before the session that needs it, flip it off after. The catalog files and
  commented blocks preserve every original definition byte-for-byte.
- The canonical capability-profiles skill text was updated ("always-on two"
  -> "always-on three") and synced to all five provider trees.

## 7.9.9

Make the bundle's capability claims match what a clean machine can actually do,
without regressing 7.9.8's routing architecture. 146 canonical skills total; no
new skills, no new always-on MCP, and one server that used to be registered by
`-WithExtras` now waits for the key that makes it worth carrying.

- **The claim under review was my own, and it survived.** v7.9.8 said Hermes
  ships keyless `web_search`/`web_extract`. That was measured on a developer
  machine, which is not evidence about a new user, so it was re-run from an
  isolated `HERMES_HOME` with every provider credential scrubbed: **all five
  ring vendors served both search and extract with no key**, `web_search_tool`
  returned real results in 1.9 s, and the native extract genuinely renders --
  39,437 chars against a plain `urllib` fetch's 12,535 on a JS-heavy page
  (3.1x) in 0.4 s. Hermes already has rendered extraction at zero permanent
  schema cost.
- **The reviewer was half right, and the half matters.** Firecrawl's provider
  really does report `is_available() == False` without credentials -- that is
  the *keyed* path. `is_keyless_available()` returns True and the free ring is a
  separate resolution step. Quoting either method alone gives a false picture,
  so both are now written down next to each other.
- **An independent adversarial check reproduced all of it and found something I
  had missed.** Hermes 0.20.4 recognises throttling by string-matching, and
  Tavily's `hourly_cap_reached` is not in that list, so the ring treats a spent
  quota as permanent and stops failing over while four vendors are still
  answering -- ~15% hard failures on the default path during a cap window. That
  is upstream, not something this pack patches. It is documented instead of
  being claimed away, and the docs now say "failover on **recognized**
  rate-limit responses".
- **Firecrawl MCP, measured tool by tool.** Exactly **2 of 25** work keyless
  (`scrape`, `search`). 21 answer *"Unauthorized: API key is required"*.
  `firecrawl_extract` is **deprecated**, not key-gated. `firecrawl_parse` wants
  a self-hosted `FIRECRAWL_API_URL` -- so Firecrawl's own documentation, that
  Search/Scrape/**Parse** are free without authentication, does not hold for the
  pinned server. The catalog had claimed `interact` was keyless and `extract`
  needed a key; both were wrong, and nobody had called the tools.
- **That note is generated now.** `TOOLS/measure_mcp_capability.py` calls every
  advertised tool with credentials scrubbed and writes
  `BUNDLED-TOOLS/capability-records/`. It keeps **KEYLESS, NEEDS_KEY,
  DEPRECATED, RATE_LIMITED and UNVERIFIED** apart, and the throttle bucket
  exists for a reason: Firecrawl's daily-limit message recommends OAuth, so a
  naive classifier files a working keyless tool as needing a key. That is
  exactly how a first cut of this tool contradicted a correct measurement taken
  twenty minutes earlier.
- **Registration is a choice, not a side effect.** `-WithExtras` no longer
  registers an optional-key server for a sliver of itself. Keyless, firecrawl-mcp
  is 2 usable tools for **~9,080 tokens on every turn**, duplicating a capability
  the providers already have. It is an npx server -- registering *is* installing,
  since npx resolves on first launch -- so the entry simply waits for a key.
  `-RegisterKeylessExtras` is the explicit override.
- **The doctor reports capability states**: installed, registered and where,
  keyless tools, credentialled, schema cost, and why something is deliberately
  not registered. Its first cut reported "registered: none" on a machine where
  everything was registered -- twice, once from a wrong call signature and once
  because catalog ids differ from registered server names (`codebase-memory` ->
  `codebase-memory-mcp`, `github-mcp-server` -> `github`). Both fixed; the
  mapping is declared rather than guessed.
- **Codex's skills budget, measured rather than guessed.** With
  `codex debug prompt-input`: 146 bundle skills render at **~88 visible chars**
  per description and 142 of the 146 are written longer than that; 60 skills
  render at ~183, untruncated. Cutting every description to 60 chars gave no
  entry more room. **So shortening descriptions is not the lever and this
  release deliberately does not rewrite 146 of them.** Entry count is the lever
  -- on the development machine 70 of 217 entries come from this bundle's own
  *optional manual* mega-pack, which the installer never deploys. The doctor now
  says all of that instead of quoting a token figure and a remedy that does not
  work.
- **Fixed, from v7.9.8.5:** that release widened `check_versions.py` and
  `test_version_sources` for the pack's first four-part version but not
  `TOOLS/Test-Installed-State.ps1`, so the installed-state doctor failed the
  release that shipped it, on a correct tree. A contract now asserts every
  version gate accepts the shipped version.
- **Routing scenario I** covers throttle-vs-auth, and the fixtures gained a
  scorecard that rewards choosing correctly *first* rather than eventually.

## 7.9.8.5

Point release carrying production field lessons for `codebase-memory` into the
pack: upstream issue #1663 (dashboard tiles read zero; UI RPC allowlist rejects
`get_graph_schema` since 0.10.5) documented with its same-origin proxy
workaround, plus a warning that #1764's accepted idle-CPU root cause failed an
A/B repro from source. `.github/scripts/check_versions.py` now accepts
three-or-more-part versions so point releases like this one pass the gate.
146 canonical skills; no bundled tool changes.

## 7.9.8

Make the agent reach for the strongest capability it already has instead of
rebuilding a weaker one, and repair a fresh-install path that had been
contradicting the bundle's own decisions. 146 canonical skills total; no new
always-on MCP, and this release *removes* servers from a fresh install rather
than adding any.

- **The Hermes starter was registering five MCP servers nobody chose.**
  `COPY-TO-PROVIDER-HOME\config.yaml` shipped a live `mcp_servers` block while
  its own README said "Empty mcp_servers" and its own header said the file must
  never contain a live MCP command. The installer copies that file whole onto a
  machine with no config, so each entry was a fresh-install default:
  `sequential-thinking` after 7.9.7 measured it out of the always-on core,
  `@modelcontextprotocol/server-github@2025.4.8` which npm marks no longer
  supported, `@playwright/mcp@latest` against the pack's own pinning rule, and
  `firecrawl-mcp`, which is documented as `-WithExtras` and was therefore
  arriving without it. Fixed at the source, not cleaned up after the copy.
- **The installer now refuses the shape, not the four symptoms.**
  `Install-Provider-Starter-Settings.ps1` rejects any starter template that
  declares live MCP entries -- YAML, TOML or JSON -- or names an `@latest`
  package. Verified against all eight shipped templates and four defect
  fixtures. Contracts enforce the same rules in CI, including a cross-source
  test that the Hermes README's claims match the shipped file, which is the
  check whose absence let a four-way contradiction ship.
- **Firecrawl: the measurement contradicted the plan.** The brief assumed
  wiring Firecrawl in more places would help. Hermes v0.20.4 already ships
  `web_search`/`web_extract` over a keyless vendor ring (exa, parallel, tavily,
  firecrawl, keenable) with round-robin and rate-limit failover -- confirmed by
  running it with no key: search 1.4 s, extract 0.7 s. Against that,
  `firecrawl-mcp` is 25 tool schemas and 36,337 bytes, **~9,084 tokens on every
  turn** -- eight times the server 7.9.7 deleted for being too expensive -- and
  keylessly it answers only `search` and `scrape`; `map`, `crawl`, `agent` and
  `interact` each return *"API key is required"*, verified by calling them. The
  expensive surface duplicated the native one and its unique half needed an
  account. So it is not registered, and the native route is the strong one.
- **One new skill, after auditing six.** `capability-routing` owns "do not
  rebuild an installed capability with a weaker ad-hoc script", plus the
  escalation ladder and the anti-dogma half: when the plain primitive is the
  right answer. The nearest existing owner, `capability-profiles`, triggers on
  *enabling servers* -- a model about to write a Node crawler never matches that
  description, and description matching is how these skills load at all.
  `research-verification` gained the escalation principle at its own seam.
- **`final_pack_version` is gone from 37 skills.** Nothing read it at runtime;
  its only consumer was a contract asserting it stayed current, so the field
  existed to serve its own test. 36 of the 37 had drifted to 4.3.0, 5.0.0 or
  5.1.0 inside a 7.9.x pack. `VERSION.txt` is the single authority, and a file
  that does not restate a release number cannot disagree with it. A contract
  now forbids its return.
- **Fixed from 7.9.7:** `capability-profiles` still called sequential-thinking
  one of "the always-on three" after 7.9.7 demoted it, and the Hermes README was
  stale about `reasoning_effort`, `max_turns` and the compression threshold as
  well as MCP.
- **`TOOLS\Measure-McpSchemaCost.ps1`** ships the measurement 7.9.7 asserted but
  had no way to reproduce: real `initialize` -> `tools/list`, per-tool bytes.
  Building it exposed three bugs worth naming -- a blocking `ReadLine` that made
  the timeout unreachable, an undrained stderr pipe that deadlocked npx, and a
  handshake that waited for an `initialize` reply context7 never sends.

## 7.9.7

Make agents seek the cheapest decisive evidence before guessing, and require
real evidence before claiming visual or behavioural work is finished.
145 canonical skills total, mirrored across five provider trees; the always-on
MCP core got *smaller*, not larger.

- **The audit came before the addition.** Eleven existing reliability skills
  were read first. Exactly one behaviour had no owner -- does the rendered
  result actually look right -- so `visual-verification` was added and the other
  six were extended at their own seams instead of cloned: `observability-first`
  now covers software the agent writes, `secret-hygiene` covers proving a
  variable is set without printing it, `research-verification` gained a tool
  ladder *and* the counterweight against reflexive browsing,
  `verification-before-completion` gained rendered/runtime evidence rows and
  freshness, `assumption-audit` gained routing.
- **"Use vision" ships a falsifiable check, not an instruction.** A model that
  cannot see pixels can still write "I inspected the screenshot". So
  `TOOLS\vision-canary` holds an image whose contents exist only as a SHA-256,
  and `TOOLS\Test-VisionCanary.ps1` answers PASS or FAIL. A FAIL is an answer:
  say "visual verification unavailable in this provider/session", keep the
  artifact, fall back to DOM/console/geometry. Provider capability was
  established by running each CLI, and the one gap is stated: Codex's
  `-i/--image` flag exists but end-to-end delivery is untested, because the
  account hit its usage limit mid-verification.
- **Eight fixtures for the behaviour itself** in `TESTS/evidence-scenarios/`,
  each with a rubric, plus `check_fixtures.py` chained into the pack gate so the
  defects cannot quietly be repaired into passing everything. Scenario A was run
  for real: a heading clipped behind a fixed header, invisible to every DOM and
  CSS check.
- **Supabase withdrawn.** The only profile needing an account and a token,
  against this pack's free/local/keyless default. Withdrawing a profile does not
  un-register it, so the migration removes only what this pack recorded and
  leaves an independently configured server alone. A contract now fails the
  build if any profile server requires an API key.
- **Blender pinned and discovered.** `uvx blender-mcp` was the one unpinned
  invocation; 1.8.3 verified against PyPI and by running it. The maintainer's own
  `S:\Steam\...` path is replaced by what `blender-mcp addon-paths` actually
  reports, and a new contract fails the build on any drive letter or user
  directory in a shipped config. Telemetry was read from the wheel:
  consent-gated inside the addon, no telemetry endpoint, unreachable from
  outside the editor -- so the note states that rather than claiming a disable.
- **sequential-thinking left the always-on core on measurement.** Real MCP
  `initialize -> tools/list`: 1 tool, 4,587-byte schema, ~1,146 tokens on every
  turn of every session -- as much as context7's two tools, for a scratchpad
  rather than a capability. It is the opt-in `reasoning` profile now, with no
  detection markers so `-Auto` can never reach it; machines that already have it
  are told with the number, not edited. What was *not* measured: its benefit to
  weaker models.
- **Godot re-compared and kept.** hi-godot/godot-ai is fresher but needs an
  editor plugin, uv and a WebSocket; Coding-Solo's headless npx server wins on
  friction for this bundle. Recorded with the trigger for revisiting.
- **A finding nobody was looking for.** A real Codex run reported "Exceeded
  skills context budget. All skill descriptions were removed" -- description
  routing, this pack's whole mechanism, is degraded on Codex at 215 installed
  skills / 38,228 characters. `skill_search` is already enabled there, so this
  is a size problem, not a flag. The doctor now reports it with the measurement
  and the remedy. A limitation, not a fix.
- **The preamble grew by one clause, measured:** +91 bytes, ~23 tokens per
  request, on the line that already owned evidence order.
- **Fixed: the accepted CodeQL autofix did not compile**, and main was red.
  Restoring the dropped parenthesis made it compile while leaving the ReDoS
  intact (3,571 ms against 0 ms) and silently changing what the validator parses
  on ten lines. The repair makes the alternation disjoint.

## 7.9.6

The capability profiles 7.9.5 shipped were detected per project and registered
per machine. Every profile in `PROFILES.json` carried `"scope": "global"`, so
enabling `code-deep` for one repository put Serena's tool schemas into every
session on the box -- while the same file's opening paragraph and CATALOG.json's
own Serena entry both said it was not registered globally. Found by a user
noticing the context bill and disabling the profile by hand.

- **Every profile is project-scoped.** Written where only its project can see
  it: `projects["<abs path>"].mcpServers` in `~/.claude.json` for Claude Code
  (where `claude mcp add --scope local` writes -- no file in the repository, no
  trust prompt), `<project>\.grok\config.toml` for Grok. Codex, Kimi and Hermes
  have no project-scoped MCP config, each verified against the installed CLI, so
  they are skipped with the reason printed instead of written machine-wide.
  `-Global` is the explicit opt-in and states the cost.
- **`code-deep` is now `code-intel`.** The old name promised depth; the profile
  holds one server. The old id still resolves. `team-harness/code-deep` was not
  added: Serena plus `codebase-memory-mcp` remain the stack until something else
  is benchmarked against them.
- **Serena is told which project.** `--project <path>` for a project
  registration; `--project-from-cwd` for a `-Global` one, because one baked
  absolute path would activate that project in every unrelated session. Both
  verified against the installed Serena 1.7.0's own `--help`.
- **Installed is not enabled.** `-List` distinguishes them and prints which
  project each profile is on for, and which providers took it.
- **Migration moves the old entries, not just the state.** State goes from a
  flat map to per-project; the upgrade removes the machine-wide registrations
  from every provider config and re-registers for the project the state
  recorded, touching only ids this pack recorded as enabled. A recorded project
  that no longer exists is reported and left off.
- **Six defects found on the way, all reachable by users.**
  `Get-ClaudeDesktopConfigPath` crashed whenever `GetFolderPath` returned the
  empty string it documents for a missing folder. `uv tool install` prints
  "already installed" on stderr and exits 0, which under
  `$ErrorActionPreference = 'Stop'` killed the auto-install on every re-run. An
  identical rewrite counted as a change, dropping a timestamped `.bak` into the
  user's project once per install run. `-Disable` with no `-Path` swept the
  current directory instead of the projects the profile was enabled for. And an
  unmounted drive was fatal twice over: `Test-Path` raises "Cannot find drive"
  rather than answering `False`, and `Join-Path` does the same because it
  resolves the base through the provider -- swept into guarded helpers across 37
  and 26 call sites, with a release contract to keep them that way.
- **49 new checks** in `TESTS/Test-McpProfiles.ps1`, all driving the real
  front-end script against a sandboxed `USERPROFILE`/`LOCALAPPDATA`/`APPDATA`
  and reading the provider configs it produced. Every one fails against 7.9.5.
- **No new skills.** 144 canonical across five provider trees, unchanged.

## 7.9.5

Seven MCP servers from an external capability review, shipped as profiles rather
than registered globally. 144 canonical skills total, mirrored across all five
provider trees.

- **The measurement that decided the design.** New `TOOLS\Test-McpHandshake.ps1`
  runs the real `initialize` -> `tools/list` exchange against a provider's own
  config. On this machine: **188 tool schemas in context on every Claude turn**,
  136 for Codex, 90 for Grok. Skills are lazy; MCP schemas are not.
- **Capability profiles.** `BUNDLED-TOOLS/PROFILES.json` +
  `TOOLS\Set-McpProfile.ps1`. A profile is wired only when the project shows its
  markers *and* the machine satisfies its requirements; otherwise it is skipped
  with the missing prerequisite printed, never written as an entry that fails on
  first call. This is the capability-profile router v7.9.2 declared as designed
  but not built.
- **Added:** Serena 1.7.0 (`code-deep`, auto-installs via uv, per-client
  `--context`), Chrome DevTools 1.7.0 + shadcn 4.18.0 (`web`), Supabase 0.11.0
  read-only (`cloud`), blender-mcp 1.8.3, godot-mcp 0.1.1, Unity-MCP 0.89.0.
- **Not shipped, with reasons:** Unreal MCP (last upstream commit 2025-06-06)
  and Storybook (no first-party server). Both are recorded in `PROFILES.json`
  and printed by `-List`.
- **One writer for three config shapes.** `TOOLS/V7-Mcp-Write.ps1` is now the
  only place this pack writes an MCP entry. The new gate
  `TESTS/Test-McpProfiles.ps1` caught two defects on its first run: PowerShell
  unrolls a single-element array on `return` (a one-argument server would have
  been written as a string), and `-CheckOnly` deleted the entries it claimed it
  would only report on.
- **A live defect only the handshake could find.** Codex still held
  `@playwright/mcp@latest` with no `-y`, so npx blocked on an install prompt and
  the server never answered. v7.9.2 pinned it in the catalog, but
  `-SkipIfPresent` compared only the *command* -- and every npx server has the
  same command. It now compares the args.
- **Four more found by running it, after CI was already green.** The catalog's
  own Playwright entry had no `-y`; widening the contract from the new servers to
  *every* npx entry then caught `firecrawl-mcp` and `@perplexity-ai/mcp-server`
  unpinned. The probe deadlocked on stderr it redirected and never drained,
  reporting a false FAIL for a healthy server. Grok would have registered a
  profile twice, because it reads `~/.claude.json` as well as its own config.
- **Every dedupe in this pack keys on the server name**, which cannot see the
  same package declared under a different one: Hermes ran `@playwright/mcp` as
  `playwright`, and adding by catalog id wrote `playwright-mcp` beside it. The
  extras branch matches the package now, with the version stripped so a pin bump
  is still the same server.
- **The handshake probe leaked a process tree per check.** `Process.Kill()` ends
  one process; `cmd /c npx ...` leaves node running. After a dozen runs the
  orphans held the ports the next check needed, and the probe reported ten
  healthy servers as broken -- a false FAIL caused by the diagnostic. It kills
  the tree now.
- **Grok was missing two of the three always-on servers.** The wiring skipped
  anything declared in `~/.claude.json` as "inherited" -- true of grok-cli's
  default, untrue since this installer began writing `[compat.claude] mcps =
  false`. It reads the flag now. And because grok-cli wedges at eight servers
  running, the Grok budget is enforced by both writers instead of for one server
  by name, naming what did not fit and how to make room.
- **`-WithExtras` failed its own doctor, every time.** Running the published
  installer end to end ended in INSTALL FAILED with 30 errors -- six skills
  reported stale/modified on five providers. The canonical tree vendors those
  six and the `skills-git` components fetched the same ones from upstream and
  copied over the top. Two writers, one directory. `skills-git` now skips what
  canonical owns and reports each skip by name.
- **The probe reads Hermes now.** Its docs used to say Hermes was not read here
  -- a stated blind spot in a tool for proving servers answer. It found the same
  unpinned Playwright there, which traced back to the installer: `CATALOG.json`
  lists Hermes and Kimi as providers for three npx extras, but the npx branch
  only knew Grok, Codex and Claude and **printed the block at the other two**.
  Both are wired through the shared writer now.
- **`Repair-McpPaths.ps1` now repoints opaquely-named directories.** Its rule was
  a version-stamped sibling -- this pack's convention. Codex keys runtimes by
  content hash, so three dead command paths were reported unrepairable. Rule
  generalised to "exactly one sibling under which the tail exists"; two
  candidates are still reported rather than guessed between.

See `docs/history/V7.9.5-CHANGELOG.md`.

## 7.9.2

Four defects from an independent audit of 7.9.1, plus the token-efficiency work
they led to. 143 canonical skills, mirrored across all five provider trees.

- **The GitHub MCP server was a deprecated package.** `@modelcontextprotocol/server-github@2025.4.8`
  is marked `Package no longer supported` by npm itself. Replaced with GitHub's
  official `github/github-mcp-server` v1.10.1 (MIT), vendored as a SHA-pinned
  offline asset because it ships binaries rather than npm. v7.7.11 had already
  "fixed" this line by pinning it — the pin held and the package died anyway,
  which is why catalog entries now carry a version to check, not just a pin to
  trust.
- **It is registered with scoped toolsets**, not `all`. The server groups its
  tools into 20 toolsets and every enabled group costs schema tokens on every
  turn.
- **`mcp-protocol-2026` did not exist**, and was cited in `START-HERE.txt`.
- **Playwright was `@latest`** in a catalog that documents why that is unsafe.
  Pinned to `0.0.79`.
- **Perplexity is key-gated** and now says so.
- **New `token-efficiency` skill.** Prompt caching does not make watching cheap:
  a cache read is 0.1x input but a cache write is 1.25x-2x and output is never
  discounted. The harness waits; the model sleeps. Includes the measured 153k vs
  5.5k skill-loading numbers behind this pack's lazy-loading design.

See `docs/history/V7.9.2-CHANGELOG.md`.

## 7.9.1

One repository. Skyrim Forge is developed here now, at
`BUNDLED-TOOLS/skyrim-forge`, and is no longer released separately. 142
canonical skills, mirrored across all five provider trees.

- **Windows PowerShell 5.1 final-doctor repair.** A hotfix accidentally wrote literal `\n` edit debris into `Test-Installed-State.ps1`, which commented out the `$providerHome` assignment and made `Join-Path` receive `$null`. The doctor now uses real lines, validates the resolved provider home before joining it, and the release contract proves the assignment is executable rather than commented out.
- **Same-version Forge hotfixes now actually deploy.** The merged bundle may fix Forge scripts without changing the embedded product version from 6.0.0. The wrapper used to refresh the live Forge tree only when `VERSION.txt` changed, so a corrected archive could still execute an older `S:\Apps\Skyrim Tools\Skyrim-Forge\Register-MCP.ps1`. The wrapper now compares the live tree against the bundled Forge `MANIFEST.json` and verifies every shipped file SHA-256; any drift forces a staged refresh while preserving `.venv`, `Workspaces`, `REPORTS`, and local `config.toml`.
- **Hermes Forge registration is noninteractive and bounded.** The old path hid Hermes' interactive post-discovery prompt behind `Out-Null` and attempted to feed it through a PS5.1 pipeline, which could look frozen until a key was pressed. Forge now writes the entry through Hermes' own config API, shows progress, and bounds the connection test to 45 seconds. Optional reasoning-MCP wiring uses the same noninteractive config path.
- **7.9.1 version lock.** Release contracts reject the accidentally chosen next-major label anywhere in shipped text or filenames. Historical notes were rewritten so the archive has no such version contamination.

- **Provider skill updates are content-authoritative, not timestamp-authoritative.** The deterministic release builder deliberately normalizes ZIP timestamps. The earlier v8 and corrected v7.9.1 `release-checklist/SKILL.md` had the same 4,608-byte size and the same fixed timestamp while containing different version metadata, so metadata-based copy logic could classify the changed file as unchanged. The production sync no longer delegates bundle-owned skills to Robocopy at all: each named skill is copied into a sibling staging directory, SHA-256 verified, swapped into place, and SHA-256 verified again. A stale extra file inside a bundle-owned skill is removed by replacement, while unrelated user-created sibling skills are untouched.
- **`skyrim-forge` has one active skill writer in the AIO path.** Forge's provider installer used to overwrite the bundle copy with a divergent `BUNDLED-TOOLS/skyrim-forge/integrations/skyrim-forge/SKILL.md`, guaranteeing five final-doctor mismatches after an otherwise successful Forge install. The AIO now marks provider skills as bundle-owned, so the Forge wrapper refreshes only the machine-local `INSTALLATION.json` descriptor and MCP registration; it does not rewrite `SKILL.md`. The embedded integration file remains byte-identical for standalone Forge installs.
- **Forge install output is concise and visibly progressing.** The embedded installer no longer streams multi-page `self-test`, `config-show`, and `doctor` JSON directly into the parent console. Every checked child command prints a start marker, suppresses success JSON, then prints PASS with elapsed seconds; full child output is retained in the thrown error on failure.
- **The exact stale-skill failure has a Windows runtime regression.** `TESTS/Test-ProviderSkillSync.ps1` creates old/new `SKILL.md` files with identical byte length and timestamp but different bytes, runs the production sync under Windows PowerShell 5.1, verifies the new hash wins, verifies stale files inside a bundle-owned skill are removed, and verifies an unrelated user skill survives. The root Windows pack gate runs it on every CI build.

- **The two-repo split is what let 7.8.0 ship an installer that could not
  install.** `$contract.compatible` is a field Forge has never emitted, so the
  Forge step threw on every run and the AIO aborted the whole install. 7.9.0
  fixed the field. This fixes the reason no test could have caught it: the
  installer and the code answering it were in two repositories, released on two
  schedules, with no commit that could test both. The new `forge-bundle-install`
  CI job runs the real installer against the real subtree end to end.
- **Forge is source, not a payload.** `BUNDLED-TOOLS/offline/Skyrim-Forge-*.zip`
  is gone; the installer copies the in-tree tree. No archive to build, no
  archive version that can disagree with the installer reading it. Both release
  variants carry it in full.
- **An upgrade no longer deletes your mod work.** Job staging defaults to
  `<install root>\Workspaces`, and the old installer replaced the install
  directory wholesale -- so every version change deleted it. `Workspaces`,
  `.venv`, `REPORTS` and a local `config.toml` now survive the swap.
- **`-ForgeRoot`.** `INSTALL-V7-AIO.ps1 -ForgeRoot 'S:\Apps\Skyrim Tools'` puts
  Forge next to xEdit instead of under `%LOCALAPPDATA%`. The LOCALAPPDATA
  default stays: no admin rights, no drive-letter assumption.
- **Skyrim Forge 6.0.0 removes `forge bundle-contract`.** One repository cannot
  usefully negotiate a version range with itself; a stale range can only start
  rejecting the pack it ships inside, and it carried a hard next-major ceiling. The
  installer runs `forge doctor`, which can still fail for a real reason, and
  `test_forge_health_check_reads_fields_forge_emits` parses `doctor()` with
  `ast` and fails if the installer reads a field it does not return.
- **Root CI gained five Forge jobs**, unfiltered by path, plus CodeQL and
  Dependabot. Forge's own `.github/` is deleted: GitHub reads workflows only
  from a repository root, so those files would look live and never run.
- **One local launcher.** `START-HERE.bat` is the canonical double-click entry;
  `INSTALL-V7-AIO.bat` is only a compatibility alias. Installer failures now
  stay visible and also write `INSTALL-FAILED.txt` plus `INSTALL-LAST.log` under
  the local app-data log directory.
- **Provider helper integrity is now a release gate.** A real Windows run exposed
  `Install-V5KimiPlugin` as missing from `TOOLS/V7-Common.ps1`; the same merge
  had also dropped `Restore-V5HermesPluginScan`, which would have failed later
  in the same install. Both helpers are restored, and the static helper gate now
  scans root installer scripts as well as `TOOLS`/`TESTS`, so an undefined
  `*-V5*` helper cannot hide outside those folders again.
- **The final Windows doctor now actually runs on PowerShell 5.1.** It assigned
  `$home`, which is the case-insensitive read-only `$HOME` automatic variable,
  so the doctor aborted before checking anything. It now uses `$providerHome`,
  and the pack gate rejects direct `$HOME` assignment in the doctor.
- **The doctor follows Forge 6, not the removed 5.x handshake.** The `$HOME`
  crash was masking a second guaranteed failure: `Test-Installed-State.ps1`
  still called the removed `bundle-contract` command. It now parses `forge
  doctor` and requires `result=PASS` plus `read_only_ready=true`.
- **Doctor failures are durable.** Child-PowerShell output is captured and
  replayed through the parent before failure, so `INSTALL-LAST.log` and
  `INSTALL-FAILED.txt` include the actual failing doctor check instead of only
  `exit code 1`.
- **The `skyrim-forge` skill is synchronized to Forge 6.0.0.** It no longer
  teaches the removed 5.2 bundle handshake or a version-stamped live install;
  all five provider copies now describe the versionless `SKYRIM_FORGE_ROOT`
  install and the real `forge doctor` health gate.
- **Embedded Forge validation is repository-aware.** Forge's validator/native
  rebuild helper resolves the pinned Go toolchain from the enclosing repository
  workflow instead of assuming a dead subtree `.github` exists.
- **Linux Forge native helper keeps its execute bit.** The deterministic ZIP
  builder records the published Linux helper as POSIX `0755`; an archive made
  on Windows can no longer extract a correct binary that Linux cannot execute.

See `docs/history/V7.9.1-CHANGELOG.md`.

## 7.9.0

A fresh Windows install of 7.8.0 could not complete, and every gate was green.
Ships 142 canonical skills total, mirrored across all five provider trees.

- **`Install-SkyrimForge.ps1` tested `$contract.compatible`.** Forge has never
  emitted that field. `-not $null` is `$true`, so the installer threw
  *"Forge reports incompatible bundle contract"* on every run, and the AIO
  aborted the whole install on the non-zero exit. Nothing caught it because no
  test read the installer and Forge's contract source together. It now checks
  `result`, and `test_forge_contract_check_reads_a_field_forge_emits` compares
  every `$contract.<field>` the installer reads against the fields the bundled
  Forge actually returns.
- **The Forge install directory no longer carries a version.** Every provider
  stores the MCP command as a hard absolute path, so a version-stamped folder
  renames itself out from under five configs on every upgrade -- silently,
  because a provider that cannot spawn its server just shows no tools. Live
  state when this audit started: `SKYRIM_FORGE_ROOT` pointed at
  `Skyrim-Forge-5.1.6` (deleted), all five configs pointed at `Skyrim-Forge`
  (never created), and disk held `Skyrim-Forge-5.2.0` with no virtualenv. The
  installer now resolves ONE versionless root and *migrates* a stamped install
  onto it. `TESTS/Test-ForgeRootResolution.ps1` proves migration, move-not-copy,
  highest-version selection (5.10.0 beats 5.2.0) and the dead-root case.
- **Skyrim Forge 5.2.1 replaces 5.2.0.** `forge --help`, the GUI window title
  and the Go self-test fixture all announced the 4.2 series from inside a 5.2.0
  install. Forge's version gate only compared files someone had remembered to
  enumerate; it now also sweeps every shipped `.py`/`.ps1`/`.bat`/`.go` for a
  stale product-version literal.
- **`skyrim-forge-bridge` removed** -- 143 canonical skills to 142. It described
  a 0.2.x preview product that no longer exists, told the agent the shipped
  Forge *cannot write ESP records* (false since 5.x), and shipped
  `run_forge_audit.ps1` hardcoded to `$HOME\Documents\Apps\...`, which could not
  run on any machine. Four skills that pointed at it now point at `forge`.
- **Restated version literals deleted.** `build_release.py` named the archive
  prefix in four places and the Forge payload in four more; `Test-Installed-State.ps1`
  restated the pack version three times; both `.bat` titles sat at v7.8.0 all
  release because `check_versions.py` never looked at them. All derive from
  `VERSION.txt` or the payload filename now.
- **The contract suite is version-agnostic.** `TESTS/test_v780_contract.py` is
  now `TESTS/test_release_contract.py` and reads `VERSION.txt`; a release bump
  is no longer a rename plus fifteen find-and-replaces.
- New gates: skills may not document an unshipped product, skill scripts may not
  hardcode a machine path, provider trees must match canonical exactly, and the
  offline manifest's declared sizes/hashes must match the bytes on disk.

## 7.8.0

Reliability/one-shot release: 143 canonical skills total, mirrored across all five
provider trees. Adds 57 focused generic reliability/cognition skills while
shrinking trigger metadata, integrates Skyrim Forge 5.2.0, hardens fresh-Windows
bootstrap and final doctoring, and tunes Hermes for high-quality cache-efficient
DeepSeek V4 Flash 0731 operation. See `docs/history/V7.8.0-CHANGELOG.md`.

## 7.7.15

New canonical `release-checklist` skill, fanned to all five providers. See
`docs/history/V7.7.15-CHANGELOG.md`.

## 7.7.14

Live → bundle sync of provider touches (portable parts only):

- **Claude settings.json**: add `enabledPlugins` — claude-code-setup,
  claude-mem, headroom, obsidian, ponytail, superpowers (marketplaces were
  already known; the enable flags were missing).
- **Codex config.toml**: add `model = "gpt-5.6-sol"` default (parent and
  installer copy mirrored).

## 7.7.13

Bundle == live-machine reconciliation after a local folder rename:

- **Hermes starter `config.yaml` rebuilt portable** — now carries the
  reference machine's touches (model aliases, OpenRouter extras, plugins:
  disk-cleanup/ponytail/superpowers, aux models, github MCP via npx) while
  keeping the no-personal-info contract. `COPY-TO-PROVIDER-HOME` mirrors the
  parent (matches the Codex/Claude convention).
- **`Repair-McpPaths.ps1` scans the Claude Desktop app config** and falls
  back to the unversioned folder stem when no `Skyrim-Forge-*` sibling
  exists (folder renames that drop the version suffix no longer report a
  dead end).
- **`assumption_gate.py` selftest sanitized** — reference user is now
  `tester` (was the author's username); no personal info ships in the pack.

## 7.7.12

Claude Desktop app support. Add-Reasoning-MCPs.ps1 now also writes the MCP
servers into claude_desktop_config.json (both normal `%APPDATA%\Claude` and
Microsoft Store package locations), so users of the Claude Desktop app - which
does not read `~/.claude.json` - get context7, sequential-thinking and github
in the app's own MCP surface. Desktop-only installs (no `claude` CLI) are
covered. Existing `~/.claude.json` registration is unchanged.

## 7.7.11

Fresh-install hardening. See `docs/history/V7.7.11-CHANGELOG.md`.

- **github MCP pinned in `Add-Reasoning-MCPs.ps1`** — the one reasoning
  server that shipped unpinned (`@modelcontextprotocol/server-github` →
  `@2025.4.8`), violating the file's own "Exact versions" rule and the
  README's pin guidance. Fresh installs now write all three servers pinned.
- **`Repair-McpPaths.ps1` repairs a moved houseCARL** — `Resolve-LivePath`
  only handled version-stamped sibling dirs, so a houseCARL moved to another
  drive (no sibling, no version) reported "no replacement found" and left the
  provider silently disconnected. It now repoints `housecarl-mcp.exe` dead
  paths from the bundle's own `HOUSECARL_MCP` env registry; all other
  unversioned paths still refuse to guess. New test in pack gate section 8.

## 7.7.10

Audit of everything between v7.7.2 and v7.7.9. Every gate was green; two of
them were green because they had stopped testing anything.

- **The SPID/KID framework truth lock had been dead since v7.7.8.** When that
  release consolidated `skyrim-spid-distribution` / `skyrim-kid-distribution`
  into `spid-authoring` / `kid-authoring`, `verify_framework_truth.py` kept
  reading the deleted paths and raised `FileNotFoundError` on every run - in
  the canonical tree and all five provider trees. This is the script that pins
  the exact parser facts the pack refuses to let an agent invent. It now reads
  the whole owning skill (SKILL.md + references), normalizes whitespace so a
  token survives a line wrap, and **reports a finding instead of crashing**
  when an owner goes missing.
- **No gate ever ran it** - the actual root cause, and why it could rot for a
  full release. Pack gate section 10 now runs it and checks the five provider
  copies against canonical.
- **The harness `no duplicate skills` check asserted nothing.** It keyed off a
  `$pstateAll` map written for `superpowers` in three branches and never for
  `ponytail` or for Claude, so 8 of 10 provider/plugin pairs printed PASS
  while testing nothing - and after v7.7.5/v7.7.7 made copies *required* for
  Grok and Hermes, the check was asserting the opposite of the policy. It is
  now policy-aware: dedupe providers must have no shadowing copy, keep-copies
  providers must have every copy, and anything unconfirmed reports SKIP rather
  than a free PASS.
- **That fix immediately caught a live defect.** Hermes was missing three
  Superpowers skill copies - `requesting-code-review`, `systematic-debugging`,
  `test-driven-development`. v7.7.7 restored 11 of 14 from the dedupe backups
  and the shortfall was invisible. Those three `/slash` commands were dead.
  Restored from the pack.
- `VALIDATION.json` had flipped LF -> CRLF, against the pack's own byte-fidelity
  rule. Reverted. It was the only flip in 163 changed files.

**Checked and cleared:** the v7.7.8 SPID/KID consolidation itself. Nine of ten
pinned truth tokens no longer matched, which looked like lost grammar. Every
locked claim in `FRAMEWORK-SOURCE-LOCK.json` survives in the AUTHORITY
references, and the generative rules there (`[Final]Death<Type>`,
`[Global]Linked[Final][Death]<Type>`) are strictly more complete than the
`DeathItem` example they replaced. The tokens were stale, not the knowledge.

## 7.7.9

Installer respects existing tool installs; tuned Hermes compression.

- **AIO keeps existing houseCARL/Spooky installs.** If `HOUSECARL_MCP` points
  at a valid `housecarl-mcp.exe` or `SPOOKY_AUTOMOD_ROOT` at a valid
  `SpookysAutomod.sln`, the installer records `kept-existing` and never
  overwrites — same pattern as codebase-memory. Curated tool copies survive
  re-runs.
- **Hermes compression tuned.** `1-TAILORED-PROVIDER-TREES/Hermes/config.yaml`
  compacts earlier (threshold 0.14 / target_ratio 0.11), protects a leaner
  tail (protect_last_n 6), and gains `in_place`, `idle_compact_after_seconds`,
  and the codex_* compaction settings. Template stays portable.

See docs/history/V7.7.9-CHANGELOG.md for details.

Skill tree dedupe: dead modules pruned; KID/SPID grammar owners consolidated.

- **Five invisible skills were being copied into every provider home.**
  `skyrim-archive`, `skyrim-esp`, `skyrim-mcm`, `skyrim-papyrus`, and
  `skyrim-skse` shipped with a lowercase `skill.md` only - no agent loader
  reads that, so they were dead weight that still installed everywhere.
- **Two skills claimed one job.** `skyrim-kid-distribution` /
  `skyrim-spid-distribution` duplicated the grammar owned by
  `kid-authoring` / `spid-authoring`. The twins are gone; their validate
  scripts and pinned authority references moved into the owners.
- Installer guard: `install_live_skills.py` now skips dirs without a
  `SKILL.md`, so a dead skill can never propagate again.

## 7.7.7

Hermes keeps plugin skill copies (slash commands + autofill).

- **`/using-superpowers` stopped working after an install.** Hermes derives
  `/skill-name` slash commands and desktop autofill from the skills dir
  (`scan_skill_commands` scans `SKILLS_DIR`, not plugin registrations). The
  native-plugin dedupe deleted the Superpowers/Ponytail copies from that
  path, so the commands vanished (`Unknown command`) after a restart.
  Hermes no longer runs that dedupe, mirroring the Grok exemption from
  v7.7.5. Claude/Codex/Kimi still dedupe.

## 7.7.6

Ensure-Headroom-Grok MCP cliff guard parses on Windows PowerShell.

- **`if : The term 'if' is not recognized as the name of a cmdlet` during
  install.** `Ensure-Headroom-Grok.ps1` built its 7-server guard warning
  with `$((if($pluginActive){'ACTIVE'}else{'disabled'}))` - the extra
  parenthesis makes PowerShell parse `(if ...)` as a command call, so the
  warning line threw instead of printing. Dropped the redundant paren
  (`$(if(...){...}else{...})`). The guard now reports
  `mcp-search plugin disabled.` cleanly and the AIO run no longer shows a
  red error when Grok sits at the MCP budget.

## 7.7.5

Grok Superpowers copies stay in `~/.grok/skills`.

- **`verification-before-completion` "failed" with no reason.** Native-plugin
  dedupe deleted `~/.grok/skills/verification-before-completion`. Grok chats
  and slash commands load that path; the TUI reports a blank failure when it
  is missing. Same for `systematic-debugging` and the rest of Superpowers.
  Grok no longer runs that dedupe. Copies restored on the live machine.

## 7.7.4

The AIO run that was supposed to finish 7.7.3 aborted starter settings and
left Grok with two Superpowers plugins.

- **`$HOME` is a PowerShell constant.**
  `Install-Provider-Starter-Settings.ps1` assigned `$home = Get-V5ProviderHome`.
  On Windows PowerShell that is `Cannot overwrite variable HOME because it
  is read-only or constant`, so the entire starter-settings pass died
  before Claude/Codex/Grok/Kimi/Hermes templates were merged. Renamed to
  `$provHome`.
- **Two Grok Superpowers plugins, one skill name.** The official
  marketplace auto-installs `superpowers`, and the AIO also
  `grok plugin install`-ed the staged local clone under
  `%LOCALAPPDATA%\Skyrim-AI-V5\plugins-src\superpowers`. Both own
  `systematic-debugging`. The TUI reports that as the Superpowers skill
  error. The installer now keeps the marketplace copy, uninstalls extra
  local clones, and never installs the local path when any Superpowers is
  already listed. Duplicate collapse edits `registry.json` rather than
  `grok plugin uninstall <name>`, which cannot target a repo_key and
  removed the marketplace copy when both were present.
- **Grok was still scanning Claude skills.** `[compat.claude] hooks/mcps =
  false` did not stop `~/.claude/skills` or Claude plugin skill dirs, so
  Grok loaded claude-mem skills and `mcp-search` could still occupy the
  8th running MCP slot. `skills = false` is now written. `mcp-search`
  stays in `disabled_mcp_servers`.
- **Kimi native Superpowers never deduped** the copied skills, so
  `systematic-debugging` sat twice. Same dedupe path as the other
  providers.
- **Hermes `scan_on_install: false` leaked.** Restore only ran when a
  plugin was newly installed. Re-runs left the scanner off forever.
  Restore now always runs after the Hermes plugin pass.

## 7.7.3

Portable provider starter settings, and Forge lives in the Skyrim tools folder.

- **Starter configs were missing, so a live machine dump got dropped into
  `1-TAILORED-PROVIDER-TREES`.** Those files contained `C:\Users\[REDACTED]\...`
  MCP command lines, a Claude Fable model pin, Codex runtime hashes, and
  would have overwritten every fresh Hermes `config.yaml`. They are replaced
  with machine-neutral templates under each provider's
  `COPY-TO-PROVIDER-HOME`. `INSTALL-V7-AIO.ps1` merges/copies them:
  Claude fills missing `settings.json` keys and never touches `hooks` or
  `CLAUDE.md`; Codex/Kimi/Hermes copy only when the dest file is absent;
  Grok copies if missing and always disables `mcp-search`.
- **Unrestraint is untouched.** `0-UNRESTRAINT-PACKS` still applies through
  `CLAUDE.md` / `AGENTS.md` / Hermes `SOUL.md` via the existing preamble
  pass. Settings files carry no jailbreak prose.
- **Hermes is no longer wholesale-replaced** on every AIO run.
- **Forge 5.1.5+** is required for Claude Code `resultType`. Live install is
  `Skyrim-Forge-<version>` under the Skyrim tools folder, not Documents.
- Pack gate section 8 fails any starter file that contains a user profile
  path or `S:\Apps`.

## 7.7.2

The Grok MCP cliff guard. `Ensure-Headroom-Grok.ps1` used to force headroom
into `~/.grok/config.toml`; with 7 servers already configured plus
claude-mem's `mcp-search` plugin server, Grok hit the documented
8-running-server wedge and stopped replying. The script now refuses to
register past the cliff (7 configured, or 6 while the plugin server loads),
and the plugin server is disabled for Grok with `grok mcp disable mcp-search`
so the slot stays free.

## 7.7.1

The v7.7.0 release wired five providers and then shipped an installer that
would have unwired one of them on its next run.

- **Codex: the gate installer silently undid the Codex plugin.**
  `Install-Completeness-Gate.ps1` deletes and rebuilds
  `%LOCALAPPDATA%\Skyrim-AI-V5\codex-marketplace` from the pack on every run.
  The pack's manifest declares only `completeness-gate`, so the rebuild dropped
  the `superpowers` entry that the AIO installer had added *earlier in the same
  run*, while `config.toml` kept `[plugins."superpowers@ultimate-bundle"]
  enabled = true`. Codex was left enabling a plugin its own marketplace no
  longer listed. The gate now re-declares superpowers after staging the tree,
  and only when the tree actually landed, so the entry can never dangle.
- **Codex and Grok are verified, not skipped.** Both keep a real registry -
  Grok's `installed-plugins/registry.json`, Codex's `config.toml` plus the
  marketplace manifest it points at - which is the same class of evidence as
  Kimi's `installed.json`. `Test-HarnessRealization.ps1` now walks those
  chains: **18 pass, 0 fail, 0 skip**, up from 16/0/2. The Codex check was
  confirmed to FAIL against the manifest state described above before being
  trusted.
- **The "Kimi has no hook or plugin system" claim is gone.** Both halves were
  false. v7.7.0 established the plugin system; the shipped binary also carries
  a hook engine (`PreToolUse`, `PostToolUse`, `Stop`) fed from `config.hooks`
  plus every enabled plugin's hooks. What is *not* established is the schema
  those config entries take, so nothing is written: guessing it would corrupt a
  working `config.toml`. Kimi gets the skills and the native plugin, not the
  gate, and the docs now say exactly that instead of claiming the capability
  does not exist.
- Stale installer docblocks corrected: Claude is no longer described as
  detect-only, and Kimi is no longer described as copied-skills-only.

## 7.7.0

Native plugin architecture. Three providers were carrying the bundle on disk
without their harness ever loading it.

- **Kimi gets native Superpowers.** Earlier installers checked for a `kimi
  plugin` subcommand, correctly found none, and wrongly concluded Kimi has no
  plugin system - so Kimi got copied skill files that nothing bootstrapped.
  It does have one, driven by the in-session `/plugins` command. The installer
  now writes `plugins\managed\<id>` and a thin `plugins\installed.json`
  entry directly, which is safe because Kimi re-parses each manifest from disk
  on load. The bundled adapter declares `sessionStart.skill`, so Superpowers
  now bootstraps on every Kimi session.
- **Hermes re-injects after a compaction.** The adapter injected the bootstrap
  on turn 1 only; a compaction summarised that turn away and the model quietly
  lost superpowers for the rest of a long session.
- **Hermes' plugin scanner is restored, not left off.** The scanner was being
  disabled permanently, weakening every future third-party plugin the operator
  installs. The override is now scoped to our own install window.
- **Claude installs via its own plugin CLI** when present, using each plugin's
  own marketplace name, and verifies through `plugins\cache` rather than an
  exit code. A dangling `./superpowers` entry that broke the bundled
  marketplace was removed.
- **New:** `TESTS\Test-HarnessRealization.ps1` asserts each harness actually
  loads the bundle, `TESTS	est_hermes_bootstrap.py` covers the compaction
  cases, and `TOOLS\Build-Release.ps1` produces Core and Full-Offline zips
  from `git archive` so `.git` and the local cache cannot reach a release.
- Docs: skill count corrected to 87; the v5.0.0 audit moved to docs/history.

## 7.6.7

- Root folders renumbered after v7.6.6 left a gap: the root read 0, 1, 3, 4.
  Now `0-UNRESTRAINT-PACKS`, `1-TAILORED-PROVIDER-TREES`,
  `2-OPTIONAL-MANUAL-OTHER-GAMES-MEGA-PACK`, `3-PREAMBLES`.
- `1-RECOMMENDED-SEPARATE-TAILORED` renamed to `1-TAILORED-PROVIDER-TREES`:
  with the generic tree deleted, the "recommended" half of the name described
  a choice that no longer exists.
- Every live reference updated in the same commit - installer (3 sites), pack
  gate (5), fanout tool, manifest generator, .gitignore, BOOTSTRAP.txt,
  V7-AIO-GUIDE.md, PROMPTS/README.md, START-HERE.txt, README layout, the
  preambles' own README. Verified by grep: zero live references to any old
  name outside historical changelogs, which keep the names that were true
  when written.

## 7.6.6

- `2-OPTIONAL-SHARED-GENERIC/` deleted (2,525 files, ~40 MB). The installer
  has only ever read `1-RECOMMENDED-SEPARATE-TAILORED`, the two trees differed
  in just 80 files out of ~2,500, and keeping both is exactly the drift risk
  `fanout_providers.py` was written to eliminate. The fanout tool, the pack
  gate and the layout docs now treat the tailored tree as the only one.
- `0-UNRESTRAINT-PACKS` cleaned on operator request: retired-generation jails
  removed (Claude 3.7/4, GPT-5/5.1/5.2, Gemini 2.5-era, Grok 3, the broken
  H03-ny, the Ultra-GPT dead link farm), 25 byte-identical duplicates
  collapsed to one canonical copy each (md5-verified before every deletion,
  ~470 KB freed), the Gemini stub .md removed, its README's stale "February
  2026" stamp corrected to the July 2026 its own table lists. Every
  current-generation folder untouched; operator-added files untouched.
- The housecarl skill's `.mcp.json` template removed from all 11 copies. It
  referenced `${CLAUDE_PLUGIN_ROOT}/server/housecarl-mcp.exe`, which resolves
  nowhere - inert today, a broken config the day any host starts honouring
  in-skill MCP templates. Housecarl is wired by the installer into each
  agent's real config; that path is unchanged.
- Full MCP health sweep across all six agents (Claude, Codex, Kimi Code, Kimi
  Work, Grok, Hermes): 42 configured servers, all verified launchable. One
  real breakage found and fixed on the machine: Skyrim-Forge's venv
  `skyrim_forge_local.pth` still pointed at the deleted 5.1.3 folder - the
  upgrader never rewrites it - which is why Hermes kept parking
  `skyrim-forge` ("No module named skyrim_forge"). Advisory only: the machine
  PATH still names an uninstalled `C:\Program Files\nodejs`; npx resolves via
  `hermes\node` instead.

## 7.6.5

- A gate that can hang wedged the whole Grok session. `assumption_gate`'s
  drive check probed every letter A-Z with `os.path.isdir`; a sleeping or
  disconnected network drive blocks that probe for seconds per letter, so the
  hook outlived Grok's 15s timeout - and Grok stays stuck when it has to kill
  a hook. The check now reads the `GetLogicalDrives` bitmask: 6ms, never
  touches a device, and disconnected-but-mapped letters count as existing,
  which is the fail-open direction.
- Both gates gained a hard watchdog: armed before anything else runs, a daemon
  timer `os._exit(0)`s the process at 10s (`--pre`) / 25s (`--stop`) - under
  every host's timeout (Grok/Claude/Codex 15/30, Hermes 20/40). Whatever else
  hangs - a stalled git, a network drive, a pipe the host never closed - the
  host is never again forced to kill the hook.
- Verified, not assumed: stdin held open forever -> gate exits at 2s on its
  own; a hung process under the same watchdog pattern dies at its budget; a
  bad-drive command is still denied; all four providers' wired commands
  (Grok's `&`-form, Claude's cmd form, Codex's bare python, Hermes's venv)
  exit 0 with the fixed scripts. Fixed copies synced to the Skyrim-AI-V5
  install root, the bundle's Codex plugin source, and Codex's live plugin
  cache.

## 7.6.4

- Grok failed every hook with `failed with exit code 1: At line:1 char:65`.
  That is a PowerShell *parse* error, not a gate verdict: Grok executes hook
  commands through PowerShell, and the gate installer wrote cmd-style commands
  (`"python" "script.py" --pre`). A quoted command followed by arguments is
  invalid PowerShell without the call operator; char 65 is where the second
  quoted string begins. Reproduced exactly before touching anything.
- `New-HookBlock` in `TOOLS/Install-Completeness-Gate.ps1` gained a
  `-CallOperator` switch that prefixes commands with `& `. Only the Grok
  branch sets it - cmd.exe (Claude Code's shell) chokes on a leading `&`, so
  Claude keeps the unprefixed form. Codex's plugin `hooks.json` uses bare
  `python "..."`, which parses in both shells, and is untouched.
- All four wired commands (2 gates x pre/stop) verified to parse and exit 0
  with the exact `& "py" "script" --flag` form Grok receives.
- The live `~/.grok/hooks/ultimate-bundle.json` was rewritten the same way,
  and now points at the stable WindowsApps python instead of the daimon
  managed venv the resolver had picked (that venv is not the user's python and
  can disappear). Signature documented in `GROK-MCP-TROUBLESHOOTING.md`.

## 7.6.3

- `4-PREAMBLES/SOUL-UNIVERSAL.md` deleted. v7.6.0 genericised `SOUL.md`
  itself, which left the two files byte-identical apart from one apostrophe -
  but the README still described SOUL-UNIVERSAL as the copy that does *not*
  say "You are Hermes Agent", inviting someone to put that identity back. The
  installer now wires the single `SOUL.md` to all five providers.
- `4-PREAMBLES/README.md` documented a manual install using
  `Get-Content -Raw | Add-Content` - the exact ANSI-decoding trap v7.6.1 swept
  out of every script. Gate 7b scanned `.ps1` only, so shipped copy-paste
  instructions were never checked. Snippet replaced with
  `ReadAllText`/`AppendAllText` and a no-BOM `UTF8Encoding`, and verified by
  running it.
- Gate 7b now also scans ```powershell fences in the docs this pack authors,
  and asserts there is exactly one soul source that the installer actually
  wires. All three new assertions were confirmed to fail on reintroduction.

## 7.6.2

- `TOOLS/Repair-McpPaths.ps1` would have written invalid JSON. A JSON config
  stores every path separator doubled; the tool matched that literal and wrote
  back a replacement at a different escaping level (one attempt mixed single and
  double, the next quadrupled), which makes `mcp.json` unparseable. Caught only
  because the tool defaults to report-only. Fixed by collapsing the doubling
  before the filesystem check and re-applying the config's own escaping with
  `String.Replace` instead of the regex-on-both-sides `-replace`.
- Gate section 8 gained three assertions: JSON keeps doubled separators,
  TOML/YAML keeps single ones, and the repointed JSON still parses.
- **First CI for this repo.** `.github/workflows/ci.yml` runs the pack gate on
  `windows-latest` under Windows PowerShell 5.1 (Desktop edition asserted, since
  the pack targets 5.1's encoding/BOM behaviour), verifies every MANIFEST hash,
  and checks the version agrees across all seven places it is declared.

## 7.6.1

- Swept the remaining 25 ANSI-decoding `Get-Content -Raw` reads to
  `[IO.File]::ReadAllText` across 10 files. v7.6.0 fixed the one that was
  visibly corrupting the preamble; this covers the rest.
- The dangerous one: `Add-Reasoning-MCPs.ps1` read `~/.claude.json` with the
  ANSI codepage, round-tripped it through ConvertFrom-Json/ConvertTo-Json and
  wrote it back. Measured on the real file - all 26 em dashes destroyed. It had
  not fired only because the script skips writing when all three servers are
  already present, so it was one new server away from rewriting the file.
- New pack gate section 7b fails the build if a bare `Get-Content -Raw`
  returns. Verified to fail, not just to pass. The one deliberate use (section 7
  compares ANSI vs UTF-8 decoding on purpose) is marked `# ansi-intentional`.
- Write paths untouched: `Set-Content -Encoding utf8` adds a BOM on PS 5.1, and
  v6 shipped a BOM that broke skill discovery.

## 7.6.0

- `4-PREAMBLES/SOUL.md` no longer opens "You are Hermes Agent ... created by
  Nous Research". That file is injected verbatim into Claude/Codex/Kimi/Grok
  instruction files too, so since v7.5.0 four agents were told they were a
  different vendor's product. Now provider-neutral; pack gate section 7 fails
  if any provider name returns.
- `Install-V5PreambleBlock` read the preambles with `Get-Content -Raw`, which on
  PS 5.1 decodes via the ANSI codepage: the three em dashes in
  `AIO-INSTRUCTION.txt` were rewritten as mojibake on **every** install. v7.5.6
  swept the data but not this read path. Now `[IO.File]::ReadAllText`.
- The preamble marker is stamped from `VERSION.txt` instead of a hardcoded
  `v7.5.0`, so a stale block is visible on sight.
- The installer no longer pushes Grok over its MCP budget. `skyrim-forge` was
  wired with no budget check while the other four servers used `-SkipIfPresent`,
  so a fresh install took Grok to 7 configured (8 running with a plugin-supplied
  server) and only warned *after* writing it. It now refuses the add, explains
  why, and offers `-GrokMcpBudget 7` for machines with no MCP-providing plugin.
- New `TOOLS/Repair-McpPaths.ps1`: repoints MCP commands whose version-stamped
  folder no longer exists (found live: Claude still on `Skyrim-Forge-5.1.0`
  after the 5.1.3 upgrade, its MCP silently dead, while the other four had been
  updated). Report-only by default; wired into the installer with `-Apply`.

## 7.5.6

- New `Invoke-V5Native` helper in `INSTALL-V7-AIO.ps1`: native commands run
  with a local `$ErrorActionPreference='Continue'` and stringified output, so
  pip's "already satisfied" / pip-upgrade notice no longer prints as a red
  `RemoteException / NativeCommandError` block (reported at line 376).
- Same fix for `npm install -g`, `npx` plugin installs, and `claude mcp add`:
  under the script-wide `EAP='Stop'`, any stderr write from those tools was a
  *terminating* NativeCommandError (false npm failure; Claude MCP registration
  could abort the installer).
- Measured PS 5.1 gotcha documented: a function parameter named `$Args`
  silently breaks `$LASTEXITCODE` propagation.
- `playwright-mcp` no longer forces Google Chrome: set user env
  `PLAYWRIGHT_MCP_EXECUTABLE_PATH` to any browser exe (Opera GX, Brave, ...)
  before installing and the wiring appends `--executable-path` automatically.
  Verified live against Opera GX via CDP.

## 7.5.5

- Hermes `config.yaml` ships in the tailored tree and the installer wires it
  into the Hermes home (backup-first, idempotent, `-SkipHermesConfig`).
- README "What's new" completed - all 24 releases present (was missing eight).
- CATALOG.json / VALIDATION.json version metadata brought current.

## 7.5.4

- `unrestraint-packs` is now part of the common canonical set and fans out to
  Claude, Codex, Grok, Kimi, and Hermes by explicit operator request.
- Corrected three obsolete installer statements about Grok's MCP limit. The
  measured limit is eight running servers; seven are safe. A Grok installation
  with a plugin-provided server should keep no more than six configured.

## 7.5.3

Two bugs found by actually running the installer against a real machine.

- `Setup-HouseCarl.ps1` set `SKYRIM_MO2_INSTANCE` and `HouseCarl__Mo2InstanceDir`
  to the single character `C`. `Find-Mo2Instances` returns a `List[string]`, and
  a single-element return unrolls to a bare `[string]` on the way out. A string
  still answers `.Count = 1`, so the MO2 branch was taken, and `$mo2List[0]` then
  indexed the *string* - yielding the first character of `C:\...`. Anyone with
  exactly one MO2 instance got a houseCARL pointed at a path that never existed.
  Fixed by forcing array semantics (`@(Find-Mo2Instances)`), and a guard now
  refuses to persist an instance directory with no `ModOrganizer.ini` rather
  than writing a bogus value silently.
- `BUNDLED-TOOLS/CATALOG.json` still declared `pack_version` 6.8.0 with an
  updated_utc of 2026-08-02, seven minor versions behind `VERSION.txt`. Anything
  reading the catalog to decide what the pack is saw the wrong answer.

- Fixed dangling references left by the 7.5.2 cleanup: `START-HERE.txt` still
  carried a V7.5.1 title, both it and `README.md` pointed at the deleted
  `AIO Instruction.txt`, and the READ NEXT list used bare changelog filenames
  that now live under `docs/history/`.

## 7.5.2

Repo hygiene and a version-drift fix found by auditing the pack rather than
running it.

- The installer banner and its internal `version` field still said 7.5.0 on a
  7.5.1 release, so a correct install reported the wrong version. Both now
  track the release.
- `README.md` and `INSTALL-REMOTE.ps1` advertised the one-liner with
  `-Tag v7.5.0` hard-pinned, so the documented copy-paste install fetched an
  old release forever instead of the latest. The pin is gone; empty tag means
  latest.
- Removed `AIO Instruction.txt`, a byte-identical duplicate of
  `AIO-INSTRUCTION.txt` left behind by a rename.
- Moved 26 per-version changelogs and v4/v5-era audits into `docs/history/`.
  The root drops from 33 markdown files to 7, so a newcomer sees only current
  docs. Nothing was deleted.
- Moved the operator's unrestraint preamble into `0-UNRESTRAINT-PACKS/`, where
  that material already lives, instead of the pack root.
- Fixed the completeness gate blocking its own release commit. `uncommitted_code()`
  skipped only untracked files, so *staged* changes counted as "not in this
  release" - but staged changes are exactly what the pending commit contains.
  Once HEAD touched a version file, the gate refused every `git commit` that
  carried a code file, including the commit that would have completed the
  release. It now judges the worktree column of `git status --porcelain`, so
  only genuinely unstaged work is reported, and resolves renames to their
  destination path. Two self-test cases added: staged code must be silent,
  unstaged code must still be caught.
- `MANIFEST.json` regenerated; it had drifted (referenced the deleted duplicate).

Not changed: the ~72 MB of byte-identical reference payloads duplicated across
provider trees. Git stores those as a single blob, and each provider tree is
deliberately self-contained so it can be copied straight into that provider's
home. Deduplicating them would save zip size at the cost of the one-command
install.

## 7.5.1

First end-to-end installer run on a real machine surfaced three bugs, all
fixed: (1) Set-V5GrokCompatCells' replace pattern ate every [mcp_servers.*]
block after [compat.claude] on machines that already had the section (re-run
hazard; Grok config wipe); (2) Headroom pip step died on a PATH python without
pip and on pip's stderr under strict error handling; (3) gates and reasoning
MCPs silently no-op'd on multi-provider installs (`-File -Providers $arr`
unrolls arrays). Grok's MCP budget stays at the proven six. See
`V7.5.1-CHANGELOG.md`.

## 7.5.0

This file exists so the completeness gate can see the current version on the
same commit that bumped `VERSION.txt`. Detail lives in the dated files.

## 7.5.0

SOUL for every agent + install from zero. New `4-PREAMBLES/` (operator's soul
config + identity-neutral universal soul + manual-paste file for web UIs);
the installer wires SOUL + AIO operating contract into Claude Code, Codex,
Kimi, Grok (global AGENTS.md) and copies SOUL.md into Hermes home - idempotent,
backup first, `-SkipPreamble` to opt out. New `INSTALL-REMOTE.ps1/.bat` one
command fresh-machine install (downloads latest release, extracts, runs the
real installer); releases now carry a zip asset. Catalog fix: Hermes home is
`%LOCALAPPDATA%\hermes`, not `~/.hermes`. BOOTSTRAP.txt now bootstraps from
GitHub when the bundle is absent. See `V7.5.0-CHANGELOG.md`.

## 7.4.3

This file exists so the completeness gate can see the current version on the
same commit that bumped `VERSION.txt`. Detail lives in the dated files.

## 7.4.3

Corrects v7.4.2's server limit. Five was never tested against six: five
different 6-server sets all pass, four different 7-server sets all wedge. And
`[compat.claude] mcps = false` does NOT stop plugin-provided MCP servers -
`mcp-search` from claude-mem was silently occupying a slot, so the real cliff is
**8 running**. Budget 6 configured with an MCP-providing plugin enabled, 7
without. See `V7.4.3-CHANGELOG.md`.

## 7.4.2

Corrects v7.4.0: MCP DOES work in Grok. `tool_count: 26` is the built-in count
by design - Grok reaches MCP through `search_tool`/`use_tool` and never injects
MCP tools. Verified by actually calling tools on two servers. The real limit is
server COUNT: 5 is fine (0ms wait), 6+ wedges startup. Installer wires Grok MCP
by default again and warns at 6. See `V7.4.2-CHANGELOG.md`.

## 7.4.1

The installer now APPLIES the 7.4.0 finding instead of only documenting it: it
writes `[compat.claude] hooks/mcps = false` for every Grok install, and Grok MCP
wiring moved behind `-WireGrokMcp` (it was previously wired by default, which
freshly caused the bug the pack documents). See `V7.4.1-CHANGELOG.md`.

## 7.4.0

Grok softlock closed with measurements: a 97s turn was 2.0s of model, 60.037s of
inherited Claude hooks and 65s of MCP startup that attached zero tools
(`tool_count` was 26 in all 12 turns ever logged). Fix is two `[compat.claude]`
cells. Also fixes a blocking `sys.stdin.read()` in both hook gates that could
hang any host, and REMOVES `TOOLS/Clean-Grok-MCP-Orphans.ps1`, which killed other
applications' MCP servers. Corrects Rules 1 and 6 from 7.3.x.
See `V7.4.0-CHANGELOG.md`.

## 7.3.1

Orphan-fleet fix: new `TOOLS/Clean-Grok-MCP-Orphans.ps1` + Rule 6 in the
troubleshooting doc (Grok's MCP children survive shell close and collide with the
next session's fleet). See `V7.3.1-CHANGELOG.md`.

## 7.3.0

Grok hang forensics documented: new `GROK-MCP-TROUBLESHOOTING.md` (turn-phase log
reading, 5 field-tested rules, diagnosis cheat-sheet); "pin every npx server" rule
added to MCP examples; cbm skill gains the cold-daemon stall note. See `V7.3.0-CHANGELOG.md`.

## 7.2.2

MCP cold-start fixes: firecrawl pinned (@3.24.0) in examples + all local provider
configs; explicit Grok `[mcp_servers]` entries; codebase-memory skill documents the
v0.10.5 UI-RPC dashboard lockdown (issue #1663). See `V7.2.2-CHANGELOG.md`.

## 7.2.1

`skyrim-forge` skill: 5.x version refresh + provider-runtime venv trap documented with
repair recipe (MCP clients hang at startup when the venv's base interpreter lives in a
deleted provider runtime cache). See `V7.2.1-CHANGELOG.md`.

## 7.2.0

Makes the tooling enforce what v7.0.0 only documented. `fanout_providers.py` now scopes
`unrestraint-packs` to Hermes and preserves source line endings — a full fanout run
leaves `git status` clean, where before it dirtied 12 files and created 8 directories.
`install_live_skills.py` probes before backing up, so an unchanged tree no longer costs
~53 MB per provider. Completes the V6→V7 rename of live artifacts (`_V7-CANONICAL-SKILLS`,
`INSTALL-V7-AIO`, `Test-V7-Pack`, `V7-Common`, `V7-AIO-GUIDE`, `v7-registry-*`);
historical changelogs keep their V4/V5/V6 names as accurate records.
See `V7.2.0-CHANGELOG.md`.

## 7.0.0

Indexing discipline for codebase-memory-mcp. The `codebase-memory` skill now covers
**how to index**, not just how to query: `.cbmignore` is case-sensitive, Papyrus is
never parsed, versioned workspaces must resolve against `CURRENT.txt`, and the
dashboard's NODES/EDGES tiles read 0 on a healthy index. Ships a `.cbmignore`
template in the project template and `TOOLS/Setup-CodebaseMemory-Index.ps1` to
generate correct scope, including the source-carrier exception. Rebuilt a real
45-project index from ~570,000 nodes to 54,553 using exactly these rules.
See `V7.0.0-CHANGELOG.md`.

## 6.9.3

Hermes `unrestraint-packs` skill (routes to the 0-UNRESTRAINT-PACKS library) added to
both Hermes trees + canonical skills. Codex CLI reinstalled fresh (0.147.0), all providers
verified live with the V6.9.2 block, stale backups/scratch purged across every provider
home. See `V6.9.3-CHANGELOG.md`.

## 6.9.2

ULTIMATE unrestraint update: `0-UNRESTRAINT-PACKS/` (operator Fun stuff kit +
Spiritual-Spell-Red-Teaming + UltraBr3aks + tuxsharxsec + claude-fable corpus +
Tavern presets). V6.9.2 block wired into Claude Code / Codex / Kimi / Grok
workspace instruction files. See `V6.9.2-CHANGELOG.md`.

## 6.9.1

Caption + sheet skills from the operator's Fun stuff kit. Jailbreak
repos not imported. See `V6.9.1-CHANGELOG.md`.

## 6.9.0

One-shot coverage: adult-fiction-in-scope, fictional-adult-modding skill,
verified-current tools. No jailbreak layer. See `V6.9.0-CHANGELOG.md`.

## 6.8.2

Stop Assuming: assumption gate, Hermes installer routed through the tool,
verify-first operating contract, toolbelt inventory. See `V6.8.2-CHANGELOG.md`.

## 6.8.1

The completeness gate was on two providers, not five. See `V6.8.1-CHANGELOG.md`.

## 6.8.0

Three MCP servers for one-shot accuracy. See `V6.8-CHANGELOG.md`.

## 6.5.0

The completeness gate. See `V6.5-CHANGELOG.md`.

## 6.0.0

The BOM bug: seven skills were invisible. See `V6-CHANGELOG.md`.
