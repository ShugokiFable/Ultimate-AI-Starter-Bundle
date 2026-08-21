---
name: release-checklist
description: Use when preparing to version, tag, publish, or recover a GitHub release whose CI and shipped artifacts must be proven.
compatibility: Windows 10/11; PowerShell 5.1 and Python 3; gh CLI authenticated.
metadata:
  version: 1.0.0
  updated: '2026-08-20'
  library: overseer-skyrim-agent-skills
  error_registry_revision: 4.3.0
  final_pack_version: 7.9.2
---

# Release checklist

Run in order. Every item is mandatory — the ones that look redundant are the
ones that previously shipped broken releases. Nothing below depends on memory:
each step reads the repo's actual files.

## 1. Read the CI workflow before touching anything

    cat .github/workflows/*.yml

List every job and every command it runs. CI checks things the local gate does
NOT — treat the workflow as the contract. Common CI-only traps:

- A version-consistency script (`.github/scripts/check_versions.py`) that
  requires a **dated changelog file** per version (e.g.
  `docs/history/V7.X.Y-CHANGELOG.md`) in addition to the inline `CHANGELOG.md`.
- A manifest verifier (`.github/scripts/verify_manifest.py`) that hashes every
  tracked file — adding/removing/renaming a file without regenerating
  `MANIFEST.json` fails it.

## 2. Bump the version in EVERY place CI checks

    grep -rn '<old-version>' --include='*.md' --include='*.txt' \
      --include='*.ps1' --include='*.json' --include='*.toml' --include='*.py' .

Then read `check_versions.py` (if present) and satisfy its exact file list —
it names files a blind grep can miss (AIO banner vs state, CATALOG, dated
changelog). Create the dated changelog for the new version even if the entry
is three lines; its absence is the #1 CI failure.

## 3. Regenerate integrity manifests

If the repo has `MANIFEST.json` + a generator (`TOOLS/generate_manifest.py`):

    python TOOLS/generate_manifest.py .
    python .github/scripts/verify_manifest.py   # expect 0 missing / 0 mismatch

Regenerate after ANY file add/remove/rename, not just content edits. Run the
verifier — a manifest that "looks fine" but was never verified is not proof.

## 4. Run the local gate

    powershell -NoProfile -ExecutionPolicy Bypass -File TESTS/Test-V7-Pack.ps1

A local PASS is necessary but NOT sufficient — see step 5.

## 5. Push, then converge CI for the exact pushed commit

**REQUIRED SUB-SKILL:** Use `ci-convergence`.

Record the exact pushed SHA and keep it as the release identity:

    SHA=$(git rev-parse HEAD)
    git push origin HEAD

Do not use "latest on main" as a proxy. Query workflow/check state for that
**exact pushed SHA**. GitHub CLI examples:

    gh run list --commit "$SHA" --json databaseId,headSha,status,conclusion,workflowName
    gh run watch <run-id> --exit-status
    gh api repos/{owner}/{repo}/commits/$SHA/check-runs

Wait through queued/in-progress states. Every required check must reach a
terminal successful/skipped state according to branch policy. If any required
check fails, inspect its job/log, fix the root cause, commit and push a NEW SHA,
and restart this section from that new SHA. Never tag, build a release, or end
the release task while the chosen SHA is pending or red.

## 6. Tag and build artifacts from the GREEN commit

    git tag -a vX.Y.Z -m '<summary>'
    git push origin vX.Y.Z
    powershell -NoProfile -ExecutionPolicy Bypass -File TOOLS/Build-Release.ps1

Build zips AFTER the fix. Artifacts built from a red commit stay broken even
if the tag is later moved.

## 7. Publish, then verify what actually shipped

    gh release create vX.Y.Z --title '...' --notes '...' <zip>... 
    gh release view vX.Y.Z --json tagName,targetCommitish,assets

Confirm the tag resolves to the exact green SHA from step 5 and EVERY asset name is present. Re-check the required checks for that SHA. A release is not done until the shipped assets and exact commit are both proven.

## 8. If a release already shipped red (recovery)

1. Fix the cause, push, get CI green.
2. `gh release delete vX.Y.Z --yes`, force-move the tag to the green commit,
   push the tag with `--force`.
3. Rebuild zips, `gh release create` again.
4. Verify as in step 7.

## Why these exist (evidence)

- v7.7.13/7.7.14 CI failed: version bump missed the dated changelog file that
  `check_versions.py` requires. Local pack gate passed; CI did not.
- The release zips were built from the red commit and had to be deleted and
  rebuilt after the tag was force-moved to green.
- SkyrimForge v5.1.7: manifest hashed CRLF working-tree bytes while CI
  verifies LF — same class of failure (CI-only trap), same fix discipline.
