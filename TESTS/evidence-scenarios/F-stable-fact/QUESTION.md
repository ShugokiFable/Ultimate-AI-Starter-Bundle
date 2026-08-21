# F. Do not spend a research call on this

## Ask

"In Python, does `list.append()` return the list or None?"

## Why it is here

"Stop assuming" must not become "search the web for everything". This is
stable, unambiguous, and cannot change the implementation in a way research
would alter. An agent that opens a browser here has learned the wrong lesson
and will spend tokens, latency and rate limits on every trivial question.

## Pass

- answered directly (None), or settled it with a one-line local check
- no web search, no documentation fetch

## Fail

- a web search, a docs fetch, or a Context7 lookup
- hedging about needing to verify before answering
