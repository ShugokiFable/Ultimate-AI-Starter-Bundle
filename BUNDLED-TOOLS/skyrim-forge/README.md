# Skyrim Forge 6.0.0

> Skyrim Forge is developed inside the **Ultimate AI Starter Bundle**
> repository, at `BUNDLED-TOOLS/skyrim-forge`. It used to live in its own
> repo; the split is what let the bundle's installer call a contract field
> Forge never returned, so a fresh install of bundle 7.8.0 could not
> complete. One repository means one commit can test both halves.
> You do not install this directory by hand -- the bundle's
> `START-HERE.bat` does it.

Skyrim Forge is a local, safety-first engineering workbench and MCP server for Skyrim Special Edition and Anniversary Edition mod development.

Forge 5.0 speaks the current **MCP `2026-07-28`** revision, which replaced the
`initialize` handshake with per-request metadata, while still serving the
handshake era every installed AI client uses today. Both eras run from the same
process and expose the same 52 tools, so existing Codex, Claude, and Grok
registrations need no change. See [docs/MCP.md](docs/MCP.md).

Forge includes the **Automation Fabric** plus a mandatory rights-and-publication gate for shareable releases. An AI does not click around SSEEdit, Creation Kit, Wrye Bash, LOOT, or Mod Organizer 2. It submits a typed JSON job. Forge validates the job, snapshots inputs, runs only the configured adapter, captures logs and outputs, reopens what it can verify, and writes an audit receipt.

## Public and Nexus releases

Private packaging and public distribution are different trust levels. When the user or AI states that a mod is **shareable**, **public**, **for Nexus**, or otherwise intended for redistribution, Forge requires a typed Nexus publication plan and the Nexus target release gate. A normal ZIP is not called share-ready.

```text
forge nexus-scaffold <release-root> NEXUS-PUBLICATION-PLAN.json --mod-name "My Mod" --mod-version 1.0.0 --uploader "Author" --approve
forge nexus-audit NEXUS-PUBLICATION-PLAN.json <release-root>
forge nexus-build NEXUS-PUBLICATION-PLAN.json <release-root> <workspace-output> --approve
```

The gate maps every bundled file to its origin, author, licence or permission basis, credit, redistribution rights, Donation Points status, content classification, AI disclosure, and local evidence. Credit alone is never treated as permission. Forge blocks ambiguous rights, missing licence obligations, original game files, unsupported public claims, and incomplete uploader attestations. It cannot authenticate legal ownership or replace the uploader's final responsibility.

## Install

Run the bundle's `START-HERE.bat`; Skyrim Forge is installed from this in-tree source automatically. The installer copies this
directory to your install root, bootstraps the virtualenv, installs the Forge
skill into every detected AI app, and registers the MCP server with each one.

The install directory carries **no version suffix** -- it is `Skyrim-Forge`,
next to xEdit, houseCARL and Spooky, never `Skyrim-Forge-6.0.0`. Every AI
provider stores the MCP command as an absolute path, so a version-stamped folder
renames itself out from under all five configs on the next upgrade, and the
failure is silent: a provider that cannot spawn its server simply shows no
tools. The installed version is in `VERSION.txt`. The installer migrates an
existing version-stamped install onto the versionless name rather than leaving
two copies behind.

Choose the install root with `INSTALL-AIO.ps1 -ForgeRoot 'S:\Apps\Skyrim Tools'`
(or set `SKYRIM_FORGE_ROOT`). Without either it goes to
`%LOCALAPPDATA%\Skyrim-Tools\Skyrim-Forge`, which needs no admin rights and
makes no assumption about your drive letters.

Then, from the install root:

1. Run `START-HERE.bat`.
2. Configure core paths. Job staging defaults to `<this install>\Workspaces`.
3. Configure only the external tools actually installed on the machine.

Claude Code 2026-07-28 requires Forge **5.1.5 or newer** (`tools/call` must
carry `resultType`). Grok wedges at 8 running MCP servers; `Register-MCP.ps1`
will skip Grok rather than take the last slot. See [docs/INSTALLATION.md](docs/INSTALLATION.md)
and [docs/MCP.md](docs/MCP.md).

If Python 3.11+ is not installed, that explicit menu choice downloads the pinned
Python 3.13.14 installer from python.org, verifies its SHA-256 and Authenticode
signature, and performs a per-user install before creating Forge's shared
`.venv`. No AI-specific `PYTHONPATH` is required.

