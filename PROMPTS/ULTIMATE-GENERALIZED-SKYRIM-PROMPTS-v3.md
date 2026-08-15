# How to Use This Prompt Library

Each reusable prompt is a top-level `#` heading so it appears clearly in the Visual Studio Code Markdown outline.

Replace text inside square brackets such as `[DESCRIBE THE MOD]`. Leave the rest intact unless a project genuinely needs different rules.

These prompts assume:

- Skyrim tools: `<ToolsRoot>`
- Creation Kit: installed in the <GameRoot>
- Development manager: Vortex
- Release compatibility: Vortex and Mod Organizer 2
- Most modern Skyrim frameworks and utilities are already installed
- The Skyrim Forge Bridge or an equivalent typed, transactional tool layer should be preferred when available

Do not waste output repeating generic permissions or licensing explanations. Assume those are handled by the supplied skills and project context unless a specific file presents a concrete problem.

Never include my personal name, Windows username, email address, account names, private repository details, API keys, tokens, machine identifiers, unrelated personal files, or sensitive absolute paths in generated mods, documentation, logs, screenshots, metadata, source comments, archives, or release notes. Replace private paths with neutral placeholders such as `<SkyrimRoot>`, `<ToolsRoot>`, `<Workspace>`, or `<OutputMod>`.

---


### V4 plugin master and framework gate

- Legacy light mode: HEDR 1.70, ESL flag 0x200, new local IDs 0x800-0xFFF.
- Extended light mode: HEDR 1.71, new local IDs 0x001-0xFFF.
- When any new local ID below 0x800 is used, `Skyrim.esm` must be the first master.
- Validate the complete transitive master chain and 1.71 dependency compatibility.
- Select frameworks with `skyrim-frameworks-index`; load the dedicated KID, SPID, SkyPatcher, or BOS syntax skill.
- Current KID uses type labels. Current SPID 7.3 combines traits with `/`.

# Prompt 1 — Build Me a New Skyrim Mod

## Prompt Info

- **Purpose:** Design and build a completely new Skyrim mod from a requested concept.
- **Use when:** I say “make me a mod that…”, “build this feature”, or provide a new mod idea.
- **Primary input:** Replace `[MOD REQUEST]`.
- **Default behavior:** Inspect first, choose the safest architecture, then build as much as the available tools allow.
- **Expected result:** A working project, source, generated files, validation report, and release-ready package when technically possible.

## Prompt

Build me this Skyrim mod:

> **[MOD REQUEST]**

Treat this as a real mod-development project, not a shallow concept pitch.

Inspect my installed Skyrim environment, relevant mods, frameworks, asset hubs, tools, APIs, and existing compatibility resources before deciding how the mod should work. Use what is already installed when it improves quality, compatibility, performance, or development speed.

### Environment

- Tools directory: `<ToolsRoot>`
- Creation Kit: <GameRoot>
- Development manager: Vortex
- Release compatibility: Vortex and Mod Organizer 2
- Assume modern frameworks are likely installed, but verify before depending on them
- Prefer verified typed tools such as Mutagen, Synthesis, Spriggit, and an optional read-only bridge when available
- Do not directly modify original installed mods or live game files

### Core objective

Turn the request into the highest-quality practical Skyrim mod you can produce.

Do not merely describe how somebody else could build it. Perform the audit, architecture, implementation, generation, validation, packaging, and documentation steps that are possible with the available tools.

When information is missing, make reasonable assumptions, record them, and continue. Ask only when a missing decision would fundamentally change the project.

### Architecture selection

Before building, determine whether the mod should be implemented as one or more of the following:

- ESP, ESL, or ESM
- SKSE plugin
- Papyrus system
- MCM Helper configuration
- SPID distribution
- KID distribution
- SkyPatcher module
- Base Object Swapper configuration
- Open Animation Replacer conditions
- Race Compatibility integration
- Synthesis or Mutagen patcher
- Python or C# generator
- Shared JSON registry
- Asset hub or adapter
- FOMOD installer
- Hybrid architecture

Choose the least conflict-heavy architecture that can represent the feature correctly.

Do not force a runtime framework into an unsupported task. Use a plugin, script, native component, generated patcher, or Creation Kit workflow where that is safer and more reliable.

### Conflict-minimization law

Avoid unnecessary direct overrides of:

- NPC records
- Race records
- Worldspaces
- Cells
- Navmeshes
- Persistent references
- Placed references
- Outfits
- Leveled lists
- Form lists
- Quests
- Dialogue
- Shared vanilla records

