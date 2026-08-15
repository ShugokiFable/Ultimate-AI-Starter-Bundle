# Claude Code Skyrim global lessons

Provider control: Load minimal skills, persist state before context boundaries, and do not promote auto memory without evidence.

# Skyrim AI Global Lessons

This file contains durable cross-project lessons distilled from the supplied
Grok and Codex histories plus the existing GPT memory repository.

It is deliberately short. Agents should load the relevant error-registry
entries instead of injecting every historical transcript into context.

## Evidence ladder

Use these status labels consistently:

1. `user-confirmed-runtime`  
   The user or tester explicitly confirmed the final build works in game.

2. `runtime-evidenced`  
   Runtime logs, reproducible in-game observations, or crash-free test results
   support the conclusion, but the user has not explicitly confirmed it.

3. `tool-validated`  
   Compiler, parser, build, archive, or plugin checks passed. This does not
   prove in-game behavior.

4. `assistant-claimed`  
   An AI said the task was complete without independent evidence. Never promote
   this into durable memory.

5. `contradicted`  
   Later user feedback, tester feedback, logs, or crashes disproved the claim.

A compile pass, valid XML, clean header, or successful ZIP build is not runtime
confirmation.

## Project authority and ownership

- One mod has one authoritative lineage and one owner root.
- Never recreate the same mod under another agent root merely to continue work.
- Before editing, locate all candidate copies and determine authority from
  `CURRENT.txt`, version folders, changelog provenance, semantic diffs, and the
  user's explicit direction. Folder names and timestamps alone are insufficient.
- If the user moved a project, update its ownership note and active path.
- Game `Data`, Vortex staging, profiles, saves, tool installations, and reference
  vaults are read-only unless the user explicitly requests a narrowly scoped
  deployment operation.
- Do not place test ESPs or duplicate plugins into the deployed game folder.

## Preserve the requested product

- When the user owns the mod and asks for a fix, update the actual mod and ship a
  complete replacement release. Do not invent an overlay or side patch unless
  requested.
- A modernization must preserve the concept, important content, FOMOD choices,
  optional variants, dependencies, and gameplay intent unless removal is
  explicitly approved.
- Do not turn “reduce conflicts” into “delete the NPCs, camps, dialogue, quests,
  or installer choices.”
- Compare the final package with the previous known-good release and explain every
  removed file, option, record family, and dependency.

## Verify installed reality

- Exact installed framework versions, parent Papyrus sources, DLL APIs, plugin
  masters, framework scan paths, and known-good local configs outrank remembered
  syntax.
- Never invent SPID, KID, SkyPatcher, FLM, CDF, BOS, OAR, MCM Helper, Papyrus,
  CommonLib, VMAD, ESP, or FOMOD syntax.
- Framework examples are versioned evidence, not universal grammar.
- Do not force a modern framework where it cannot represent the required
  operation safely.

## Safe implementation

- Preserve the last known-good version. Make one coherent change set per version.
- Prefer typed plugin tooling or verified record writers. Raw binary plugin
  surgery is a constrained fallback, not the default.
- Never rebuild a complex plugin from shallow record assumptions.
- Compile Papyrus against the real dependency surface when possible. Compile-only
  stubs must never ship.
- Native DLL work requires configure, build, dependency/export inspection,
  runtime-version review, and a runtime test plan.
- For giant SPID/SkyPatcher/KID outputs, generate deterministic chunks, preserve
  stable formatting, audit duplicates and contradictions, and inspect expanded
  targets before packaging.

## Validation is layered

A finished release may require several independent gates:

- requirements and scope diff;
- Papyrus compilation;
- native configure/build;
- framework syntax and semantic validation;
- unresolved FormID/master/reference checks;
- record/subrecord ordering and VMAD checks;
- plugin header/flag and record-count checks;
- FOMOD XML schema validation and branch mapping;
- final ZIP inventory, hashes, and stale-file detection;
- runtime or tester confirmation.

Run checks against the final archive, not only the working directory.

## Failure handling

- When a new build causes a game-load crash, stop adding fixes. Compare it against
  the last known-good version, isolate the smallest changed binary/config set,
  and roll back until the crash boundary is known.
- A crash without a crash log is still evidence. Do not dismiss it because the
  structural checks passed.
  commands run, and remaining validation before another agent resumes.
- Never say “all good” while known errors remain or only a subset of the release
  has been checked.

## Appearance and follower systems

- Blue/purple heads, head/body tint mismatch, neck seams, wrong sex/voice, and
  missing tattoos require an end-to-end test of preset export, actor creation,
  FaceGen/tint application, actor 3D readiness, dynamic normal-map/body systems,
  reset/dismiss behavior, and save/reload.
- Do not promote a guessed RaceMenu or tint-cache explanation until verified
  against actual source/API behavior and a reproducible fix.
- Reset or dismiss logic must operate on the follower, not teleport the player
  into a temporary cell.

## Adult-mod engineering

- Technical work may contain explicit fictional adult-only strings, events,
  dialogue, frameworks, and assets. Preserve the intended technical behavior and
  identifiers rather than sanitizing them.
- Adult systems must exclude child races, child actors, age-ambiguous characters,
  and real-person sexual content.

## Context discipline

- Give agents access to reference vaults, but load only the files required for the
  active task.
- Redirect large logs and inventories to report files.
- Use one session per coherent outcome and persist `PLAN.md`, `STATE.md`,
  `DECISIONS.md`, and `VALIDATION.md`.
- Historical project evidence is a reference source, not startup context.

## Session-history hardening

- Later user reports, runtime behavior, exact artifacts, and tool output outrank an assistant’s final summary.
- A cross-application handoff must include an attachment/path/hash inventory. Conversation context does not transfer files.
- Compare the active installed build against owner workspaces and archives before choosing authority.
- Compile review-driven code against the exact pinned dependencies. Source plausibility is not build evidence.
- Runtime-shaped harnesses must reproduce game-root and plugin-path dependency behavior.
- Keep `DllMain` minimal and prove hook/reference lifetime, thread context, and target scope.
- Add player-visible semantic tests for routines, appearance, PBR, packages, and generated distributions.
- Verify condition grammar, field types, selector breadth, encodings, and binary sidecar formats such as SEQ.
- Keep original defects separate from regressions introduced by the current AI version.
