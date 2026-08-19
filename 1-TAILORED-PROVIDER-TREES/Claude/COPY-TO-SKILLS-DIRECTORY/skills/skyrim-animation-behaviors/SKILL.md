---
name: skyrim-animation-behaviors
description: Create or diagnose Skyrim animation and behavior integrations involving OAR, BFCO, Nemesis, Pandora, animation
  events, conditions, generated behavior output, and combat compatibility.
compatibility: Windows 10/11; Skyrim Special Edition or Anniversary Edition; PowerShell and Python 3 when bundled scripts
  are used
metadata:
  version: 4.3.0
  updated: '2026-07-22'
  library: overseer-skyrim-agent-skills
  error_registry_revision: 4.3.0
  final_pack_version: 4.3.0
---

# Animation and behavior integration

## Classify the layer

- OAR condition and folder selection;
- animation file and annotation/event data;
- behavior graph source patch;
- Nemesis or Pandora generator input/output;
- BFCO or other combat-framework contract;
- native event hook or Papyrus listener;
- missing animation asset referenced by a behavior graph.

## Missing HKX law

A missing `.hkx` and a missing/generated behavior entry are different failures.

For every missing animation path:

1. normalize the relative path beneath `meshes`;
2. identify the actor/creature behavior graph that references it;
3. locate the owning mod through loose-file conflict data, archive inventories,
   and source manifests;
4. check exact case and path;
5. determine whether the file is:
   - a shipped source asset;
   - a generated behavior output;
   - an optional patch asset;
   - a stale reference to a removed animation;
6. fix the owning source or dependency, then regenerate only when the generator
   actually owns the missing output.

An A-pose suppressor reports or mitigates the symptom. It cannot create a missing
animation.

Custom creature paths such as `Actors\<Creature>\Animations\...` normally
require the creature mod's own movement set or a compatible creature behavior
patch. Nemesis/Pandora should not be prescribed as a universal cure because
they cannot invent absent custom assets.

## Workflow

1. Record exact framework and generator versions.
2. Inspect source behavior/mod files, not only generated output.
3. Resolve animation event names from source or known working files.
4. Map conflicts by graph, node, annotation, condition priority, and output owner.
5. Make one source-level change, regenerate, and compare outputs.
6. Keep generated outputs in their own versioned mod.
7. Test first/third person, sex variants, weapon classes, NPC/player paths,
   creatures, interruptions, paired animations, and relevant transitions.
8. Route crashes to `skyrim-crash-diagnostics`.

## Validation

Run:

```text
scripts\audit_missing_animations.py --log <APoseFix-log> --root <deployed-mod-root>
```

The script checks loose files and optional supplied archive-inventory text. It
does not parse BSA archives and must label archive coverage accordingly.
