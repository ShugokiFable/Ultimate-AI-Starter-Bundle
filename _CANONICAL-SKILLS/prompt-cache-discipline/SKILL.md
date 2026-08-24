---
name: prompt-cache-discipline
description: Use when repeated model calls share large instructions, tools, context, or prefixes and cache efficiency materially affects cost or latency.
---

# Prompt Cache Discipline

Keep the **stable prefix** stable. Prompt caching pays when large reusable instructions and references remain byte/order-stable across requests.

## Contract

1. Put durable instructions, schemas, and reusable reference context before volatile turn data.
2. Do not rewrite, reorder, timestamp, or reserialize a warm prefix without a correctness reason.
3. Keep session-scoped state small and append volatile facts after the reusable prefix.
4. Batch related reads/reasoning so repeated calls do not resend slightly different giant contexts.
5. Measure `cached_tokens`, uncached input, output, latency, and total cost when telemetry exists.
6. If compaction is required, preserve durable constraints and avoid repeated micro-compactions that churn the cache.

Cache hits never outrank correctness. Invalidate a stale prefix deliberately when facts or governing instructions change.
