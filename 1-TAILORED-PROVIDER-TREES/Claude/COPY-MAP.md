# Claude tailored V5 copy map

Copy all folders under `COPY-TO-SKILLS-DIRECTORY\skills` into `%CLAUDE_CONFIG_DIR%\skills`. Default home: `%USERPROFILE%\.claude`.

Copy `COPY-TO-PROVIDER-HOME\CLAUDE.md` to `%CLAUDE_CONFIG_DIR%\CLAUDE.md`.

`INSTALL-AIO.ps1` merges `COPY-TO-PROVIDER-HOME\settings.json` into
`%CLAUDE_CONFIG_DIR%\settings.json` (missing keys only). It never replaces
`hooks` (completeness gate) or `CLAUDE.md` (`0-UNRESTRAINT-PACKS` / SOUL).

Copy `COPY-TO-WORKSPACE\CLAUDE.md` into the user-selected workspace root. No workspace name is assumed.

The registry is already at `%CLAUDE_CONFIG_DIR%\skills\skyrim-memory\references\ERROR-REGISTRY.json`.

The preflight guard is at `%CLAUDE_CONFIG_DIR%\skills\skyrim-versioned-workspace\scripts\guard.py`. Run it before any write or shell command.

Copy the whole `COPY-TO-WORKSPACE\` tree into the workspace root, including `.claude\`. `.claude\settings.json` registers the guard as a `PreToolUse` hook; merge it into an existing `settings.json` rather than overwriting one.
## V5 extras

After copying skills, optionally:

1. Run pack `TOOLS\discover_tools.ps1` (from the pack root, not from skills).
2. Register MCP servers you installed (see `TOOLS\MCP-CONFIG-EXAMPLES.toml.txt`).
3. For Grok + codebase-memory: `TOOLS\Fix-Grok-Codebase-Memory-Direct.ps1`.
4. Fully restart the AI application.

Skills now include houseCARL helpers, Spooky modules, Superpowers, Ponytail, Headroom, CodeBurn, and discovery skills. Missing binaries are OK — the AI should recommend installs rather than assume paths.