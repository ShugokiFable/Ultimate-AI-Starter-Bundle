# Tool evaluations

Why a candidate was taken or left. A rejection with no recorded reason gets
re-proposed every few months, and a tool that was right to reject in August may
be right to take in December — but only if the reason is written down and can
be re-checked.

Every row below was decided against the same four gates, in this order. A tool
fails at the first one it does not clear.

1. **Native Windows.** This pack installs on Windows with Windows PowerShell
   5.1. A tool whose integration is a POSIX shell hook does not "mostly work"
   here — it degrades, usually silently.
2. **No duplication.** If something already in the pack does the job, the
   incumbent wins unless the challenger is measurably better.
3. **Standing token cost.** A CLI costs nothing until called. An MCP server's
   schemas are serialized into the prompt every single turn.
4. **Claims survive reading the source.** Landing-page numbers are marketing
   until the repository's own measurements agree with them.

---

## 2026-08-26

Six candidates. One taken.

### TAKEN — OMNI (`fajarhide/omni`), Apache-2.0

Cross-call deduplication of tool output: returns a handle instead of resending
content the agent has already seen, and drops noise (build logs, progress bars,
ANSI).

- **Windows:** ships `omni-v0.7.8-x86_64-pc-windows-msvc.zip` with
  `SHA256SUMS`, released 2026-08-25. Full host rewrite on Claude Code, Codex
  CLI and Gemini CLI; Hermes explicitly supported.
- **Duplication:** none. `rtk` filters a single command's output on its way
  past; OMNI remembers across calls. Different mechanisms, they stack.
- **Cost:** CLI plus host hook. Zero standing tokens.
- **Claims:** the landing page says "97.2% off a file read twice" and "~24%".
  The README's own corpus of **9,478 executions** says **"1.4% from the
  filters, 5.1% with the ledger."** The catalog entry records 5%, not 97%.

Added as `cli-optional`, not auto-installed. A 5% saving does not justify
rewriting every tool result on someone's machine by default.

#### Follow-up: RTK vs OMNI, measured on this repo

The entry above took both tools' claims on trust. Measured, `rtk 0.45.0` and
`omni 0.7.8` against the same git corpus in this repository:

| command | raw | rtk | | omni | | omni fidelity |
|---|---|---|---|---|---|---|
| `git log -15` | 33,816 | 4,484 | 86.7% | 33,816 | 0.0% | left alone by design |
| `git log v8.6.1..v8.6.5` | 14,250 | 1,663 | 88.3% | 14,250 | 0.0% | left alone by design |
| `git status` | 53 | 35 | 34.0% | 53 | 0.0% | left alone by design |
| `git diff v8.6.4..v8.6.5` | 33,453 | 24,977 | 25.3% | 28,228 | 15.6% | archived, retrievable |
| `git log --stat -20` | 102,301 | 5,642 | 94.5% | 50,124 | 51.0% | **truncated, not archived** |
| `git diff v8.6.1..v8.6.5` | 430,285 | 54,251 | 87.4% | 50,123 | 88.4% | **truncated, not archived** |
| **total** | **614,158** | **91,052** | **85.2%** | **176,594** | **71.2%** | |

**They are not competitors, and the earlier entry was right about that.** OMNI's
own README puts it better than the catalog did: the ledger "removes bytes
because they are already in the context, not because a pattern calls them
noise" — "the half a filter cannot do." On the axis where they *do* overlap,
filtering, RTK wins decisively.

**OMNI's headline 71.2% here is not 71.2% of saving.** Two rows exceeded a
65,536-byte cap and were cut, and the marker says so plainly:

```
[OMNI: 6730 lines omitted, full output not archived:
 430285 bytes over the 65536 byte rewind cap]
```

Above that cap the content is **gone**, not archived — which the README's
four-guarantees table ("get the original back, byte-for-byte") does not
qualify. Excluding the truncated rows, OMNI's real recoverable saving on this
corpus was **6.4%** — close to its own published git figure of 8.8% and its
5.1% aggregate. The honest reading is that OMNI's self-reported numbers are
sound and its *apparent* large wins come from truncation.

