HERMES PORTABLE STARTER — bundle v7.7.3

COPY-TO-PROVIDER-HOME\config.yaml is a machine-neutral starter:
- DeepSeek V4 Flash at reasoning=high, max_turns=350
- Compression trigger 250K tokens, lean tail
- Empty mcp_servers (AIO discovers houseCARL / Forge / Headroom)
- No username, no drive letter, no completeness-gate command line

INSTALL-V7-AIO.ps1 copies that file only if %LOCALAPPDATA%\hermes\config.yaml
does not exist. An existing Hermes config is left alone.

Do not paste a live config.yaml from one PC into this folder. The pack gate
fails any starter file that contains C:\Users\<name> or S:\Apps.

Unrestraint / SOUL prose is not in config.yaml. It is wired into SOUL.md by
the AIO preamble pass from 3-PREAMBLES and 0-UNRESTRAINT-PACKS.
