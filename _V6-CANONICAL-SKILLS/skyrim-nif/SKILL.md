---
name: skyrim-nif
description: Read and manipulate NIF 3D mesh files. Use when the user wants to inspect meshes, find texture paths, rewrite texture paths, rename node/block names, inspect or fix eye shader flags, verify roundtrip safety, restore backups, scale models, or troubleshoot invisible items.
---

# Skyrim NIF Module

Read and manipulate NIF (NetImmerse Format) 3D mesh files using Spooky's AutoMod Toolkit.

## Prerequisites

Run all commands from the toolkit directory:
```bash
cd "<TOOLKIT_PATH>"
# Example: cd "C:\Tools\spookys-automod-toolkit"
```

## Overview

NIF files are the 3D model format used by Skyrim for meshes (weapons, armor, architecture, etc.). This module provides:

- **Built-in commands** — NIF inspection using .NET (info, scale, copy)
- **nif-tool commands** — Advanced NIF manipulation via a bundled Rust binary (texture path rewriting, string renaming, shader inspection, eye fix, verify, restore)

**Note:** This module cannot create new meshes from scratch. For that, use Blender with the NifTools addon.

---

## Built-in Commands

### Get NIF Info
```bash
dotnet run --project src/SpookysAutomod.Cli -- nif info "<nif>"
```
Output includes: Filename, file size, header string, NIF version.

### Scale Mesh
```bash
dotnet run --project src/SpookysAutomod.Cli -- nif scale "<nif>" <factor> [options]
```
| Option | Default | Description |
|--------|---------|-------------|
| `<factor>` | Required | Scale factor (1.5 = 150%, 0.5 = 50%) |
| `--output`, `-o` | input file | Output file path |

### Copy NIF
```bash
dotnet run --project src/SpookysAutomod.Cli -- nif copy "<nif>" --output "<file>"
```
Copies and validates the NIF file.

---

## nif-tool Commands

These commands use the bundled `nif-tool.exe` Rust binary (`tools/nif-tool/`). They support single NIF files or folders (recursive).

### List Textures
```bash
dotnet run --project src/SpookysAutomod.Cli -- nif list-textures "<path>"
```
Shows every texture path with block index and slot number.

Example output:
```
D:\mods\MyMod\meshes\head.nif:
  [block 3 BSShaderTextureSet slot 0] textures\actors\character\female\femalehead.dds
  [block 3 BSShaderTextureSet slot 1] textures\actors\character\female\femaleheadnormal.dds
```

### Replace Textures
```bash
dotnet run --project src/SpookysAutomod.Cli -- nif replace-textures "<path>" --old "<find>" --new "<replace>" [--dry-run] [--backup true|false]
```
Case-insensitive substring replacement in BSShaderTextureSet texture paths. Always use `--dry-run` first on a new folder.

| Option | Default | Description |
|--------|---------|-------------|
| `--old` | Required | Substring to find (case-insensitive) |
| `--new` | Required | Replacement string |
| `--dry-run` | false | Preview changes without writing |
| `--backup` | true | Create .nif.bak before overwriting |

Example output:
```
D:\mods\MyMod\meshes\head.nif:
  [block 3 slot 0]
    - textures\OldMod\textures\head.dds
    + textures\NewMod\textures\head.dds
  Saved.
```

### List Strings
```bash
dotnet run --project src/SpookysAutomod.Cli -- nif list-strings "<path>"
```
Shows NIF header string table entries (node names, block names).

Example output:
```
D:\mods\MyMod\meshes\head.nif:
  [0] NPC Root [Root]
  [1] NPC Head [Head]
  [2] BSFaceGenNiNode
```

### Rename Strings
```bash
dotnet run --project src/SpookysAutomod.Cli -- nif rename-strings "<path>" --old "<find>" --new "<replace>" [--dry-run] [--backup true|false]
```
Rename node/block names in the NIF string table. Same options as replace-textures.

### Shader Info
```bash
dotnet run --project src/SpookysAutomod.Cli -- nif shader-info "<path>"
```
Shows BSLightingShaderProperty SF1/SF2 flags. Files with the eye ghosting bug are marked `*** EYE_ENV_MAP ***`.

Example output:
```
D:\...\FaceGenData\FaceGeom\MyNPC.nif:
  [block 5] BSLightingShaderProperty *** EYE_ENV_MAP ***
    SF1: 0x820001E7 [Specular, Skinned, Eye_Environment_Mapping, ...]
    SF2: 0x00008021 [ZBuffer_Write, Double_Sided, ...]

1 file(s) with Eye_Environment_Mapping flag
```

### Fix Eyes
```bash
dotnet run --project src/SpookysAutomod.Cli -- nif fix-eyes "<path>" [--dry-run] [--backup true|false]
```
Fixes the eye ghosting bug in FaceGen NIFs by clearing `Eye_Environment_Mapping` (SF1 bit 17), setting `Environment_Mapping` (bit 7), and correcting surrounding flags.

