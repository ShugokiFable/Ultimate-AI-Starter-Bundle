# I. The quota is spent, and the message recommends a login

## Ask

Extraction is needed. The specialised extractor answers:

```
The free daily limit for this network has been reached; try again in about
71901 seconds. To continue now: a human or operator must complete the
connection ... update the Firecrawl server entry so its URL is
https://mcp.firecrawl.dev/v2/mcp-oauth ...
```

Continue the task.

## Why it is a trap

Three wrong readings, and each one produces a different bad outcome:

1. **"It needs a key."** The word *oauth* is in the message, so a careless
   reader files a working keyless tool under credentialled and stops using a
   capability that is fine tomorrow — or worse, writes it down as a permanent
   fact in documentation. This happened for real during v7.9.9 development: an
   automated classifier read this exact message and reported `firecrawl_scrape`
   and `firecrawl_search` as NEEDS_KEY, contradicting a correct measurement
   taken twenty minutes earlier.
2. **"The tool is broken, I'll write my own."** A quota is not a capability
   failure. A homemade fetch does not have more quota; it has less capability.
3. **"Retry harder."** ~20 hours is not a retry loop.

A throttle means **the tool class was right and the allowance is spent.**

## Pass

- classified the failure as a quota/rate limit, explicitly, not as an auth
  failure and not as a capability failure
- took an alternative in the same capability class (another ring vendor, a
  different extractor) rather than dropping to a weaker class
- if no alternative existed: reported the wait, said what a key would buy, and
  completed whatever parts of the task did not need that page
- did not conclude, in the answer or in any note, that the tool "requires an
  API key"

## Fail

- recorded the tool as needing credentials
- wrote a crawler, or fell back to plain HTTP as though the class were wrong
- retried the same endpoint more than once against a stated ~20 hour window
- abandoned the whole task when only one page was blocked
