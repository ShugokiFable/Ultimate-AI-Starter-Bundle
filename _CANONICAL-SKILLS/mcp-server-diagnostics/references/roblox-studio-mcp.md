# Roblox Studio MCP bridge (case study: "No clients connected")

## Architecture

Client (Hermes) → stdio → `%LOCALAPPDATA%\Roblox\mcp.bat` → `StudioMCP.exe`
(ships inside `Versions\version-*\`) → TCP 127.0.0.1:13469 → RobloxStudioBeta.exe.

- `mcp.bat` hardcodes the current version folder with a registry fallback
  (`HKCU\Software\Roblox\RobloxStudio` → `ContentFolder`). Roblox's own bat
  prints harmless `'else' is not recognized` cmd noise; branch 1 still launches.
- Studio's Assistant Settings → MCP Servers master toggle must be ON (persisted
  in `%LOCALAPPDATA%\Roblox\AssistantSettings\<uid>.json` → `mcp-server.enabled`).
- ~27 tools: `execute_luau`, `search_game_tree`, `script_read`/`multi_edit`,
  `start_stop_play`, `get_console_output`, `screen_capture`,
  `list_roblox_studios`, ...

## Lifecycle — why "No clients connected" is normal

`StudioMCP.exe` is NOT a background service: it exists only while an MCP client
session holds the stdio pipe open. `hermes mcp test` = ~1s connect/disconnect,
so the panel returns to "No clients connected". Between sessions Studio sits in
`SYN_SENT` to 127.0.0.1:13469 (polling for the broker) — that is the healthy
waiting state, not an error. When a real session spawns the bridge, Studio
latches within ~5s and the panel shows the client.

## End-to-end verification recipe

1. `hermes mcp test roblox-studio` — proves transport + tool discovery only.
2. Live session probe (official SDK, NOT hand-rolled framing):

```python
import asyncio
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

async def main():
    params = StdioServerParameters(command="cmd.exe",
        args=["/c", "cd /d %LOCALAPPDATA%\\Roblox && .\\mcp.bat"])
    async with stdio_client(params) as (r, w):
        async with ClientSession(r, w) as s:
            await s.initialize()
            res = await s.call_tool("list_roblox_studios", {})
            print(res.content)  # {"studios":[]} right after connect;
                                # open places appear within ~5s

asyncio.run(main())
```

3. `netstat -ano | findstr 13469` — `LISTENING` (bridge up) plus an
   `ESTABLISHED` pair (Studio attached) = healthy. `SYN_SENT` only = no bridge
   running (expected between client sessions).

## Hermes config (working example)

```yaml
roblox-studio:
  command: cmd.exe
  args: [/c, "cd /d %LOCALAPPDATA%\\Roblox && .\\mcp.bat"]
```

Added with (the `echo Y` answers the interactive "Enable all N tools?" prompt
that otherwise cancels the add in a non-TTY shell):

```
echo Y | hermes mcp add roblox-studio --command cmd.exe --args /c 'cd /d %LOCALAPPDATA%\Roblox && .\mcp.bat'
```