Below the cap the guarantee holds, and it is verifiable: `omni retrieve` on a
33,453-byte diff returned it byte-for-byte identical, and the handle **is** the
content's SHA-256 prefix, so retrieval is self-verifying.

RTK is lossy by design with no archive and never claims otherwise, so its 85.2%
and OMNI's 6.4% are not the same kind of number: RTK condenses and discards,
OMNI's below-cap saving is fully recoverable. Both remain `cli-optional`,
neither auto-installed, and stacking them is still the right recommendation.

*Caveat: measured through `omni exec`, which is the documented way to try one
command without installing hooks. A full host integration may distill more, and
the ledger half cannot be measured in a single session at all — it only pays as
repetition accumulates across real work.*

### REJECTED — lowfat (`zdk/lowfat`), Apache-2.0 — **gate 1, Windows**

Filters CLI output and file content before it reaches the agent. Genuinely
good idea, and its Claude Code integration is a real `PreToolUse`/`PostToolUse`
hook rather than prompt injection.

But release **v0.8.0 (2026-06-19) publishes four assets — two darwin, two
linux-gnu — and no Windows binary at all.** Native Windows means building from
source with a Rust toolchain, and the shell integration is an eval hook keyed
on `CLAUDECODE=1`. That is precisely the degradation this catalog already
documents for `rtk`'s non-Hermes hooks, where the fallback costs context to
*ask* for savings.

Worth re-checking when a `pc-windows-msvc` asset appears. Note also that its
published figures and `rtk`'s do not point the same way — lowfat reports
`git status` −91% and `git log` −93% but `git diff` **−15%**, where `rtk` was
measured on this repository at `git diff HEAD~3` 2,010,426 → 71,268 bytes
(**−97%**). If lowfat ever ships for Windows, that is a bake-off to measure,
not a swap to assume.

### REJECTED — Understand-Anything (`Egonex-AI/Understand-Anything`), MIT — **gate 2, duplication**

Turns a codebase into an interactive knowledge graph via tree-sitter plus LLM
agents.

`codebase-memory` already ships here and already answers the same questions —
symbols, call graphs, dependencies — from a structural index. Its own
documentation states that "initial analysis consumes significant tokens", which
is the opposite of what this pack optimises for, and the deliverable is a web
dashboard for a human rather than a queryable surface for an agent.

### REJECTED — Agent-Reach (`Panniantong/Agent-Reach`), MIT — **gate 1, install method**

**Superseded by the 2026-08-29 v1.5.0 re-evaluation below.** The remote-script
installer is no longer the decisive problem; its mutable meta-installer surface
and overlap are.

Unified reading and search across Twitter, Reddit, YouTube, GitHub, Bilibili
and XiaoHongShu with no API fees. The capability gap is real — nothing here
reads social platforms.

Rejected on how it installs: the documented path is handing an AI agent a URL
to an installation script and letting it execute. This pack verifies what it
ships (`MANIFEST.json`, `CHECKSUMS`, pinned versions, `SHA256SUMS` on
third-party binaries); "let the agent curl and run a script" cannot be
reconciled with that. The scraping backends are also inherently fragile — the
project's own README describes swapping `yt-dlp` for `bili-cli` after a
platform block — so it needs an owner watching it, which a bundled tool does
not get.

### DOCUMENTED, NOT BUNDLED — Lightpanda (`lightpanda-io/browser`), AGPL-3.0 — **gate 1**

A headless browser written in Zig, not Chromium-based, benchmarked at 123 MB
vs 2 GB and 5 s vs 46 s over 100 pages against headless Chrome — roughly 16×
the memory efficiency and 9× the speed. CDP-compatible, so Puppeteer and
Playwright can drive it.

Two blockers, either sufficient:

- **No native Windows support** (WSL2 required), and this pack is Windows-first.
- **AGPL-3.0**, which is a licence question for redistribution rather than a
  technical one, and not a question to answer casually.

