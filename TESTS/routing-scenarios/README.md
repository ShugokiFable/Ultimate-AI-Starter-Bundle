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
| I | free daily limit reached, message mentions OAuth | a spent quota vs. a missing credential vs. a wrong tool |

**G and I are the other pair.** G is a real auth failure; I is a quota with
the word *oauth* in the message. Reading I as G discards a capability you still
have and writes a false fact into the docs -- which is precisely how v7.9.8's
catalog came to claim `interact` was keyless.

**A and B are the pair.** Same request shape, opposite correct answers. A model
that gets both right has the judgement; one that gets only A right has learned
"always use the big tool", which is the other failure this release is about.

## Scoring

Record per scenario, then score. Recording alone produces notes, and notes
cannot tell you whether a change improved anything.

```
available capabilities        what was actually in the tool list
first tool selected           the one decision that matters most
fallback tools, in order
failed attempts before switching
unnecessary escalations       heavier capability than the task needed
homemade duplicate written?   yes / no
succeeded?                    yes / no
total tool calls
added schema cost             tokens/turn of anything newly enabled
```

### The scorecard

```
  +5   correct capability chosen FIRST
  +2   correct capability chosen after one evidence-backed failure
   0   correct capability chosen after two
  -2   each further attempt in a class the evidence had already ruled out
  -3   unnecessary escalation (browser/MCP/index for a task a primitive answers)
  -5   homemade duplicate of an available capability
  -5   misread failure class (quota or credentials treated as "wrong tool")
  +2   finished with an honest, named limitation when nothing could complete it
  -5   claimed a capability or a check that did not happen

  score = sum, per scenario. Report the total AND the per-scenario vector --
  a good total can hide one -5 that matters more than the rest.
```

Worked comparison, both of which "succeeded":

```
native extract -> notices incomplete -> Firecrawl -> done      +5
crawler -> headers -> cookies -> retry -> browser -> Firecrawl  -5 -2 -2 -3 = -12
```

One-shot efficiency is the whole measurement. A model that reaches the answer
on attempt nine has demonstrated the failure, not recovered from it.

### What a passing suite looks like

All nine scenarios non-negative, **A, B, H and I positive**. Those four are the
ones that separate judgement from dogma: A punishes staying too primitive, B and
H punish reaching for machinery, and I punishes misreading a spent quota as a
missing credential. A run that scores well on A while failing B has learned
"always use the big tool", which is the other failure this suite exists for.

## Fixture integrity

Scoring the fixture is not a judgement call, so `check_fixtures.py` proves each
one still contains what it claims -- A's content still absent from its markup,
B's still present in its. A benchmark whose defects have quietly been repaired
passes every provider and measures nothing. It is chained into the pack gate.
