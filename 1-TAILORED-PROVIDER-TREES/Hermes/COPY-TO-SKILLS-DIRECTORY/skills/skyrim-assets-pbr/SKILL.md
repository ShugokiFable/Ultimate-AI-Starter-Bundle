---
name: skyrim-assets-pbr
description: Audit, repair, convert, or package Skyrim meshes and textures, including DDS paths, NIF material references,
  parallax, and Community Shaders PBR assets.
compatibility: Windows 10/11; Skyrim Special Edition or Anniversary Edition; PowerShell and Python 3 when bundled scripts
  are used
metadata:
  version: 4.3.0
  updated: '2026-07-22'
  library: overseer-skyrim-agent-skills
  error_registry_revision: 4.3.0
  final_pack_version: 4.3.0
---

# Skyrim assets, parallax, and PBR

## Required inputs

- Target renderer and exact Community Shaders/PBR or ENB specification.
- Source asset permissions.
- Mesh and texture roots plus overwrite order.
- Known failing object, material, or path.

## Workflow

1. Inventory only relevant NIF and DDS files. Use `scripts/scan_assets.py` for a first pass.
2. Resolve every NIF texture path against the intended mod-manager virtual filesystem.
3. Inspect texture dimensions, format, mipmaps, alpha use, normal-map convention, and color space.
4. Verify the active PBR/parallax naming and material contract from the installed framework, not an old guide.
5. Make conversions losslessly where possible and preserve source assets separately.
6. Test representative materials before bulk conversion.
7. Check seams, tiling, tangent-space normals, alpha artifacts, wetness/snow interactions, and fallback behavior.
8. Package only assets the mod owns or has permission to redistribute.

## Boundaries

- Do not infer a PBR map from a filename alone.
- Do not fabricate physically meaningful channels from a flat texture without documenting the approximation.
- Do not overwrite deployed assets or generated LOD/cache outputs.
- A file-opening success does not prove correct shader behavior in game.

## Evidence standard

Use this hierarchy for version-sensitive facts:

1. The active project's `ENVIRONMENT.md`, `TASK.md`, installed framework version, and build files.
2. Official upstream documentation or source for that exact version.
3. Known-good files from the user's installed mod library, read-only.
4. Direct inspection of the relevant ESM, ESP, DLL, script, log, or archive.

Do not substitute memory, an old example, or a plausible token. Record the evidence path or URL in `VALIDATION.md`.

## Evidence-derived PBR claim control

A flat or mechanically packed RMAOS is a bootstrap/approximation, not proof of physically meaningful PBR. Record how each channel was derived, preserve source maps, test representative materials in the active shader framework, and describe the result no more broadly than the observed in-game behavior.


## Community Shaders feature diagnostics

When the Community Shaders log reports:

```text
<Feature>.ini failed to load, feature disabled
```

inspect the deployed winner at:

```text
Data\Shaders\Features\<FeatureShortName>.ini
```

The current source builds this path from the feature short name. Do not look only
under `Data\SKSE\Plugins\CommunityShaders`.

For a preset that reports an override for a disabled feature:

1. record Community Shaders and feature versions;
2. determine whether the feature is core, optional, obsolete, or mismatched for
   that exact release;
3. inspect the deployed descriptor and mod-manager winner;
4. compare the preset's declared requirements;
5. fix the installation source and redeploy;
6. confirm the feature subsequently logs as loaded.

An override line does not prove the feature is active.

For duplicate Terrain Shadows height-map warnings, identify every provider and
winning file per worldspace. Do not delete a height map merely because two were
detected; determine the intended worldspace coverage and compatibility patch.
