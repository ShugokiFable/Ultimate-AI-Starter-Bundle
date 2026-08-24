---
name: reproducible-builds
description: Use when building release binaries, generated assets, archives, manifests, wheels, native helpers, or supply-chain-sensitive artifacts.
---

# Reproducible Builds

## Core rule
A release build should be **deterministic** under its declared inputs. Pin the build **toolchain**, normalize uncontrolled metadata, and verify repeated outputs.

## Contract
Record source revision, compiler/runtime versions, dependency lock, flags, target architecture, and environment knobs that affect bytes. Build twice in clean temporary directories and compare relevant output **hash** values.

Eliminate timestamps, random temp paths, VCS metadata, locale, unordered traversal, and host-specific absolute paths from artifacts where possible. If byte reproducibility is impossible, define and test the narrower reproducibility contract explicitly.

Generate checksums/SBOM/manifests only after final artifact content is fixed.

Do not rebuild a published binary under a different compiler version and call the byte change a source fix. First prove whether the source or the toolchain changed.
