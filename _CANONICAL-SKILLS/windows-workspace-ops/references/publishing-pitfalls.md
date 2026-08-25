# Publishing to an existing repo — pitfalls (verified 2026-08-19, BDO-TEX-AIO v1.4.0 push)

## 1. The repo may already exist and be ahead of the local clone

The user's repos are often already published (made via other AI sessions).
Check BEFORE assuming create+push:

```bash
git ls-remote https://github.com/<owner>/<repo>.git          # refs/tags exist?
gh repo view <owner>/<repo> --json defaultBranch,isEmpty,licenseInfo
```

In an existing local clone, prove what is actually un-pushed:

```bash
git fetch origin
git rev-list --count origin/main..HEAD      # 0 = nothing to push at all
git hash-object <file>   # vs  git rev-parse HEAD:<file>  → byte-identity proof
```

Real case: local tree was byte-identical to tag v1.3.0 (every `git hash-object`
matched `HEAD:file`), yet `diff -rq` against a fresh clone showed every text
file differing — pure CRLF/LF checkout artifact, NOT edits. Trust the hash
comparison, not `diff -rq`, for identity.

If the tree is byte-identical to the last tag, "push it" usually means
something else — ask the user which (new feature release vs. docs-only
completion) instead of inventing scope.

## 2. Remote-ahead push rejection

Remote `main` can hold commits the local clone never had (real case: an
"Add/update CI workflows" commit made on GitHub directly, 11 days after the
last tag). `git push` fails non-fast-forward.

Fix: `git fetch && git rebase origin/main` (keeps linear history — the
user's repos are single-commit-line style), then push. Never force-push
over the remote's new commit.

## 3. Rebase needs identity from config, not `-c` flags

`git -c user.name=X -c user.email=Y commit` applies to the single commit.
`git rebase` reads committer identity from CONFIG and dies with:

```
fatal: unable to auto-detect email address (got '<user>@<host>(none)')
```

This machine has NO global git identity. Set repo-local first:

```bash
git config user.name  "<your-github-username>"
git config user.email "<id>+<your-github-username>@users.noreply.github.com"
git rebase origin/main
```

## 4. Rebase half-state recovery

A failed rebase can leave HEAD detached at the onto commit with your changes
staged, while your original commit stays intact on the branch. Reflog shows
only `rebase (start): checkout origin/main` — the cherry-pick never committed.

Verify with `git log --all --oneline` (your commit is there), then:

```bash
git reset --hard <original-commit>   # back to your commit, discards staged dup
git rebase origin/main               # now works (identity configured)
```

Never re-create the commit by hand. The original is never lost until
`git gc` prunes unreferenced objects — `git fsck --lost-found` finds it if a
branch really lost it.

## 5. Deleting a "duplicate" git folder (`-git-push` mirrors)

Safe to rm -rf ONLY after BOTH hold:
- the working folder has no `.git` of its own (the mirror is the only local
  clone — deleting orphans local history, though the remote survives), and
- `git rev-list --count origin/main..HEAD` == 0 after fetch (nothing un-pushed).

Real case: `BDO-AIO-git-push` looked like a duplicate but the main `BDO-AIO`
folder had no `.git`; after fetch, count was 0 → true mirror → deletion was
safe, but the check is what proved it.

## 6. Syntax-checking patched `.ps1` from bash

Inline `powershell -Command "...$var..."` mangles every `$var` (bash expands
first) → fake parser errors. Write the check to a temp `.ps1` file:

```powershell
$e = $null
[System.Management.Automation.Language.Parser]::ParseFile('C:\path\file.ps1', [ref]$null, [ref]$e) | Out-Null
if ($e) { $e | ForEach-Object { $_.Message }; exit 1 } else { 'ps1 parse OK' }
```

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File check.ps1`

## 7. Tag + release for an existing source-only repo

```bash
git tag -a vX.Y.Z -m "msg" && git push origin vX.Y.Z
git archive --format=zip -o <REPO>-vX.Y.Z-source.zip vX.Y.Z
gh release create vX.Y.Z <REPO>-vX.Y.Z-source.zip --title "..." --notes "..."
```

Match the existing release's asset naming (`<REPO>-v<ver>-source.zip`, flat
structure, no wrapping folder) so the repo stays consistent.
