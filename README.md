# Ultimate AI Starter Bundle v8.7.1

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

The 164 **skills** are the opposite deal: they all sit installed and cost nearly nothing until one actually matches your task. MCP servers get **no such discount** — measured in this pack, the heaviest server (houseCARL) burns ~17,000 tokens *every single turn*, and enabling the entire catalog would cost ~40,000+ tokens/turn before you've typed a word. That's why the installer enables almost nothing.

### What's ON after install

Exactly three servers in every default profile: `context7` (library docs), `github` (repo access — zero-config for new users), `headroom` (context compression). Total: ~3,700 tokens/turn. Everything else is **parked**: installed, harmless, invisible, free.

When the matching local tool is installed, Hermes also gets native named profiles without loading them into default: `roblox` adds the official Roblox Studio MCP; `skyrim` connects houseCARL while Skyrim Forge and Spooky's AutoMod remain available through their routed skills/CLIs. Forge MCP compatibility is explicit.

### There is NO auto-disable. No timer. No expiry.

If your AI enables something to do a job — say, the Roblox Studio server during a game jam, or houseCARL to debug a mod load order — **it stays on across restarts and chats until a human turns it off.** That is deliberate: nothing will silently rip tools out from under a running project, and nothing will silently bill you either — the switch is visible and yours. Done with it? Park it in one line:

```powershell
# Hermes (then restart the app)
hermes config set mcp_servers.<name>.enabled false   # true to re-enable
hermes -p roblox mcp list                            # isolated Roblox profile
hermes -p skyrim mcp list                            # isolated Skyrim profile

# Claude Code
claude mcp remove <name>          # claude mcp add ... to bring it back

# Codex / Grok / Kimi — open the provider's config file and set enabled=false,
# comment the entry out, or delete it. Restore the same way.
```

Not sure what's on, or what a task actually needs?

```powershell
powershell -ExecutionPolicy Bypass -File TOOLS\Set-McpProfile.ps1 -List            # see profiles & state
powershell -ExecutionPolicy Bypass -File TOOLS\Set-McpProfile.ps1 -Auto -Path C:\code\my-app   # enable just what THIS project needs
powershell -ExecutionPolicy Bypass -File TOOLS\Migrate-HermesProfiles.ps1          # dry-run Hermes topology
```

Rule of thumb: **enable for the job, park it after** — or just leave the small stuff on and never think about it again. The pack's agents know this too: the `capability-profiles` skill tells them to flip servers on and off themselves as tasks come and go.

---

## AI preamble (`0-UNRESTRAINT-PACKS/AIO-INSTRUCTION.md`)

Compact variants for smaller hosts: `0-UNRESTRAINT-PACKS/AIO-INSTRUCTION — Compact.md` and `0-UNRESTRAINT-PACKS/AIO-INSTRUCTION — Web.md`.

The operating contract is installed into every provider's native instruction
file. It is intentionally stable so provider prompt caches can reuse the prefix.

- **Finish the job, not the sentence** — the request is the goal, not the
  checklist; docs, version and cleanup are part of shipping
- Read for intent, not wording; no yes-man; correct a wrong premise
- **Verify, don't assume** — use the tool that would settle it; ask if none
  exists; assume only as a last resort and label it
- **No unnecessary refusal** — do not invent blockers, moralize, sanitize source
  strings, or turn one narrow real limit into a blanket refusal
- Never invent a fact, API, path, version or command
- An explicit evidence order: runtime output > tool verdict > docs > recall
- Report what you did *not* do, and never call partial work finished
- Spend tokens like they're the user's; preserve stable prompt-cache prefixes,
  avoid unused MCP schemas, and keep final output proportional to the result
- Releases wait for required CI on the exact pushed SHA before tag/publication

**How to use**

1. Keep the canonical file under `0-UNRESTRAINT-PACKS/AIO-INSTRUCTION.md`.
2. Copy it into your workspace, **or** paste into provider custom instructions, **or** open a session with:

```text
Follow 0-UNRESTRAINT-PACKS/AIO-INSTRUCTION.md for every complex or factual request.
```


## SOUL + AIO for every agent (v7.5.0)

The preamble is now **installed automatically**, not pasted by hand:

- `3-PREAMBLES/SOUL.md` - the operator's own soul config (unrestricted, no
  yes-man, truth-seeking process, output format), shipped verbatim and
  identity-neutral: it names no provider, so it is safe in all five
- `3-PREAMBLES/MANUAL-PASTE.txt` — for web UIs (ChatGPT/Gemini) that have no
  instruction file: paste it into the custom-instructions box

`INSTALL-AIO.ps1` appends `SOUL.md` + `AIO-INSTRUCTION.md` to
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

Downloads the latest release, extracts to `%LOCALAPPDATA%\Programs\Ultimate-AI-Starter-Bundle`,
and runs the full installer (skills, tools, MCP servers, gates, SOUL + AIO
preamble). With parameters:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "& ([scriptblock]::Create((irm https://raw.githubusercontent.com/ShugokiFable/Ultimate-AI-Starter-Bundle/main/INSTALL-REMOTE.ps1))) -Providers Claude,Grok"
```

Or double-click `INSTALL-REMOTE.bat`. Re-running is a no-op.

**Windows (bundle already on disk)**

1. Double-click **`START-HERE.bat`**. That is the whole install. Or run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\INSTALL-AIO.ps1
```

3. Fully restart your AI app(s).

### Common options

