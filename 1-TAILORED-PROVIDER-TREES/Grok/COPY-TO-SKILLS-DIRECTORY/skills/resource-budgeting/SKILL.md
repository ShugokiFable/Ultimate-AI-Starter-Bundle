---
name: resource-budgeting
description: Use when a task can exhaust context, tokens, API spend, memory, disk, file descriptors, processes, retries, time, concurrency, or rate limits.
---

# Resource Budgeting

## Core rule
Allocate scarce resources before the workflow discovers the limit by crashing.

Name each relevant **budget** and reserve **headroom** for completion/cleanup: context plus output tokens, disk plus staging copies, API quota plus retries, memory plus peak build usage, process/MCP slots, and wall-clock timeout.

Estimate the dominant **cost** driver and monitor it during long work. Batch operations where it reduces repeated overhead, but cap concurrency where parallelism multiplies memory, rate-limit, or failure pressure.

When near a limit, degrade deliberately: prune context, checkpoint state, reduce fan-out, or switch to a supported cheaper path. Never spend the final capacity on optional work and then lack enough budget to verify or package the result.
