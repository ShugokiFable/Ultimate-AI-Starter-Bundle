---
name: real-boundary-testing
description: Use when tests mock subprocesses, filesystems, parsers, databases, networks, CLIs, serialization, or OS/provider integration.
---

# Real Boundary Testing

## Core rule
Mocks are useful for fault injection, but a mock cannot prove the **real boundary** behaves like your assumption.

## Contract
For each important boundary, keep at least one **integration** test using the actual parser/runtime/CLI/file format or a faithful local fixture. Use a **mock** only for behavior that is impractical or unsafe to invoke directly.

Ask: what production change could break while this test stays green? If the answer is “argument quoting, encoding, schema shape, exit codes, file locking, protocol negotiation, or tool discovery”, add a boundary test.

Test both success and the most important failure mode. Assert outputs/state, not merely that a mock function was called.

A strong unit suite plus one real boundary test is usually cheaper than debugging a release that passed against an invented interface.
