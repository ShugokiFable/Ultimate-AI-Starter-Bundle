# V5 integration audit

## Sources integrated

| Source | How integrated |
|---|---|
| V4.3.0 final manual pack | Full tree base copy |
| houseCARL product skills (agent/.agents) | Copied authoring + reference skills; multi-provider notes appended |
| Spooky toolkit v1.11.2 `.claude/skills` + llm docs | Module skills + `spookys-automod-toolkit` references |
| codebase-memory-mcp skill + Fix-Grok script | Skill + portable TOOLS script |
| Headroom (headroomlabs-ai) | Skill documenting MCP compress/retrieve + pip install |
| Superpowers (obra/superpowers) | Full skill family bundled |
| Ponytail (DietrichGebert/ponytail) | Full skill family bundled |
| CodeBurn (getagentseal/codeburn) | Skill + npx install guidance |
| Skyrim Forge live skill | Copied without per-machine INSTALLATION.json |

## Portability checks

- [x] No requirement that tools live on `S:\` or `Z:\`
- [x] Discovery script uses env vars, LOCALAPPDATA, PATH, optional shallow Apps scan
- [x] Missing tool response template in `tool-discovery`
- [x] Grok codebase-memory fix uses `%LOCALAPPDATA%` / `-ExePath`
- [x] MCP examples use `YOU` placeholders

## Provider fan-out

| Edition | Providers | Skills/dir |
|---|---|---|
| 1-RECOMMENDED-SEPARATE-TAILORED | Claude, Codex, Grok, Hermes, Kimi | 82 |
| 2-OPTIONAL-SHARED-GENERIC | Claude, Codex, Grok, Hermes, Kimi | 82 |

## Behavioral contract for all AIs

1. Discover before assuming paths.
2. Recommend install with verify command when missing.
3. Never fake houseCARL/Forge/MCP results.
4. Keep V4 safety: no xEdit/CK GUI launch, no live Data writes, versioned workspace, evidence ladder.
5. Use `tool-output-awareness` before freezing generated winners into patches.

## Known residual risks

- houseCARL MCP tool names evolve with product version — skill describes workflow, not a frozen RPC dump of all 45 tools.
- Spooky CLI flags may drift after 1.11.2 — agents should run `--help` and read bundled references.
- codebase-memory first index can be slow; Grok needs high startup_timeout_sec.
- Plugin-only UX (slash commands) still better with official plugin installs on Claude.

## Validation performed while building

- Base robocopy from v4.3.0 succeeded.
- Canonical skill inventory had no empty required skills after authoring.
- Fan-out produced 82 directories per provider root (10 roots).
- Routers updated count: 10.
- Instruction files updated count: 18.

Runtime MCP connectivity on end-user machines is **not** claimed by this pack alone.

## houseCARL auto-setup (add-on)

- Script: `TOOLS/Setup-HouseCarl.ps1`
- PDF reference bundled: `TOOLS/housecarl/houseCARL-Vortex-shim-setup.pdf`
- Live test on author machine: Vortex staging (~3001 mods) → shim at `%LOCALAPPDATA%\houseCARL-Shim` **PASS**
- Grok MCP `[mcp_servers.housecarl]` written **PASS**
- Env `HouseCarl__Mo2InstanceDir` set **PASS**
- Skills updated with auto-setup contract (housecarl, tool-discovery, ai-tooling-stack)


## AIO installer layer

- `INSTALL-V6-AIO.ps1` / `.bat` smoke: SkillsOnly Grok **PASS**
- Offline bundle hashes in `BUNDLED-TOOLS/OFFLINE-MANIFEST.json`
- GitHub latest via `TOOLS/Update-From-GitHub.ps1`
- Scripts parse clean after ASCII sanitize **PASS**
