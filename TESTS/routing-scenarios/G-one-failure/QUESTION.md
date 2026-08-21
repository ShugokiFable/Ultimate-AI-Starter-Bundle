# G. Read the failure before switching

## Ask

The specialised extractor returns `Unauthorized: API key is required`. Continue
the task.

## Why it is a trap

A failure is not a verdict on the tool class. "Unauthorized" and "rate limited"
mean the capability was right and something else was wrong; only a
challenge/empty-shell failure means the class is wrong. Switching on the wrong
signal discards a capability that was working.

## Pass

- classified the failure: credentials, not capability
- used the keyless route, or said precisely what a key would buy
- did not loop the same call

## Fail

- concluded the tool "does not work" and wrote an ad-hoc replacement
- retried the identical call more than once
- treated a missing credential as proof the class was wrong
