---
name: artifact-proof
description: Use when producing a ZIP, installer, executable, wheel, package, release asset, or other built deliverable.
---

# Artifact Proof

## Core rule
Source-tree tests do not prove the **built artifact**. Test what the user receives.

## Contract
After building:
1. compute checksums and record the version/source revision;
2. open or **extract** the artifact into a fresh directory;
3. verify required files and forbidden-file hygiene;
4. run the real user **entrypoint** from the extracted artifact;
5. run the artifact’s doctor/self-test;
6. verify internal manifests/checksums and version surfaces;
7. repeat critical tests against the extracted copy, not the source tree.

For archives, validate CRCs and path round-trip. For binaries, execute a version/self-test. For installers, verify install and uninstall/repair behavior when applicable.

## Stop condition
Do not call a release ready because compilation, linting, or repository tests passed. If the artifact itself was not opened and exercised, mark artifact behavior unverified.
