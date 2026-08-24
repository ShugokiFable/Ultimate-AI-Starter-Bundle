---
name: headroom
description: Use Headroom for on-demand context compression, retrieval by hash, and session stats via MCP. Recommend install when missing. Not a Skyrim record editor.
metadata:
  version: 5.1.0
  upstream: https://github.com/headroomlabs-ai/headroom
---

# Headroom

Headroom saves context window by compressing large tool outputs and retrieving originals later.

Upstream: https://github.com/headroomlabs-ai/headroom

## Resolve

1. MCP tools present in session (`headroom_compress`, `headroom_retrieve`, …) → use them
2. Else CLI: `headroom --help` / `$env:HEADROOM_CMD`
3. Else recommend install

## Install recommendation

```text
pip install "headroom-ai[mcp]"     # tools only
pip install "headroom-ai[proxy]"   # proxy + tools
headroom mcp install               # where supported (e.g. Claude Code)
```

## When to use

- Huge logs, greps, JSON dumps, crash stacks before reasoning
- Need original later → keep the returned `hash` and `headroom_retrieve`

## When not to use

- Tiny snippets
- Replacing Skyrim domain skills
- Fabricating compression when MCP is down — just summarize carefully instead

## Multi-provider

Works with any MCP host (Claude, Cursor, Codex, Grok, …) once the server is registered. If registration fails, say so and continue without Headroom.

## Grok: MCP only. Never wrap Grok inference.

**Do not run `headroom wrap grok`, and do not set `GROK_MODELS_BASE_URL`, unless
the user has an `XAI_API_KEY`.**

Headroom's Grok proxy forwards to `https://api.x.ai` and authenticates with
`XAI_API_KEY` (`headroom/providers/grok/runtime.py` → `DEFAULT_API_URL`;
`headroom/cli/wrap.py` → `openai_api_url="https://api.x.ai"`).

A Grok **subscription / OIDC login** (`~/.grok/auth.json` with `auth_mode=oidc`)
does not use api.x.ai at all — its endpoint is
`https://cli-chat-proxy.grok.com/v1`. Headroom has no code path for it, so
wrapping such an account produces:

```text
model catalog: all retries exhausted  ("model catalog fetch returned no models")
  -> the model selector shows "unknown"; grok-4.5 becomes unselectable
Unauthorized (401) from http://127.0.0.1:8787/p/<project>/v1/chat/completions
  -> every turn fails
```

This is an auth-shape mismatch, not a misconfiguration. There is no flag that
makes the wrap work for a session login.

### Decide by auth mode

| `~/.grok/auth.json` | `XAI_API_KEY` | What Headroom may do |
|---|---|---|
| `auth_mode=oidc` (subscription) | absent | **MCP tools only** |
| any | present | MCP tools **+** optional inference wrap |

### Correct Grok setup

```text
.\TOOLS\Ensure-Headroom-Grok.ps1            # MCP registration, auth aware (default)
.\TOOLS\Ensure-Headroom-Grok.ps1 -CheckOnly # report, change nothing
.\TOOLS\Ensure-Headroom-Grok.ps1 -Repair    # undo a v5.0 wrap that broke Grok
.\TOOLS\Ensure-Headroom-Grok.ps1 -Wrap      # opt in; refuses without XAI_API_KEY
```

`[mcp_servers.headroom]` in `~/.grok/config.toml` gives Grok
`headroom_compress` / `headroom_retrieve` / `headroom_stats`. That is on-demand
compression the agent calls deliberately — it is **not** automatic traffic
compression, and for a subscription account it is the only mode available. Say
that plainly rather than promising auto-compress.

### Symptom → cause

If a user reports Grok showing an **"unknown" model**, or losing access to
grok-4.5, check in this order:

1. `GROK_MODELS_BASE_URL` / `GROK_MODEL_GROK_BUILD_BASE_URL` set to `127.0.0.1` → wrap is active, remove it
2. A `function grok` in the PowerShell profile calling `headroom wrap grok` → rename/remove it
3. `~/.headroom/deploy/default/manifest.json` with `grok` / `grok_build` in `targets` → `headroom install remove --profile default` (the deploy re-applies those env vars on every health check)
4. `~/.grok/models_cache.json` with `origin` pointing at `127.0.0.1` → delete it so Grok refetches the real catalog

Then start a **new** shell and run `grok`.

### Verify

```text
headroom install status
# For a subscription account the correct state is:
#   no GROK_* base-url env vars
#   no grok/grok_build deploy targets
#   [mcp_servers.headroom] present in ~/.grok/config.toml
#   ~/.grok/models_cache.json origin = https://cli-chat-proxy.grok.com/v1/models
```
