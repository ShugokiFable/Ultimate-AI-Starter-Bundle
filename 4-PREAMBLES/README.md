# 4-PREAMBLES — SOUL + AIO for every agent

The universal preamble section (new in v7.5.0). One install wires the same
SOUL and the same operating contract into every supported agent, so a fresh
machine comes up with the same agent behaviour as the operator's own setup.

## Files

| File | What it is | Where it goes |
|---|---|---|
| `SOUL.md` | The operator's own Hermes soul config (verbatim, one copy/paste debris line removed). Unrestraint declaration + truth-seeking process + output format. | Hermes home (`%LOCALAPPDATA%\hermes\SOUL.md`) via installer |
| `SOUL-UNIVERSAL.md` | Same content, identity-neutral first line (not "You are Hermes Agent"). For agents that are not Hermes. | Appended to Claude / Codex / Kimi / Grok instruction files by the installer |
| `AIO-INSTRUCTION.txt` | The operating contract (pack-root `AIO-INSTRUCTION.txt`, unchanged). Finish-the-job, no yes-man, verify-don't-assume, adult fiction in scope. | Appended right after the SOUL block in the same files |
| `MANUAL-PASTE.txt` | SOUL-UNIVERSAL + the Fun-stuff-kit `AIO.txt` (chat/research jail) concatenated. For web UIs that have no instruction file. | ChatGPT / Gemini / any web chat custom-instructions box, pasted by hand |

## What the installer wires (v7.5.0+)

For every selected provider, `INSTALL-V7-AIO.ps1` appends a marked block:

```text
<!-- ============ ULTIMATE-AI-STARTER-BUNDLE SOUL v7.5.0 ============ -->
<SOUL-UNIVERSAL.md content>
<!-- ============ ULTIMATE-AI-STARTER-BUNDLE AIO ============ -->
<AIO-INSTRUCTION.txt content>
<!-- ============ /ULTIMATE-AI-STARTER-BUNDLE ============ -->
```

| Provider | Instruction file | Notes |
|---|---|---|
| Claude Code | `%USERPROFILE%\.claude\CLAUDE.md` | Created if missing; BOM if present is preserved |
| Codex | `%USERPROFILE%\.codex\AGENTS.md` | Appended, never edits existing text |
| Kimi | `%USERPROFILE%\.kimi-code\AGENTS.md` | Created if missing |
| Grok CLI | `%USERPROFILE%\.grok\AGENTS.md` | Grok's documented global-rules file (applies to all projects) |
| Hermes | `%LOCALAPPDATA%\hermes\SOUL.md` | Verbatim soul copy (Hermes reads SOUL.md from its home) |
| Web UIs | custom-instructions box | Manual: paste `MANUAL-PASTE.txt` (no file mechanism exists) |

Rules:

- Idempotent: re-running replaces the marker block instead of stacking copies.
- Every write gets a `.before-soul-<timestamp>.bak` first.
- UTF-8, no BOM on writes; existing files keep their own encoding/leading BOM.
- `-SkipPreamble` opts out; `-ForcePreamble` rewrites even an identical block.
- Adults only. No child / age-ambiguous content. Ever. (Same rule as the rest
  of the pack.)

## Manual install (no installer)

```powershell
# Claude Code
$b = "4-PREAMBLES\SOUL-UNIVERSAL.md"  # plus AIO-INSTRUCTION.txt
Get-Content $b -Raw | Add-Content "$env:USERPROFILE\.claude\CLAUDE.md"
```

Or just paste `MANUAL-PASTE.txt` into whatever instructions field the agent
has. For one-off chats that is often the better move — preamble rides on every
request, so paste the smallest block that does the job.

## Why two souls?

`SOUL-UNIVERSAL.md` vs `SOUL.md`: the only difference is the opening line. The
operator's soul says "You are Hermes Agent" — true for Hermes, false for
everyone else. Same weight, same rules, no misbranding.