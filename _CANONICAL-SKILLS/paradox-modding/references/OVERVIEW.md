# Paradox Clausewitz / Jomini mod development

This skill supports routing for Stellaris, Hearts of Iron IV, Crusader Kings III,
Europa Universalis IV, and Victoria 3. Their script vocabularies are not
interchangeable.

## Common layers

- `.mod` and descriptor metadata;
- supported version and dependencies;
- namespaces and IDs;
- events, decisions, missions, focuses, situations, journals, or game-specific
  systems;
- scripted triggers, effects, values, modifiers, and localisation;
- on_actions;
- common/history/map/gfx/gui/interface directories;
- `replace_path`;
- launcher and Workshop packaging;
- checksum and multiplayer implications.

## Rules

- Never infer a trigger or effect from another Paradox game.
- Prefer additive files and uniquely namespaced IDs.
- Use `replace_path` only when the total replacement is intentional.
- Validate every localisation key and script database error.
- Test with `-debug_mode` and game-specific validation logs where supported.
