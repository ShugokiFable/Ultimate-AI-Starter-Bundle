HERMES PORTABLE STARTER

COPY-TO-PROVIDER-HOME\config.yaml is a machine-neutral starter. Every claim
below is checked against the actual file by TESTS/test_release_contract.py
(test_hermes_readme_matches_the_shipped_starter) -- through 7.9.7 this file
said "Empty mcp_servers" while the starter shipped five live servers, and
nothing was watching.

- DeepSeek V4 Flash, reasoning_effort=max, max_turns=null (unlimited)
- Compression at 120000 tokens, lean tail
- mcp_servers: {} -- empty, and it stays empty
- No username, no drive letter, no completeness-gate command line

WHY IT IS EMPTY

MCP registration is owned by INSTALL-V7-AIO.ps1 (the always-on core) and
TOOLS\Set-McpProfile.ps1 (capability profiles). Those read what is actually
installed on this machine and pick the scope each server belongs in. A
template cannot know any of that, and the copy is whole-file: anything left
here becomes a fresh-install default that outranks the bundle's own decisions.

Install-Provider-Starter-Settings.ps1 now refuses any starter template that
declares live MCP entries or an unpinned @latest package, in YAML, TOML or
JSON. The rule is enforced, not documented.

WEB CAPABILITY IS NATIVE, NOT AN MCP

Hermes v0.20.4 ships web_search / web_extract with a keyless vendor ring
(exa, parallel, tavily, firecrawl, keenable) that round-robins and fails over
on rate limits -- no key, no account. Measured against the alternative:
firecrawl-mcp is 25 tool schemas, 36,321 bytes, ~9,080 tokens on every turn,
and keyless it answers only search and scrape; map, crawl, agent and interact
all return "API key is required". That is the whole native capability, at
eight times the per-turn cost of the server 7.9.7 removed for being too
expensive. So the bundle does not register it for Hermes.

Install it deliberately with -WithExtras if you have a Firecrawl key and want
crawl/map/interact. See the capability-routing skill for when that is worth it.

INSTALL-V7-AIO.ps1 copies config.yaml only if %LOCALAPPDATA%\hermes\config.yaml
does not exist. An existing Hermes config is left alone.

Do not paste a live config.yaml from one PC into this folder. The pack gate
fails any starter file that contains C:\Users\<name> or S:\Apps.

Unrestraint / SOUL prose is not in config.yaml. It is wired into SOUL.md by
the AIO preamble pass from 3-PREAMBLES and 0-UNRESTRAINT-PACKS.
