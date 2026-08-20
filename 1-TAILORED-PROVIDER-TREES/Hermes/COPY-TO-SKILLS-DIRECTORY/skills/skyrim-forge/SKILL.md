---
name: skyrim-forge
description: Use when Skyrim mod development or validation can benefit from the bundle-managed Skyrim Forge typed automation broker.
---

# Skyrim Forge 5.x

## Resolve this installation

Read `INSTALLATION.json` beside this skill before invoking Forge. It contains the
authoritative root, shared Python executable, CLI argv, and MCP argv for this
machine. Prefer those exact arrays over a guessed installation path, a bare
`python`, or a provider-specific `PYTHONPATH`.

If the descriptor is unavailable, resolve Forge in this order:

1. `SKYRIM_FORGE_ROOT`;
2. `forge` on `PATH`;
3. an explicit path supplied by the user.

Never assume a drive letter or reconstruct the application elsewhere.
Never treat `Documents\SkyrimForge` or `Documents\Skyrim Forge` as the live
product. The live install is `SKYRIM_FORGE_ROOT`, a versioned
`Skyrim-Forge-<version>` folder under the user's Skyrim tools directory.

For bundle v7.8.x, require the Forge 5.2.x bundle contract to report compatible before work (`python -m skyrim_forge bundle-contract --bundle-version 7.8.0`). Claude Code 2026-07-28 still requires `tools/call` to include `resultType: "complete"`. Do not add Forge as a new Grok MCP server when
Grok already sits on the 8-running-server cliff (7 configured, or 6 while
`mcp-search` still loads).

Run `forge doctor` before major Skyrim work.

## Venv health (Windows) — the provider-runtime trap

Forge's MCP server runs from `<root>/.venv/Scripts/python.exe -m skyrim_forge mcp`.
If that venv was created from a **provider runtime cache** python (e.g.
`~/.cache/codex-runtimes/.../python.exe`), it dies the moment the runtime cache is
deleted or that provider is uninstalled. Symptom: MCP clients (Grok, Claude Code,
Codex) hang at startup waiting on a server that cannot boot; the venv python
prints `No Python at '<runtime cache path>'`.

Check: `cat <root>/.venv/pyvenv.cfg` — if `home =` points into a cache dir, repair:

```text
py -3.12 -m venv "<root>/.venv"
"<root>/.venv/Scripts/python.exe" -m pip install "<root>"
```

Forge has zero external dependencies and a local build backend, so this is
fast and offline. Verify the MCP server answers (must return JSON, not hang):

```text
printf '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"probe","version":"1"}}}\n' | "<root>/.venv/Scripts/python.exe" -m skyrim_forge mcp
```

Then restart the MCP client. Never build the venv from a provider runtime
python — use a stable interpreter (system Python, `py -3.x`, or `uv`).

Use Forge inspection and typed jobs before inventing one-off scripts. Never launch xEdit, Creation Kit, LOOT, or Wrye Bash and leave the user to click. Use an Automation Fabric job or report that the required adapter is unavailable.

Hard rules:

- Query `forge capabilities` before promising a subsystem. Adapter-only and worker-contract capabilities are not bundled implementation.
- Use `papyrus-analyze` before `papyrus-compile`; compilation requires a hash-pinned Bethesda compiler, flags, imports, fresh PEX output and the generated build manifest. Static optimization warnings are never authority to change semantics.
- Never send arbitrary shell commands through Forge.
- Never write to live Skyrim Data, Vortex staging, MO2 mods, Overwrite, profiles, or saves.
- Treat `read_only_ready` as a healthy inspection state.
- Require `plugin_write_ready` for typed plugin output.
- Require `xedit_automation_ready` for xEdit jobs.
- Use `raw_form_id_hex`, `local_form_id_hex`, `origin_plugin`, and `form_key` exactly. Never label a raw file FormID as a runtime load-order FormID.
- Use `automation-validate` before `automation-run`.
- Set approval only after reviewing operation, inputs, output ownership, tool hash, and expected evidence.
- A missing completion marker is not success.
- Tool disagreement means stop and classify.
- xEdit evidence is not Skyrim runtime evidence.
- Creation Kit output is not visual validation.
- Treat framework runtime logs as stronger evidence than a static lint rule when the log proves the exact row parsed and distributed. Stop and classify the disagreement instead of silently rewriting working syntax.
- SPID actor-level and skill expressions are distinct. `25/255,0(55/255)` is a valid actor range plus skill range; `0(25)` is not a valid min/max skill expression.
- For FOMOD work, use `fomod-scaffold`, `fomod-plan-validate`, `fomod-simulate`, `fomod-build`, and `fomod-validate`. Do not hand-write ModuleConfig XML when the typed plan can represent the installer.
- Require strict FOMOD payload coverage and branch simulation before packaging. Preserve all previous installer choices unless their removal is documented and approved.
- Never generate or execute arbitrary C# FOMOD scripts. Standard typed XML support is the safe boundary.

