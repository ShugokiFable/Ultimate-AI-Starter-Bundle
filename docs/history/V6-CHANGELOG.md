# Ultimate AI Starter Bundle — v6.0.0

Date: 2026-08-14
Base: v5.2.5

v6 is a **correctness release**. The headline is not new features: it is that
v5.2.5 shipped a class of silent packaging bug that made some of its most
important skills invisible to the agents that were supposed to load them, and
that nothing in the pack could have caught it. v6 fixes the bugs, rebuilds from
the install that actually works, and adds gates so the same class cannot ship
again.

---

## 1. The BOM bug (highest impact)

**7 skills per install had no usable description.**

A UTF-8 BOM sits before the opening `---` of a `SKILL.md`. A strict YAML
frontmatter reader looks for `---` at byte 0, does not find it, never opens the
block, and the skill loses its `description`. The description is the *only*
thing an agent matches on when deciding whether to load a skill — so the skill
is installed, listed, and effectively invisible.

Affected: `ai-tooling-stack`, `codeburn`, `housecarl`, `skyrim-memory`,
`skyrim-tool-router`, `spookys-automod-toolkit`, `tool-discovery`.

Two of those — `skyrim-memory` and `skyrim-tool-router` — are the skills the
workspace instructions tell every agent to load **first** on any substantial
task. The mandated entry points were the broken ones.

Measured before the fix:

| Tree | Skills | BOM | Frontmatter unparseable |
|---|---|---|---|
| `.claude` | 88 | 7 | 7 |
| `.grok` | 87 | 6 | 6 |
| `.codex` | 158 | 7 | 7 |
| `.kimi-code` | 88 | 7 | 7 |
| v5.2.5 canonical | 48 | 5 | 5 |

Confirmed independently: the harness's own skill listing rendered those exact
skills with an empty `---` description.

Registry entry `SKILL-BOM-001`. Note that `ENC-001` had *already* warned that
BOM/encoding drift breaks valid-looking files — and the pack shipped BOMs
anyway. A written warning is not a control, which is why v6 ships a gate.

## 2. The inverse bug, found while fixing the first

**A `.ps1` needs its BOM as much as a `SKILL.md` needs to not have one.**

The first pass at fixing #1 normalised every text file to BOM-less LF UTF-8.
That broke PowerShell: `Update-From-GitHub.ps1` went from 0 to 5 parse errors.
Windows PowerShell 5.1 decodes a BOM-less file using the ANSI code page, so the
single em dash on line 49 turned into a stray quote that ended a string early,
and the parser failed on line 64.

v6 classifies files by **execution target**, not by "is it text":
`.ps1/.psm1/.psd1/.bat/.cmd` are copied byte-for-byte, never re-encoded, never
re-lined. Registry entry `PS-BOM-001`.

## 3. Mojibake repair that actually fires

`housecarl`'s description carried `â€"` for an em dash — UTF-8 read as CP1252
and re-encoded — through every v5 release. The naive repair (re-encode the whole
file to CP1252, decode as UTF-8) never ran, because the file also contains `→`,
which CP1252 cannot represent, so the strict encode threw and the whole file was
skipped.

v6 repairs **one mojibake run at a time**, so a single un-encodable character
elsewhere cannot block the repair, and legitimate accented prose is never
touched (a lone accented letter is not followed by a continuation-range
character, so it never matches). Registry entry `PS-ENC-001`.

## 4. Canonical rebuilt from the live install

v5.2.5's canonical tree had drifted behind the working install:

- **3 validator scripts missing** from the bundle but present live —
  `validate_kid.py`, `validate_spid.py`, `validate_skypatcher_layout.py`.
- **`codebase-memory` guidance was wrong.** The bundle said "never enable the
  HTTP UI". The live skill had the corrected knowledge: `--ui`/`--port` are
  persisted into the tool's *own global config*, not into one agent's MCP entry,
  so passing them from one provider changes behaviour for all of them — and the
  dashboard dies when its stdin closes, which is why it "randomly" disappears.
- **6 extras skills** were never captured (`code-review-skill`, `defuddle`,
  `json-canvas`, `obsidian-bases`, `obsidian-cli`, `obsidian-markdown`).

v6 canonical is generated **from the live install**, machine-specific files
excluded and verified excluded:

- `skyrim-forge/INSTALLATION.json` (discovered tool paths)
- `housecarl/server/houseCARL.user.json` — which was leaking the operator's own
  MO2 shim path into a redistributable. Caught by a new portability check.

**88 skills, 0 BOM, 0 unparseable frontmatter, 0 machine-path leaks.**

One more fault surfaced here that a file-level audit cannot see: `.grok`'s
`skyrim-memory` was a **Windows junction** pointing at a shared `.agents`
directory that does not exist. Grok had no `skyrim-memory` at all while still
reporting 87 installed skills, because a dangling link still *lists*. Python
treats a junction as a directory rather than a symlink, so an ordinary recursive
copy walks into the dead link and aborts even with `symlinks=True`. Registry
entry `SKILL-LINK-001`; the installer now clears dangling links before writing,
and the audit opens every `SKILL.md` rather than counting directories.

## 5. One source of truth, generated fan-out

The five provider skill trees were byte-identical to each other in v5, so
maintaining them by hand bought nothing and lost drift-resistance — that is
exactly how the corrected `codebase-memory` skill ended up live but stale in the
bundle. v6 generates all ten trees (5 tailored + 5 generic) from canonical via
`TOOLS/fanout_providers.py`. Per-provider tailoring lives outside the skills
directory and is never touched; the only in-skill tailoring is the `provider:`
metadata tag, rewritten per target.

## 6. New gates (the actual deliverable)

