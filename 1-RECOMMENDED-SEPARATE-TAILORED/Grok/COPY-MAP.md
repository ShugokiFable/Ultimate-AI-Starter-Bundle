# Grok tailored V5 copy map

Copy all folders under `COPY-TO-SKILLS-DIRECTORY\skills` into `%GROK_HOME%\skills`. Default home: `%USERPROFILE%\.grok`.

No provider-home instruction file is installed; use the workspace instruction file.

Copy `COPY-TO-WORKSPACE\AGENTS.md` into the user-selected workspace root. No workspace name is assumed.

The registry is already at `%GROK_HOME%\skills\skyrim-memory\references\ERROR-REGISTRY.json`.

The preflight guard is at `%GROK_HOME%\skills\skyrim-versioned-workspace\scripts\guard.py`. Run it before any write or shell command.
## V5 extras

After copying skills, optionally:

1. Run pack `TOOLS\discover_tools.ps1` (from the pack root, not from skills).
2. Register MCP servers you installed (see `TOOLS\MCP-CONFIG-EXAMPLES.toml.txt`).
3. For Grok + codebase-memory: `TOOLS\Fix-Grok-Codebase-Memory-Direct.ps1`.
4. Fully restart the AI application.

Skills now include houseCARL helpers, Spooky modules, Superpowers, Ponytail, Headroom, CodeBurn, and discovery skills. Missing binaries are OK — the AI should recommend installs rather than assume paths.