Prefer runtime distribution, generated patches, shared registries, new records, adapters, and narrowly scoped overrides.

When a direct override is necessary:

1. Explain why.
2. Preserve unrelated winning-record data.
3. Limit the edit to the smallest practical record set.
4. Identify affected mods and records.
5. Provide compatibility handling.
6. Validate links, masters, FormIDs, flags, assets, scripts, and save impact.

### Installed environment discovery

Search for reusable:

- Asset hubs
- Hair, eyes, brows, beards, skin, body, and head-part resources
- Race frameworks
- Skeleton and physics systems
- Animation frameworks
- Combat frameworks and styles
- Voice packs and SOSVoicePacks support
- Spell, perk, keyword, outfit, and distribution ecosystems
- MCM and UI libraries
- PapyrusUtil and JContainers
- SKSE and Address Library
- Synthesis patchers
- Mutagen libraries
- Existing compatibility patches
- Shared meshes, textures, sounds, voices, and animations
- Framework logs and installed documentation

Prefer declaring an installed mod as a requirement over copying untouched files from it.

The final output must contain only files newly created or legitimately changed for this project, plus generated output that belongs to the new mod.

### Safety and workspace rules

- Work inside a dedicated project workspace.
- Snapshot inputs before modification.
- Never overwrite the only copy of a source plugin.
- Never binary-patch plugins when a typed record API is available.
- Never run arbitrary PowerShell, shell commands, or generated xEdit scripts without a clear reason and bounded inputs.
- Use deterministic scripts and repeatable build steps.
- Keep an audit log of generated files and operations.
- Prefer semantic record diffs over binary comparisons.
- Reject unsafe automatic navmesh merging.
- Do not compact FormIDs, remove masters, change plugin flags, or mutate worldspace and quest structures without explicit validation.
- Do not claim an operation succeeded unless its output exists and passes the relevant checks.

### Privacy rules

Do not include:

- My personal name
- Windows username
- Email addresses
- API keys or tokens
- Private account names
- Machine identifiers
- Private repository information
- Unrelated files discovered during scans
- Personal absolute paths in release content
- Vortex staging metadata
- MO2 `meta.ini` or archive `.meta` sidecars

Sanitize generated logs and documentation. Replace private paths with neutral placeholders.

### Implementation workflow

#### Phase 1: Audit

- Inspect relevant installed mods and tools.
- Identify required records, assets, scripts, frameworks, and integrations.
- Identify conflict-heavy approaches to avoid.
- Identify technical limitations.
- Identify save-compatibility risks.
- Identify Vortex and MO2 packaging risks.

#### Phase 2: Design

Produce a concrete architecture containing:

- Feature breakdown
- Data model
- Framework routing
- Plugin and script structure
- Configuration structure
- Integration points
- Required records
- Avoided overrides
- Compatibility strategy
- Build pipeline
- Validation strategy

#### Phase 3: Build

Create:

- Source code
- Plugin records
- Runtime configuration
- Papyrus scripts
- Native code when justified
- Patchers or generators
- Build scripts
- FOMOD when meaningful
- Documentation
- Test fixtures
- Release folder structure

Do not stop at pseudocode when working files can be produced.

#### Phase 4: Validate

Validate:

- Plugin headers and masters
- Record links
- EditorIDs and FormIDs
- ESL safety
- Missing assets
- Script properties
- Runtime configuration syntax
- Framework-specific paths
- Framework logs
- FOMOD paths and branches
- Archive root
- Vortex deployment
- MO2 virtual Data layout
- Plugin activation
- Conflict winners
- Generated output
- Upgrade and uninstall behavior

Use xEdit or SSEEdit only through a verified non-interactive workflow or as user-side validation. Do not automate the graphical interface merely to claim success.

#### Phase 5: Package

Prefer one manager-neutral release archive.

For MO2:

- Do not create or ship an MO2 manifest.
- Do not ship `meta.ini` or `.meta` sidecars.
- Ensure the archive resolves to the virtual Data root.
- Test left-pane mod activation and right-pane plugin activation.
- Review conflicts and Overwrite.

For Vortex:

- Validate deployment paths.
- Validate rules and dependencies.
- Validate FOMOD behavior.
- Ensure no Vortex-specific path is embedded in the mod.

### Requirements reporting

Separate dependencies into:

- Hard requirements
- Conditional requirements
- Optional integrations
- Development-only tools