| Tool | What it refuses to let ship |
|---|---|
| `TOOLS/audit_skills.py` | BOM, unopenable frontmatter, missing description, mojibake in a description. Warns on tier-1/tier-2 context budget. |
| `TOOLS/build_canonical_skills.py` | Machine-specific paths, machine state files; repairs BOM/mojibake/CRLF; script files verbatim. |
| `TOOLS/merge_registry.py` | Registry rows missing required fields or claiming an evidence level outside the ladder. |
| `TOOLS/fanout_providers.py` | Hand-edited provider drift. |
| `TESTS/Test-V6-Pack.ps1` | Runs all of the above plus a parse check of every shipped `.ps1`. |

## 7. Evidence registry: 70 → 85 entries

15 new, each from a real failure with its evidence attached:

`SKILL-BOM-001`, `PS-BOM-001`, `PS-ENC-001`, `SKILL-LINK-001`,
`PLUG-HEDR-003`, `FRAME-SPID-KEY-002`, `OAR-OVERLAY-001`, `MCM-GLOB-001`,
`RM-SLIDER-001`, `RM-JSLOT-001`, `LOC-FULL-001`, `DEP-HASH-001`,
`ARMA-RACE-001`, `VAL-REACH-001`, `NPC-STANDALONE-001`.

Highlights:

- **`ARMA-RACE-001`** — `Race=DefaultRace` on an ArmorAddon is **not** a
  wildcard. Vanilla `NakedTorso` also has `Race=DefaultRace` *and* lists 10
  additional races including NordRace; `NordRace.ArmorRace` is a null link.
  Read from the installed game, not recalled.
- **`VAL-REACH-001`** — adding another static check does **not** turn
  tool-validated into runtime-confirmed. Evidence: a build passed a ship gate,
  a defect was found, a new gate was written that failed the old build and
  passed the new one — and the new build was still broken in game.
- **`NPC-STANDALONE-001`** — evidence status **`contradicted`**. Retargeting an
  NPC's race to drop a body-framework master is an unproven technique; baked
  FaceGen is race-coupled and normally needs a Creation Kit re-bake. Recorded as
  a failure so it is not repeated.

## 8. Protocol and model baselines refreshed

- **MCP 2026-07-28** — new skill `mcp-protocol-2026`. The protocol is now
  **stateless**: the `initialize`/`initialized` handshake and `Mcp-Session-Id`
  are retired, server-initiated calls are replaced by Multi Round-Trip Requests,
  `Mcp-Method`/`Mcp-Name` routing headers are required, list results are
  cacheable via `ttlMs`/`cacheScope`, authorization moves to RFC 9207 issuer
  validation and Client ID Metadata Documents, and Tasks / MCP Apps / EMA become
  formal extensions. Roots, Sampling and Logging are deprecated on a 12-month
  window. Every server this pack wires is local stdio, so **no config change is
  required** — the skill exists so that is a verified statement rather than an
  assumption.
- **Agent Skills three-tier budget** documented and gated. `name` +
  `description` sit in context for *every installed skill on every request*;
  the body loads on activation; bulk belongs in reference files. Measured by
  `TOOLS/audit_skills.py` across the 88 canonical skills.
- **Grok 4.6** (SpaceXAI, 2026-08-12) — long-running agents, stronger agentic
  coding, self-checking during long tasks.

## 9. Tool refresh

| Component | v5.2.5 | v6 |
|---|---|---|
| Superpowers | 6.2.0 | **6.3.0** |
| Ponytail | 4.8.4 | **4.9.0** |
| houseCARL | 1.9.0 | 1.9.0 |
| Spooky's AutoMod Toolkit | 1.11.2 | 1.11.2 |
| codebase-memory-mcp | 0.9.0 | 0.9.0 |
| Headroom | 0.33.0 | 0.33.0 |
| CodeBurn | — | 0.9.19 |

Offline assets re-fetched and hash-verified; `OFFLINE-MANIFEST.json`
regenerated with real sha256 values; superseded assets removed so the
`asset_match` globs cannot pick a stale zip.

## 10. Renames

`INSTALL-V5-AIO.ps1/.bat` → `INSTALL-V6-AIO.ps1/.bat`;
`TOOLS/V5-Common.ps1` → `TOOLS/V6-Common.ps1`;
`_V5-CANONICAL-SKILLS/` → `_V6-CANONICAL-SKILLS/`.

Deliberately **not** renamed: internal function names (`Copy-V5RoboSafe`) and
the `%LOCALAPPDATA%\Skyrim-AI-V5` state directory. Renaming those is churn that
would orphan existing installs for no user-visible gain.

Three skills (`ai-tooling-stack`, `housecarl`, `tool-discovery`) still told
agents to run `INSTALL-V5-AIO.ps1`, a file v6 does not ship — the README's own
"recommend the installer, don't invent paths" contract pointing at a missing
path. Corrected in canonical and regenerated to all ten provider trees.

## Upgrade from v5.2.5

```powershell
.\INSTALL-V6-AIO.ps1
```

Then **fully restart** each AI app. To verify the BOM fix took:

```powershell
python TOOLS\audit_skills.py "$env:USERPROFILE\.claude\skills"
```

Expect `RESULT: PASS (0 fail, ...)`. Warnings are context-budget advice, not
failures.

## Known limitations, stated plainly

- 19 skills exceed the tier-1/tier-2 context budget (22 warnings: 17 oversized
  descriptions, 5 oversized bodies). They work; they are not free. Trimming them
  is deferred, not done.
- The Skyrim follower conversion that produced `ARMA-RACE-001` is **broken in
  game** and is recorded as such (`NPC-STANDALONE-001`, evidence
  `contradicted`). Nothing in this pack cites it as a working example.
- Everything in this release is **tool-validated**: gates pass, scripts parse,
  hashes verify. The installer has not been run end-to-end on a clean machine
  as part of this build.
