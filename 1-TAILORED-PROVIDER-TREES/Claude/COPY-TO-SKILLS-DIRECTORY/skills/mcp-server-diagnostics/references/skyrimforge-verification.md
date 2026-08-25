# SkyrimForge audit & verification (live install vs repo)

Repo: github.com/ShugokiFable/SkyrimForge. The live install folder
(e.g. `S:\Apps\Skyrim Tools\Skyrim-Forge-5.1.6`) is the **extracted product —
NOT a git repo**. The repo is source of truth.

## Verify local install matches the release tag
```bash
cd "$TMP" && git clone --quiet https://github.com/ShugokiFable/SkyrimForge.git clone
cd clone
git rev-parse main v5.1.6                # same sha = tag cut at main tip
git diff --stat main v5.1.6 | tail -1    # empty = identical trees
git merge-base --is-ancestor v5.1.6 main # empty = clean ancestor
git worktree add /tmp/forge-tag v5.1.6   # GOTCHA: lands at C:/tmp/forge-tag
                                         # (git resolves /tmp natively in git-bash;
                                         #  `ls /tmp/forge-tag` FAILS, `git worktree list` shows truth)
```
Diff live install vs the worktree, excluding machine-state files:
```bash
diff -rq --exclude='.venv' --exclude='__pycache__' --exclude='INSTALLATION.json' \
  --exclude='REPORTS' --exclude='.git' --exclude='skyrim_forge_local.pth' \
  --exclude='MANIFEST.json' --exclude='VALIDATION.json' --exclude='BUILD-RECEIPT.json' \
  --exclude='SBOM.spdx.json' --exclude='SHA256SUMS.txt' --exclude='CHECKSUMS-SHA256.txt' \
  "S:/Apps/Skyrim Tools/Skyrim-Forge-5.1.6" "C:/tmp/forge-tag"
```
Expected: only `Workspaces/` (user job staging) differs. Any other diff = drift.

## Fresh-install audit checklist (bug classes to hunt)
- MCP registration is **self-healing by design**: `Register-MCP.ps1` re-writes every
  provider config from `$PSScriptRoot` live paths — a moved install just needs a
  re-run, not path surgery.
- Provider skill copies carry a baked `INSTALLATION.json` descriptor;
  `Install-Forge-Skill.ps1` refreshes it on every run (staged copy + rollback +
  reparse-point guards). Verify all 5: `~/.claude/skills`, `~/.codex/skills`,
  `~/.grok/skills`, `~/.kimi-code/skills`, `%LOCALAPPDATA%\hermes\skills`.
- Env overrides honored: `CODEX_HOME`, `CLAUDE_CONFIG_DIR`, `GROK_HOME`,
  `KIMI_CODE_HOME`, `HERMES_HOME`.
- Grok cliff: max 8 running MCP servers — Register-MCP skips Forge for Grok at 7
  configured (or 6 while `mcp-search` loads). Replacing an existing entry is allowed.
- Claude 2026-07-28 schema: Forge 5.1.5+ emits `resultType:"complete"`; 5.1.4 is
  unusable with Claude Code — never let fresh installs land on 5.1.4.

## Verify live health
```bash
.venv/Scripts/python.exe -m compileall -q skyrim_forge tests scripts
.venv/Scripts/python.exe -m unittest discover -s tests     # expect OK (157)
.venv/Scripts/python.exe -m skyrim_forge self-test          # expect PASS
writer/published/win-x64/SkyrimForge.Native.exe self-test   # expect PASS
powershell -NoProfile -ExecutionPolicy Bypass -File PowerShell-Parse-Gate.ps1  # PASS (9 scripts)
```

## Stale report pitfall
`REPORTS\ai-integration.json` can survive from an older version folder — root still
pointing at `Skyrim-Forge-5.1.5`, providers marked FAILED/NOT_INSTALLED that are
actually fine. Dead paths in reports are the confusion class users hate; regenerate
honestly: `powershell -NoProfile -ExecutionPolicy Bypass -File Register-MCP.ps1
-Provider All -Yes`. The Hermes branch is **idempotent** (remove/add/test with
byte-exact config restore on failure) and only manages the `skyrim-forge` entry —
safe to run even when the user is handling hermes config themselves.

## NOT_INSTALLED ≠ broken
Register-MCP reports `Claude: NOT_INSTALLED` when the `claude` binary can't be
resolved (`Get-Command` fallthrough). Before concluding misconfiguration, check the
binary actually exists: `which claude`, `npm root -g` contents, WinGet Links dir. A
scaffolded `~/.claude` tree (skills/plugins/config present) **without the CLI** is
genuine machine state — the resolver is correct to refuse to guess, and the existing
`~/.claude.json` entry is still valid for whenever the CLI gets installed.