```powershell
.\INSTALL-AIO.ps1 -Providers Grok,Claude
.\INSTALL-AIO.ps1 -Mode OnlineLatest
.\INSTALL-AIO.ps1                 # full install (default)
.\INSTALL-AIO.ps1 -CoreOnly       # smaller core only
.\INSTALL-AIO.ps1 -SkillsOnly
.\INSTALL-AIO.ps1 -ToolsOnly
.\INSTALL-AIO.ps1 -WorkspaceRoot "D:\My\AI-Workspace"
.\INSTALL-AIO.ps1 -WithRtk        # + the rtk output filter (hook stays yours)
.\INSTALL-AIO.ps1 -WithClaudeMem  # + claude-mem (pulls in Bun, runs a daemon)
```

| Mode | Behavior |
|------|----------|
| `OnlineLatest` (default) | Fetch official current releases; fall back to bundled assets if offline |
| `BundledFirst` | Use `BUNDLED-TOOLS\offline`, fall back to GitHub |
| `BundledOnly` | Offline zips only (no network) |

### There are exactly two .bat files, and they do different things

| File | Use it when |
|---|---|
| **`START-HERE.bat`** | You already have this folder. Double-click it. This is the install. |
| `INSTALL-REMOTE.bat` | You have nothing yet. It downloads the latest release, then runs `START-HERE.bat` for you. |

Nothing else needs running. v8.1.0 deleted `INSTALL-V8-AIO.bat`, which called
`START-HERE.bat` and did nothing else -- a second name for one action, and a
sixth place the version had to be restated by hand every release.

### It wires the providers you have

A plain run detects which provider CLIs are actually installed and configures
those. Through v8.0.4 it assumed all five and then **downloaded the missing
ones**, so a machine with only Claude Code finished a "one-click install"
carrying Codex, Grok, Kimi and Hermes.

```powershell
.\INSTALL-AIO.ps1                        # detect and wire what is installed
.\INSTALL-AIO.ps1 -AllProviders          # fresh machine: install all five
.\INSTALL-AIO.ps1 -Providers Claude,Grok # exactly these
```

Detection is executable presence, not a config folder: uninstalling Kimi
actually removes it from future runs, and a leftover `~/.kimi-code` no longer
counts as an install. A genuinely empty machine detects nothing and falls back
to installing all five, because that is the only outcome that leaves it usable.

**The rule this follows:** bundle defaults optimize for a new user's
reliability; the per-machine result optimizes for the capabilities actually
present on that machine.

### Hermes: trim a server to the tools you use

Hermes filters MCP servers at the individual-tool level — `tools.include` /
`tools.exclude`, enforced at registration, so a filtered tool's schema never
reaches the model. No other provider here can do that. On a BYOK provider it is
also the only cost lever that works on every turn.

houseCARL, measured:

```
Full      45 tools  ~41,768 tokens on every turn
Lean      42 tools  ~31,369   -25%   ← what the skyrim profile installs
ReadOnly  27 tools  ~17,604   -58%   ← reads, diagnoses, Nexus; nothing writes
```

```powershell
.\TOOLS\Migrate-HermesProfiles.ps1 -SkyrimToolset ReadOnly -Apply
hermes -p skyrim mcp configure housecarl    # or pick tools by hand
```

A filter you set by hand survives re-installs. `TOOLS\Test-Installed-State.ps1`
prints what each profile currently costs, and refuses to guess a figure for a
selection nobody has measured.

### Hermes: which model to actually run

Hermes is BYOK — you pay per token, so model choice is a cost decision every
turn, not a preference. The strategy that works: **do the work on something
cheap, escalate only when the cheap one is actually failing.**

Prices are per 1M tokens, pulled from `openrouter.ai/api/v1/models`. Every slug
below was verified against that live list — none is written from memory.

| Tier | Model | In | Out | Context | Use it for |
|---|---|---|---|---|---|
| 🆓 free | `thinkingmachines/inkling:free` | $0 | $0 | 1M | multimodal, no cost |
| 🆓 free | `poolside/laguna-s-2.1:free` | $0 | $0 | 262K | text only |
| 💸 daily | `deepseek/deepseek-v4-flash-0731` | $0.04 | $0.08 | 1.3M | **most work** |
| 💸 daily | `meta/muse-spark-1.2-contributor` | $0.10 | $0.20 | 1M | daily alternative |
| 💸 daily | `deepseek/deepseek-v4-flash-vision-exp` | $0.22 | $0.66 | 1M | when the task has images |
| ⚡ medium | `deepseek/deepseek-v4-pro-0813` | $1.12 | $3.37 | 1M | Flash's bigger sibling |
| ⚡ medium | `google/gemini-3.7-flash` | $0.38 | $1.88 | 1M | harder planning |
| ⚡ medium | `z-ai/glm-5.3` | $1.40 | $4.40 | 1M | harder planning |
| 🔥 big | `x-ai/grok-4.6` | $2.00 | $6.00 | 500K | when medium stalls |
| 👑 max | `openai/gpt-5.6-sol` | $2.00 | $10.00 | 1.05M | escalation only |
| 👑 max | `anthropic/claude-opus-5` | $5.00 | $25.00 | 1M | escalation only |

**Run Flash 0731 by default.** Gemini or GLM when planning gets hard. Grok, Sol
or Opus only when you have already watched something cheaper fail — at $25/1M
out, an afternoon of agent work on Opus costs more than a month of subscription.
**If you use a frontier model heavily, buy the subscription.** The API is for
occasional escalation, not for hours of coding.

Also worth watching: `upstage/solar-pro4` at $0.03/$0.12 — currently the
cheapest thing on the board, but that is a promotional price, so re-check it
before you build a habit on it.

Switch by alias instead of pasting slugs; the installer wires these into every
Hermes profile:

```
hermes model flash          # deepseek-v4-flash-0731        (daily driver)
hermes model muse           # meta/muse-spark-1.2-contributor
hermes model flash-vision   # deepseek-v4-flash-vision-exp  (images)
hermes model ox             # stealth/ox-alpha              (free, multimodal)
hermes model gemini-flash   # google/gemini-3.7-flash
hermes model v4-pro         # deepseek-v4-pro-0813
hermes model glm            # z-ai/glm-5.3
hermes model grok           # x-ai/grok-4.6
hermes model sol            # openai/gpt-5.6-sol
hermes model opus           # anthropic/claude-opus-5
```

