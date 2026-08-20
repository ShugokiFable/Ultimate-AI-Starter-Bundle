---
name: numerical-sanity-check
description: Use when calculations, pricing, timings, sizes, probabilities, rates, memory limits, token budgets, measurements, or converted values affect a decision.
---

# Numerical Sanity Check

## Core rule
A precise-looking number can still be dimensionally or conceptually wrong.

Write the **units** beside inputs and outputs. Check expected **range**, sign, ordering, and rough **magnitude** before trusting exact arithmetic. Recompute critical totals independently or with a calculator, especially after percentage, currency, binary/decimal size, time-zone, or per-million-token conversions.

For estimates, separate measured values from assumptions and show sensitivity to the biggest uncertain input. For rates, verify numerator/denominator and time window. For percentages, distinguish percentage points from percent change.

Reject impossible results early: negative file counts, probabilities above 1, cache savings larger than total input, or a converted value off by powers of 10.
