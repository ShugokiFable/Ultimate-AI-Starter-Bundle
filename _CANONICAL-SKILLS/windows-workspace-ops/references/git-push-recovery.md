# Git push / rebase recovery on this PC (verified on BDO-TEX-AIO releases)

## Stale `.git/rebase-merge` blocks every future rebase

If a rebase dies mid-flight (e.g. the commit step fails with
`unable to auto-detect email address`), git leaves `.git/rebase-merge/`
behind. Every later `git rebase` then refuses with:

```
error: ... I am stopping in case you still have something valuable there.
```

The message names the directory. Once you verify (a) the working tree is
clean (`git status --porcelain`) and (b) the branch is at the commit you
want, clear the stale state and re-run the rebase:

```bash
rm -rf .git/rebase-merge
git rebase origin/main
```

Read the FULL rebase output, not `2>&1 | tail -2` of a piped stream — the
identity failure and the stale-dir refusal both get truncated and look
identical at the tail.

## `git reset --hard` on a DETACHED HEAD keeps you detached

After an interrupted rebase, HEAD can be detached at the remote's commit.
A `git reset --hard <sha>` on a detached HEAD moves HEAD but NEVER updates
the branch ref, so `git push origin main` still fails with
`non-fast-forward` while the rebased commit sits unreferenced. Reattach and
move the branch in one step, then push:

```bash
git checkout -B main <rebase-result-sha>
git push origin main
git tag -a v<ver> -m "..."
git push origin main --tags
```

## Tag-matching source zip without a clone

`git archive --format=zip -o <out.zip> v<tag>` produces a source zip that
exactly matches the tagged commit — the BDO-TEX-AIO release flow. No
`cp -a` overlay needed when the repo IS the workspace.

## robocopy exit codes are bitmasks, not 0/1

| Code | Meaning |
|------|---------|
| 0    | Nothing copied (no change) |
| 1    | **Success** — files copied |
| 2+   | Extra files/dirs (still fine) |
| >=8  | FAILURE (incl. 8, 16, 32...) |

`echo ROBOCPY_EXIT=$?` printing `1` is SUCCESS — do not treat it as an
error. Before `rm -rf` of the source, verify the backup byte-exact:

```bash
SRC=$(find SRC -type f | wc -l); DST=$(find DST -type f | wc -l)
SRCB=$(du -sb SRC | cut -f1); DSTB=$(du -sb DST | cut -f1)
[ "$SRC" -eq "$DST" ] && [ "$SRCB" -eq "$DSTB" ] && echo BACKUP-VERIFIED
```

Equal file counts + equal bytes = backup good, safe to delete the source.
