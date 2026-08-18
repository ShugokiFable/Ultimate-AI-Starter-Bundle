# Changelog

This file exists so the completeness gate can see the current version on the
same commit that bumped `VERSION.txt`. Detail lives in the dated files.

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
