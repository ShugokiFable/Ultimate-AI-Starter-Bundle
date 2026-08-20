# Validation

## 5.2.0 layout and Grok cliff

- Default workspace follows `SKYRIM_FORGE_ROOT\Workspaces`; empty
  `Documents\Skyrim Forge\Workspaces` migrates. Installer registers
  `SKYRIM_FORGE_ROOT` before `config-show`.
- `Register-MCP.ps1` contains `Test-GrokForgeRegistrationAllowed` and skips a
  new Grok add at the 8-running cliff.
- Claude `resultType` contract is unchanged from 5.1.5.

## Current results

- Source regression suite: PASS, 155 tests.
- Full repository validator, `--scope full`: PASS with zero errors.
- PowerShell parser gate and exact START-HERE startup probe: PASS.
- Exact native build: PASS with pinned Go 1.23.2 for Windows x64 and Linux x64.
  Two-build reproducibility PASS; packaged and published helpers hash-equal;
  the rebuilt helper reports `SkyrimForge.Native 5.1.3 go` and self-tests PASS.
- Go format, vet, tests and race test: PASS.
- Wheel and source distribution builds: PASS and deterministic.
- MCP static surface: 52 tools, 19 resources, 7 prompts.
- MCP dual-era smoke against the real stdio server: PASS.
  - `server/discover` returns the supported version list, capabilities and
    `serverInfo`, with `resultType: "complete"` and caching hints.
  - A modern `tools/list` carries the mandatory caching hints.
  - An unknown version is refused with code `-32022` and the supported list.
  - The `initialize` handshake still negotiates `2025-11-25`.
  - A legacy inventory result carries none of `resultType`, `ttlMs`, `cacheScope`.
  - `tools/call` carries `resultType: "complete"` with and without `_meta`.
  - Both eras return an identical 52-tool inventory.

## MCP resultType hotfix (5.1.5)

- Reproduced against the 5.1.4 stdio server: modern `tools/list` included
  `resultType`; `tools/call` for `forge_version` did not, with or without
  `_meta`. That is the exact Claude Code schema failure.
- After the fix, the same two `tools/call` payloads return
  `resultType: "complete"` and no caching hints.
- Version source gate: PASS. Eight restatements agree with
  `skyrim_forge/version.py`, and neither the workflow nor the archive builder
  hardcodes a version.
- Distributed integrity: PASS. All 215 manifest entries verify against the tree
  as checked out, and every file declared `eol=crlf` has CRLF endings on disk.
- Skyrim runtime test: UNTESTED. Static validation does not prove gameplay or
  third-party GUI behavior.

## AI bridge fixes (5.1.1)

- `forge_papyrus_compile` was present in `tools/list` but missing from the MCP
  dispatcher. A real MCP request now reaches the service and has a dedicated
  regression.
- Kimi registration preserves unrelated MCP servers, writes the exact shared
  Forge Python command, and runs `kimi doctor`. If doctor fails, the prior
  configuration is restored byte-for-byte. Array-shaped server maps are
  rejected without changing the file.
- Hermes registration uses its supported `mcp add` and `mcp test` commands;
  failed add/test sequences restore the prior configuration byte-for-byte.
- Hermes skill discovery defaults to `%LOCALAPPDATA%\hermes`; explicit
  `HERMES_HOME` still wins.
- Windows integration tests execute the real Forge PowerShell scripts against
  isolated provider homes and controlled client command surfaces. They do not
  mutate the user's live AI configuration.
- Read-only live audit: Codex, Grok, and Kimi have enabled entries for the exact
  installed 5.1.0 Python/MCP command. Hermes is installed but has no Forge MCP
  entry. Claude is not installed. Slash-style differences in Grok/Kimi paths
  were normalized before comparison.

## Hermes registrar hotfix (5.1.2)

- Hermes requires confirmation before enabling discovered Forge tools. Cancelling
  that prompt returns exit code zero, so Forge now supplies the explicit `Y`.
- A missing Hermes server also returns exit code zero. Forge now requires the
  actual connection/tool-discovery text before it reports `READY`.

## Release automation hotfix (5.1.3)

- The v5.1.2 tag workflow failed only at publication because the public release
  already existed. The release workflow now creates a missing release or
  refreshes an existing release's assets with `--clobber`.
- A regression requires both publication branches so a retry cannot regress to
  duplicate-release failure.
- The installed 5.1.2 venv launcher was present but could not execute because
  its base interpreter was missing. The installer now treats execution as the
  health gate and reconstructs only the exact non-reparse-point `.venv`.

## Reproducing the release gate

Report files hash the tree they ship with, so a source change makes the shipped
manifest stale by definition. Run the validator twice: the first pass rewrites
the reports, the second pass is the gate that must return PASS.

```text
python scripts/validate_repository.py --scope full --write-reports
python scripts/validate_repository.py --scope full --write-reports
```

## FOMOD false positives (5.0.1)

Each case below is legal per the published `ModConfig5.0.xsd` and was rejected
before 5.0.1. Evidence: fixtures built directly from the schema, run against
`validate_fomod`, failing before the fix and passing after.

| Case | Before | After |
|---|---|---|
| Option carrying an `<image>` | FAIL "must contain files or conditionFlags in ModuleConfig 5.0 order" | PASS |
| `xsi:noNamespaceSchemaLocation` omitted | FAIL "must use the canonical schema-location token" | PASS + warning |
| Schema location spelled with `https` | FAIL | PASS, no comment |
| `foseDependency` | FAIL "Unsupported dependency element" | PASS + unverified warning |

The first is the significant one: the schema sequence is `description, image?,
(files, conditionFlags? | conditionFlags, files?), typeDescriptor`, and the
optional image was not allowed for, so any option with a screenshot was refused.

Verified not to be false positives, and left strict: unreferenced payload under
`strict_coverage`, missing source paths, ambiguous destination collisions,
undefined and temporally-unavailable condition flags, path traversal, and C#
scripted installers. Images referenced by `path=` outside `fomod/` were already
counted as covered.

## What this release fixed, and how it was proven

- **Modern MCP clients could not connect.** Proven by the server advertising
  only `2025-11-25`, `2025-06-18` and `2024-11-05`. Now proven fixed by a live
  stdio exchange covering discovery, negotiation, refusal and both eras.
- **`MANIFEST.json` did not verify in a clone.** Reproduced in a clean clone:
  five files (`Install-AI-Bridge.ps1`, `Install-Forge-Skill.ps1`,
  `Install-or-Update.ps1`, `Register-MCP.ps1`, `START-HERE.bat`) hashed
  differently because `.gitattributes` declares `eol=crlf` for them while the
  manifest recorded LF bytes. Now regenerated from the checked-out tree and
  gated by a regression that hashes every manifest entry.
- **CodeQL failed on every Dependabot branch.** Root cause was not permissions:
  `init` and `analyze` were bumped in separate pull requests, so they ran
  different releases and the scan died with "Loaded a configuration file for
  version '4.37.6', but running version '4.36.0'". Both are now pinned to one
  revision, Dependabot groups the pair, and a regression fails if they diverge.

## Evidence boundary

The release is tool-validated. Skyrim gameplay, save behavior, third-party GUI
automation, and visual results remain untested runtime gates.

The modern MCP era is validated against Forge's own stdio server and the
published specification, not against a shipped AI client, because no installed
client speaks `2026-07-28` yet. The legacy era remains the path every currently
registered client uses, and it is unchanged.

The Windows scripts and provider registration paths were exercised in isolated
homes. Live provider configurations were audited but not repointed to this
workspace candidate. GitHub CI and actual client restarts remain publication
and deployment gates.
