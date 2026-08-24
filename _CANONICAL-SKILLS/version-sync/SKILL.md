---
name: version-sync
description: Use when bumping versions, publishing packages, rebuilding binaries, changing protocol compatibility, or updating release metadata.
---

# Version Sync

## Core rule
Define one **single source** of truth for the product **version** and treat every other version string as a derived surface.

## Contract
Enumerate all required surfaces: runtime constant, package metadata, CLI output, native binary, installer banner, catalog, docs, changelog, manifest/SBOM, compatibility contract, artifact filename, and CI assertions.

Automate verification that every required surface matches the source. Search for the previous version to catch undeclared copies, then classify intentional historical mentions separately.

For mixed-language builds, verify the built binary reports the same version as the source tree. For compatibility ranges, test accepted and rejected neighbors.

Any unexplained **drift** blocks release. Do not “fix” drift by changing the test to accept multiple versions unless multiple versions are genuinely part of the contract.