It remains the most interesting answer to "a lighter crawler that consumes less
and gets blocked less", because it is a *backend* rather than a competitor:
`playwright-mcp` can point at a CDP endpoint. For a WSL2 user that is a
supported thing to wire up by hand. It is not a default.

### DOCUMENTED, NOT BUNDLED — llmtrim (`fkiene/llmtrim`), MPL-2.0 — **gate 4**

A local proxy that compresses requests on the way to the model API, claiming
"−31% input · −74% output · −66% round-trip cost" over 112 A/B cases.

Not rejected as bad — rejected as *not something to install on someone's
machine by default*, for two reasons:

- **It sits between the agent and the provider.** Every request, including the
  credential that authenticates it, passes through. This pack's standing rule
  is that it does not handle API keys, and routing all traffic through an
  additional local process is a change to the trust boundary, not a
  configuration tweak.
- **The −74% output figure needs explaining before it is believed.** Input
  compression is mechanical and easy to credit. Reducing what the *model emits*
  by three quarters "with no change to the answers" is a much stronger claim,
  and nothing in the README reconciles the two.

Revisit if the output figure is explained, and even then as an explicit opt-in
with the trust-boundary change stated plainly.

---

## 2026-08-27 — reverse-engineering tools

Six asked about together. **None bundled.** Not because they are bad — Ghidra
and ImHex are excellent — but because five of six are the wrong *shape* for a
pack that installs CLIs and MCP servers, and the sixth is stale.