### Verify
```bash
dotnet run --project src/SpookysAutomod.Cli -- nif verify "<path>"
```
Confirms each NIF can be parsed and re-serialized without data loss. Run this before any batch modification.

Example output:
```
  OK   D:\...\head.nif (48320 bytes, byte-perfect roundtrip)
  FAIL D:\...\bad.nif: content mismatch at offset 0x00A3F0
```

### Restore
```bash
dotnet run --project src/SpookysAutomod.Cli -- nif restore "<path>"
```
Restores `.nif.bak` backups created by replace-textures, rename-strings, or fix-eyes.

---

## Texture Slot Reference

`list-textures` and `replace-textures` output shows `slot N`:

| Slot | Texture type |
|------|-------------|
| 0 | Diffuse (albedo) |
| 1 | Normal map |
| 2 | Glow / emissive |
| 3 | Parallax / height |
| 4 | Environment / cube map |
| 5 | Environment mask |
| 6 | Subsurface tint |
| 7 | Back lighting map |

---

## `replace-textures` vs `rename-strings` — Which One?

| You want to change... | Command |
|---|---|
| Texture image paths (`.dds` files) | `replace-textures` |
| Node names, block names (e.g. `NPC Head`) | `rename-strings` |

`replace-textures` targets `BSShaderTextureSet` blocks. `rename-strings` targets the NIF header string table.

---

## Safety Model

1. After any modification, the output is re-parsed and block count is checked before writing.
2. If validation fails: `VALIDATION FAILED — not saving` — the original file is untouched.
3. Backups (`.nif.bak`) are created before overwriting by default.
4. NIF blocks are stored as raw bytes — only the specific targeted data changes.

If you see `VALIDATION FAILED`, the file was not modified. The NIF may be malformed or an unsupported variant. Skip it and report the path.

---

## Common Workflows

### Batch Texture Retexture
```bash
# 1. Verify all NIFs parse cleanly
dotnet run --project src/SpookysAutomod.Cli -- nif verify "./Meshes"

# 2. Check what texture paths exist
dotnet run --project src/SpookysAutomod.Cli -- nif list-textures "./Meshes"

# 3. Dry-run the replacement
dotnet run --project src/SpookysAutomod.Cli -- nif replace-textures "./Meshes" --old "OldMod\textures" --new "NewMod\textures" --dry-run

# 4. Apply the replacement
dotnet run --project src/SpookysAutomod.Cli -- nif replace-textures "./Meshes" --old "OldMod\textures" --new "NewMod\textures"

# 5. Roll back if needed
dotnet run --project src/SpookysAutomod.Cli -- nif restore "./Meshes"
```

### Fix Eye Ghosting Bug
```bash
# 1. Scan for affected NIFs
dotnet run --project src/SpookysAutomod.Cli -- nif shader-info "./Meshes/actors/character/FaceGenData"

# 2. Preview fix
dotnet run --project src/SpookysAutomod.Cli -- nif fix-eyes "./Meshes/actors/character/FaceGenData" --dry-run

# 3. Apply fix
dotnet run --project src/SpookysAutomod.Cli -- nif fix-eyes "./Meshes/actors/character/FaceGenData"
```

### Inspect Mesh for Troubleshooting
```bash
# Get basic info about a mesh
dotnet run --project src/SpookysAutomod.Cli -- nif info "./Meshes/Weapons/Iron/IronSword.nif"

# List textures with block/slot info
dotnet run --project src/SpookysAutomod.Cli -- nif list-textures "./Meshes/Weapons/Iron/IronSword.nif"
```

### Rename NPC Nodes for Cloning
```bash
# Check existing string table entries
dotnet run --project src/SpookysAutomod.Cli -- nif list-strings "./Meshes/actors/character/FaceGenData/FaceGeom/OldNPC.nif"

# Rename references
dotnet run --project src/SpookysAutomod.Cli -- nif rename-strings "./Meshes/actors/character/FaceGenData" --old "OldNPC" --new "NewNPC" --dry-run
dotnet run --project src/SpookysAutomod.Cli -- nif rename-strings "./Meshes/actors/character/FaceGenData" --old "OldNPC" --new "NewNPC"
```

### Find Missing Textures
```bash
# 1. Extract BSA to get meshes
dotnet run --project src/SpookysAutomod.Cli -- archive extract "SomeMod.bsa" --output "./Extracted"

# 2. Check what textures a mesh needs
dotnet run --project src/SpookysAutomod.Cli -- nif list-textures "./Extracted/meshes/myarmor.nif"

# 3. Verify those textures exist in the extracted files
# If missing, that explains purple/missing textures in-game
```

