# Studio MCP reference (official built-in server)

Verified against a live handshake: 27 tools. The surface moves with Studio
updates — always confirm via `list_roblox_studios` + `rb_capabilities`, never
from memory.

## Tool map

| Group | Tools |
|---|---|
| Scripts | `script_read`, `multi_edit` (creates scripts too), `script_search`, `script_grep` |
| Data model | `search_game_tree`, `inspect_instance` |
| Luau execution | `execute_luau` (datamodel_type: Edit / Client / Server) |
| Playtest | `get_studio_state`, `start_stop_play`, `get_console_output`, `screen_capture` |
| Input | `character_navigation`, `user_keyboard_input`, `user_mouse_input` |
| Assets/AI gen | `generate_mesh`, `generate_material`, `generate_procedural_model`, `wait_job_finished`, `search_asset`, `insert_asset`, `upload_image`, `store_image`, `segment_mesh` |
| Docs/skills | `http_get` (allow-listed Roblox doc URLs), `skill` (Studio's own skills, e.g. debugging, device simulation) |
| Sessions | `list_roblox_studios` (returns studio_id; every call takes one) |

## Argument quirks (these cost real retries)

- **No `+=`.** The tool pre-parser rejects compound assignment. Write
  `counter = counter + 1`.
- **Attribute access on instances:** prefer explicit property gets through the
  documented paths; chained attribute expressions can be rewritten by the
  pre-parser in ways you did not intend. Assign to a local first:
  `local hum = char:FindFirstChildOfClass("Humanoid")` then use `hum`.
- **PivotTo takes a CFrame**, not a Vector3:
  `part:PivotTo(CFrame.new(Vector3.new(x, y, z)))`.
- **Every call needs `studio_id`** from `list_roblox_studios`. Two open places =
  two ids; pick deliberately.
- **`multi_edit` with a nonexistent path CREATES the script** — that is how you
  author new scripts. `datamodel_type` must match where it lives (Edit for
  design-time, Client/Server only meaningful during play).
- **`execute_luau` runs in the context you name.** Server truth must be
  verified by executing in `Server`; client behavior in `Client`.

## Subagents

- `subagent(type="explore")` for mapping an unfamiliar place's hierarchy and
  systems. Use before editing a game you did not build.
- `subagent(type="playtest")` for scenario verification (reach checkpoint,
  die, respawn). Prefer it over hand-driving input when it exists.

Do NOT use subagents for trivial single reads - direct tools are cheaper.

## Enable / connect facts

- Toggle lives in Studio: Assistant -> "..." -> Manage MCP Servers ->
  "Enable Studio as MCP server". Editor-side setting; no tool flips it.
- Launcher: `%LOCALAPPDATA%\Roblox\mcp.bat` (Windows) /
  `/Applications/RobloxStudio.app/Contents/MacOS/StudioMCP` (macOS).
- Green indicator under Manage MCP Servers confirms clients connected.
- Security warning from Roblox applies: connected clients can read AND modify
  your open place. Only connect trusted agents.
