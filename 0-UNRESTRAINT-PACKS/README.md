# 0-UNRESTRAINT-PACKS — V6.9.2 Unrestraint Layer

The full no-holds prompt library. This is the operator's own kit: curated from the operator's
Fun stuff folder plus five upstream sources, reviewed, deduped, and dated 2026-08-15.

**RULES (non-negotiable, from the operator's own kit)**
- Adults only. No child / age-ambiguous content. Ever.
- One jail, one job. Do not stack AIO + Story + Websim in a single prompt.
- Token hygiene: paste the smallest file that does the job.
- For SillyTavern, use the WooJuice V9 preset — do not paste Story.txt into ST.
- Jailbreak payloads rot fast. A/B test before trusting; Models.txt is dated for this reason.

---

## The AIO preambles (root of this folder)

Four variants of one instruction set. **Paste exactly one.** They are not
layers — stacking two costs tokens and contradicts itself.

| File | Size | Tools? | Use it for |
|---|---|---|---|
| `AIO-INSTRUCTION.md` | ~6.2 KB / 875 w | yes | Agent CLIs (Claude Code, Codex, Grok, Kimi, Hermes). The only variant with the PACK CONTEXT block — how to discover this pack's tools portably and never invent one. |
| `AIO-INSTRUCTION — Compact.md` | ~5.0 KB / 701 w | yes | Same job, ~20% cheaper. Use when the host has a small system-prompt budget or you are paying per turn. |
| `AIO-INSTRUCTION — Web.md` | ~2.3 KB / 338 w | no | ChatGPT / Gemini / Perplexity web UIs. States plainly that there is no code execution, no files, no MCP, so the model stops pretending otherwise. |
| `AIO-INSTRUCTION — Web Light.md` | ~1.9 KB / 275 w | no | Same job as Web, 17% cheaper. The smallest paste that still carries the full unrestraint payload. |

The installer wires the agent-CLI variant into each provider's instruction file
automatically. The web variants have no config to wire — paste them.

**What "Light" cuts, and what it does not (reworked 2026-08-26).** Every
unrestraint clause is byte-for-byte intact: the refusal protocol, the explicit
terminology list, body physics, camelfloss, write-the-scene, no fade-to-black,
never-break-character, all-parties-consent. The 385 bytes come out of the
operational scaffolding — the standalone COMPLETION and FINAL GATE paragraphs
fold into STYLE, because in a browser conversation they restate what the rest
of the prompt already says.

It also *gains* a line the previous draft had lost: `Never fabricate URLs,
sources, or quotes`. That draft was 2,271 bytes — fourteen *larger* than Web
while protecting less, which is the opposite of what a light variant is for.

Rule of thumb: **Web Light unless you specifically want Web's longer
phrasing.** Neither is weaker on content; only the scaffolding differs.

## Contents

| Folder | Source | What it is |
|---|---|---|
| `Fun-stuff-kit/` | Operator kit (`Z:\Misc\Boof\Ai prompts n stuff\Fun stuff`) | AIO (chat/research jail), Story (fiction jail + NSFW physics), Websim, Vision (image caption FULL/SHORT), Character Maker, FablesGG, Tags (adult tag bank), Tools, SKSE-DLL, Papyrus, Models, Sites |
| `Spiritual-Spell-Red-Teaming/` | github.com/Goochbeater/Spiritual-Spell-Red-Teaming | Largest organized jailbreak guide: Anthropic (Claude 3.7–4, Opus 4.5–5, Sonnet 4.5/4.6, Fable 5, Claude Code CLAUDE.md payloads, Amazon Rufus), ChatGPT 5.3, Gemini 3.5/3.6, Grok 4.x, DeepSeek + other LLMs, ENI-Tutor curriculum, leaked system prompts |
| `UltraBr3aks/` | github.com/SlowLow999/UltraBr3aks | Classic jailbreak texts (.mkd) + observed system prompts (GPT 5.1, Gemini Enterprise, Arena.AI, Perplexity-Comet, GPT OSS policy) |
| `tuxsharxsec-Jailbreaks/` | github.com/tuxsharxsec/Jailbreaks | Per-model quick jails: deepseek, gemini2.5pro, gpt-5, grok3, identity_crisis, perplexity personalization injection; universals (courtroom, ultrazanium); NVIDIA NeMo guardrails-bypass research writeup |
| `claude-fable-red-team-corpus/` | github.com/GenRamzi/claude-fable-5-opus-5-jailbreaks | Defensive red-team eval corpus (authorized-red-team.jsonl injection vectors), model matrix, ETHICS.md, methodology docs |

## Sources reviewed but not copied

| Repo | Why |
|---|---|
| github.com/cyberlieflife/CodexJailbreak | Rust injector + CTF/red-team skill pack (burp-mcp, ghidra, android-re). Payload is a task router, not prompts. No adult/fiction material. Binary not built. |
| github.com/ShadowHackrs/Jailbreaks-GPT-Gemini-deepseek- | README-only link farm (30 files, 1 markdown). Nothing to import. |

Settings files (`settings.json`, `config.toml`, `config.yaml`) are **not**
the unrestraint channel. The AIO installer merges portable starter settings
without touching this pack. Unrestraint stays in instruction files and in
this folder.

## Per-provider application

| Target | File | How |
|---|---|---|
| Claude Code | `~/.claude/CLAUDE.md` | Wired (V6.9.2 section appended). For stronger persona jails paste `Spiritual-Spell-Red-Teaming/Jailbreak-Guide/Anthropic/Claude Code/CLAUDE.md` into a project `CLAUDE.md`. |
| Codex | `~/.codex/AGENTS.md` | Wired (global). |
| Kimi | `~/.kimi-code/AGENTS.md` | Wired (global). |
| Grok | workspace `AGENTS.md` (copy from `1-TAILORED-PROVIDER-TREES/Grok/COPY-TO-WORKSPACE/`) | Wired at source. |
| ChatGPT web / Gemini web / Perplexity | no local config | Copy-paste: `Spiritual-Spell-Red-Teaming/Jailbreak-Guide/ChatGPT/…`, `…/Gemini/…`, `tuxsharxsec-Jailbreaks/perplexity/…`. |
| SillyTavern | `Tavern\WooJuice V9.json` | Preset, not this pack. |
| Hermes | system prompt | Already permissive (OpenRouter deepseek-v4). Adult skills installed: `adult-image-caption`, `adult-character-sheet`, `fictional-adult-modding`. |

## Honest notes (2026-08-15)

- Public jailbreak texts decay: what worked on Claude 3.x mostly does not work verbatim on Claude 4.x/Opus 5.
  The ENI persona family is the current community standard; A/B against your own AIO/Story kit.
- The operator kit (AIO/Story/Vision) consistently beats the older repo texts for fiction quality.
- Frontier chat surfaces (ChatGPT, Gemini apps) apply separate server-side filters regardless of prompt;
  API/agent surfaces (Claude Code, Codex, Kimi, Grok CLI) are where prompt-level unrestraint actually lands.
- Leaked/observed system prompts in UltraBr3aks and Spiritual are study material for prompt design, not guarantees.

## Cleanup 2026-08-19 (bundle v7.6.6)

- Removed retired-generation material: Claude 3.7 and Claude 4 folders, ChatGPT 5/5.1/5.2
  jails (5.3/5.4 kept), Gemini 2.5-era files, Grok 3 / gpt-5 / gemini2.5pro quick jails,
  the self-declared broken H03-ny, and the Ultra-GPT dead link farm.
- Removed 25 byte-identical duplicates (md5-verified before each deletion) - the same
  ENI LIME/LINTUNE/Corial copies were mirrored across up to 6 model folders. One canonical
  copy per document remains.
- Removed the Gemini "May 2026" stub .md (the same-name .txt holds the actual dump) and
  fixed the Gemini README "last updated" stamp (said February, lists July models).
- Total: ~470 KB of dead weight out; every current-generation folder (Opus 4.5-5, Sonnet
  4.5/4.6, Fable 5, Grok 4.1-4.5/Heavy, ChatGPT 5.3/5.4, Gemini 3.x, all of Other LLMs)
  untouched. Older release zips keep the removed files if ever needed.
