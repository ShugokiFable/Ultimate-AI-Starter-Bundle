# Provider starter settings

These are **portable** defaults the AIO installer merges into a new user's
provider home. They are not a dump of any one machine.

| Provider | Template | Installed as | Merge rule |
|---|---|---|---|
| Claude | `Claude/COPY-TO-PROVIDER-HOME/settings.json` | `%USERPROFILE%\.claude\settings.json` | Fill missing keys only. Never replace `hooks` (completeness gate owns those) or `CLAUDE.md` (unrestraint/SOUL live there). |
| Codex | `Codex/COPY-TO-PROVIDER-HOME/config.toml` | `%USERPROFILE%\.codex\config.toml` | Copy only if the file does not exist. Never copy MCP, projects, or notify paths. |
| Grok | `Grok/COPY-TO-PROVIDER-HOME/config.toml` | `%USERPROFILE%\.grok\config.toml` | Copy if missing; otherwise keep live MCP and ensure `mcp-search` is disabled. `[compat.claude] skills = false` so Claude plugin skills (claude-mem) do not load. Budget: 7 configured / 6 while a plugin server loads. |
| Kimi | `Kimi/COPY-TO-PROVIDER-HOME/config.toml` | `%USERPROFILE%\.kimi-code\config.toml` | Copy only if missing so OAuth is not wiped. |
| Hermes | `Hermes/COPY-TO-PROVIDER-HOME/config.yaml` | `%LOCALAPPDATA%\hermes\config.yaml` | Copy only if missing. Never overwrite a live YAML (MCP, keys, hooks). |

## What is intentionally absent

- Any `C:\Users\...` or `S:\Apps\...` path
- Live MCP command lines (AIO discovers houseCARL / Forge / Headroom)
- Jailbreak / SOUL / AIO prose — that stays in `0-UNRESTRAINT-PACKS` and in
  `CLAUDE.md` / `AGENTS.md` / Hermes `SOUL.md`
- A subscription model name (Claude Fable, a pinned Codex runtime hash, …)

`INSTALL-AIO.ps1` installs these automatically. `-SkipStarterSettings` opts out.
Hermes `-SkipHermesConfig` still skips only Hermes.

A template that contains a user profile path is rejected by the installer and by
`TESTS\Test-Pack.ps1`.
