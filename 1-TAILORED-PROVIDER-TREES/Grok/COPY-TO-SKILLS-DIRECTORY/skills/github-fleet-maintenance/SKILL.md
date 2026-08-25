---
name: github-fleet-maintenance
description: Upgrade many GitHub repos in one fleet pass - CI workflows, dependabot, topics, licenses, tags, releases, and security alerts applied across an owner account and verified per repo.
---

# GitHub Fleet Maintenance

Class-level workflow for "make all my repos max quality": one owner account, N repos, same upgrade applied everywhere (CI workflows, dependabot, topics/descriptions/licenses/tags/releases, security alerts), each repo verified individually. All commands assume `gh` authenticated with `workflow` scope.

## Core loop (per fleet pass)

1. **Inventory** — `gh api --paginate "user/repos?per_page=100&type=owner"` → dump RAW JSON to a file, flatten page arrays in Python. Never trust `--paginate --jq` merging (it doesn't merge pages).
2. **Parallel audit** — one Python script, `concurrent.futures.ThreadPoolExecutor(max_workers=10)`, checking per repo: workflows present + last run conclusion, description, topics count, license, releases vs tags, `.github/dependabot.yml`, open dependabot/code-scanning/secret-scanning alerts. Print only gaps.
3. **Fix gaps** — batch edits through the API (see below); ask the user 3–4 decision questions FIRST when defaults are ambiguous (forks included? which license? branch protection?). Record answers; they apply fleet-wide.
4. **Verify per repo** — every new workflow must produce a terminal-green run on the default branch before declaring done. Pending is not success. CodeQL/security alerts close minutes AFTER CI goes green — re-query alert counts at the end.
5. **Report honestly** — per-repo table: green / intentionally-CI-less (say why) / known limitation (e.g. `continue-on-error` job with root cause).

## Editing repos WITHOUT cloning (preferred for small batches)

Use the git data API as ONE atomic commit per repo (no clone, no pull race):

```
GET git/refs/heads/<default_branch>          # head sha (check .default_branch first — not always main!)
GET git/commits/<head>                       # base tree sha
POST git/blobs   {content: b64, encoding:"base64"}        # per changed file
POST git/trees   {base_tree, tree:[{path,mode:"100644",type:"blob",sha}]}
POST git/commits {message, tree, parents:[head]}
PATCH git/refs/heads/<branch> {sha, force:false}
```

**Pitfalls (all hit in practice):**
- Every POST/PATCH needs BOTH `-X METHOD` AND `--input -`; piping stdin without `--input -` sends no body → misleading 404/422.
- Default branch varies per repo (`main`, `master`, `develop`). Read it from `repos/{owner}/{repo}`; don't guess.
- Verify after push: `gh run list -R owner/repo --limit 1` shows the new SHA going terminal-green.

## Manifest hash-gates

Some of the user's repos (SkyrimForge, Ultimate-AI-Starter-Bundle) gate tracked files against `MANIFEST.json` `{path, sha256, size}` entries (shape differs: dict-with-`files` vs bare list — handle both). ANY edit to gated files (including Dependabot bumps under `.github/`) MUST resync matching entries in the same commit or CI fails by design. Flow: fetch manifest → update entries for changed paths with fresh sha256/size → commit manifest together with the files. This failing mid-session is PROOF the gate works — fix forward, never disable.

## Dependabot fleet rollout

- After adding `.github/dependabot.yml` configs (ecosystems per repo language; group codeql-action bumps), Dependabot opens PRs within ~30 min. Merge policy: squash-merge ONLY when the PR's own checks are terminal-green; if `BEHIND`/conflicts, comment `@dependabot rebase`, wait, re-check. Never force-close.
- **Guard-test trap:** repos whose tests assert exact action versions (`setup-python@v5`) go red on major bumps. Fix the test to match intent (assert action NAME, not version) in a separate main commit, then `@dependabot rebase` the PR.
- Merging workflow-file bumps into manifest-gated repos trips the hash gate — resync manifests right after merges and watch CI.

## Security alerts cleanup

Sweep all three kinds: `repos/{o}/{r}/dependabot/alerts?state=open`, `/code-scanning/alerts?state=open`, `/secret-scanning/alerts?state=open`. Code-scanning location fields live at `.most_recent_instance.location.{path,start_line}` (shortcut fields return null on list endpoints).

**ReDoS in PowerShell string regexes (CodeQL py/redos)** — vulnerable shape `` r'"(?:`.|[^"\r\n])*"' ``: backtick matches BOTH alternation branches → exponential backtracking. Correct fix makes branches DISJOINT by excluding the backtick from the class: `` r'"(?:[^"`\r\n]|`.)*"' ``. Two failed shortcuts to never repeat:
1. Reordering alternation alone is NOT enough — `` [^"\r\n] `` still admits the backtick; CodeQL re-flags and it stays exponential on unterminated strings.
2. When transforming regex source text programmatically, compile-check EVERY extracted pattern locally (ast-walk string constants → `re.compile`) BEFORE pushing. A swap that drops the closing paren passes grep-diff review and explodes at runtime in CI.
Also more semantically correct afterward: backtick-quote before a closing quote means unterminated string in real PowerShell.

## Adding CI to repos (templates)

- C++/CMake/vcpkg template: see `templates/ci-cpp-vcpkg.yml`; static HTML sites: tidy validation + lychee link check, single ubuntu job.
- Before writing any workflow, READ the repo first: build system (xmake? cmake presets?), dependency fetch mechanism (vendored path? submodule?), hardcoded dev-machine paths (common failure: absolute path to a framework on the author's PC — replace with an explicit checkout + `-D<VAR>` cache flag).
- Submodule stale/pinned too old: bump pointer via trees API (nested subtrees need recursive walk: find parent tree id, PUT new subtree with updated entry, then root tree with new parent).
- Upstream-incompatible source (compiles nowhere): do NOT fake green. Mark that job `continue-on-error: true`, keep healthy jobs required, state the root cause in the report.
- Forks often have Actions disabled or upstream workflows lacking `workflow_dispatch` — can't dispatch remotely without editing an upstream-tracked file; let the next push/PR trigger runs instead.

## Version tags & releases

Derive versions from project metadata (CMakeLists `project(... VERSION x.y.z)` — beware grabbing `cmake_minimum_required(VERSION ...)` instead). Create annotated tag + release with `generate_release_notes`. Wrong tag created: delete BOTH the release (by ID, not tag) and the ref before recreating (`DELETE repos/{o}/{r}/releases/{id}`, then `DELETE git/refs/tags/<tag>`).
