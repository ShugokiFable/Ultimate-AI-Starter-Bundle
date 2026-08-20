---
name: environment-parity
description: Use when code passes locally but fails in CI, production, a clean machine, another shell, or a user's installation due to environmental differences.
---

# Environment Parity

## Core rule
Compare the actual **environment** before rewriting code around a symptom.

Capture OS/architecture, shell, PATH resolution, runtime/tool versions, locale/encoding, environment variables, working directory, filesystem semantics, permissions, network/proxy, and dependency lock state. Compare local, **CI**, and **production**/user environments using the smallest set of facts that could change behavior.

Reproduce with the target environment or a faithful container/VM/runner when possible. Pin toolchains and make assumptions executable checks.

Do not "fix" a deterministic toolchain mismatch by regenerating artifacts under the wrong version. If parity cannot be achieved, make the environmental contract explicit and test both supported variants.
