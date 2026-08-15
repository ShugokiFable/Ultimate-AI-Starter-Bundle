---
name: skyrim-runtime-log-forensics
description: Interpret Skyrim SKSE, framework, asset, animation, and runtime logs without blaming the wrong field, DLL, mod,
  or dependency.
compatibility: Windows 10/11; Skyrim Special Edition or Anniversary Edition; exact installed framework/runtime versions must
  be verified
metadata:
  version: 4.3.0
  updated: '2026-07-22'
  library: overseer-skyrim-agent-skills
  error_registry_revision: 4.3.0
  final_pack_version: 4.3.0
---

# Skyrim runtime log forensics

Logs are parser/runtime evidence, not self-explanatory verdicts. Identify the
component that emitted the message and verify that component's exact source or
documentation before recommending a change.

## Required workflow

1. Record game runtime, framework/DLL version, log filename, timestamp, and the
   exact deployed file that generated the line.
2. Preserve the complete diagnostic line and enough neighboring context.
3. Identify the parser stage or subsystem that emitted the message.
4. Parse the affected configuration by fields. Never diagnose delimiters using
   a whole-line grep.
5. Separate:
   - syntax rejection;
   - unresolved form or dependency;
   - optional rule skipped;
   - feature disabled;
   - safe hook abort;
   - deterministic conflict winner;
   - missing asset;
   - ordinary informational noise.
6. Prove the root cause against installed source/docs or matching upstream
   source before mass-editing.
7. Make the smallest reversible correction in the owning mod's source/output,
   redeploy, and compare the new log.
8. Do not delete or edit active `Data` directly. Fix the owning mod or generated
   output and redeploy through the mod manager.

## High-risk interpretation rules

### SPID

- `Unsupported form type Weapon` means the distribution key is unsupported.
  For distributing a weapon or staff, current SPID uses `Item` or the generic
  `Form` key, not `Weapon`.
- `invalid stoul argument` is not enough to blame Traits or Chance. Inspect the
  field position. A LevelFilters value such as `65/` has an empty range endpoint
  and is malformed.
- `-D` is a valid starts-dead trait exclusion.
- A trailing `!` on Chance, such as `18!`, is valid deterministic chance.
- More than seven pipe-separated value sections is invalid.
- Comma-separated TraitFilters are invalid; slash-separated traits are correct.

### Native hooks

An address outside the expected executable `.text` section proves that the
candidate hook target is invalid for that installation. It does not prove which
other DLL, relocation, vtable layout, or runtime mismatch caused it. Require
module ownership, relocation/vtable index, runtime version, target bytes, and
section bounds before naming a culprit. A safe abort is preferable to installing
an unverified hook.

### Community Shaders

`<Feature>.ini failed to load, feature disabled` means the feature's own
descriptor was not loaded. For the current integrated architecture, descriptors
are sought under:

```text
Data\Shaders\Features\<FeatureShortName>.ini
```

A preset override cannot make an unloaded feature operational. Inspect winning
files and feature versions rather than assuming the preset installed the feature.

### Missing animations

A missing `.hkx` is not repaired by an A-pose suppressor. Resolve the animation
path to its owning behavior graph and source mod. A behavior generator can
regenerate supported behavior output, but it cannot invent an absent custom
creature animation.

### BOS

The last config alphabetically wins conflicts, but a deterministic winner is not
proof that the winning transform belongs to the affected reference/worldspace.
Inspect the specific reference, section, conditions, and intended patch.
Transform tokens such as `rotR(x,y,z)` must remain one token.

### Missing forms and dependencies

Classify each unresolved form as hard requirement, conditional requirement,
optional integration, or stale configuration. Do not claim a missing optional
plugin breaks the entire framework. Do not auto-delete a config until its owner
and intended feature are known.

Read `references/LOG-CASEBOOK.md`. Run `scripts/analyze_runtime_logs.py` for a
conservative first pass, then inspect every reported row manually.
