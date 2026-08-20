---
name: fresh-install-proof
description: Use when shipping installers, setup scripts, portable bundles, bootstrap flows, or “works on a fresh machine” claims.
---

# Fresh Install Proof

## Core rule
An installer is proven from **empty** state, not from the developer machine that already has dependencies and config.

## Required matrix
Test a disposable user/home with no prior product state. Include a destination containing **spaces** and **Unicode** characters. Exercise missing runtimes, missing config files, read-only/locked files where relevant, offline-vs-online modes, and an **idempotent** second install.

A passing fresh-install proof requires:
- one documented entrypoint;
- dependencies installed or a functional automatic fallback;
- no required manual “now edit/copy/approve this” step when automation is supported;
- failure returns non-zero and never prints a success banner;
- re-running preserves user settings and repairs partial state;
- final doctor verifies installed state, not merely source files.

## Evidence
Record the exact command, clean-state assumptions, exit code, installed paths, and doctor result. A test against an already-configured profile is a regression test, not fresh-install proof.