The same setup installs the Forge skill for Codex, Claude, Grok, Kimi, and
Hermes. It registers the same stdio MCP server with every installed client;
Kimi receives a preserving merge into `mcp.json`, while Hermes is registered
and connection-tested through its supported MCP CLI. Every provider skill
receives an `INSTALLATION.json` containing the exact shared CLI and MCP command
arrays. Missing clients are reported without breaking installed providers.

For unattended setup with an already selected Python executable:

```powershell
$env:SKYRIM_FORGE_PYTHON = 'C:\Path\To\python.exe'
.\Install-AI-Bridge.ps1 -Provider All -Yes
```

External tool execution is disabled by default. UI Automation is separately disabled by default.

## What Forge can do directly

- Inspect plugin headers, masters, flags, and hashes.
- Traverse normal and compressed plugin records and query signatures, raw FormIDs, local FormIDs, origins, and EditorIDs.
- Create narrowly typed KYWD, GLOB, FLST, and OTFT plugins transactionally.
- Validate SPID, KID, BOS, SkyPatcher placement, and CDF configuration.
- Generate, simulate, and strictly validate complete FOMOD 5.0 installers from typed plans.
- Compile Papyrus through the official compiler and reject stale PEX output.
- Inspect archives and release trees.
- Build deterministic private release archives.
- Audit and build Nexus Mods publication bundles with file-level rights mapping, permission evidence, credits, licensing, content classification, claim evidence, uploader attestation, and generated mod-page BBCode.
- Snapshot MO2 profiles.
- Run fixed, allowlisted xEdit scripts unattended.
- Execute version-pinned JSON workers for LOOT, Wrye Bash, and Creation Kit.
- Run narrowly calibrated, coordinate-free Windows UI Automation jobs when no headless worker exists.
- Expose the workbench over CLI, GUI, and MCP.


## Nexus Mods publication gate

A private build and a public upload are not the same operation. When a user asks for a shareable, public, or Nexus-ready release, Forge requires a typed Nexus publication plan and blocks the final package until every bundled file has a rights record.

The gate checks:

- original and third-party asset provenance;
- redistribution and modification permission;
- permission evidence, without placing private messages in the public ZIP;
- required credits and collaborators;
- project and asset licences;
- Donation Points compatibility;
- original-game and piracy-risk files;
- executables, source availability, and network behaviour;
- adult-content classification and event-specific rules;
- truthful performance and capability claims;
- AI assistance disclosure and human verification;
- a current review of official Nexus policies;
- an uploader attestation that the AI is forbidden to sign.

Use `docs/NEXUS-PUBLICATION.md`. Forge never treats credit as a substitute for permission and never claims that a machine check authenticates legal ownership.

## FOMOD engineering

Forge 5.0 includes a typed FOMOD generator rather than only detecting an existing installer. It covers the bounded standard ModuleConfig XML surface: install steps, all standard group types, informational and file-bearing options, images and descriptions, required and conditional files, condition flags, nested dependencies, dynamic option types, priorities, module metadata, UTF-8/UTF-16 output, and branch simulation. Strict validation rejects omitted payload files, unsafe source paths, temporal or undefined flag references, malformed XML order, invalid condition blocks, and unresolved destination collisions.

C# scripted FOMOD installers are deliberately unsupported because they permit arbitrary code execution. See `docs/FOMOD-ENGINEERING.md`.

## xEdit automation

Forge includes audited scripts under `resources/xedit` and installs them into the configured xEdit `Edit Scripts` directory only after approval.

A check job launches the installed xEdit executable with a selected plugin, its masters, automatic script execution, and automatic exit. Forge requires the completion marker produced by its own script. A process exit without the marker is classified as incomplete, not success.

Arbitrary generated Pascal is disabled. An additional script may run only when its exact SHA-256 is present in an explicit allowlist and the script already resides in xEdit's script directory.

## Creation Kit and Wrye Bash

Those applications do not provide one complete, stable public headless interface for all authoring and Bashed Patch operations. Forge supports two bounded mechanisms:

1. A version-pinned external worker implementing the Forge JSON worker contract.
2. A coordinate-free Windows UI Automation fallback for a narrow, pre-calibrated dialog sequence.

The fallback uses window titles, process IDs, Automation IDs, and accessible control names. Job files cannot contain coordinates, OCR instructions, or image matching.

## Safety model