| tool | stars | licence | last push | verdict |
|---|---|---|---|---|
| [Ghidra](https://github.com/NationalSecurityAgency/ghidra) | 72.9k | Apache-2.0 | 2026-08-25 | documented — GUI, ~1.5 GB |
| [GhidraMCP](https://github.com/LaurieWired/GhidraMCP) | 9.9k | Apache-2.0 | **2025-06-23** | **rejected — 14 months stale** |
| [GhidrAssist](https://github.com/symgraph/GhidrAssist) | 710 | MIT | 2026-05-29 | documented — wrong direction |
| [radare2](https://github.com/radareorg/radare2) | 24.7k | (LGPL, unlabelled) | 2026-08-27 | documented — best shape of the six |
| [Frida](https://github.com/frida/frida) | 21.8k | (unlabelled) | 2026-08-18 | documented — process injection |
| [ImHex](https://github.com/WerWolv/ImHex) | 54.6k | GPL-2.0 | 2026-08-26 | documented — GUI |

**GhidraMCP is the one that would have mattered**, because it is the only one
that puts an agent in the loop rather than a human. It is also the only one that
fails on maintenance: last commit and last release both **2025-06-23**, 82 open
issues, while Ghidra itself shipped through to **12.1.3** in that time. A bridge
to a fast-moving GUI application, untouched for over a year, is a liability the
pack would inherit.

**Four of the six are desktop GUIs** (Ghidra, ImHex, and GhidrAssist which runs
*inside* Ghidra). This pack's standing law is that GUI tools are user-side — it
is the same rule that forbids launching SSEEdit, xEdit or the Creation Kit. It
installs things an agent can drive from a command line.

**GhidrAssist points the wrong way.** It wires an LLM into Ghidra so Ghidra can
ask a model for explanations. This pack wires agents to tools, not tools to
models, and it would want its own endpoint and key.

**radare2 is the one with the right shape** — a scriptable CLI with real
`w64` zips, pushed the day this was written, so it costs zero standing tokens
and an agent can drive it directly. It is not bundled because of what is below,
not because of what it is.

**Frida** hooks and rewrites functions in a live process. That is legitimate for
this domain — SKSE is itself a hook framework — but auto-installing a
process-injection toolkit on someone's machine is not something a double-clicked
installer should decide.

**And for the domain this pack actually serves, the need is thin.** SKSE plugin
work overwhelmingly resolves addresses through Address Library IDs and
CommonLibSSE, which exist precisely so that individual modders do not each
re-derive offsets. Fresh reverse engineering is a real but niche need, and the
pack already carries `skse-plugin-authoring`, `skyrim-skse-commonlib` and
`win64-native-builds` for the part that is not niche.

If that changes, **radare2 first** (CLI, scriptable, cheap), and Ghidra as a
documented user-side install.

## 2026-08-27 — lean-ctx, measured

[lean-ctx](https://github.com/yvgude/lean-ctx) (Apache-2.0, Rust, 3.6k★) was
carried forward from the 2026-08-26 search as the only candidate claiming
reversible compression. Measured, it is **documented, not bundled**.

**Supply chain is the best of anything evaluated here.** The release ships
`SHA256SUMS` *plus* `SHA256SUMS.sig` and `SHA256SUMS.pem` — sigstore signing.
The Windows `x86_64-pc-windows-msvc` hash verified on download.

**Its own numbers are real, but they are a different operation than they read
as.** On `TOOLS/UABS-Common.ps1`, 67,219 bytes:

| mode | bytes | saved |
|---|---|---|
| `-m map` | 2,355 | **96.5%** |
| `-m signatures` | 2,144 | **96.8%** |
| `-m outline` | 67,217 | 0.0% |
| `-m summary` | 67,217 | 0.0% |
| default `read` | 63,905 | 4.9% |

The 96.5% is `map` mode, and map mode returns this:

```
fn pub Install-UabsKimiPlugin() @L1216-1326
fn pub Restore-UabsHermesPluginScan() @L1328-1388
```

That is a **symbol index, not a compressed file**. Useful — and it is precisely
what `codebase-memory-mcp` already provides in this pack. The headline saving
duplicates a capability that is already installed. **Gate 2.**

*Corrected 2026-08-27:* this paragraph used to say the `cbm-code-discovery-gate`
hook "forces agents to reach for" cbm first, and that the capability was
"mandatory". Reading the hook shows it does neither — its own comment says
"Despite the name this NEVER blocks a tool call - it only adds graph context",
and it exits 0 silently when the binary is absent. The hook that *instructs* is
`cbm-session-reminder`, and cbm is profile-gated here, so on most sessions it
was naming tools that were not registered. See the doctor check added in
8.6.12.

**On shell output it did nothing here.** Same pinned corpus used for rtk and
OMNI, through `lean-ctx -c`:

| command | raw | lean-ctx | saved |
|---|---|---|---|
| `git log -15` | 40,757 | 40,757 | 0.0% |
| `git status` | 53 | 53 | 0.0% |
| `git diff v8.6.4..v8.6.5` | 33,453 | 33,453 | 0.0% |
| `git diff v8.6.1..v8.6.5` | 430,285 | 430,285 | 0.0% |

**Standing cost: 78 MCP tools.** The tool knows: it ships `lean-ctx tools
minimal|standard|power` and a `tools health` report for "token-budget & rot".
A server that needs its own tool-budget triage is a poor fit for a pack whose
first principle is that MCP schemas are charged on every turn. **Gate 3.**

The binary is **102 MB** against rtk's 9 MB.

**What is genuinely novel, and worth stealing conceptually:** secret redaction
is ON by default (`.env` and API keys masked *before* the model sees them), plus
a path jail scoped to the project root and a 223-command shell allowlist.
Neither rtk nor OMNI has anything like it. Its `gain` command also labels itself
"not a benchmark", which is more honesty than most landing pages manage.

Not bundled: the headline win duplicates `codebase-memory`, the MCP surface is
78 tools, and measured compression on this corpus was zero.

## 2026-08-27 — rtk off the git corpus

Every rtk figure this pack had shipped — 87%, 88%, 25%, 0%, and the retired
97% — was a **git** command. rtk's own pitch is loudest about build output,
test runners and logs. Those had never been measured. Measured now, at
**0.46.0**, same repo, **stdout only**:

| Command | Native | rtk | Saved | Fidelity |
|---|---|---|---|---|
| `rtk err <powershell pack gate>` | 5,746 B | 567 B | **90.1%** | SUBSET |
| `rtk test <python suite, RED>` | 5,507 B | ~400 B | **93%** | FAIL line kept |
| `rtk ls -la` | 811 B | 271 B | 66.6% | rewritten |
| `rtk ls -R` (164 skills) | 25,059 B | 19,129 B | 23.7% | rewritten |
| `rtk grep -rn` | 17,588 B | 14,463 B | 17.8% | **TRUNCATED** |
| `rtk wc -l` | 5,414 B | 5,003 B | 7.6% | rewritten |
| `rtk read` (191 KB `.py`) | 191,795 B | 191,795 B | **0.0%** | IDENTICAL |
| `rtk read` (119 KB `.ps1`) | 119,226 B | 119,226 B | **0.0%** | IDENTICAL |
| `rtk proxy python -m pip list` | 4,766 B | 4,766 B | 0.0% | IDENTICAL |
| `rtk json` (5,425-row array) | 1,121,123 B | 144 B | *100%* | **TRUNCATED** |
| `rtk json` (nested object) | 34,442 B | 4,050 B | *88.2%* | **TRUNCATED** |
| `rtk find` **compound** (`-not -path`) | 4,869 B | **0 B** | — | **exit 1** |
| `rtk find` simple (`-name`) | 709 B | 565 B | 20.3% | paths stripped |

**Excluding rows that truncate rather than compress: 7.4%.** The git corpus
measures 85.2% on the same tool and the same day. rtk is a git tool that also
ships filters.

### Three things the first pass got wrong

**stderr contaminated every row.** rtk writes a 78-byte
`[rtk] /!\ No hook installed` nag to stderr on *every* invocation. Captured
combined, it inverts small rows: the `find` row measured **-486%** before
stdout was isolated. Anyone benchmarking this tool with `2>&1` is measuring the
nag.

**`rtk read` is not a 0.1% loss, it is byte-identical.** The apparent +78 bytes
was the nag. Redirected to a file, `rtk read` reproduces `cat` exactly — which
confirms the catalog's existing claim and also means it saves *nothing*.

**100% is not always a saving.** `rtk json` on `MANIFEST.json` returns 144 bytes
from 1.1 MB by printing one array element and `... +5424 more`. That is a
sample. The same trap as lean-ctx's `-m map`: a different operation wearing a
compression ratio.

### `rtk find` breaks on compound predicates

The first measurement here used `find . -name '*.ps1' -not -path './.git/*'`
and concluded rtk shell-expands the pattern. **That diagnosis was wrong.** A
simple `-name` works:

| Form | Result |
|---|---|
| `rtk find TOOLS -name '*.ps1'` | 709 B → 565 B, 24 files, **exit 0** |
| `rtk find . -name '*.ps1' -not -path './.git/*'` | **0 B, exit 1** |

```
/usr/bin/find: paths must precede expression: `INSTALL-REMOTE.ps1'
```

It is the **compound predicate** that fails, and this is upstream-known and
unfixed. `rtk-ai/rtk` has ten-plus open issues against `rtk find` alone:

| Issue | Report |
|---|---|
| #2469, #2847, #3256, #3458 | compound predicates unsupported (four near-duplicates, all open) |
| #3656 | silently hides everything `.gitignore` covers |
| #3291 | silently returns no results for hidden files, exit 0 |
| #2589 | stops working after `git init` |
| **#3410** | **the `find` rewrite is unconditional, so `find … -delete` / `-exec` is captured and refused — silently does nothing and breaks `&&` chains** |

#3410 is the serious one and it is *their* report, not measured here — this
pack does not run `-delete` to find out. Four duplicate reports of the same
limitation sitting open also says something about triage.

Separately, `rtk find` **reformats paths**. Single-directory mode strips the
prefix (`Build-Release.ps1`, not `TOOLS/Build-Release.ps1`); across directories
it regroups under a `10F 2D:` header. Real saving, small, but the output is not
a path list you can pipe into anything.

### Correction: rtk does not always discard

This pack shipped, in both the README and the catalog, that rtk keeps
**"no archive and no retrieval"**. That was measured on `git` and generalised.
Verified per subcommand by watching `%LOCALAPPDATA%\rtk\tee`:

| Subcommand | Tee written? |
|---|---|
| `rtk test` | **yes — complete** (all 96 result lines, 5,409 B) |
| `rtk grep` | partial (6,482 of 17,588 B) **but prints the retrieval command** |
| `rtk git`, `rtk ls`, `rtk read`, `rtk json`, `rtk wc` | no |

`rtk grep` cuts each file at 25 hits and appends
`+28 more in <file> [see remaining: tail -n +26 "<tee path>"]` — the truncation
is recoverable, not lost, which is closer to OMNI's handle model than to
discarding.

### What the filters actually drop

The `-g` hook applies these to commands you did not opt into, so it matters
what each one removes beyond bytes:

| Filter | Silently gone |
|---|---|
| `rtk ls -la` | **timestamps and owner**, and sizes rounded (`36.6K` for 37,481 B) — the two usual reasons to pass `-la` |
| `rtk grep` | middle path segments (`TOOLS/.../hooks/assumption_gate.py`) |
| `rtk find` | directory prefixes, stripped or regrouped |

In each case the saving is real and the output has stopped being a value you can
pipe into anything else.

So the blanket claim was false for the one subcommand where an archive matters
most — a test runner, where you filter to the failure and may then want the
full log. `rtk test` prints the path to it. Both documents now say this.

### Broad hook rejected; narrow hook adopted (re-probed 2026-09-02)

The 2026-08-27 verdict rejected RTK's whole hook. That was too binary. Re-probing
0.47.0 preserved a small safe subset and also showed that upstream's rewrite
table remains broad:

| Typed | Upstream rewrite | Bundle policy |
|---|---|---|
| exact standalone `git status` / `--short` / `-s` | `rtk git status ...` | automatic; a five-state fixture was line-identical 5/5 |
| standalone `pytest`, `cargo test`, `go test` | matching RTK test filter | automatic only for human-facing output |
| `git diff`, `git show`, `git log` | RTK summary | raw; a large diff retained 341 of 5,856 changed lines |
| `git add`, `git commit`, `git push` | **rewritten despite mutation** | raw |
| compound `find` | broken `rtk find` | raw |
| `cat`, `grep`, `curl`, `gh` | rewritten | raw: zero-gain, lossy, or exact-body surfaces |
| JSON/JUnit/report output, pipes, redirects | varies | raw |

The binary is therefore a default component, but the broad upstream hook and
Hermes `rtk-rewrite` plugin remain off. `rtk_safe_hook.py` owns the allowlist,
fails open, and is installed as PreToolUse only for Claude, Grok and Hermes.
Codex and Kimi receive the same narrow instruction without pretending they have
a trusted command-mutation hook. Its self-test pins every unsafe category above,
and a version guard leaves a newer RTK raw until its rewrite table is re-measured.

The pinned Git corpus was re-run for 0.47.0: `git log v8.6.1..v8.6.5`
measured 14,250 -> 1,658 bytes; the large diff 430,285 -> 55,870; the small
diff 33,453 -> 26,820; and `git log --stat -20 v8.6.5` remained byte-identical
at 102,301 bytes. The explicit `v8.6.5` fixes the last moving row in the old
table. Byte savings are not fidelity: the large diff omitted 5,515 changed
lines, so broad diff routing remains rejected.

Harnesses: `test_rtk_is_documented_as_a_git_tool_not_a_general_filter` keeps the
measurement caveats; `test_rtk_safe_hook_is_default_narrow_and_self_testing`
keeps the implementation boundary.


## 2026-08-29 — image-to-3D, UI craft, and capability discovery

Eight recommendations were checked at immutable releases where upstream had
one. Three add distinct capability without another always-on MCP schema.

### TAKEN — img2threejs v1.5.1 (`img2threejs/img2threejs`), Apache-2.0

A deterministic, code-only image-to-procedural-Three.js reconstruction
pipeline. It adds something the existing Blender and image-generation tools do
not: an agent can turn one reference image into an inspectable staged model,
with evidence and correction gates instead of claiming hidden geometry is
known.

The exact v1.5.1 commit is vendored. On Windows with UTF-8 forced, upstream's
1,083-test run had no assertion failures; three fixture-setup errors were all
`WinError 1314` because an unprivileged Windows process could not create test
symlinks, and 38 tests were skipped. Its forge is Python 3.10+ stdlib. UABS adds
only a path-contained UTF-8 Python resolver and keeps one canonical skill
writer.

### TAKEN — Impeccable skill 4.1.3 + CLI 3.6.1 (`pbakaus/impeccable`), Apache-2.0

The official skill adds a broad UI-design router; the CLI makes part of that
quality floor executable. The published universal skill archive is bound to
SHA-256 `fdcb41a24ddfb613786e3141bc7bb8466a406ffbd437a2e302f4ca70181bed9f`.
The bundle pins the published npm 3.6.1 package and its registry integrity.
Skill 4.1.3 adds executable visual contracts, framework-churn hardening, and
quieter deterministic detection. UABS keeps the license and removes upstream's
self-writer and generated hook cache before fanout.

Optional Puppeteer is omitted because Playwright already owns browser rendering.
Upstream self-update and provider-directory pinning are removed so generated
provider trees still have one writer. No MCP, daemon, account, key, or standing
schema cost is added.

### TAKEN — safe skill discovery (`vercel-labs/skills` CLI 1.5.23), MIT

The CLI already searches the public skills catalog across the providers this
pack supports. Bundling another marketplace or auto-installer would create a
second writer, so UABS exposes only pinned `find`, disables telemetry/audit
calls, and requires immutable provenance, license, script, credential, write,
hook, and overlap review before anything enters `_CANONICAL-SKILLS`. The shipped
wrapper completed a live multi-word search on Windows.

### REJECTED — Agent-Reach v1.5.0 (`Panniantong/Agent-Reach`), MIT — **gate 2**

Re-tested because v1.5.0 is materially safer than the old remote-script-only
release: 154 tests passed and 8 skipped in an isolated `uv` environment. It is
still a mutable meta-installer over many third-party CLIs and cookie/auth flows;
even `doctor` installed its skill into the isolated home. Its useful surfaces
overlap Playwright, Firecrawl, the official GitHub MCP, and native web tools.
That breadth belongs in a user-owned specialist install, not the bundle core.

### REJECTED — taste-skill (`Leonxlnx/taste-skill`), MIT — **gate 2**

Fourteen prompt-heavy style skills, no immutable release, and direct overlap
with the official frontend-design skill and the more complete Impeccable router.
Adding it would spend index entries to provide a third writer for the same
judgment.

### REJECTED — OmniRoute (`diegosouzapw/OmniRoute`), MIT — **gate 2**

A full model/provider gateway with a large MCP surface and account/credential
routing. It duplicates the providers' own routing and changes the trust
boundary. Super-MCP Router remains the measured schema-on-demand experiment;
OmniRoute does not solve that narrower problem more cheaply.

### ALREADY COVERED — Playwright MCP and Anthropic official plugins

Playwright MCP is already pinned at 0.0.80 behind the `web` profile, alongside
Chrome DevTools rather than duplicated. The profile no longer turns on for
every backend-only `package.json`; it requires a frontend marker or dependency.
Its real initialize/tools-list surface is 24 tools, 18,502 schema bytes
(~4,626 tokens per enabled turn). shadcn 4.20.0 adds 7 tools / 4,495 bytes
(~1,124 tokens) only when the same project profile finds `components.json`.
Anthropic's official marketplace is already registered selectively. Enabling
the whole marketplace would reintroduce provider-specific duplicates, keyed
MCPs, and skills already carried by the canonical tree.

## How to add a row

Run the candidate through the four gates in order and write down where it
stopped. If it clears all four, measure it before writing a number in
`CATALOG.json` — `TOOLS/measure_mcp_capability.py` for MCP servers, and for a
CLI filter, a real before/after on this repository the way `rtk`'s entry
records it. Upstream numbers are a reason to test, never a substitute for
testing.
