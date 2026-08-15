---
name: codeburn
description: Local-first AI coding token/cost analytics via CodeBurn CLI (npx codeburn). Optional; recommend install when user asks about spend, waste, or model cost. Not a Skyrim mod tool.
metadata:
  version: 5.0.0
  final_pack_version: 5.0.0
  upstream: https://github.com/getagentseal/codeburn
---

# CodeBurn

Local dashboards for AI coding token usage and estimated cost. Reads local session logs — no cloud upload of your code.

Upstream: https://github.com/getagentseal/codeburn  
Site: https://codeburn.app/

## Resolve

```text
codeburn --help
npx codeburn --help
```

## Install recommendation

```text
npx codeburn              # no global install
npm install -g codeburn   # Node.js 22.13+ recommended
```

## Common commands

| Command | Purpose |
|---|---|
| `npx codeburn` | Interactive TUI overview |
| `npx codeburn overview` | Text summary |
| `npx codeburn optimize` | Waste / inefficiency scan |
| `npx codeburn web` | Local web UI |

## Skyrim AI pack note

CodeBurn does not compile plugins or read ESP data. Use it when the user cares about **AI spend**, session efficiency, or comparing models — often alongside `ponytail` (write less) and `headroom` (send less).

If Node/npm is missing, recommend installing Node first, then CodeBurn.
