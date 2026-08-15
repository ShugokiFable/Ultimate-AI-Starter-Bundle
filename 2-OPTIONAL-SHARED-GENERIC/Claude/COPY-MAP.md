# Claude shared V5 copy map

Copy all skills into `%CLAUDE_CONFIG_DIR%\skills`. Copy the workspace instruction file into any user-selected workspace root. No workspace path is assumed. The error registry is embedded in `skyrim-memory\references`.

The preflight guard is at `%CLAUDE_CONFIG_DIR%\skills\skyrim-versioned-workspace\scripts\guard.py`. Run it before any write or shell command.

Copy the whole `COPY-TO-WORKSPACE\` tree into the workspace root, including `.claude\`. `.claude\settings.json` registers the guard as a `PreToolUse` hook; merge it into an existing `settings.json` rather than overwriting one.
## V5 extras

After copying skills, optionally:

1. Run pack `TOOLS\discover_tools.ps1` (from the pack root, not from skills).
2. Register MCP servers you installed (see `TOOLS\MCP-CONFIG-EXAMPLES.toml.txt`).
3. For Grok + codebase-memory: `TOOLS\Fix-Grok-Codebase-Memory-Direct.ps1`.
4. Fully restart the AI application.

Skills now include houseCARL helpers, Spooky modules, Superpowers, Ponytail, Headroom, CodeBurn, and discovery skills. Missing binaries are OK — the AI should recommend installs rather than assume paths.