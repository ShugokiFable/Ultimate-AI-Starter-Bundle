---
name: token-efficiency
description: Use when an agent is about to wait on something slow (CI, a build, a download, a deploy), when a session is burning tokens on polling or re-reading, when choosing how many MCP servers or skills to load, or when the user asks about cost, caching, or context bloat. Corrects the common belief that prompt caching makes watching things cheap.
---

# Token efficiency

Most agent waste is not verbosity. It is **re-reading**: the same context sent
again and again because the agent kept asking "is it done yet?"

Every request resends the entire conversation. A 150k-token session that polls
CI forty times sends 6M input tokens, plus forty replies saying "still running."
The work was one command and one answer.

## The pricing that decides everything

| | cost |
|---|---|
| cache **read** | **0.1x** base input |
| cache **write** | **1.25x** (5-min TTL), **2x** (1-hour TTL) |
| **output** | full price. Caching does nothing for output. |

Three consequences people get wrong:

1. **A cache write costs more than an uncached read.** Caching is not free
   insurance. Break-even is 2 requests on the 5-minute TTL, 3 on the 1-hour.
   Caching a prefix used once is a pure loss.
2. **Caching never reduces output cost.** A chatty agent is expensive no matter
   how well its prefix caches.
3. **Cheap is not free.** 0.1x of a huge context, forty times, still dwarfs the
   thing you were trying to save.

So "keep the model watching so it stays cached" is backwards. The model watching
*is* the cost.

## The rule: the harness waits, the model sleeps

Blocking in a shell costs **zero** model tokens. Blocking in the model costs a
full context read per check.

Wait for a condition with a loop in the shell, backgrounded, and let it wake the
agent once when the condition is met:

```bash
until [ -z "$(gh run list --commit "$SHA" --json status \
    --jq '.[]|select(.status!="completed")')" ]; do sleep 30; done
gh api "repos/$REPO/commits/$SHA/check-runs" --jq '.check_runs[]|"\(.conclusion)  \(.name)"'
```

Twelve minutes of CI, one wake-up, one result. The polling version is the same
twelve minutes and forty full-context requests.

The same applies to builds, downloads, installs, test suites, deploys and any
`sleep`-and-check loop. If the harness offers a background/notify mechanism, that
is the mechanism. Reach for in-model polling only when the thing being watched
cannot be expressed as a shell condition.

**Do not** schedule wake-ups to "keep the cache warm." A cache write is 1.25x-2x;
warming a prefix nothing is waiting on is spending money to save none.

## Keep the cacheable prefix stable

Cache matching is a **prefix** match, rendered `tools` -> `system` -> `messages`.
One changed byte anywhere invalidates everything after it.

- Stable first: frozen system prompt, deterministic tool list, project context.
- Volatile last: timestamps, per-request ids, the actual question.
- A clock reading or an unsorted JSON dump near the top of a prompt silently
  destroys every cache hit after it, and nothing errors.
- Verify with `usage.cache_read_input_tokens`. Zero across repeated requests
  means something is invalidating; do not assume caching is working because you
  configured it.

Changing the tool list mid-session invalidates the whole prefix. That is a real
cost of loading MCP servers "just in case."

## Load capability, not catalogues

This pack ships 142 skills. Their bodies total roughly **153,000 tokens**; the
name-and-description index the agent actually needs is about **5,500**. That is a
28x difference, and it is the single largest lever available.

- Skills load **by description**, and the body loads only on invocation. Never
  paste skill bodies into context speculatively.
- MCP tool schemas are **not** lazy. Every connected server's tools sit in
  context on every turn. Eight servers you might need cost more than two you do.
- Scope servers that support it. The official GitHub MCP server groups its tools
  into 20 toolsets; this pack enables five. `--toolsets=all` would multiply the
  schema cost for tools nobody calls.
- Where a provider offers deferred tool loading or tool search, prefer it: the
  agent sees a few meta-tools and fetches schemas on demand.
- Grok wedges at eight running MCP servers, so the budget is enforced there
  whether or not you think about it. See `GROK-MCP-TROUBLESHOOTING.md`.

## Cheap models for cheap decisions

Selection, routing, approval and summarisation do not need the expensive model.
Hermes routes `skills_hub`, `mcp` and `approval` through separate aux models
precisely so the main model is not spent deciding *which* skill to read. If a
provider exposes aux-model routing, use it.

## Batch the round trips

- Independent tool calls go in **one** message, not one per turn. Each extra turn
  is another full context read.
- Read the file once. Re-reading a file you already have in context to "check" is
  a full re-send for information you were already holding.
- Do not re-run a passing gate to feel sure. If nothing changed, nothing changed.

## What this is not

Not an argument for terse thinking or skipped verification. Reasoning tokens are
cheap relative to a wrong answer that costs a full debugging session. Cut
**repetition**, never comprehension: the expensive failure mode is an agent that
polls forty times and still gets it wrong.

## Checklist

- [ ] Waiting on something slow? Shell loop in the background, not model polling.
- [ ] Volatile content (clocks, ids) after the stable prefix, never before.
- [ ] Only the MCP servers this task needs are connected.
- [ ] Scoped toolsets where the server supports scoping.
- [ ] Independent tool calls batched into one message.
- [ ] No wake-ups scheduled purely to warm a cache.
