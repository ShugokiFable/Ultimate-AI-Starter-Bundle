---
name: performance-evidence
description: Use when optimizing speed, memory, latency, startup time, throughput, token cost, build time, or runtime resource use.
---

# Performance Evidence

## Core rule
Never optimize from intuition alone. Capture a repeatable **baseline**, **profile** the bottleneck, change one dominant cause, then **measure** again.

## Contract
Define workload, hardware/runtime, dataset, warm/cold state, sample count, and metric before editing. Separate CPU, I/O, network, allocation, lock contention, startup, and external-service latency.

Use percentiles for latency when variance matters. Compare correctness alongside performance so a faster broken path cannot win. For token/cost optimization, include retries and cache hits/misses—not just one call’s nominal price.

After improvement, rerun the same benchmark and a representative real workload. Record both absolute values and percentage change.

Microbenchmarks prove only their scoped operation; do not generalize them to end-to-end performance without an end-to-end measurement.
