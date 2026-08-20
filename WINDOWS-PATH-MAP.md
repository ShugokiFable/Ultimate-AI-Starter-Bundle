# Provider-native Windows path map (V5)

This package does not assume a workspace name, drive letter, or username.

## Provider homes and skills

| Application | Provider home | Provider-native skills | Global instructions |
|---|---|---|---|
| Codex | `%CODEX_HOME%`, default `%USERPROFILE%\.codex` | `%CODEX_HOME%\skills` | `%CODEX_HOME%\AGENTS.md` |
| Claude Code | `%CLAUDE_CONFIG_DIR%`, default `%USERPROFILE%\.claude` | `%CLAUDE_CONFIG_DIR%\skills` | `%CLAUDE_CONFIG_DIR%\CLAUDE.md` |
| Grok Build | `%GROK_HOME%`, default `%USERPROFILE%\.grok` | `%GROK_HOME%\skills` | none installed; use workspace `AGENTS.md` |
| Kimi Code | `%KIMI_CODE_HOME%`, default `%USERPROFILE%\.kimi-code` | `%KIMI_CODE_HOME%\skills` | `%KIMI_CODE_HOME%\AGENTS.md` |
| Hermes Agent | `%HERMES_HOME%`, default `%USERPROFILE%\.hermes` | `%HERMES_HOME%\skills` | none installed; use workspace `AGENTS.md` |

The package intentionally avoids cross-tool shared skill directories for the
**tailored** edition. The optional generic edition is still per-provider copy.

Claude may also load plugin skills from Claude's plugin cache; pack skills remain
the portable baseline.

## Optional tool locations (discovered, not assumed)

| Tool | Discovery |
|---|---|
| Skyrim Forge | `SKYRIM_FORGE_ROOT` pointing at a **versionless** `Skyrim-Forge` folder (default `%LOCALAPPDATA%\Skyrim-Tools\Skyrim-Forge`). The installer migrates a `Skyrim-Forge-x.y.z` folder onto that name, because a version in the folder disconnects every provider's absolute MCP path on upgrade. Never Documents. |
| houseCARL MCP | `HOUSECARL_MCP` / `HOUSECARL_ROOT` / search `housecarl-mcp.exe` |
| Spooky toolkit | `SPOOKY_AUTOMOD_ROOT` (folder with `SpookysAutomod.sln`) |
| codebase-memory-mcp | `CODEBASE_MEMORY_MCP` or `%LOCALAPPDATA%\Programs\codebase-memory-mcp\` |
| Headroom | `headroom` on PATH or `HEADROOM_CMD` |
| CodeBurn | `codeburn` or `npx codeburn` |
| MO2 instance | `SKYRIM_MO2_INSTANCE` (folder with `ModOrganizer.ini`) |

Run `TOOLS\discover_tools.ps1` after install.

## Workspace

The workspace is whichever directory the user chooses for Skyrim AI work. It can
be on any drive and can be shared by every supported application.

Files installed in a selected workspace:

```text
<WORKSPACE_ROOT>\AGENTS.md
<WORKSPACE_ROOT>\CLAUDE.md
<WORKSPACE_ROOT>\_PROJECT-TEMPLATE\
```

## Error registry

```text
<PROVIDER_NATIVE_SKILLS>\skyrim-memory\references\ERROR-REGISTRY.json
```

## MCP config (V5)

See `TOOLS\MCP-CONFIG-EXAMPLES.toml.txt` and `TOOLS\Fix-Grok-Codebase-Memory-Direct.ps1`.
Always fully restart the AI app after MCP edits.

## houseCARL instance / Vortex shim

| Item | Default |
|---|---|
| Setup script | `TOOLS\Setup-HouseCarl.ps1` |
| Vortex shim root | `%LOCALAPPDATA%\houseCARL-Shim` |
| Setup state | `%LOCALAPPDATA%\houseCARL-data\v5-setup-state.json` |
| MCP env | `HouseCarl__Mo2InstanceDir` = instance or shim |
| User env | `SKYRIM_MO2_INSTANCE`, `HOUSECARL_MCP` |

Run setup once per machine; `-RefreshOnly` after Vortex load-order changes.
