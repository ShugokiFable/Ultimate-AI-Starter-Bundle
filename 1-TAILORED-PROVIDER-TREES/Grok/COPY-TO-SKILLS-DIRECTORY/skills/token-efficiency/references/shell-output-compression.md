# Compressing command output before it reaches context

Re-reading is the biggest waste; the second biggest is a single command that
dumps a megabyte into the window. `git diff` across a few commits on a large
repo is routinely 2 MB — around half a million tokens for one tool call.

**RTK** (`rtk`, Apache-2.0, single Rust binary) sits in front of common dev
commands and filters, groups, deduplicates and truncates their output. It is a
CLI, so it costs **zero standing tokens** — the rule from `ai-tooling-stack`
applies: a CLI is free until you run it, an MCP server bills on every turn.

## Measured, on this pack's own repository

| Command | Raw | Through rtk | Saved |
|---|---|---|---|
| `git diff HEAD~3` | 2,010,426 B | 71,268 B | **97%** |
| `git log` | 158,877 B | 2,460 B | **99%** |
| `git status` | 321 B | 72 B | 78% |

One `git diff` accounted for ~496K tokens of savings by rtk's own accounting.
The small commands are noise; the large ones are the entire case.

## What it does and does not rewrite

Verify with `rtk rewrite '<command>'` — empty output means passthrough.

- **Rewritten:** `git *`, `ls`, `cat` (to `rtk read`), `rg`, `curl`,
  `python -m pytest`, `cargo build`, and other build/test runners.
- **Passthrough:** `sha256sum`, `certutil`, `gh`, `npm test`, and
  `git -C <path> ...` — rtk declines the repo-redirect form rather than
  guessing.
- `rtk read` was verified faithful at file scale: a 741-line file came back
  as 741 lines.

## Install it scoped, not globally

The failure mode is a lossy layer between a tool and the agent, silently
turning a wrong answer into a smaller one. Two rules:

**Exclude commands whose exact bytes matter.** `~/AppData/Roaming/rtk/config.toml`
on Windows, `~/.config/rtk/config.toml` elsewhere:

```toml
[hooks]
exclude_commands = ["curl"]
```

`curl` earns its exclusion: its output is usually an API response that gets
parsed or hash-checked, where a filtered body is a wrong answer.

**Do not install the transparent hook everywhere.** Coverage is uneven and the
platform matters more than the vendor list suggests:

| Agent | Integration | Native Windows |
|---|---|---|
| Hermes | Python plugin mutating the terminal command | works — no shell hook involved |
| Claude Code / Cursor / Gemini | `PreToolUse` shell hook | **degrades to prompt injection**; real hooks need WSL |
| Codex / Kimi | `AGENTS.md` instructions | prompt-level by design |
| Grok | none | unsupported |

Prompt-level "modes" cost context on every session to *ask* for savings, and
the agent may ignore them. On Windows, install the Hermes plugin — the one
integration that actually rewrites — and otherwise keep `rtk` on PATH so
skills can call it explicitly where verbosity is the known problem.

Note also that Claude Code's built-in `Read`, `Grep` and `Glob` never pass
through the Bash hook, so file-level savings do not apply there even under
WSL. The win is concentrated in `git`, test runners and builds.

## Verifying it is actually running

An agent cannot tell you. It reports the command it *asked* for; the rewrite
happens after that. Use out-of-band evidence:

```
rtk gain
```

A command listed there with real execution time that you never typed yourself
came from the hook. Telemetry is a separate, opt-in setting
(`[telemetry] enabled = false` by default) — `rtk telemetry status` should
read `consent: never asked`.
