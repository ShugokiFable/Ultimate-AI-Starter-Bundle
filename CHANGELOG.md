# Changelog

This file exists so the completeness gate can see the current version on the
same commit that bumped `VERSION.txt`. Detail lives in the dated files.

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
