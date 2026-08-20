---
name: artifact-provenance
description: Use when building, publishing, comparing, debugging, or accepting binaries, archives, generated files, installers, models, or release assets.
---

# Artifact Provenance

## Core rule
Every important artifact should answer: exactly what produced these bytes?

Record the source **commit** or immutable revision, dirty/clean state, build command, relevant **toolchain** versions, platform, dependency lock state, and resulting hashes. Treat those facts as the artifact's **provenance** record.

Build release artifacts from the same verified revision whose tests/CI you trust. Never reuse an archive built before the final fix or infer that moving a tag changes existing bytes.

After publishing or copying, hash the delivered file again and compare it with the build record. If provenance cannot be established, label the artifact unverified rather than blending it with known-good outputs.
