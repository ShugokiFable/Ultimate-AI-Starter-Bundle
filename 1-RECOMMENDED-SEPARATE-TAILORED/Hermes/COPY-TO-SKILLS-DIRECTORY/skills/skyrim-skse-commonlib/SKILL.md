---
name: skyrim-skse-commonlib
description: Create, port, diagnose, or optimize native SKSE DLL plugins using CommonLibSSE or CommonLibSSE-NG, CMake, vcpkg,
  Address Library, hooks, and runtime-safe logging.
compatibility: Windows 10/11; Skyrim Special Edition or Anniversary Edition; PowerShell and Python 3 when bundled scripts
  are used
metadata:
  version: 4.3.0
  updated: '2026-07-22'
  library: overseer-skyrim-agent-skills
  error_registry_revision: 4.3.0
  final_pack_version: 4.3.0
---

# SKSE and CommonLib

## Required inputs

- Supported game runtimes: SE, AE, GOG, VR, or an explicit subset.
- SKSE, Address Library, and CommonLib fork/revision.
- CMake presets, vcpkg manifest, compiler toolset, and dependency lock.
- Hook sites, relocation strategy, and expected thread context.
- Crash logs and symbol files for diagnosis.

## Workflow

1. Reproduce the current configure and build before editing.
2. Pin the exact CommonLib fork and commit. The repository name alone is insufficient.
3. Prefer public events, messaging, and APIs over hooks.
4. When hooking, document calling convention, overwritten bytes, trampoline size, lifetime, and runtime coverage.
5. Use relocations and version checks rather than raw offsets.
6. Keep game-thread-only APIs on the game thread.
7. Avoid allocation, locks, filesystem access, and logging in hot hooks unless measured.
8. Provide deterministic logs with plugin version and detected runtime.
9. Build every supported target and inspect DLL imports/exports.
10. Test failure behavior for missing dependencies and unsupported runtimes.

Use `scripts/build_commonlib.ps1` as a parameterized starting point, then follow the project's presets.

## Optimization standard

Measure first. Report baseline, workload, profiler or timing method, change, and regression risk. Hardware-specific tuning must retain a safe fallback and must not pretend software can explicitly control CPU cache, SSD DRAM, or Resizable BAR.

## Evidence standard

Use this hierarchy for version-sensitive facts:

1. The active project's `ENVIRONMENT.md`, `TASK.md`, installed framework version, and build files.
2. Official upstream documentation or source for that exact version.
3. Known-good files from the user's installed mod library, read-only.
4. Direct inspection of the relevant ESM, ESP, DLL, script, log, or archive.

Do not substitute memory, an old example, or a plausible token. Record the evidence path or URL in `VALIDATION.md`.

## Evidence-derived native-code controls

- Compile every review-driven change against the exact CommonLib fork and checkout. Header-valid expressions can still fail to link when template instantiations are unavailable.
- Keep `DllMain` minimal. Defer settings I/O, logging setup, library/API resolution, hooks, UI, SetupAPI, and other heavy work to framework initialization.
- Reconfigure from a clean build directory after moving or version-copying a project.
- Use a runtime-shaped harness that mirrors the game root and `Data\SKSE\Plugins` dependency layout.
- Prove hook scope, handle ownership, reference lifetime, and thread context. Revalidate stored handles after transitions and before side effects.
- Do not claim direct control of X3D cache, ReBAR, RAM timings, or SSD internals; software may detect and adapt only where measured.


## Hook-target ownership gate

Before installing any vtable, call-site, or function hook:

1. resolve the runtime and relocation/vtable index;
2. determine the target address;
3. query its owning memory module;
4. verify that an expected game-code target lies inside `SkyrimSE.exe` and its
   executable `.text` section;
5. capture target bytes and the expected function contract;
6. abort safely when any check fails.

An address outside the expected `.text` section proves only that the candidate
target is invalid for the intended hook. It does not prove that a named combat
DLL hooked first. Possible classes include runtime mismatch, wrong relocation,
stale vtable index, changed object layout, already-modified slot, or ownership by
another module.

Required failure log:

```text
runtime=<...>
relocation_or_vtable=<...>
candidate=<...>
owner_module=<...>
expected_module=SkyrimSE.exe
text_range=<start-end>
bytes=<...>
action=ABORTED
```

Disable a failing optional feature as a reversible mitigation, then perform
module-ownership and isolation testing. Do not publish a culprit list based only
on mod category.
