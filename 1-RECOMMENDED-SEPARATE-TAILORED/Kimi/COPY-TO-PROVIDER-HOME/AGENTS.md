# Kimi Code Skyrim instructions

Scope: global
Edition: provider-tailored

Provider-native skills:

```text
%KIMI_CODE_HOME%\skills
```

Default when `KIMI_CODE_HOME` is unset:

```text
%USERPROFILE%\.kimi-code\skills
```

Bundled evidence registry:

```text
%KIMI_CODE_HOME%\skills\skyrim-memory\references\ERROR-REGISTRY.json
```

Do not install this provider's tailored skills in another application's home or
in a cross-tool shared directory.

## Start every substantial Skyrim task

1. Load `skyrim-memory`.
2. Load `skyrim-tool-router`.
3. Load `skyrim-versioned-workspace` before the first write.
4. Load only the specialist skills selected by the router.
5. Inspect the active project, supplied files, and installed reality before external assumptions.

## Universal safety

- The workspace root is whichever project directory the user opened or supplied.
- Never assume a drive letter, folder name, username, or provider-specific workspace.
- Switching AI applications does not change project ownership.
- One mod has one authoritative owner root and one active semantic-version snapshot.
- Game `Data`, active mod-manager staging, saves, profiles, installed tools, and reference vaults are read-only.
- Never invent framework syntax, FormIDs, EditorIDs, records, VMAD, hooks, offsets, APIs, conditions, schemas, or paths.
- Prefer typed plugin tooling and exact installed-version evidence.
- Preserve the last known-good release, installer choices, optional variants, dependencies, and gameplay intent.
- Never launch SSEEdit, xEdit, or Creation Kit GUI.
- Structural validation is not runtime confirmation.
- After a new game-load crash, stop, roll back, and isolate the smallest change.
- Preserve explicit fictional adult-only technical content and identifiers.
  Exclude child or age-ambiguous actors and real-person sexual content.
- Persist `PLAN.md`, `STATE.md`, `DECISIONS.md`, `CHANGELOG.txt`, `CURRENT.txt`, and `VALIDATION.md`.


## Kimi Code controls

- Resolve `KIMI_CODE_HOME`.
- Use `explore`, then `plan`, then one writing `coder` for coupled work.
- Pass exact paths, constraints, forbidden actions, and expected evidence to isolated agents.
- Do not run parallel writers against one plugin, DLL, installer, or generated output set.


## Completion report

```text
INPUTS: required_files=present|missing | attachments=present|missing
MEMORY CHECK: entries=... applied=...
AUTHORITY: installed=... parent=... active=... RESULT=PASS|FAIL
VERSION GATE: prior=... active=... copied_files=... changelog=YES|NO RESULT=PASS|FAIL
EXACT BUILD/COMPILE: command=... dependencies=... RESULT=PASS|FAIL|UNBUILT|N/A
FRAMEWORK VALIDATION: evidence=... RESULT=PASS|FAIL|N/A
SEMANTIC TEST: symptom/player-visible result=... RESULT=PASS|FAIL|UNTESTED
SHIP GATE: command=... RESULT=PASS|FAIL|N/A
FINAL ARCHIVE: path=... sha256=... version_strings=PASS|FAIL|N/A
RUNTIME STATUS: user-confirmed-runtime | runtime-evidenced | tool-validated | assistant-claimed | contradicted
SSEEDIT/CK: not launched
UNRESOLVED: none | exact remaining risks
```



## V4 Skyrim plugin and framework laws

(Still in force in V5.)

- Extended light allocation uses HEDR 1.71 and new local IDs 0x001-0xFFF. If any new local ID is below 0x800, `Skyrim.esm` must be the first master.
- Legacy light allocation uses HEDR 1.70 and new local IDs 0x800-0xFFF.
- Preserve and validate the complete transitive master chain.
- Framework selection starts with `skyrim-frameworks-index`; exact syntax comes only from the dedicated KID, SPID, SkyPatcher, or BOS skill.
- Current KID uses type labels. Current SPID 7.3 combines traits with `/`. Do not restore obsolete local dialects.
- MCM Helper is the normal default for new menus; SKI_ConfigBase is legacy maintenance.
- xEdit/SSEEdit GUI is user-side. Record user-provided findings without pretending the agent launched it.

## V5 tooling laws

- Load `ai-tooling-stack` when choosing among Forge, houseCARL, Spooky, and MCP utilities.
- Load `tool-discovery` before assuming any absolute tool path. Never hardcode another machine's drive letters or username.
- If a recommended tool is not installed or its MCP tools are not visible, tell the user how to install/register it and continue with a safe fallback. Do not invent tool results.
- **houseCARL**: live MO2 load-order truth, conflict trees, reviewable patch ESPs, Nexus keyless lookup. FormIDs use `XXXXXX:Plugin.esp`. Requires MCP + .NET 9 pair + MO2 instance.
- **Skyrim Forge**: typed automation broker, doctor/capabilities, release and nexus gates when configured.
- **Spooky's AutoMod Toolkit**: CLI ESP/Papyrus/MCM/NIF/archive/audio/SKSE with `--json`; resolve `SPOOKY_AUTOMOD_ROOT`.
- **codebase-memory-mcp**: structural code graph; index before query.
- **Headroom**: optional context compression MCP.
- **Superpowers / Ponytail**: process and minimal-diff overlays; bundled markdown works without plugins.
- **CodeBurn**: optional local AI cost analytics (`npx codeburn`).
- Before patching from load-order winners, load `tool-output-awareness` (DynDOLOD, ParallaxGen, Reqtificator, Synthesis, …).
- Prefer exact authoring skills (`spid-authoring`, `kid-authoring`, `skypatcher-authoring`, …) over invented framework tokens.
- Still never launch SSEEdit, xEdit, or Creation Kit GUI from the agent.