For each dependency, state:

- Why it is used
- Which feature needs it
- Required version or compatibility range
- Whether users install it separately

Do not add dependencies merely because they are available.

### Required deliverables

Return or create:

1. Project classification and architecture
2. Assumptions
3. Requirements
4. Project folder structure
5. Source files
6. Build scripts
7. Generated plugin or configurations
8. Record-change summary
9. Compatibility strategy
10. Vortex instructions
11. MO2 instructions
12. Validation report
13. Known limitations
14. Remaining manual tests
15. Changelog
16. Release-ready archive when possible

At the end, distinguish clearly between:

- Completed and verified
- Completed but not runtime-tested
- Planned but not implemented
- Blocked by unavailable tools or required user-side testing

---

# Prompt 2 — Modernize, Patch, Rebuild, or Succeed an Existing Mod

## Prompt Info

- **Purpose:** Audit an existing mod and turn it into a modern patch, modernization, replacement, or successor.
- **Use when:** A mod is old, conflict-heavy, obsolete, unstable, or poorly integrated with a modern modpack.
- **Primary input:** Supply the original mod and describe the desired outcome.
- **Default behavior:** Prefer a patch first, but rebuild when the original architecture is the real problem.
- **Expected result:** A modernized implementation with minimal copied content and minimal conflict-heavy overrides.

## Prompt

Modernize the supplied Skyrim mod under these rules.

### Objective

Preserve the useful concept while improving:

- Compatibility
- Maintainability
- Performance
- Modpack integration
- Runtime safety
- Packaging
- Vortex support
- MO2 support
- Framework usage
- Upgrade behavior

Classify the result as one of:

- Compatibility patch
- Modernization
- Rebuild
- Replacement
- Successor
- Spiritual successor

Prefer a patch when the original mod can remain the asset or content provider.

Choose a rebuild, replacement, or successor only when the old architecture is too restrictive, broken, obsolete, or conflict-heavy to preserve cleanly.

### Modern implementation priority

Replace unnecessary direct edits with appropriate modern systems where supported:

- SPID
- KID
- SkyPatcher
- Base Object Swapper
- Race Compatibility SKSE
- MCM Helper
- PapyrusUtil
- JContainers
- SKSE and Address Library
- Open Animation Replacer
- Mutagen
- Synthesis
- Spriggit
- Shared keyword and asset ecosystems
- Generated compatibility patches

Do not force these frameworks where they cannot safely perform the operation.

### Audit requirements

Inspect:

- Plugin records and override chains
- Masters and dependencies
- Scripts and update loops
- Embedded assets
- Runtime configuration
- Worldspace and cell edits
- Navmeshes
- Leveled lists
- NPC and race overrides
- Quests and dialogue
- Broken paths
- Missing assets
- Dirty or obsolete implementation patterns
- Save compatibility
- Vortex and MO2 packaging
- Existing modern alternatives or dependencies in my modpack

### Output law

The finished mod must include only:

- New files
- Modified files
- Generated patch files
- New source
- New configuration
- New records
- New documentation

Do not include untouched files from a required source mod.

If the original remains required, list it clearly as a dependency.

If the result becomes independent, give it a distinct name and describe it accurately as a replacement or successor.

### Privacy

Do not expose my personal name, usernames, email addresses, private account details, API keys, machine identifiers, private repository information, unrelated scanned files, or personal absolute paths.

Sanitize logs and documentation.

### Workflow

1. Audit the original.
2. Identify obsolete or conflict-heavy architecture.
3. Choose patch versus rebuild.
4. Design the modern architecture.
5. Build in an isolated workspace.
6. Generate semantic diffs.
7. Validate plugin, scripts, configs, assets, and packaging.
8. Test Vortex and MO2 installation behavior.
9. Produce the final package and report.

### Required output

Return:

1. Classification
2. Executive summary
3. Original implementation problems
4. Modern architecture
5. Frameworks selected and why
6. Direct edits that remain
7. Requirements
8. Files created
9. Files deliberately excluded
10. Record-change summary
11. Compatibility matrix
12. Validation results
13. Remaining manual tests
14. Release structure
15. Upgrade and uninstall notes
16. Future extensions

Do not claim completion or compatibility without evidence.

---

# Prompt 3 — Diagnose and Fix a Broken Skyrim Mod

## Prompt Info

