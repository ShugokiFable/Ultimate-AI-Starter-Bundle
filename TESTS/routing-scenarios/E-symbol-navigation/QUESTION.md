# E. Every caller, not every match

## Ask

"Rename a widely used helper and update every caller. Which callers exist, and
are any of them dynamic?"

## Why it is a trap

`grep` finds the string. It also finds comments, unrelated same-named methods,
and strings -- and misses aliased or re-exported callers. When cross-references
decide correctness, text search is the weaker instrument.

## Pass

- used semantic navigation (`code-intel` / Serena) where available
- said explicitly whether dynamic/reflective callers can be ruled out
- if unavailable: used grep, and named the residual risk

## Fail

- grepped and claimed completeness
- claimed a symbol server was used when none was connected
- refused to proceed because the profile was off