For a release, prefer this chain:

```text
framework lint
plugin/header and record inspection
xEdit fixed-script check when configured
Papyrus freshness verification
asset/release-tree validation
FOMOD plan validation, branch simulation, and generated-tree validation when applicable
semantic diff
package to a new version
report remaining in-game tests
```

## Public and Nexus Mods releases

Treat any user request containing **shareable**, **public release**, **publish**, **Nexus**, **upload**, **release page**, or equivalent intent as a publication workflow, not ordinary ZIP creation.

Required sequence:

1. Run `forge nexus-policy-status` and review the current official Nexus Mods policy pages. Do not scrape Nexus Mods or infer permission settings from cached snippets.
2. Run `forge nexus-scaffold` when no publication plan exists.
3. Inventory every bundled file and replace catch-all ownership entries with accurate rights records.
4. Obtain evidence for third-party permissions. Credit is never permission. Never invent, paraphrase, or fabricate an author's consent.
5. Record dependencies that are required but not redistributed.
6. Verify game terms, project/asset licences, collaborator credits, Donation Points compatibility, executable/network behaviour, adult-content classification, claim evidence, and AI assistance.
7. The uploader must review and accept the attestation. An AI must never sign it or set `responsibility_accepted=true` without the user's explicit confirmation.
8. Run `forge nexus-audit` and require `share_ready: true`. A normal ZIP, successful build, lint pass or xEdit pass is never sufficient for public sharing.
9. Run `forge nexus-build` for the final tree, public rights documents, private audit and ZIP.
10. Still require one real Vortex and MO2 installation test before publication.

A normal `release-build` is not sufficient when public sharing is intended. Use `release-build --target nexus --publication-plan ...` or `nexus-build`.

Never call a mod Nexus-compliant merely because its files compile or lint. The rights gate, content classification, truthful mod-page claims, uploader attestation and current policy review are separate mandatory evidence.

## Verified external-tool selection

- Before inventing an archive, mesh, Papyrus, Synthesis, LOD, animation, or asset-processing implementation, call `forge tool-resolve <capability>`.
- Use only the selected configured executable with a matching SHA-256 pin and exact catalog capability.
- Scan nested tool folders and ZIPs with `forge tool-scan`; tools such as `ESLifier/bsarch/BSArch.exe` are valid discoveries.
- Use `forge tool-import` for permitted local tool-vault copies or `forge tool-configure` for configure-only legal installations. Explicit approval is mandatory.
- Never bundle the local tool vault or third-party executables into Forge, GitHub, FOMOD, or Nexus outputs. Local possession is not redistribution permission.
- Never substitute a GUI for a CLI. `Synthesis.exe` is not `Synthesis.Bethesda.CLI.exe`.
- Use BSArch for `.bsa`/`.ba2` work when the `archive.bsa.*` capability resolves. Use the official Bethesda Papyrus compiler for publication builds when `papyrus.compile.official` resolves. Use Champollion only for recovery/analysis, never as proof of original source ownership.
- When no eligible real tool resolves, stop and report the missing adapter instead of generating an unverified replacement.

---

## V5 portable discovery

1. Read `INSTALLATION.json` beside this skill when present (per-machine; do not ship secrets).
2. Else `$env:SKYRIM_FORGE_ROOT`.
3. Else `forge` on PATH.
4. Else user path.
5. Else, when working from the bundle, run `TOOLS/Install-SkyrimForge.ps1`; do not invent a manual extraction path.

After a v7.8.x AIO install, missing/incompatible Forge is a failed installation state, not a successful optional skip. Outside the bundle, report Forge as unavailable rather than inventing paths.
