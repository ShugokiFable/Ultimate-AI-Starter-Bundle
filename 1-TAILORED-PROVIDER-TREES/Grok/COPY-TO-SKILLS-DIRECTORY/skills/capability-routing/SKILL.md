---
name: capability-routing
description: Use before writing a crawler, scraper, parser, browser-automation layer, API client, or any wrapper around work an installed tool already does; when a fetch returns a challenge page, login wall, empty JS shell, 403/429, or content that is visibly missing from what was extracted; when choosing between a native tool, an MCP server, and a few lines of shell/Python/Node; and when the same approach has already failed twice.
---

# Capability routing

One question decides this, and it is not "which tool do I have?"

```
WHAT IS THE HARD PART OF THIS TASK?
        v
WHICH AVAILABLE CAPABILITY DIRECTLY OWNS THAT HARD PART?
        v
USE THE CHEAPEST TOOL THAT FULLY COVERS IT
        v
IF IT FAILS BECAUSE THE CAPABILITY IS INSUFFICIENT: ESCALATE THE CLASS
```

The rule is **not** "always use a bundle tool". It is:

> When several tools can do the job, take the cheapest reliable one whose
> strengths match the hard part. Do not rebuild a weaker version of something
> already installed just because shell, Python or Node is familiar.

Both halves are load-bearing. A pile of excellent servers the model never
reaches for is worse than a small set it routes correctly — and so is a browser
stack launched to read a static JSON file.

## The failure this exists to stop

```
BAD                                  GOOD
need data from a difficult site      need data from a difficult site
-> write an axios/fetch crawler      -> notice it needs rendering / anti-bot
-> get a Cloudflare shell            -> use the extraction capability that owns that
-> add a User-Agent                  -> check the result is actually complete
-> add cookies, retry                -> escalate to interaction only if needed
-> add a regex, get partial HTML
-> "the site blocks scraping"
```

Nothing in the left column is stupid. Each step is locally reasonable, which is
exactly why it runs to ten turns. The error was made at step one, by treating a
rendering/anti-bot problem as a text-fetching problem.

**Do not solve a specialized problem with a primitive that is known to omit the
specialized part.**

## Before writing an implementation, four questions

1. Is a **loaded** tool already doing this? (in the tool list right now)
2. Is there an **installed but lazy** capability/profile that does it?
   (`capability-profiles` — installed is not enabled)
3. Does a bundle skill say which tool owns this operation?
4. Is what I am about to write **actually more capable** than those?

If 1–3 give you the capability and 4 is no — use the existing capability.
If 4 is genuinely yes, write it, and say why in one line.

## Fitness, not brand

```
        task_match x reliability x evidence_quality x availability
fitness = ---------------------------------------------------------
                setup_cost x context_cost x latency
```

Not a formula to compute — a reminder that a specialized tool earns priority by
**materially improving the task**, not by being specialized. A native tool that
is already sufficient and cheaper wins. An ad-hoc script is normally last when a
specialized capability exists, and normally first when none of the hard parts
are specialized.

## Who owns what

Route to the owner of the hard part. Verify availability before relying on it;
benchmark beats this table if they disagree.

| the hard part | owner | not |
|---|---|---|
| live web search / ordinary extraction | the host's native web tool | a hand-rolled HTTP client |
| rendered / anti-bot / JS-only content | Firecrawl or a real browser backend | fetch + cheerio, more headers |
| clicking, scrolling, login, infinite scroll | browser automation / interact | guessing at the next URL |
| current library API or version fact | installed `--help`/source, Context7, upstream | model recall |
| GitHub repo, PR, CI, release state | the official GitHub MCP / `gh` | scraping github.com HTML |
| symbol-level navigation, references | `code-intel` / Serena | grepping every file when cross-refs matter |
| Skyrim live load-order winner | houseCARL | parsing plugins.txt and guessing |
| Skyrim typed build/release | Skyrim Forge / the owning toolkit | reimplementing its pipeline in Python |
| ESP / Papyrus / NIF / BSA operations | Spooky's toolkit where it owns it | hand-rolled binary parsing |
| does the rendered UI look right | `visual-verification` + a vision-capable path | reading the CSS |

### And where the primitive genuinely wins

| task | use |
|---|---|
| read one local JSON/text file | a file read — not code-intel |
| GET one simple static public URL | native extract — not a browser stack |
| replace a known string in three files | ordinary editing — not a symbol server |
| count matches in a log | grep — not an indexer |

Reaching for the heavyweight tool here is the same error wearing the opposite
costume. Twelve tool calls for a page that `curl` answers is not thoroughness.

## Escalate the class, do not tune the weak tool

After **one or two** evidence-backed failures, change the class of tool. Do not
retry the same HTTP client with another header.

```
cheap normal extraction
    | incomplete / challenged
rendered extraction (Firecrawl, browser backend)
    | needs interaction
browser interaction (click, scroll, wait, login)
    | genuinely gated
stop, and say what is required
```

Signals that the class is wrong — not the parameters:

- a Cloudflare/anti-bot interstitial or placeholder
- 403, 429, or a redirect loop
- HTTP 200 with a JS shell and no rendered body
- the extract holds only header/footer/nav
- visible page content absent from the extracted text
- content that appears only after a click or scroll
- a login or consent wall

Two failures of the same shape is the signal. A third attempt at the same class
is a decision to keep failing.

## Read the failure before switching

A tool that failed is evidence, and the useful question is *why*:

| failure says | means | do |
|---|---|---|
| unauthorized / API key required | capability exists, credentials do not | use the keyless route, or say what a key would buy |
| rate limited / quota | right tool, wrong moment | back off, or take the next vendor |
| challenge page / empty shell | **wrong class** | escalate the class |
| tool not found / no such tool | not enabled here | `capability-profiles`, or fall back and say so |
| malformed argument | your call, not the tool | fix the call |

Only the third is a reason to change tools. Switching on the first or last just
loses the capability you already had.

## When the capability is not available

Fall back cleanly, finish the task, and **name what is unverified**. Do not
claim a tool you do not have, and do not stop work that the fallback can still
complete. "Extracted with the plain fetch; a rendered extractor was not
available, so JS-injected content may be missing" is a complete answer.

## Worked example, measured

The routing decision for Hermes' web stack in 7.9.8, since it shows the method:

- Hermes v0.20.4 ships `web_search` / `web_extract` over a keyless vendor ring
  (exa, parallel, tavily, firecrawl, keenable) with round-robin and rate-limit
  failover. Verified by running it: keyless Firecrawl search 1.4 s, extract
  0.7 s, no key.
- firecrawl-mcp adds 25 tool schemas, 36,337 bytes, **~9,084 tokens on every
  turn** (`TOOLS\Measure-McpSchemaCost.ps1`).
- Keyless, that server answers only `search` and `scrape`; `map`, `crawl`,
  `agent` and `interact` return *"API key is required"*. Verified by calling
  each one.

So the expensive surface duplicated the native one and its unique half was
unreachable without an account. It is not registered by default — and the
native route is the strong one, not a compromise. Add it deliberately with
`-WithExtras` when you have a key and need crawl/map/interact.

The point is not the conclusion, it is that the conclusion came from three
measurements instead of an assumption about which brand sounds stronger.

## Terminal and execute-code are an escape hatch

Especially where a shell and a code runner are always in the tool list: their
presence is not evidence that writing a new implementation is the right choice.
They are what you use when **no** specialized capability owns the hard part —
which is often, and is fine. The mistake is reaching for them *first* on a
problem something else already solves better, and discovering the reason for
that tool's existence one failed retry at a time.
