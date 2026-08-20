# Release process

0. Rebuild native helpers with `python scripts/rebuild_native_helpers.py`. This uses the exact deterministic profile: Go 1.23.2, `-trimpath`, `-buildvcs=false`, stripped symbols, and an empty build ID.

1. Run the complete repository validator with `--write-reports` **twice**. The
   report files hash the tree they ship with, so any source change makes the
   committed manifest stale by definition: the first pass rewrites the evidence
   and may fail on that staleness, and the second pass is the gate that must
   return PASS. A third run without `--write-reports` confirms idempotence.
2. Run all required GitHub CI and CodeQL jobs.
3. Execute the Windows installer twice in CI.
4. Execute the bundled Windows native helper and its self-test.
5. Build the repository archive twice and require identical hashes.
6. Build the wheel and source distribution twice and require identical hashes.
7. Publish only from the validated tag commit.
8. State separately which installed tools and Skyrim runtime tests were actually exercised.

## Nexus Mods or other public redistribution

When publication intent is present, run the target-specific rights gate before tagging or uploading:

```text
forge release-validate <release-root> --target nexus --publication-plan NEXUS-PUBLICATION-PLAN.json
forge release-build <release-root> <output.zip> --target nexus --publication-plan NEXUS-PUBLICATION-PLAN.json --approve
```

A generic successful release-tree check proves packaging hygiene only. It must not be described as Nexus-ready. Store permission screenshots, messages, invoices, licence copies, and review notes outside the public archive; Forge hashes them into the private audit without publishing them.