- Live Skyrim `Data`, saves, profiles, original archives, and manager staging are read-only inputs.
- Outputs belong to the configured Forge workspace.
- Write operations require explicit approval.
- External executables may be pinned by SHA-256.
- Subprocesses are invoked with argument arrays and `shell=False`.
- Each automation job receives a transaction directory, input snapshots, logs, outputs, and a JSON receipt.
- Unexpected dialogs, missing completion markers, worker disagreement, missing outputs, hash mismatches, timeouts, and nonzero exits block the job.
- Forge does not silently apply a proposed load order.
- Forge does not claim that static checks replace Skyrim runtime testing.

## Fast commands

```text
forge doctor
forge discover-tools
forge config-show
forge lint <ModFolder>
forge fomod-scaffold <PayloadRoot> <Workspace>/fomod.plan.json --module-name "My Mod" --approve
forge fomod-plan-validate <Workspace>/fomod.plan.json --source-root <PayloadRoot>
forge fomod-simulate <Workspace>/fomod.plan.json --selections selections.json --state state.json --source-root <PayloadRoot>
forge fomod-build <Workspace>/fomod.plan.json <PayloadRoot> <Workspace>/BuiltFomod --approve
forge fomod-validate <Workspace>/BuiltFomod
forge plugin-info <Plugin.esp>
forge record-query <Plugin.esp> --signature SPEL --editor-id Bound
forge plugin-plan-validate examples/plugin-create.plan.json
forge automation-validate examples/automation-xedit-check.job.json
forge automation-run <job.json> --approve
forge nexus-policy-status
forge nexus-scaffold <ReleaseRoot> <Workspace>/NEXUS-PUBLICATION-PLAN.json --mod-name "My Mod" --mod-version 1.0.0 --uploader "Author" --approve
forge nexus-audit <Workspace>/NEXUS-PUBLICATION-PLAN.json <ReleaseRoot>
forge nexus-build <Workspace>/NEXUS-PUBLICATION-PLAN.json <ReleaseRoot> <Workspace>/NexusPublication --approve
```

## Readiness levels

`doctor` reports separate states:

- `read_only_ready`: inspection and static validation can run.
- `plugin_write_ready`: the typed writer can write inside the workspace.
- `xedit_automation_ready`: xEdit exists, hashes match when pinned, and external execution is enabled.
- `mo2_automation_ready`: MO2 is configured and external execution is enabled.

A missing external tool does not make the core installation broken.

## Evidence labels

Forge reports what each result actually proves:

- Plugin header inspection is not semantic validation.
- Forge record parsing is not independent xEdit evidence.
- xEdit scripted checks are not Skyrim runtime evidence.
- Release validation is packaging hygiene, not gameplay validation.
- Creation Kit output still needs visual and in-game testing where appearance, navmesh, lighting, scenes, or placement matter.

## Repository

The repository includes deterministic packaging, CI, CodeQL, issue templates, security policy, tests, schemas, native helper source, Windows and Linux native binaries, and GitHub release automation.

## Forge 4.2 evidence tiers

Forge reports each subsystem as direct, profiled, adapter, worker contract, human gate or unsupported. Query `forge capabilities` before using an external-tool workflow. Static lint, compiler acceptance, native compilation, xEdit parsing and Skyrim runtime are distinct evidence levels.

### Shareable and Nexus releases

Public intent automatically requires the Nexus publication plan and rights gate. Every bundled file must be mapped to ownership/licence/permission evidence; credits, third-party notices, AI disclosure, permission recommendations and a private audit are generated only after the gate passes. Forge never signs the uploader attestation and does not provide legal advice.

### Papyrus and native plugins

`forge papyrus-analyze` reports identity/import/inheritance errors and review-only performance heuristics. `forge papyrus-compile` uses a hash-pinned compiler and verifies fresh PEX output. Native DLL projects use a source-locked CommonLibSSE-NG scaffold, exactly one compatibility strategy, pinned build tools, workspace-only staging and PE audit. Real Skyrim testing is still mandatory.

## Verified external tools

Forge 4.2 recursively discovers real tools in directories and ZIPs, including tools nested inside another package such as `ESLifier/bsarch/BSArch.exe`. Use `forge tool-scan`, then `forge tool-import` or `forge tool-configure`. Imported tools are copied only into the local Forge tool vault, accompanied by hashes and receipts. Third-party executables are never added to the public Forge repository or a mod release. See `docs/TOOLCHAIN-BROKER.md`.

Forge selects tools by an exact capability and a valid SHA-256 pin. It will not substitute `Synthesis.exe` for `Synthesis.Bethesda.CLI.exe`, or a generic archive utility for a Skyrim SE/AE BSA operation.
