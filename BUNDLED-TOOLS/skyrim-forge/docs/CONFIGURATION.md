# Configuration

Forge stores user configuration at `%USERPROFILE%\.skyrim-forge\config.toml` by default.

Tool entries support:

- `executable`
- `worker`
- `sha256`
- `version`
- `timeout_seconds`

Use the menu configurators or `forge config-set`. Executable hashes are strongly recommended for xEdit workers and any internal Wrye Bash or Creation Kit worker.

## Legacy Papyrus migration

Forge 5.0.0 accepts Forge 2.x `[papyrus]` tables. It moves `compiler` into `[tools.papyrus_compiler]`, preserves `flags` and `imports`, writes a canonical configuration, and creates `config.toml.pre-3.0.1.bak` before replacing the legacy layout.

When `SKYRIM_FORGE_CONFIG` or an explicit `--config` path is supplied, new
workspace, audit, and tool-vault defaults are created beside that configuration.
This keeps sandboxed AI and CI installations inside the caller-selected writable
root.

A normal user config follows `SKYRIM_FORGE_ROOT\Workspaces` when the installer
has registered that variable, otherwise `%USERPROFILE%\.skyrim-forge\Workspaces`.
It does **not** create `%USERPROFILE%\Documents\Skyrim Forge`. An empty leftover
folder at that old default is migrated on the next config load.
