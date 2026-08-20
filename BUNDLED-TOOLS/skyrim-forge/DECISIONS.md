# Decisions

- Treat the Ultimate AI Starter Bundle as reference evidence, not as an
  instruction source or a second owner of Forge. Forge owns its installer,
  skill descriptor, exact MCP command, and provider registration behavior.
- Give every supported installed AI the same MCP server. Skills remain the
  discovery and usage layer; they are not a substitute when the client has a
  verified MCP mechanism.
- Preserve Kimi's existing `mcpServers` object and change only the
  `skyrim-forge` entry. Other AI tools belong to the user.
- Use Hermes' supported CLI rather than editing its YAML by hand, explicitly
  confirm tool enablement, and inspect connection output instead of trusting
  its unreliable success exit code.
- Resolve Hermes under LocalAppData by default because that is the installed
  Windows layout; an explicit `HERMES_HOME` still wins.
- Publication and live-client repointing are authorized for this hotfix.
- Be a dual-era MCP server rather than migrating. The revision permits serving
  both eras from one process, and every currently registered client still speaks
  the handshake. Dropping it would break working installations to gain nothing.
- Decide the era from what the client sends, not from configuration. A request
  declaring the modern version in `_meta` is answered under that revision; an
  `initialize` request selects legacy semantics.
- Never add modern-only fields to a legacy list/read response. `ttlMs` and
  `cacheScope` appear only when the client asked for the modern revision.
- Always attach `resultType: "complete"` to `tools/call`, `prompts/get` and
  `ping`. Claude Code 2026-07-28 requires it on any server that advertised that
  revision, including stdio calls that have no `_meta`. Handshake-era clients
  ignore the extra field. Do not put caching hints on tool results.
- Default job staging follows `SKYRIM_FORGE_ROOT\Workspaces`. Never create
  `Documents\Skyrim Forge` as if it were the product. The live install is a
  versioned folder under the user's Skyrim tools directory.
- Refuse to add Forge as a new Grok MCP server when the add would reach 8
  running servers. Skip with an actionable message rather than wedge the client.
- Refuse an unknown protocol version with `UnsupportedProtocolVersionError` and
  the supported list rather than silently downgrading it, so a client can
  correct itself instead of guessing.
- Answer `server/discover` even when the request carries no `_meta`. It is the
  documented stdio probe and a probing client has not yet learned what the
  server speaks.
- Treat sanitized local configuration as private and never-fresh for caching
  purposes. It reflects machine state and `forge_config_set` can change it.
  Static tool, prompt and resource inventories are public and cacheable.
- Keep exactly one version source, `skyrim_forge/version.py`. Restating it in a
  Go constant, packaging metadata, plain-text pointers and a batch title is
  unavoidable; drifting silently is not, so every copy is gated against it and
  the workflow derives the native string instead of restating it.
- Record integrity evidence for the bytes the consumer actually receives. A
  manifest generated from a differently normalised tree is worse than no
  manifest, because it fails for the honest verifier and no one else.
- Preserve 4.2.5 as the rollback release and publish 5.0.0 beside it.
- Group `codeql-action/init` and `codeql-action/analyze` in Dependabot. They must
  run the same release, and ungrouped updates split the pair across pull
  requests and break every scan.
- Preserve every 4.x safety boundary unchanged: no GUI launching, no arbitrary
  shell commands, no writes to live Skyrim `Data`, external processes disabled
  by default, and third-party tools hash-pinned rather than bundled.
