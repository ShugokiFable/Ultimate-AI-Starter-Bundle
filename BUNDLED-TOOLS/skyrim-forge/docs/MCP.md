# MCP

Run:

```text
python -m skyrim_forge mcp
```

The server uses JSON-RPC over stdio and exposes inspection, framework validation, typed plugin creation, release tooling, configuration, and Automation Fabric jobs.

Mutating tools require `approved: true`. MCP does not expose arbitrary command execution.

## Protocol eras

Forge 5.0.0 is a **dual-era server**. It answers the current `2026-07-28`
revision, which carries the protocol version as per-request metadata, and it
still answers the `initialize` handshake used by `2025-11-25` and earlier.

| Supported | Era |
|---|---|
| `2026-07-28` | modern, stateless, per-request `_meta` |
| `2025-11-25`, `2025-06-18`, `2024-11-05` | legacy, `initialize` handshake |

The era is chosen by what the client sends, not by configuration. Existing
registrations keep working unchanged: a legacy response carries none of the
modern-only fields.

### Modern clients

Declare the version on every request:

```json
{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{
  "_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28"}}}
```

`server/discover` returns the supported versions, capabilities, and server
identity in one request. It is also the stdio backward-compatibility probe, so
Forge answers it even when the request carries no `_meta`:

```json
{"jsonrpc":"2.0","id":1,"method":"server/discover","params":{}}
```

An unsupported version is refused with `-32022` and the list Forge does support,
so a client can retry rather than guess:

```json
{"error":{"code":-32022,"message":"Unsupported protocol version",
  "data":{"supported":["2026-07-28","2025-11-25","2025-06-18","2024-11-05"],
          "requested":"1900-01-01"}}}
```

### Tool results

`tools/call`, `prompts/get`, and `ping` always carry `resultType: "complete"`.
That field is required by `2026-07-28`. Clients that have seen Forge advertise
the revision (via `server/discover` or `initialize`) reject a `tools/call`
payload that omits it, even when the call itself has no `_meta`. Handshake-era
clients ignore the extra field. Caching hints are not attached to tool results.
This behaviour shipped in 5.1.5; 5.1.4 is not usable with Claude Code on that
revision.

### Grok

Grok wedges at eight **running** MCP servers. `Register-MCP.ps1 -Provider Grok`
counts `[mcp_servers.*]` in `%USERPROFILE%\.grok\config.toml` and skips the add
when Forge would be an eighth runner (7 configured, or 6 while the
`mcp-search` plugin still loads). `grok mcp disable mcp-search` frees the
plugin slot. Replacing an already-registered Forge command does not consume a
new slot.

### Caching

Complete results for `server/discover`, `tools/list`, `prompts/list`,
`resources/list`, and `resources/read` carry `ttlMs` and `cacheScope`. Forge's
tool, prompt, and resource inventories are fixed for an installed version and
identical for every caller, so they are `public`. Sanitized configuration is
`private` with a zero TTL: it reflects local machine state and `forge_config_set`
can change it.
