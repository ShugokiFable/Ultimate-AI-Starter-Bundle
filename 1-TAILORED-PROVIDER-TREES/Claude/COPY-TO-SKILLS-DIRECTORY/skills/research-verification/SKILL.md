---
name: research-verification
description: Use when answering niche, changing, disputed, technical, product, policy, pricing, compatibility, or current-information questions.
---

# Research Verification

## Core rule
Prefer a current **primary source** for factual mechanics, then use independent sources to **corroborate** where stakes or ambiguity justify it.

## Workflow
- Identify which claims are time-sensitive and set a **freshness** requirement.
- Search broadly enough to discover terminology, then open the highest-authority source.
- Compare publication date with the date the event/change actually occurred.
- Distinguish docs, source code, release notes, issue reports, community anecdotes, and marketing claims.
- For software behavior, source/tests can outweigh stale prose documentation.
- Resolve conflicts explicitly instead of silently choosing one result.

Quote sparingly; synthesize the evidence. Never invent a citation for a claim the source does not support.

## Which tool, in which order

Weaker agents fail this by defaulting to recall. Work down until the question is settled, and stop there:

1. **Run it.** Actual runtime output, a test, a repro. Beats every document.
2. **Read the local source**, including the installed package's own code and tests.
3. **Ask the installed tool.** `--help`, `--version`, `<cmd> list`. It is the truth for the version actually on this machine, which is the version that matters.
4. **Official upstream** source, release notes, changelog, issue tracker.
5. **Context7** for current library/framework documentation.
6. **Web search / Firecrawl** for discovery, when you do not yet know the terminology or where the answer lives.
7. **Model memory** -- last, and labelled as such.

Order varies by question: source and tests outrank stale prose docs. Whatever you use, record which one settled it.

If no research capability is available at all, say which assumption is unresolved instead of presenting recall as a check.

## Do not browse reflexively

"Stop assuming" is not "search the web for everything". That spends tokens, latency and rate limits to re-learn something stable.

Research in proportion to **uncertainty × consequence × freshness**:

- high uncertainty + material consequence + information that changes → research
- stable fact, or an answer that cannot change the implementation → continue
- already answered by local source, runtime output or `--help` → do not open a browser

When the authoritative source is unavailable, state the limitation and reduce confidence rather than laundering a secondary claim into certainty.
