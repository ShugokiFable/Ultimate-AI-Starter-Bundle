# Sweeping a docs-heavy repo at release time

## When to Use

- The user asks to "push the latest changes", "make sure GitHub is up to date", or ship a version bump on a docs-heavy repo (README + changelogs + version files + manifests)
- The user complains the release page shows an old version after you pushed commits

## Workflow

1. **Decide the bump** (only when content changed: docs, skills, tooling).
2. **Sweep every version surface in ONE commit.** Find all stale refs with a repo-wide grep (`grep -rIl "<old-version>" --exclude-dir=.git`), then update each:
   - README: title, "What's new in vX.Y.Z" section (top of the What's-new stack), Version footer
   - START-HERE / quick-start headers and any "READ NEXT" changelog list
   - `CHANGELOG.md` top entry (gate scripts may read it) + a new dated `VX.Y.Z-CHANGELOG.md`
   - `VALIDATION.json` (version, base, notes) if present
   - `VERSION.txt`
   - Installer banner strings (`.ps1` — preserve BOM/CRLF!)
   - Regenerate any manifest (`python TOOLS/generate_manifest.py <root>` for the bundle)
   - Propagate canonical-file changes to all tree copies before committing
3. **Commit + tag + release + push (all four, always):**
   ```bash
   git add -A && git commit -m "vX.Y.Z - <summary>"
   git tag -a vX.Y.Z -m "vX.Y.Z - <summary>"
   git push origin main vX.Y.Z
   gh release create vX.Y.Z --title "vX.Y.Z — <short title>" --notes-file VX.Y.Z-CHANGELOG.md
   ```
4. **Verify on GitHub, not just locally:** `gh release list --repo <owner>/<repo> --limit 2` must show the new tag as **Latest**; check repo About box (homepage/description) for stale links.
5. **Verify live deployment surfaces** if the repo ships to a machine: configs wired, tools patched, skills copied to every provider home. The user's bar: "everything live so I don't need to do anything more."

## Pitfalls (user-corrected)

- **Pushing commits does NOT create a Release.** GitHub's Releases section ranks by tag. The user will check and come back angry — always tag + `gh release create`.
- If docs fixes land AFTER the tag, **force-move the tag** (`git tag -f` + push) so the release tarball contains the final docs — otherwise downloaders get the pre-docs commit.
- Historical references to old versions inside dated changelogs are CORRECT — don't purge them; only the public-facing surfaces change.
- `git -C` with MSYS-style `/z/...` paths fails on this machine — pass native `Z:/...` forward-slash paths to git/robocopy.
- Windows encoding rules: `.ps1`/`.bat` keep BOM or stay pure ASCII; `SKILL.md` = UTF-8 no BOM. Verify with `head -c 3 file | xxd`.

## References

- Full per-file checklist for the Ultimate-AI-Starter-Bundle: `references/ultimate-bundle-release.md`.