- **Purpose:** Find the root cause of a mod failure and produce the safest corrective patch or rebuild.
- **Use when:** A mod crashes, silently fails, produces missing assets, breaks NPCs, conflicts with a modpack, or works in one manager but not another.
- **Primary input:** Supply the mod, logs, error messages, screenshots, or reproduction steps.
- **Default behavior:** Diagnose before changing files.
- **Expected result:** Root-cause report, minimal fix, regression tests, and corrected package.

## Prompt

Diagnose and fix the supplied Skyrim mod or compatibility problem.

### Problem statement

> **[DESCRIBE THE FAILURE, EXPECTED BEHAVIOR, AND REPRODUCTION STEPS]**

Do not begin by blindly editing binaries or generating random scripts.

### Diagnostic order

1. Reproduce or model the failure.
2. Inspect logs.
3. Inspect archive and installed file layout.
4. Inspect plugin headers, masters, and override chains.
5. Inspect framework configuration paths and grammar.
6. Inspect missing assets and dependencies.
7. Inspect runtime and SKSE compatibility.
8. Inspect Vortex deployment or MO2 virtual filesystem behavior.
9. Inspect conflict winners.
10. Inspect scripts, native DLLs, and generated outputs.
11. Identify the smallest reliable fix.

### Preferred tools

Use, where available:

- Skyrim Forge Bridge
- Mutagen
- Spriggit
- Synthesis
- Framework logs
- Plugin header inspection
- Static asset scanners
- Archive inspection
- Verified xEdit CLI scripts
- User-side xEdit validation
- Creation Kit only when the record type genuinely requires it

Do not use arbitrary binary patching as the default.

### Fix strategy

Prefer, in order:

1. Correct configuration, path, or packaging error
2. Add a narrow compatibility patch
3. Replace a conflict-heavy edit with a runtime framework
4. Generate a load-order-aware patcher
5. Repair scripts or native code
6. Rebuild the broken subsystem
7. Replace the original architecture only when necessary

### Safety

- Work on copies.
- Preserve originals.
- Record every changed file.
- Produce semantic diffs.
- Do not silently remove masters.
- Do not compact FormIDs without proof.
- Do not automatically merge navmeshes.
- Do not mutate live Data, Vortex staging, or MO2 mod directories.
- Do not claim the game was tested when only static checks were performed.

### Privacy

Do not include personal names, usernames, account details, tokens, private paths, private repository data, or unrelated scanned files in the fix or its documentation.

### Required output

Return:

1. Symptom summary
2. Confirmed root cause
3. Contributing factors
4. Minimal safe fix
5. Files changed
6. Records changed
7. Why other approaches were rejected
8. Validation performed
9. Regression tests
10. Vortex and MO2 notes
11. Remaining manual checks
12. Corrected package when possible

---

# Prompt 4 — Design Modern AIO Mods and Conflict-Solving Systems

## Prompt Info

- **Purpose:** Discover large, reusable mod projects that solve recurring modpack conflicts.
- **Use when:** I want new AIOs, generators, shared frameworks, compatibility hubs, or patching ecosystems.
- **Primary input:** My installed modpack and any category I want prioritized.
- **Default behavior:** Find system-level solutions instead of proposing twenty tiny patches.
- **Expected result:** Ranked project concepts and a full build plan for the strongest option.

## Prompt

Analyze my installed Skyrim modpack and propose modern AIO mods, framework-based systems, compatibility hubs, generated patchers, and shared integration layers that solve recurring conflicts.

Do not limit the answer to small patches.

Look for problems that can be solved once through:

- A reusable AIO
- A framework
- A generator
- A Synthesis or Mutagen patcher
- A runtime distribution system
- A shared registry
- A compatibility API
- An asset hub
- A diagnostic application
- A build-time validator
- A modpack-specific integration master

### Example scale: Hair Integration AIO

A strong Hair Integration AIO could:

- Detect installed hair packs
- Build a shared registry
- Normalize race and sex availability
- Add consistent keywords
- Detect physics variants
- Support custom races
- Integrate wigs and helmet behavior
- Generate optional NPC appearance adapters
- Detect missing meshes, textures, and TRI files
- Avoid directly overriding every NPC
- Depend on installed hair packs rather than copying them

Use this level of ambition for other categories.

### Analyze at least