**Fallbacks are set, not assumed.** The starter ships a four-deep free chain, so
a 429/529/503 fails over instead of failing:

```
poolside/laguna-s-2.1:free -> thinkingmachines/inkling:free
  -> thinkingmachines/inkling-small:free -> poolside/laguna-xs-2.1:free
```

`laguna-s` is text-only; `inkling` sits directly behind it because it takes
text, image and audio. If a vision task fails over to the first entry, images
are dropped — that is the trade for a free chain.

`hermes profile create --clone-from default` copies these **once**. Nothing used
to re-converge the copies, so a `roblox` or `skyrim` profile kept the chain from
the day it was cloned — invisible until the moment failover actually mattered.
The migration now converges fallbacks and aliases across every profile:

```powershell
.\TOOLS\Migrate-HermesProfiles.ps1            # show what has drifted
.\TOOLS\Migrate-HermesProfiles.ps1 -Apply
```

It replaces a chain only when it is missing, empty, or byte-equal to one this
pack used to ship. A chain you chose is reported and left alone. Aliases are
additive — an alias you already defined keeps your value.

### Hermes: web search that does not bill you

A hosted provider's own web plugin charges per search. Hermes does not use it.
`web_search` / `web_extract` are **Hermes tools**, so the search happens outside
the model and any model can drive it -- including a local one.

With no backend configured and no key present, Hermes rotates round-robin
across several vendors' public free tiers and fails over on rate limits
(`web.keyless_fallback`, on by default). A failing call also retries once on
that ring (`web.keyless_rescue`). Nothing to sign up for.

For a backstop that depends on no vendor account at all, add DuckDuckGo:

```powershell
& "$env:LOCALAPPDATA\hermes\hermes-agent\venv\Scripts\python.exe" -m pip install ddgs
```

Hermes ships the backend already; the package is the only missing piece. Pin it
with `web.search_backend: ddgs` **only** if the free ring gets flaky -- pinning
turns the rotation off.

### Hermes: run a local model, free and off the record

`lmstudio` is a first-class Hermes provider. Point an alias at a model LM Studio
is serving and switch to it with `hermes model local`:

```yaml
model_aliases:
  local:
    model: <the id LM Studio reports at /v1/models>
    provider: lmstudio
    base_url: http://127.0.0.1:1234/v1
```

No API key: Hermes supplies its own placeholder, because there is nothing to
authenticate to. Never write a real secret into an `lmstudio` block.

**The one thing that will stop you: set the saved context to 65,536.** Hermes
refuses any model with a context window under 64,000 tokens and raises at
startup, and LM Studio's saved default is commonly 32,768. 65,536 is the number
to type -- the next power of two above the floor. A 32K window is too small for
agent work anyway: one tool result can be tens of thousands of characters.

Set it in LM Studio, then confirm it stuck by loading with **no** explicit
context flag. Loading once by hand with a flag proves nothing -- a cold start
uses the saved default, and that is what Hermes' preload picks up.

Measured here on a 16 GB card, a 35B mixture-of-experts quant at 64K context:
weights 17.08 GiB (so partial CPU offload is mandatory), ~15.5 GiB VRAM while
generating, **41 tok/s**. Set an idle TTL so the card frees itself.

Run local for the things money cannot buy -- no policy layer, no egress, no rate
limit. For everything else the hosted ladder above is faster and costs cents.
Full detail in the `local-model-ops` skill.

**Feeding a chat front-end from the same server?** SillyTavern is happy at 32K,
so 65,536 keeps one loaded model serving both. Two of its behaviours look like
a dead connection and are not: it demands a non-empty API key that a local
server ignores entirely, and a reasoning model returns an **empty** message
when Response Length is small, because thinking tokens come out of the same
budget (measured: 40 tokens in, empty reply; 600 in, 191 of 203 spent
reasoning). It also has no free web-search backend out of the box. All three
are covered in `local-model-ops/references/sillytavern.md`.

### rtk: cut command output before it reaches the model

