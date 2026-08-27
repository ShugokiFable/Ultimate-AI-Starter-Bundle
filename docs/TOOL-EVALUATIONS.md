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
what `codebase-memory-mcp` already provides in this pack, which the
`cbm-code-discovery-gate` hook already forces agents to reach for first. The
headline saving duplicates a capability that is already installed and already
mandatory. **Gate 2.**

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

## How to add a row

Run the candidate through the four gates in order and write down where it
stopped. If it clears all four, measure it before writing a number in
`CATALOG.json` — `TOOLS/measure_mcp_capability.py` for MCP servers, and for a
CLI filter, a real before/after on this repository the way `rtk`'s entry
records it. Upstream numbers are a reason to test, never a substitute for
testing.