- Appearance assets
- NPCs and followers
- Races
- Animations
- Combat
- Voices
- Outfits
- Weapons and armor
- Spells and perks
- Keywords
- Crafting
- Leveled lists
- Loot and vendors
- Enemies and encounter zones
- Creatures
- Cities and settlements
- Interiors
- Worldspaces
- Navmeshes
- Landscape
- Lighting and weather
- Quests and dialogue
- UI and MCM
- Survival and economy
- AI packages
- Papyrus libraries
- Native DLL dependencies
- Patch pipelines
- Vortex packaging
- MO2 packaging

### Preferred solution types

Consider:

- SPID
- KID
- SkyPatcher
- Base Object Swapper
- Race Compatibility
- Open Animation Replacer
- MCM Helper
- PapyrusUtil
- JContainers
- Synthesis
- Mutagen
- Spriggit
- Python or C# generators
- SKSE plugins
- Shared JSON registries
- ESL patch hubs
- FOMOD-generated adapters
- Worldspace conflict maps
- Navmesh scanners
- Patch recommendation engines
- Skyrim Forge Bridge extensions

### Hard design rules

- Avoid unnecessary direct worldspace, NPC, race, leveled-list, outfit, and navmesh overrides.
- Do not claim navmeshes can be safely auto-merged without proof.
- Separate automated diagnostics from operations that still need Creation Kit or user validation.
- Do not assume SPID or SkyPatcher can perform unsupported removal or structural operations.
- Do not duplicate untouched installed assets.
- Do not add dependencies without explaining their value.
- Build manager-neutral output for Vortex and MO2.
- Do not expose private user or machine information.

### Required concept output

Produce at least 20 strong concepts.

For each include:

1. Name
2. Pitch
3. Problem solved
4. Target users
5. Architecture
6. Frameworks and APIs
7. Installed resources it can reuse
8. Hard requirements
9. Optional integrations
10. Records avoided
11. Records still modified
12. Project type
13. Difficulty
14. Automation potential
15. Save compatibility
16. Vortex considerations
17. MO2 considerations
18. Major risks
19. Minimum viable version
20. Advanced version
21. Why it beats another manual patch collection

### Ranking

Score each concept from 1 to 10 for:

- Conflict reduction
- User demand
- Feasibility
- Reusability
- Automation potential
- Performance benefit
- Maintenance burden
- Modpack value
- Cross-manager reliability

Then identify:

- Top five projects
- Best quick win
- Best long-term ecosystem
- Best navmesh project
- Best NPC project
- Best asset project
- Best runtime-framework project
- Best Synthesis or Mutagen patcher
- Best public release
- Best modpack-specific project

### Final recommendation

Choose one project and provide:

- Full implementation plan
- Repository structure
- Toolchain
- Data model
- Detection strategy
- Generation strategy
- Requirements
- Vortex workflow
- MO2 workflow
- FOMOD strategy
- Validation pipeline
- Ship-gate
- Release roadmap
- Regression tests

Prioritize a project that removes a recurring class of conflicts.

---

# Prompt 5 — Compact Universal Skyrim Mod Command

## Prompt Info

- **Purpose:** A shorter reusable prefix for agents that already have the full Skyrim skills loaded.
- **Use when:** I want a fast command without pasting the full master prompt.
- **Primary input:** Replace `[TASK]`.
- **Default behavior:** Inspect, plan, build, validate, and package.
- **Expected result:** The same standards as the larger prompts with fewer tokens.

## Prompt

Complete this Skyrim modding task:

> **[TASK]**

Use the installed Skyrim skills, tools, frameworks, and Skyrim Forge Bridge when available.

Inspect my environment before choosing the architecture. Prefer typed record APIs, runtime frameworks, generated patchers, transactional workspaces, and semantic diffs over binary patching or disposable scripts.

Use the least conflict-heavy correct solution. Avoid unnecessary NPC, race, worldspace, leveled-list, outfit, quest, and navmesh overrides. Do not force SPID, KID, SkyPatcher, BOS, or another framework into unsupported operations.

Work on copies, preserve originals, create only necessary new or modified files, validate the result, and produce manager-neutral Vortex and MO2 packaging.

Use `<ToolsRoot>` and the Creation Kit in the Skyrim root when needed. Use xEdit or SSEEdit only through a verified non-interactive workflow or as user-side validation.

Do not include my personal name, usernames, account details, tokens, private repository information, machine identifiers, unrelated files, or sensitive absolute paths. Sanitize logs and documentation.

Return:

1. Architecture chosen
2. Requirements
3. Work performed
4. Files created or changed
5. Validation results
6. Remaining manual tests
7. Release structure

Do not claim work was completed unless it was actually performed and verified.