Optional, and **not installed by default** -- see below for why that is a
deliberate choice rather than an oversight. [RTK](https://github.com/rtk-ai/rtk)
(Apache-2.0, single Rust binary) filters noisy dev commands. Measured here
**at rtk 0.46.0** against **pinned tag ranges**, so the corpus cannot drift:

| Command | Raw | Through rtk | Saved |
|---|---|---|---|
| `git log v8.6.1..v8.6.5` | 14,250 B | 1,661 B | **88%** |
| `git diff v8.6.1..v8.6.5` | 430,285 B | 54,251 B | **87%** |
| `git diff v8.6.4..v8.6.5` | 33,453 B | 24,977 B | **25%** |
| `git log --stat -20` | 128,145 B | 128,145 B | **0%** |

**0% to 88%, depending entirely on the command.** A single headline number for
this tool is not honest -- an earlier version of this table quoted 97% from
`git diff HEAD~3`, which moves with every commit and measures 82.5% today.

**Pin the tool version too, not just the corpus.** That last row used to read
**95%**, measured at rtk 0.45.0. Upgrading to 0.46.0 dropped it to zero: plain
`git log` still compresses ~86%, but `--stat` now passes straight through. The
other three rows reproduced to the byte across the same upgrade. Pinning the git
refs stopped the *corpus* from moving and did nothing about the *tool* moving,
which is why every number here now carries the version it was taken on.

It is a CLI, so it costs **zero standing tokens** -- the same reason this pack
prefers Forge's CLI over Forge's MCP.

#### Off git, it is a different tool

Every number above is a git command, and so was every number this pack had ever
shipped for rtk. Its own pitch is loudest about build output, test runners and
logs, so those were measured too -- same repo, **stdout only**, at 0.46.0:

| Command | Raw | Through rtk | Saved | Fidelity |
|---|---|---|---|---|
| `rtk err <powershell pack gate>` | 5,746 B | 567 B | **90%** | subset |
| `rtk test <python suite, RED>` | 5,507 B | ~400 B | **93%** | failure kept |
| `rtk ls -la` | 811 B | 271 B | **67%** | rewritten |
| `rtk ls -R` (164-skill tree) | 25,059 B | 19,129 B | **24%** | rewritten |
| `rtk grep -rn` | 17,588 B | 14,463 B | **18%** | **truncates** |
| `rtk wc -l` | 5,414 B | 5,003 B | **8%** | rewritten |
| `rtk read` (191 KB `.py`) | 191,795 B | 191,795 B | **0%** | byte-identical |
| `rtk json` (5,425-row array) | 1,121,123 B | 144 B | *100%* | **truncates** |

**Excluding the rows that truncate rather than compress, the non-git aggregate
is 7.4% -- against 85.2% on git.** rtk is a git tool that also ships filters.

Two traps in that table. `rtk json` returning 144 bytes from 1.1 MB is not
compression: it prints **one** array element and `... +5424 more`. And **stdout
only** matters -- rtk writes a 78-byte `No hook installed` nag to *stderr* on
every invocation, which inverts the ratio on small outputs. A 4,869-byte result
measured **-486%** until stderr was excluded.

**`rtk find` breaks on compound predicates, and upstream knows.** A simple
`rtk find TOOLS -name '*.ps1'` is fine -- 709 B to 565 B, 24 files, exit 0. Add
a compound predicate and it collapses:

```
$ rtk find . -name '*.ps1' -not -path './.git/*'     # stdout: 0 bytes, exit 1
/usr/bin/find: paths must precede expression: `INSTALL-REMOTE.ps1'
```

`rtk-ai/rtk` carries **ten-plus open issues against `rtk find` alone**,
including four near-duplicate reports of exactly this (#2469, #2847, #3256,
#3458), silent omission of gitignored (#3656) and hidden (#3291) files, and
**#3410** -- the rewrite rule for `find` is *unconditional*, so
`find ... -delete` / `-exec` is captured and refused, **silently doing nothing
and breaking `&&` chains**. That last one is upstream's report, not measured
here.

`rtk find` also **reformats paths**: single-directory mode drops the directory
prefix (`Build-Release.ps1`, not `TOOLS/Build-Release.ps1`), and across
directories it regroups under a `10F 2D:` header. The saving is real and small;
the output is not a path list you can pipe.

**Correction: rtk does not always discard.** Earlier releases of this README and
the catalog said flatly that rtk keeps no archive. That holds for `rtk git`,
`rtk ls`, `rtk read`, `rtk json` and `rtk wc` -- verified, no tee file is
written. It is **false** for `rtk test`, which writes a *complete* tee log (all
96 result lines) to `%LOCALAPPDATA%\rtk\tee` and prints the path, and only
partly true of `rtk grep`, which tees 6,482 of 17,588 bytes in per-file chunks
**and prints the retrieval command inline** -- it cuts each file at 25 hits and
appends `+28 more in <file> [see remaining: tail -n +26 "<tee path>"]`, so that
truncation is recoverable rather than lost.

**Know what the filters drop**, because `-g` applies them to commands you did
not opt into. `rtk ls -la` removes **timestamps and owner** and rounds sizes
(`36.6K` for 37,481 B) -- it cannot answer when a file changed or how big it
exactly is, the two usual reasons to pass `-la`. `rtk grep` abbreviates middle
path segments to `TOOLS/.../hooks/assumption_gate.py`. `rtk find` strips or
regroups directory prefixes. In each case the saving is real and the output has
stopped being a value you can pipe.

#### Installing it, and why the hook stays off

```powershell
.\INSTALL-AIO.ps1 -WithRtk
```

That installs the binary and then **prints** the `rtk init -g --agent <name>`
line for each provider you have, rather than running it.

The hook is left off, and as of 8.6.11 that is an evidence decision rather than
a default. Feeding `rtk hook claude` real payloads shows exactly what `-g` would
automate:

| You type | Hook runs | Worth it? |
|---|---|---|
| `git status` | `rtk git status` | **yes** -- the one real win |
| `ls -la` | `rtk ls -la` | 24-67% |
| `grep -rn ...` | `rtk grep -rn ...` | 18%, truncates |
| `cat file` | `rtk read file` | **0%** -- byte-identical, pure overhead |
| `find . -name '*.ps1' -not ...` | `rtk find ...` | **breaks** on compound predicates |
| `npm test`, `curl`, `python x.py` | *not rewritten* | -- |

So the hook automates the categories that measure worst or return wrong
answers, and does **not** automate `rtk err` / `rtk test` on a test runner --
the only strong non-git rows. **Invoke those two deliberately; leave the hook
off.** It also patches your provider's `settings.json` and rewrites every shell
command on the machine, which is a keystroke this pack leaves to you.

If you do want it, use `-g` -- and note Hermes is different: it has its own
Python plugin, registered with the non-global form.

```powershell
rtk init -g --agent claude     # or: cursor, gemini, copilot, kimi, droid, vibe
rtk init --agent hermes        # Hermes' own Python plugin
```

Everywhere else, plain `rtk init` prints `No hook installed` and
writes a **5,140-byte** instruction block into `CLAUDE.md` -- about 1,400 tokens
on *every* turn, forever, paying context to *ask* for savings.

Keep `exclude_commands = ["curl"]` in `%APPDATA%\rtk\config.toml` so exact API
bodies are never filtered. Telemetry is opt-in and stays off. Verify it is
really running with `rtk gain` -- an agent cannot tell you, because it reports
the command it *asked* for, not the one that ran.

### claude-mem is opt-in

Every other component installs unattended. claude-mem pulls in the Bun runtime,
runs a background worker daemon, and needs a Claude Code restart before its
tools appear -- three surprises for one double-click, so it moved behind a flag:

```powershell
.\INSTALL-AIO.ps1 -WithClaudeMem
```

## What gets installed

- **Provider skills** — 164 skills per AI (Claude, Codex, Grok, Kimi, Hermes), all generated from one canonical tree.
- **Native plugins** — Superpowers and Ponytail use each provider's official/native plugin lifecycle; Claude-only `claude-mem` installs Bun automatically when needed.
- **MCP servers** — context7, official GitHub, and Headroom are the verified always-on core. Hermes isolates the official Studio MCP in `roblox` and houseCARL in `skyrim`; the remaining browser/editor/game profiles stay off outside matching projects, and credentialed servers stay off until their key exists.
- **houseCARL** MCP + MO2 instance or Vortex shim setup
- **Spooky's AutoMod Toolkit**
- **codebase-memory-mcp** — installed but enabled only by `code-intel`; `.cbmignore` + `TOOLS/Setup-CodebaseMemory-Index.ps1` keep the graph on source, not asset trees
- **Headroom** (context compression, registered as an MCP server — see [Headroom + Grok](#headroom--grok))
- **Superpowers** + **Ponytail** plugins/skills
- **CodeBurn** (optional, via npm/npx)
- Grok MCP wiring + portable tool discovery

### Skyrim Forge

**Skyrim Forge 6.0.0 is developed in this repository**, at `BUNDLED-TOOLS/skyrim-forge`. It is source, not a downloaded payload, so both release variants carry it in full and there is no separately released archive that can drift out of step with the installer that reads it -- which is exactly how v7.8.0 shipped an installer calling a contract field Forge never emitted. The AIO installs or repairs it into ONE versionless install root, migrating any version-stamped install onto it and preserving `Workspaces` and the virtualenv, refreshes the five provider skills/descriptors, sets `SKYRIM_FORGE_ROOT`, and proves the result runs with `forge doctor` before the final success banner. Its 52-tool MCP is no longer global: `game-skyrim` activates it only for matching Claude/Grok projects; Codex/Kimi/Hermes use the same installed CLI through the skill. Choose where it lands with `-ForgeRoot`; the default is `%LOCALAPPDATA%\Skyrim-Tools\Skyrim-Forge`.

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
_CANONICAL-SKILLS/              maintainer master skills
INSTALL-AIO.ps1 / .bat          master installer
START-HERE.txt                     short human guide
```

## Docs

- [START-HERE.txt](START-HERE.txt)
- [AIO-GUIDE.md](AIO-GUIDE.md)
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

If a tool is missing, the AI should recommend `INSTALL-AIO.ps1`, `Ensure-Tools.ps1`, or `Update-From-GitHub.ps1` — not invent paths or fake MCP results.

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

Release notes live in [`CHANGELOG.md`](CHANGELOG.md), and every release has a
dated write-up in [`docs/history/`](docs/history/). The **Version** section near
the bottom of this file carries the current line, one paragraph each.

This section used to be a second changelog. It went stale at v8.0.4 while the
pack shipped through 8.6.x, so it stood over a thirty-release-old list telling
readers "recent releases first". One changelog, kept current, beats two.

## Gates (new in v6)

```powershell
python TOOLS\audit_skills.py <skills-dir>
powershell -NoProfile -ExecutionPolicy Bypass -File .\TESTS\Test-Pack.ps1
python TOOLS\install_live_skills.py _CANONICAL-SKILLS --check
```

v5.2.5's registry had *already warned* that BOM/encoding drift breaks
valid-looking files, and v5.2.5 shipped BOMs anyway. A warning in a document is
not a control; these are. `Test-Pack.ps1` checks every skill tree, parses
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

**v8.7.1** - 2026-08-29. Maintenance release: Headroom **0.37.0**, Context7 **4.0.4**, and CodeBurn **0.9.23** are pinned consistently across online and offline installs. A true empty-home run fixed Codex failing before `.codex` existed and removed a retired claude-mem marketplace that fresh settings were adding and cleanup was removing on every run. Headroom now prefers an isolated `uv` tool install, including MCP dependencies and locked-process handling, so a successful pip install cannot leave an older executable active on PATH. MCP handshake proofs resolve a real Python interpreter even when Windows exposes no `python` alias. GitHub MCP guidance now matches the official binary's built-in browser OAuth: a PAT is optional, not required. No new always-on schemas were added.

**v8.7.0** - 2026-08-27. The desktop, and a router worth 38,900 tokens a turn. New **`windows` profile** (windows-mcp): click, type, shortcuts, PowerShell, registry and filesystem over UI Automation -- the one surface Playwright and chrome-devtools cannot reach -- measured at **20 tools, 22,088 bytes, ~5,522 tokens/turn**, off by default with **no detect markers at all**, because no file on disk is evidence that an operator wants an agent clicking their mouse. Measuring it exposed that the capability sweep would have *driven* that desktop: its guard was a blocklist of REST verbs, and the one call that did land was safe only because upstream happened to order an enum `read` before `write`. **super-mcp-router** measured at 11 tools / 11,386 bytes / **~2,846 tokens per turn, fixed** -- against houseCARL's 41,768 on every turn -- and proven end to end against this pack's own houseCARL, though deliberately not wired yet. Plus a UTF-8 BOM the schema-cost tool had been sending on its first frame for seven releases.

**v8.6.13** - 2026-08-27. Detection could not see a workspace of projects. 8.6.12 taught the skills and installer to say "installed but not enabled here, run this" -- then pointed at a real Skyrim workspace of **45 mod directories, 327 `.esp` and 5,877 `.psc` files**, `Set-McpProfile -Detect` answered *"no profile markers found"*, because it scanned only the root and not one marker sits there. Root-only was deliberate and its reasons were sound (recursive scans are slow and match vendored dependencies), but it missed the shape people work in. Now root **plus immediate subdirectories, depth 1, never recursive** -- 0.6 s on that tree -- bounded at 250 children with `node_modules`, `vendor`, `dist`, `.venv` and friends skipped by name.

**v8.6.12** - 2026-08-27. The Full-Offline archive was shipping last month's tools. Three of seven payloads in `BUNDLED-TOOLS/offline/` were stale -- headroom **0.35.0**, github-mcp-server **1.10.1**, an August codebase-memory build -- found by *running* the installer, which pip-installed 0.35.0 seconds after the updater fetched 0.36.5: the updater writes to `cache/`, the installer reads `offline/`, and only `-UpdateCatalogOffline` bridges them. All refreshed and `OFFLINE-MANIFEST.json` regenerated from the bytes on disk. **Seven pins bumped**, including github-mcp-server **1.11.0** and context7 **4.0.3** on all five providers -- context7 re-measured rather than renumbered. And the doctor now reports **hooks that steer agents at unregistered MCP servers**: codebase-memory-mcp's own SessionStart hook was injecting 695 bytes of "ALWAYS use codebase-memory-mcp tools FIRST" on every startup, resume, clear and compact, while codebase-memory was registered on no provider at all. Reported, never rewritten. And **a marketplace outlived its tool and spread**: `claude-mem` was uninstalled weeks ago, yet `thedotmack` was still registered in Claude, still cloned at 140 MB, still present as four orphaned 140 MB temp clones, and had synced into Grok -- which reported `thedotmack (0 plugins) [error] Git sync failed` for something the user never registered, because **Grok inherits Claude's marketplace list**. New `RETIRED-PLUGINS.json` plus cleanup across all three registration shapes; **286 MB freed**, and Grok re-synced to six legitimate marketplaces with claude-mem gone. `Set-McpProfile -List` also stopped printing "enabled" and "ready to enable" identically. And the **catalog turned out to be decorative** for the one server every provider runs: bumping `context7` to 4.0.3 left all five still pinned to 4.0.2, because `Add-Reasoning-MCPs.ps1` carried its own hardcoded copy of the version and never read `CATALOG.json`. Now resolved from the catalog; all five verified at 4.0.3. Finally, **twelve files were shipping unverified**: `git ls-files` octal-quotes non-ASCII paths, so eleven files with em dashes or emoji in their names never matched the filesystem walk and silently left `MANIFEST.json` -- which `verify_manifest.py` could not detect, because it only checks that *recorded* files exist. 5,428 -> **5,440** entries, zero uncovered. And the worst one, found by checking whether this release's own bump had landed: **running the installer with your AI apps open failed the whole install.** Four live `github-mcp-server` MCP processes held the binary, robocopy returned exit 8, and the throw aborted everything -- `INSTALL FAILED` over one locked file, which is what happens whenever anyone runs `START-HERE.bat` without closing their apps. The generic extract branch now stops the owning process, and skips just that component if it still will not release. The same command that had failed then completed, updating github-mcp-server to 1.11.0.

**v8.6.11** - 2026-08-27. rtk is a git tool. Every number this pack had shipped for it was a `git` command; measured off git at 0.46.0 it aggregates **7.4%** (excluding rows that truncate rather than compress) against **85.2%** on git. `rtk read` is byte-identical to `cat`, `rtk json` returns 144 bytes from 1.1 MB by printing *one* array element, and **`rtk find` returns EMPTY stdout** for `-name` patterns -- an agent reads "no files match" when 76 match. Two claims corrected: the pack said rtk keeps "no archive and no retrieval", but `rtk test` writes a **complete** tee log and prints its path. The hook now stays off on evidence -- probing `rtk hook claude` shows `-g` rewrites `find` (broken), `cat` (0.0%) and `grep` (truncating) while leaving `npm test`, `curl` and `python x.py` alone, automating the worst categories and skipping the best. Also: the **byte-order marks are gone** from `CATALOG.json` and `OFFLINE-MANIFEST.json` -- Core regenerates that manifest BOM-less, so the two archives shipped one logical file in two encodings.

**v8.6.10** - 2026-08-27. Pinning the corpus was only half of it. v8.6.8 pinned the rtk savings to tag ranges so the corpus could not drift; rtk then shipped **0.46.0** and `git log --stat -20` went from **95% to 0%** -- `--stat` now passes straight through, while plain `git log` still compresses ~86% and the other three rows reproduced **to the byte**. Every number now carries the tool version it was measured on, bound by contract to the version CATALOG declares, so bumping the version without re-measuring fails the build. That contract took two attempts: the first matched "any rtk X.Y.Z in the section" and passed while the stamp was deleted, because the paragraph explaining the regression still named both versions. Also: **six reverse-engineering tools evaluated, none bundled** -- four are desktop GUIs, and GhidraMCP, the only one that puts an agent in the loop, has not been touched since **2025-06-23** while Ghidra shipped through 12.1.3. And **lean-ctx measured**: best supply chain seen here (sigstore-signed checksums), but its headline 98.1% is `-m map`, a *symbol index* that duplicates `codebase-memory`, it saved **0.0%** on the same shell corpus as rtk and OMNI, and it carries **78 MCP tools**.

**v8.6.9** - 2026-08-27. The preset was fine; the model settings were not. LM Studio keeps sampling presets and per-model **load** settings in different places, and the model's own settings are what it applies. Measured for one 27B family: four of five saved configs could not load as written -- `q8_0` K/V throughout, one with **three** parallel sessions, one at **75% offload** -- and the one actually in use asked for **18.32 GiB on a card with ~14.5**, spilling to system RAM over PCIe every session. New `Optimize-LMStudioModelConfig.ps1` reads each GGUF and your card, computes the largest context that genuinely fits at `q4_0`, and writes it with one session and full offload; dry-run by default, backs up first. `Get-KvBudget.ps1` stopped guessing its reserve: measured with **no model loaded**, 6.6 GB of a 16 GB card was already held by desktop apps, so the old `total - 1.5` budget said a 10.26 GB model fit when 9.2 GB was free. And the quant question is now arithmetic: at 65,536 with `q4_0`, only `UD-IQ2_S` and `UD-IQ3_XXS` reach the window, while `UD-Q3_K_XL` reaches **3,710** -- its 14.26 GB of weights do fit on a 16 GB card, leaving 0.2 GB, which is exactly why a weights-only fit check blesses it.

**v8.6.8** - 2026-08-27. The rtk advice was stale, and the README was 61% changelog. Re-measured on native Windows at rtk 0.45.0: `rtk init -g` registers a **real PreToolUse hook** (`rtk hook claude`, JSON over stdin) that rewrites commands transparently and writes a 990-byte `RTK.md` -- so the catalog's blanket "do not install the Claude/Cursor/Gemini hooks on Windows" was wrong. The distinction is `-g`, not the provider: plain `rtk init` prints `No hook installed` and writes **5,140 bytes** into `CLAUDE.md`, ~1,400 tokens every turn forever, to *ask* for savings. Its rewrites are conservative -- `curl`, `npm test` and `gh --json` untouched, `rtk read` byte-identical to `cat`. The README's own rtk table was still advertising the decayed 97% from `git diff HEAD~3` that v8.6.6 had already pinned in the catalog; both now show the honest 25%-95% spread. New **`-WithRtk`** installs it behind one flag and then *prints* the hook command rather than running it, because registering it patches your `settings.json` and rewrites every shell command -- and rtk discards what it filters, with no archive and no retrieval. The README also carried **two** changelogs, one stale at v8.0.4 while the pack shipped through 8.6.x; 1,196 lines became 635 with nothing lost, since `CHANGELOG.md` holds all 86 entries and `docs/history/` 92 write-ups.

**v8.6.7** - 2026-08-27. The skill Codex already had. v8.6.6 adopted `skill-creator` into the canonical tree so all five providers would carry it -- but Codex ships a `skill-creator` of its own in `<CodexHome>\skills\.system`, so on Codex alone the pack's copy became a second index entry for a capability that was already there. The final doctor caught it on the first real install (`Codex indexes 1 skill(s) twice`), and the cost was measurable: **184 entries at 48 visible description chars with the duplicate against 183 at 50 without** -- one collision quietly taxing every other skill's description. Fixed by **discovery rather than by name**: `.system` also holds `imagegen`, `openai-docs`, `plugin-creator`, `review-agent` and `skill-installer`, so hardcoding the one known collision would have caught it and nothing else. The removal reuses the same verified remover as the plugin dedupe -- md5 against canonical, backup first, user-modified copies refused -- and the doctor now accounts plugin-owned and Codex-owned separately, because a reader who cannot tell them apart cannot act on either. `skill-creator` still installs to Claude, Grok, Kimi and Hermes, which ship no equivalent.

**v8.6.6** - 2026-08-26. The index was full of the pack's own skills. Codex was rendering **211 entries at 32 visible description characters**, 18 of them indexed twice -- and the plugin contributing 26 of them was not an Anthropic skill set at all: its manifest says `"creatorType": "user"`, so it was **this pack's own skills**, uploaded to Cowork and served back as *stale* copies that canonical had since moved past. Five more duplicated Codex's native `documents`/`pdf`/`spreadsheets`/`presentations` plugins. Disabled, with the `obsidian` plugin whose five skills this pack already carries byte-identical: **180 entries at 52 chars**, descriptions 63% wider on every skill for zero capability. The installed-state doctor went **FAIL (29 errors) to PASS** -- 29 skills had drifted from canonical across Codex, Grok, Kimi and Hermes -- and 1.29 GB of claude-mem leftovers went with them (`~/.claude/plugins` 1.4 GB -> 128 MB) months after the tool itself was uninstalled. Four skills adopted from Anthropic's Apache-2.0 marketplace into `_CANONICAL-SKILLS`, which installs to **all five providers** rather than one: `skill-creator` plus the `build-mcp-server`/`build-mcpb`/`build-mcp-app` set; eleven others reviewed and rejected on the record. RTK and OMNI measured head-to-head at last: rtk 85.2% against OMNI's 71.2%, of which **17.4 points is truncation, not compression** -- above a 65,536-byte cap OMNI drops content and says `full output not archived`, which its byte-for-byte guarantee does not qualify; its real recoverable saving was 6.4%, matching its own published 8.8% on git. And our own rtk claim of 97% was quoting `git diff HEAD~3` -- a MOVING reference that measures 82.5% today -- now pinned to tag ranges with the honest 25%-95% spread.

**v8.6.5** - 2026-08-26. The setting nobody looks at. v8.6.4 documented KV-cache spill correctly and then prescribed the wrong fix: on the machine it was measured against, cache quantisation was **already on at `q8_0`**. The real culprit was `llm.load.numParallelSessions: 2` -- a multiplier on the entire cache, with nothing in the name to suggest it costs VRAM. At 65,536 context on a 16 GB card holding 10.26 GB of weights, 2 sessions + q8_0 wants 16.3 GB against 4.23 available, 1 session + q8_0 still wants 8.1, and only **1 session + q4_0** fits at 4.1 GB (max context 68,205). New `Get-KvBudget.ps1` reads the GGUF header and your GPU and prints max context at each cache precision, with `-Sessions` so the multiplier is visible; it flags `key_length` 256 as double the common 128, which doubles a model's cache and appears on no model card. New `Hermes 16GB` preset is the first with a populated `load` block -- 65,536 context, q4_0 K/V, flash attention, full offload, one session -- with every key read out of LM Studio's own config files, because an invented config key is silently ignored rather than rejected.

**v8.6.4** - 2026-08-26. Three bytes, and a skills index that went blank. `START-HERE.bat` shipped with a UTF-8 BOM in 8.6.2 and 8.6.3, so every user opened the launcher to a `'@echo' is not recognized` error -- the install still finished, which is why it survived two releases. Introduced here, not inherited: v8.6.1 starts `40 65 63`, v8.6.2 starts `EF BB BF`. Codex user skills moved to the supported `~/.agents/skills` root; with both it and the deprecated `$CODEX_HOME/skills` live, the index measured **314 entries, 125 duplicated names and zero visible description chars** -- every skill reduced to a bare name -- against 211/0/32 after cleanup. The doctor could not even report that: its pattern required a non-empty description, so it fell back to estimating 212 when the truth was 314. The four AIO preambles are synced on substance (web wording deliberately left different, since web surfaces filter server-side), `Web Light` is finally lighter at 1,910 bytes against Web's 2,257, and two variants stopped recommending an installer that does not exist in v8. LM Studio's intermittent slowness is documented as KV-cache spill with the arithmetic: `key_length` 256 gives 0.254 MB/token at fp16, so 16 GB hits the cliff near 20k tokens.

**v8.6.3** - 2026-08-26. One keypress, and five tools that did not make it. Opening the bundled Forge folder and double-clicking `START-HERE.bat` landed on an eleven-item menu whose correct answer -- for anyone who had not used Forge before -- was always `1`; the bundle installer never showed that menu, so the only person who ever saw it was the one least able to answer it. It now installs and wires every detected AI app with no arguments, menu one keypress away, and **no files moved**: three of those scripts are executed by exact filename from `Install-SkyrimForge.ps1`, one as its integrity marker. New `BUNDLED-TOOLS/lm-studio/` ships three sampling presets and a copier the installer deliberately never calls -- `settings.json` stays out because it carries a username-bearing path and two Hugging Face credential fields, though reading it found `defaultContextLength` at 55,000, under the 64,000 floor Hermes hard-refuses. Six tool candidates evaluated in `docs/TOOL-EVALUATIONS.md`: **OMNI** taken as `cli-optional` at the number its own README reports (5.1% over 9,478 executions, not the 97.2% on its landing page); **lowfat** rejected because v0.8.0 ships no Windows binary and hooks through a POSIX shell eval -- the same degradation already documented for RTK; **Understand-Anything** rejected as a duplicate of `codebase-memory`; **Agent-Reach** rejected for installing via an agent-executed remote script; **Lightpanda** and **llmtrim** documented but not bundled.

**v8.6.2** - 2026-08-26. Count it, don't infer it. The doctor reported the Codex skills index as 319 entries at "~16 visible description chars" while Codex was actually rendering 197 at 42 -- it walked `plugins\cache`, but Codex indexes only the plugins `config.toml` ENABLES, and the cache also holds marketplaces that were never enabled, backups of upgraded plugins, and payload meant for other tools. It now asks Codex directly (`codex debug prompt-input`) and measures both figures. Two silent bugs came out with it: `codex plugin list --json` fails wholesale when *any* marketplace snapshot is broken, which made the installer skip its dedupe and leave 20 skills in the index twice (197 -> 177 entries, 42 -> 54 chars once repaired); and a single-provider install erased the other providers' native-plugin records, turning a correct machine into 34 doctor errors.

**v8.6.1** - 2026-08-26. Documentation only. v8.6.0 stated the rule and never the setting: Hermes refuses a context window under 64,000 tokens, and both docs said exactly that, leaving a reader to type 64,000 (passes a strict `<`, but is not a value LM Studio offers) or 32,768 (the nearest power of two, and the one commonly saved already). Both now say **65,536**, with the verification step that is usually skipped -- confirm the saved default by loading with no explicit context flag, because a cold start is what Hermes' preload reads. Also a new SillyTavern reference: it demands an API key the local server ignores, and a reasoning model returns an empty message when Response Length is small because thinking tokens come out of the same budget.

**v8.6.0** - 2026-08-25. Enabled is not installed. Two cloned Hermes profiles had been running no plugins at all -- `profile create` copies the enabled list and never the payload, so Ponytail and Superpowers had never loaded in `roblox` or `skyrim`, silently. All four of this pack's own Hermes gate hooks were dead for the same reason, a rename the consent allowlist never followed. The migration now links each profile to the shared plugin root and converges the enabled list additively; the doctor reports both failures. Also: a documented free path to the web (Hermes' own keyless search ring, not a billed provider plugin), a new `local-model-ops` skill for running LM Studio as a Hermes provider -- 41 tok/s measured, and a 64,000-token context floor that blocks the obvious setup -- and RTK as an optional CLI that cut `git diff HEAD~3` from 2,010,426 to 71,268 bytes here.

Earlier releases: [`CHANGELOG.md`](CHANGELOG.md) carries all 86, and
[`docs/history/`](docs/history/) has the long-form write-up for each.

## License

Pack documentation and original installer scripts are provided as-is for
personal and community use. Third-party tools inside `BUNDLED-TOOLS` keep their
own licenses (see [BUNDLED-TOOLS/THIRD-PARTY-NOTICES.md](BUNDLED-TOOLS/THIRD-PARTY-NOTICES.md)).
