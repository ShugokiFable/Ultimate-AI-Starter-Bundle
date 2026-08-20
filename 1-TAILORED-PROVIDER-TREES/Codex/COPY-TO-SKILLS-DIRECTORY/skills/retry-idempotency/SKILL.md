---
name: retry-idempotency
description: Use when operations may be retried after timeouts, transient errors, duplicate delivery, process interruption, or uncertain acknowledgement.
---

# Retry Idempotency

## Core rule
Before adding a **retry**, prove repeating the operation cannot duplicate or corrupt side effects.

Prefer naturally **idempotent** operations or attach an operation/idempotency key that lets the receiver deduplicate. After an ambiguous timeout, read authoritative state before blindly issuing the write again.

Classify errors: retry transient transport/capacity failures, not permanent validation/auth/configuration failures. Use bounded attempts and **backoff** with jitter when competing clients can synchronize.

For installers and migrations, rerunning after every supported interruption point should converge to one valid state. For external writes, verify exactly-once outcomes where possible. If safe retry cannot be guaranteed, surface the uncertainty and require reconciliation rather than multiplying side effects.
