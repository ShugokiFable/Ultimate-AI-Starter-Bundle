---
name: windows-workspace-ops
description: Windows workspace plumbing - directory junctions, paths containing "!" and spaces, git overlay repositories, push recovery, and byte-exact edits that survive PowerShell quoting.
---

# Windows workspace ops (git-bash / Hermes terminal)

Plumbing layer for working on this PC: the user's project drives live at
`D:\!Projects\!!!Workspace\...` (paths permanently contain
`!`), projects are snapshot-heavy (version folders), and CommonLibSSE-style
junctions break on every folder move/copy. These are the exact, verified
methods.

## NTFS junctions

- **`cp -a` FOLLOWS junctions.** Copying a folder tree that contains an
  `extern/CommonLibSSE` junction duplicates the whole target (hundreds of MB).
  Plan around it: after copying, delete the copied contents and re-create the
  junction (see below).
- **`cmd /c mklink /J` from bash is unreliable here:** the spawned cmd can run
  with the wrong CWD (junction lands at the drive root) and MSYS mangles
  `Z:\...` backslash targets into `/z/Z:/...`. Do not fight it.
- **Reliable, no-admin method (Python 3.12+):**
  `python -c "import _winapi; _winapi.CreateJunction(r'TARGET', r'LINK')"`
  - `_winapi.CreateJunction(src, dst)`: `dst` is the link, `src` the target.
  - Verify: `os.path.exists(dst + r'\install\lib\cmake\CommonLibSSE')` (any
    marker file inside the target).
  - Remove a stray/mangled junction with `os.rmdir(path)` — works on junctions
    without admin.
  - Reusable helper: `scripts/create_junction.py <target> <link>`.
- Re-create junctions after ANY copy/move/rename of a version folder
  (absolute targets go stale) before configuring or building.

## Quoting paths that contain `!`

Interactive bash history-expands `!`: `!!` splices in the previous command, so
a path like `D:\!Projects\!!!Workspace\...` inside DOUBLE
quotes gets expanded mid-path, breaking the argument into pieces at spaces.
Rule: **single-quote every path containing `!`**. Avoid `find ... | xargs`
pipelines with such paths — the expansions compound.

## Byte-exact edits when the `patch` tool refuses

`patch` trips its escape-drift guard on C++ string-literal blocks containing
`\"` and `\n` sequences (e.g. `settings.cpp` WriteDefaultINI style), and it has
been seen literalizing a `newline="\r\n"` escape into a real newline. When it
fails or mangles, do the edit in Python instead:

```python
with open(path, 'r', encoding='utf-8') as f: c = f.read()
assert old in c            # exact bytes; fail loudly if drifted
c = c.replace(old, new, 1)
with open(path, 'w', encoding='utf-8', newline='') as f: f.write(c)
```

Re-read the file to verify. This is the fallback for any tooling that fights
the text, not just `patch`.

## Workspace-folder to GitHub publication (overlay flow)

Project convention (Modern NPC Pathing and its kin): GitHub main IS the tree;
the local version folder is the source of truth for a release. Verified flow:

1. `gh repo clone <owner>/<repo> $LOCALAPPDATA/Temp/<name>` (use
   `$LOCALAPPDATA/Temp` for scratch — native tools handle it cleanly).
2. Overlay: `cp -a <version-folder>/ <clone>/`, then DELETE dev material:
   `rm -rf build dist extern __pycache__ package/Data/SKSE/Plugins/*.dll`.
3. Expect phantom `git status` entries: with `core.autocrlf=true`, line-ending
   swaps show as modified but have no real diff. Confirm real changes with
   `git diff --name-only` (not `git status`) and `git diff <file> | head`.
4. Unstage workspace-only artifacts that were never tracked (historical
   audit docs, previous-version Nexus changelogs) with `git reset -q -- <files>`.
5. Commit with the project's author identity
   (`git -c user.name=... -c user.email=... commit`), push `main`, then:
   `gh release create v<VER> --title ... --notes-file <notes.md> <FOMOD.zip> <plain.zip> SHA256SUMS.txt`.
6. Verify assets via `gh api ... /releases/tags/v<VER>`; the project releases
   before CI finishes — watch the run in background with
   `gh run watch --exit-status` + notify.

## Pitfalls

- `gh run watch` on a queued run can block: give it a few seconds first, or
  run it as a background process with notify on completion.
- A fresh Windows clone is LF on disk: do not judge "modified" files by
  `git status` alone; always diff before staging.