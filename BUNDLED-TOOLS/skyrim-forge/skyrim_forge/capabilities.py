from __future__ import annotations

from typing import Any

from .version import VERSION

LEVELS = {"direct", "profiled", "adapter", "worker_contract", "human_gate", "unsupported"}

_CAPABILITIES: tuple[dict[str, Any], ...] = (
    {"id": "plugin.inspect", "level": "direct", "status": "implemented", "outputs": ["headers", "masters", "record queries", "hashes"], "limitations": "Forge's parser is independent of xEdit but is not a replacement for xEdit or runtime validation."},
    {"id": "plugin.write.low_risk", "level": "direct", "status": "implemented", "outputs": ["KYWD", "GLOB", "FLST", "OTFT"], "limitations": "Typed records only; no arbitrary binary record editing."},
    {"id": "framework.lint", "level": "profiled", "status": "implemented", "profiles": ["SPID 7.3", "KID 4.0.6", "BOS 3.4.1", "SkyPatcher 6.4.2 placement/core rules", "FLM 1.8.1 core rules", "CDF pinned JSON subset"], "limitations": "Unknown or version-specific syntax is reported as unverified, not automatically rewritten."},
    {"id": "framework.build", "level": "profiled", "status": "implemented", "profiles": ["SPID 7.3", "KID 4.0.6", "BOS 3.4.1", "SkyPatcher 6.4.2 core INI", "FLM 1.8.1 core INI"], "limitations": "Generates only modeled subsets and validates the generated file. It does not invent category-specific SkyPatcher properties."},
    {"id": "papyrus.analyze", "level": "profiled", "status": "implemented", "outputs": ["identity graph", "inheritance cycles", "import conflicts", "performance heuristics"], "limitations": "Performance findings are review warnings, never automatic semantic rewrites."},
    {"id": "papyrus.compile", "level": "adapter", "status": "implemented", "requires": ["pinned Bethesda PapyrusCompiler", "flags file", "source imports"], "limitations": "Compilation proves compiler acceptance and fresh PEX output, not runtime correctness."},
    {"id": "native.scaffold", "level": "profiled", "status": "implemented", "outputs": ["CommonLibSSE-NG CMake project", "vcpkg manifests", "SKSE entry point", "CI workflow"], "limitations": "The scaffold is source-locked; installed compilers and dependencies remain external."},
    {"id": "native.build", "level": "adapter", "status": "implemented", "requires": ["pinned CMake", "pinned vcpkg", "Visual Studio C++ toolchain"], "limitations": "Builds only inside the Forge workspace and does not deploy to live Data."},
    {"id": "native.binary_audit", "level": "direct", "status": "implemented", "outputs": ["PE architecture", "DLL characteristic", "imports", "hash"], "limitations": "Static PE evidence does not prove compatibility with every SKSE plugin or runtime."},
    {"id": "fomod.engineering", "level": "profiled", "status": "implemented", "outputs": ["typed plan", "ModuleConfig XML", "simulation", "release gate"], "limitations": "Declarative ModuleConfig only; arbitrary C# installers are blocked."},
    {"id": "xedit.automation", "level": "adapter", "status": "implemented", "requires": ["installed hash-pinned xEdit", "allowlisted Pascal scripts"], "limitations": "The xEdit process may show a window, but jobs require completion markers and no user interaction."},
    {"id": "creation_kit", "level": "worker_contract", "status": "adapter_only", "requires": ["version-pinned local CK or CKPE worker"], "limitations": "No universal headless CK bridge is bundled. UI automation is narrow and coordinate-free."},
    {"id": "wrye_bash", "level": "worker_contract", "status": "adapter_only", "limitations": "Requires a version-pinned worker around the installed Wrye Bash version."},
    {"id": "loot", "level": "worker_contract", "status": "adapter_only", "limitations": "Forge validates and applies typed plans; it does not invent unsupported LOOT GUI arguments."},
    {"id": "mo2", "level": "adapter", "status": "implemented", "limitations": "Profile capture and bounded launching only; live profile changes require approval."},
    {"id": "vortex", "level": "adapter", "status": "read_only", "limitations": "Forge inspects staging and builds archives. It does not mutate Vortex's internal database."},
    {"id": "nexus.publication", "level": "human_gate", "status": "implemented", "outputs": ["rights manifest", "credits", "third-party notices", "permissions", "AI disclosure", "private evidence audit", "Nexus BBCode page"], "limitations": "Forge enforces machine-checkable declarations and evidence completeness, but cannot authenticate legal ownership, consent, trademark/privacy clearance, or permission conversations. The uploader must attest and remains responsible."},
    {"id": "runtime.skyrim", "level": "human_gate", "status": "required", "limitations": "Crashes, visuals, balance, navmesh, save migration, hooks, animation quality, and gameplay require real runtime testing."},
    {"id": "synthesis", "level": "worker_contract", "status": "adapter_only", "limitations": "Requires a pinned local Synthesis worker and patcher source; Forge can confine outputs and receipts but does not bundle the .NET ecosystem."},
    {"id": "toolchain.discovery", "level": "direct", "status": "implemented", "requires": ["local directory or ZIP"], "limitations": "Static discovery never launches tools; local import does not grant redistribution rights."},
    {"id": "archive.bsarch", "level": "direct", "status": "implemented", "requires": ["configured hash-pinned BSArch"], "limitations": "Pack input and all outputs are confined to the Forge workspace; runtime game loading remains separate evidence."},
    {"id": "papyrus.decompile", "level": "direct", "status": "implemented", "requires": ["configured hash-pinned Champollion"], "limitations": "Decompiler output is not authoritative original source and conveys no redistribution rights."},
    {"id": "synthesis.cli", "level": "direct", "status": "implemented", "requires": ["Synthesis.Bethesda.CLI executable"], "limitations": "Synthesis.exe GUI is not accepted as the CLI. Patcher-specific runtime behavior requires output verification."},
    {"id": "mesh.deadmesh", "level": "direct", "status": "implemented", "requires": ["configured hash-pinned dmscan with sidecars"], "limitations": "Static collision findings require mesh and runtime review."},
    {"id": "assets.archive", "level": "adapter", "status": "implemented", "outputs": ["safe inventory", "hashes", "deterministic ZIP"], "limitations": "BSA/BA2 creation requires a pinned Archive/BSArch worker; archive acceptance is not asset correctness."},
    {"id": "assets.mesh_texture", "level": "worker_contract", "status": "adapter_only", "requires": ["pinned asset worker"], "limitations": "NIF, DDS, parallax, PBR, and optimizer transforms require version-specific tools and visual review."},
    {"id": "animation.behavior", "level": "worker_contract", "status": "adapter_only", "requires": ["pinned animation worker"], "limitations": "Pandora/Nemesis/OAR/HKX generation is tool-version specific and requires in-game animation review."},
    {"id": "bodyslide", "level": "worker_contract", "status": "adapter_only", "requires": ["pinned BodySlide worker"], "limitations": "Batch build can be confined and inventoried, but body/physics output needs visual and collision testing."},
    {"id": "lod", "level": "worker_contract", "status": "adapter_only", "requires": ["pinned xLODGen/DynDOLOD worker"], "limitations": "Worldspace/load-order-specific generation and visual inspection remain mandatory."},
    {"id": "grass_cache", "level": "worker_contract", "status": "adapter_only", "requires": ["pinned grass-cache worker"], "limitations": "Generation depends on runtime, load order, worldspaces, and stability; Forge does not bundle NGIO or game files."},
    {"id": "audio.voice", "level": "worker_contract", "status": "adapter_only", "requires": ["pinned audio worker"], "limitations": "FUZ/LIP/voice generation requires legal source audio, tool-specific processing, and in-game dialogue timing review."},
    {"id": "facegen", "level": "worker_contract", "status": "adapter_only", "requires": ["pinned Creation Kit/CKPE worker"], "limitations": "Generated NIF/DDS identity and appearance require xEdit verification and in-game visual review."},
    {"id": "quest.dialogue", "level": "worker_contract", "status": "adapter_only", "limitations": "CK fragment/SEQ/voice manifests may be automated by a pinned worker; quest flow, aliases, scenes, and dialogue timing require CK and runtime review."},
    {"id": "worldspace.landscape", "level": "human_gate", "status": "not_automated", "limitations": "Reference placement, landscape, lighting, occlusion, and seams are not safely judged by generic static automation."},
    {"id": "navmesh.write", "level": "unsupported", "status": "blocked", "limitations": "No generic NAVM writer is exposed. CK finalization and in-game traversal checks remain required."},
)


def registry() -> dict[str, Any]:
    assert all(item["level"] in LEVELS for item in _CAPABILITIES)
    return {
        "product": "Skyrim Forge",
        "version": VERSION,
        "result": "PASS",
        "capabilities": [dict(item) for item in _CAPABILITIES],
        "rule": "An AI must not claim a stronger evidence level than the capability registry reports.",
    }


def get_capability(identifier: str) -> dict[str, Any]:
    for item in _CAPABILITIES:
        if item["id"] == identifier:
            return dict(item)
    return {"id": identifier, "level": "unsupported", "status": "unknown", "limitations": "Capability is not registered and must not be claimed."}
