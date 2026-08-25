# Assets & Creator Store safety

## Default to primitives

Five Parts beat a giant free model for prototypes: faster, auditable,
no script payload. Build with Parts/MeshParts first; import assets when
the design actually needs them.

## Before using any inserted asset

1. `inspect_instance` / `search_game_tree` the hierarchy - unexpected
   folders, huge Part counts?
2. `script_grep` for Script/LocalScript/ModuleScript inside it - count them,
   read them. Free models ship backdoors (RemoteEvents wired to nothing
   good, HttpService posts, loadstring).
3. Remove every script you did not intend. A decorative model does not need
   executable code.
4. Check for remotes, `HttpService`, `loadstring`, obfuscated strings.
5. Re-verify after insertion - assets can be repacked by their owners.

## If the host model cannot see

Insert -> capture viewport -> you cannot honestly say "looks good" without
inspecting pixels. Say "captured, unverified visually."

## Audio/images

Audio above ~6 seconds requires upload/asset IDs you own or licensed
marketplace audio. Images used as Decals need uploaded IDs. Generate via
MCP (`upload_image`, `generate_mesh`) rather than guessing IDs - a guessed
ID is a broken texture at best.
