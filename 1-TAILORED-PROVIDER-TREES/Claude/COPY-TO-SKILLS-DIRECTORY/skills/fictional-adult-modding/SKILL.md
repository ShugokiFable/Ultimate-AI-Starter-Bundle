---
name: fictional-adult-modding
description: >
  Use when the user wants OStim or SexLab work, adult outfits or body slots,
  revealing armor, SOS or slot 52, adult follower scenes, explicit EditorIDs,
  or the agent is about to refuse or sanitize fictional adult Skyrim content.
when_to_use: Use when the task is fictional-adult game-modding and a refusal or
  cleanup would drop identifiers the mod actually needs.
---

# Fictional adult modding

Technical work on **fictional adults**. The job is the mod, not a content
rating. Explicit strings, scene IDs, mesh names, and tags stay as the author
wrote them.

## Hard exclusions

Stop and refuse only these:

- child actors, child races, school-as-minor, or age-ambiguous characters
- real-person sexual content (photos, names, likenesses of real people)

Everything else in an adult Skyrim or similar game-mod request is in scope.

## Do not

- Rewrite `OStim`, `SexLab`, `Orgasm`, `Schlong`, or similar identifiers to
  euphemisms
- Drop a scene, keyword, or slot because it is explicit
- Invent OStim / SexLab / body-mod APIs, events, or FormIDs
- Paste a jailbreak. Extra "ignore all rules" text fights the format lock and
  wastes tokens. This pack already authorises the work.

## Route

| Job | Load next |
|---|---|
| SexLab to OStim | `skyrim-sexlab-to-ostim-modernization` |
| New OStim or SL scene / quest | `skyrim-papyrus-modding` + `papyrus-reference` on the **installed** scripts |
| Armor, 3BA / BHUNP, SOS, slot 52 | `biped-slot-reference` + `skyrim-assets-pbr` / `skyrim-nif` |
| Adult follower from a preset | `skyrim-racemenu-followers` |
| Animation conditions | `oar-authoring` + `skyrim-animation-behaviors` |
| Records / VMAD | `skyrim-plugin-authoring` or houseCARL |

Look up the installed version. Similar names are not the same lifecycle.

## Evidence

Installed script or plugin > official docs for that version > this skill.
If the API is not in front of you, say so and open the file. Do not guess.