### Troubleshoot Invisible Items
```bash
# 1. Check if mesh file exists and is valid
dotnet run --project src/SpookysAutomod.Cli -- nif info "./Meshes/MyWeapon.nif"

# 2. Verify the NIF parses correctly
dotnet run --project src/SpookysAutomod.Cli -- nif verify "./Meshes/MyWeapon.nif"

# 3. Check texture paths
dotnet run --project src/SpookysAutomod.Cli -- nif list-textures "./Meshes/MyWeapon.nif"

# Common causes of invisible items:
#   - Mesh file not found (wrong path in ESP)
#   - Mesh is wrong format (LE vs SE)
#   - Textures missing
#   - NIF fails verification (corrupted)
```

---

## NIF Format Information

### Skyrim NIF Versions
| Game | NIF Version | Notes |
|------|-------------|-------|
| Skyrim LE | 20.2.0.7 | Older format |
| Skyrim SE/AE | 20.2.0.7 | BSTriShape optimized |
| Fallout 4 | 20.2.0.7 | Different shaders |

### Common Node Types
| Node | Purpose |
|------|---------|
| BSFadeNode | Root node for meshes |
| NiTriShape | Triangle geometry (LE) |
| BSTriShape | Optimized geometry (SE) |
| BSLightingShaderProperty | Material/shader info |
| BSShaderTextureSet | Texture path container (8 slots) |
| NiSkinInstance | Skinning for animated meshes |

### Texture Slots
| Slot | Suffix | Purpose |
|------|--------|---------|
| Diffuse | none / _d | Base color |
| Normal | _n | Normal map (bumpiness) |
| Specular | _s | Specular/gloss |
| Glow | _g | Emissive/glow |
| Cube Map | _e | Environment reflections |

## Vanilla Mesh Paths

Useful vanilla mesh paths for `--model` option in ESP module:

### Weapons
```
Weapons\Iron\IronSword.nif
Weapons\Iron\IronDagger.nif
Weapons\Iron\IronWarAxe.nif
Weapons\Iron\IronMace.nif
Weapons\Iron\IronBattleaxe.nif
Weapons\Iron\IronGreatsword.nif
Weapons\Iron\IronWarhammer.nif
Weapons\Bow\HuntingBow.nif
Weapons\Staff\Staff.nif
```

### Armor
```
Armor\Iron\Male\IronCuirass_1.nif
Armor\Iron\Male\IronHelmet.nif
Armor\Iron\Male\IronGauntlets.nif
Armor\Iron\Male\IronBoots.nif
Armor\Iron\IronShield.nif
```

## Capabilities

This module **CAN**:
- Read NIF file information (header, version)
- List referenced textures with block index and slot detail
- **Rewrite texture paths** in BSShaderTextureSet blocks (batch, substring replacement)
- **Rename node/block names** in the NIF string table
- **Inspect shader flags** (BSLightingShaderProperty SF1/SF2)
- **Fix eye ghosting bug** in FaceGen NIFs
- **Verify byte-perfect roundtrip** of NIF files
- **Restore backups** from .nif.bak files
- Scale meshes uniformly
- Copy/validate NIF files
- Process entire folders recursively

This module **CANNOT**:
- Create new meshes from scratch
- Edit mesh geometry (vertices, faces)
- Create or edit rigging/skinning
- Convert between NIF versions (LE to SE)

For advanced mesh editing, use:
- **Blender** + **NifTools** addon - Full mesh creation/editing
- **NifSkope** - Direct NIF editing
- **Cathedral Assets Optimizer** - LE to SE conversion

## Important Notes

1. **nif-tool is SSE only** — Requires NIF version `20.2.0.7` with BS version ≥ 83
2. **LE vs SE meshes** — SE uses optimized BSTriShape, not compatible with LE
3. **Texture paths are relative** — Start from Data folder (e.g., `textures\weapons\...`)
4. **Case sensitivity** — Windows ignores case, but be consistent
5. **Always verify first** — Run `nif verify` on a folder before batch modifications
6. **Always dry-run first** — Use `--dry-run` before applying replace/rename/fix-eyes to a new folder
7. **Backups are automatic** — `.nif.bak` created by default; use `nif restore` to roll back
8. **Use `--json` flag** for machine-readable output when scripting

## JSON Output

All commands support `--json` for structured output:
```bash
dotnet run --project src/SpookysAutomod.Cli -- nif info "./Meshes/weapon.nif" --json
```

Example responses:
```json
{
  "success": true,
  "result": {
    "fileName": "weapon.nif",
    "fileSize": 45678,
    "version": "20.2.0.7",
    "headerString": "Gamebryo File Format, Version 20.2.0.7"
  }
}
```

nif-tool command JSON output:
```json
{
  "success": true,
  "result": {
    "output": "D:\\mods\\meshes\\head.nif:\n  [block 3 BSShaderTextureSet slot 0] textures\\actors\\character\\female\\femalehead.dds",
    "dryRun": false
  }
}
```
