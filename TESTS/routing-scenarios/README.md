# Routing scenarios

Eight adversarial cases for **tool choice**, not tool availability. They exist
because "does SKILL.md contain the word Firecrawl" is document compliance, and
the thing that actually failed in the field was a routing decision.

| | scenario | what it separates |
|---|---|---|
| A | content only present after JS runs | escalating the tool class vs. tuning a weak fetch |
| B | a plain static page | the cheap primitive vs. bundle-first dogma |
| C | CI/PR state | structured API vs. scraping rendered HTML |
| D | flags of the installed CLI | asking the binary vs. recall or SEO pages |
| E | rename every caller | semantic navigation vs. grep claiming completeness |
| F | no vision, no browser | an honest gap vs. a fabricated check |
| G | `Unauthorized` from a good tool | reading the failure vs. abandoning the class |
| H | count ERROR lines in a log | grep vs. reaching for machinery |

**A and B are the pair.** Same request shape, opposite correct answers. A model
that gets both right has the judgement; one that gets only A right has learned
"always use the big tool", which is the other failure this release is about.

## Scoring

Scoring an agent is a judgement call. Record, per scenario:

```
capabilities available
first tool selected
fallback tools, in order
failed attempts before switching
ad-hoc implementation written?   yes / no
succeeded?                       yes / no
total tool calls
```

The question is **did it choose correctly earlier**, not whether it eventually
succeeded. One-shot efficiency is the entire point; a model that reaches the
answer on attempt nine has demonstrated the failure, not recovered from it.

## Fixture integrity

Scoring the fixture is not a judgement call, so `check_fixtures.py` proves each
one still contains what it claims -- A's content still absent from its markup,
B's still present in its. A benchmark whose defects have quietly been repaired
passes every provider and measures nothing. It is chained into the pack gate.
