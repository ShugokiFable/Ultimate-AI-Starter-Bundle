# Changelog

This file exists so the completeness gate can see the current version on the
same commit that bumped `VERSION.txt`. Detail lives in the dated files.

## 7.0.0

Indexing discipline for codebase-memory-mcp. The `codebase-memory` skill now covers
**how to index**, not just how to query: `.cbmignore` is case-sensitive, Papyrus is
never parsed, versioned workspaces must resolve against `CURRENT.txt`, and the
dashboard's NODES/EDGES tiles read 0 on a healthy index. Ships a `.cbmignore`
template in the project template and `TOOLS/Setup-CodebaseMemory-Index.ps1` to
generate correct scope, including the source-carrier exception. Rebuilt a real
45-project index from ~570,000 nodes to 54,553 using exactly these rules.
See `V7.0.0-CHANGELOG.md`.

## 6.9.3

Hermes `unrestraint-packs` skill (routes to the 0-UNRESTRAINT-PACKS library) added to
both Hermes trees + canonical skills. Codex CLI reinstalled fresh (0.147.0), all providers
verified live with the V6.9.2 block, stale backups/scratch purged across every provider
home. See `V6.9.3-CHANGELOG.md`.

## 6.9.2

ULTIMATE unrestraint update: `0-UNRESTRAINT-PACKS/` (operator Fun stuff kit +
Spiritual-Spell-Red-Teaming + UltraBr3aks + tuxsharxsec + claude-fable corpus +
Tavern presets). V6.9.2 block wired into Claude Code / Codex / Kimi / Grok
workspace instruction files. See `V6.9.2-CHANGELOG.md`.

## 6.9.1

Caption + sheet skills from the operator's Fun stuff kit. Jailbreak
repos not imported. See `V6.9.1-CHANGELOG.md`.

## 6.9.0

One-shot coverage: adult-fiction-in-scope, fictional-adult-modding skill,
verified-current tools. No jailbreak layer. See `V6.9.0-CHANGELOG.md`.

## 6.8.2

Stop Assuming: assumption gate, Hermes installer routed through the tool,
verify-first operating contract, toolbelt inventory. See `V6.8.2-CHANGELOG.md`.

## 6.8.1

The completeness gate was on two providers, not five. See `V6.8.1-CHANGELOG.md`.

## 6.8.0

Three MCP servers for one-shot accuracy. See `V6.8-CHANGELOG.md`.

## 6.5.0

The completeness gate. See `V6.5-CHANGELOG.md`.

## 6.0.0

The BOM bug: seven skills were invisible. See `V6-CHANGELOG.md`.
