# Third-party skills bundled here

Most skills in `_CANONICAL-SKILLS/` are written for this pack. The ones below
came from other projects and are redistributed under their own licences. They
are listed so provenance is visible without opening every `SKILL.md`.

This file covers **skills**. For the redistributed tools and binaries, see
[`BUNDLED-TOOLS/THIRD-PARTY-NOTICES.md`](../BUNDLED-TOOLS/THIRD-PARTY-NOTICES.md).

The pack installs these to **every detected provider** (Claude, Codex, Grok,
Kimi, Hermes). That is the point of carrying them here rather than leaving them
as a plugin: a plugin serves one provider, a canonical skill serves all five.

## Anthropic — `anthropics/claude-plugins-official`, Apache-2.0

| skill | upstream plugin | note |
|---|---|---|
| `skill-creator` | `skill-creator` | Authoring, evaluating and benchmarking skills. Carries its own `LICENSE.txt`. Its `agents/` helpers use Claude Code subagents and do nothing on other providers; the authoring guidance and the Python scripts are portable. |
| `build-mcp-server` | `mcp-server-dev` | Entry point for MCP server development; hands off to the two below. |
| `build-mcpb` | `mcp-server-dev` | Packaging an MCP server as a `.mcpb` bundle. |
| `build-mcp-app` | `mcp-server-dev` | Interactive UI widgets over MCP. |

The three `mcp-server-dev` skills are kept as a **set**: `build-mcp-server`
explicitly hands off to the other two, so taking one alone leaves a dangling
reference.

## img2threejs — `img2threejs/img2threejs`, Apache-2.0

`img2threejs` is vendored from tag **v1.5.1**, commit
`dede5909be4e494b228c801a55dda47439143932`. CI metadata, sponsor assets and the
upstream provider-specific `CLAUDE.md` are excluded; the skill, stdlib Python
forge, documentation, fixtures and license are retained. UABS adds one Windows
Python/UTF-8 resolver and replaces upstream's provider symlink instructions with
canonical fanout.

## Impeccable — `pbakaus/impeccable`, Apache-2.0

`impeccable` is the `.agents/skills/impeccable` payload from the official
**skill-v4.1.2** `universal.zip` (17,906,506 bytes, SHA-256
`5ee960e62e308d423e5290c29277958115827813aad70cb91045f0481c22742c`). UABS
removes its provider-directory pin/self-update path and routes deterministic
scans through the separately pinned CLI. The included `LICENSE` is upstream's.

## skills CLI — `vercel-labs/skills`, MIT

No upstream source is vendored. The `skill-discovery` wrapper invokes the exact
published `skills@1.5.23` package on demand with telemetry disabled and exposes
only its read-only `find` command. Its output is discovery evidence, never an
installation decision.

## kepano — `kepano/obsidian-skills`

| skill |
|---|
| `defuddle` |
| `json-canvas` |
| `obsidian-bases` |
| `obsidian-cli` |
| `obsidian-markdown` |

These were absorbed earlier. The upstream `obsidian` plugin is therefore
**redundant on this machine** and is left disabled: it served the same five
skills to one provider while these serve all five providers.

## What was deliberately NOT taken

Reviewed from the same Apache-2.0 marketplace and rejected, so the decision is
not re-litigated every time someone browses it:

- **`hookify/writing-rules`** — teaches the rule syntax of `hookify`, a plugin
  this pack does not install. A skill describing an absent tool is index budget
  spent on nothing.
- **`claude-security`** — `disable-model-invocation: true`, and it orchestrates
  Claude Code agent panels, so it is inert on the other four providers. The pack
  already carries `security-boundaries`, `secret-hygiene` and
  `supply-chain-verification`.
- **`claude-md-management/claude-md-improver`** — would audit and rewrite the
  same `CLAUDE.md` this pack's own preamble wiring owns. Two writers, one file.
- **`plugin-dev/*`** (7 skills) — Claude Code plugin format: structure,
  settings, commands, agents. Correct for Claude, noise on the other four.
- **`frontend-design`** — prompt-only and now overlapped by Impeccable's
  cross-provider design router plus executable detector.
- **`session-report`, `receipts`, `project-artifact`,
  `playground`, `math-olympiad`, `example-plugin/*`, `cwc-makers/*`** — off
  mission for a provider-setup pack.

Every entry added here costs index budget on every provider, and on Codex that
budget is fixed and split across all entries — so the bar for adding one is
that it works on more than one provider and is not already covered.
