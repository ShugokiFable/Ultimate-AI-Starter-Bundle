---
name: user-intent-lock
description: Use when optimizing, refactoring, simplifying, automating, or making trade-offs could accidentally remove or weaken something the user explicitly asked for.
---

# User Intent Lock

## Core rule
Optimization is subordinate to **user intent**.

Translate explicit requests and necessary implied deliverables into an **acceptance** ledger before making trade-offs. When a proposed optimization changes behavior, quality, scope, security posture, artifact shape, compatibility, or manual-work expectations, check it against that ledger first.

Do not silently reinterpret "fast" as "incomplete", "cheap" as "low quality", or "simple" as "manual setup". Preserve literal constraints such as supported platforms, output formats, versions, and zero-chore installation unless they are impossible or conflict with a higher-priority requirement.

If two goals genuinely trade off, choose using the user's stated priorities and make the remaining compromise explicit.
