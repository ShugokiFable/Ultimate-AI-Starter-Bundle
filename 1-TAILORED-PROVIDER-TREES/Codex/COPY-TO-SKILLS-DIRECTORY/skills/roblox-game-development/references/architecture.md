# Roblox architecture — where code and authority belong

Roblox is client/server by default. The server is the authority for shared game state.

## Mental model

**SERVER OWNS TRUTH**
- currency
- inventory
- damage
- rewards
- progression
- matchmaking/round state
- ownership/permissions
- DataStores

**CLIENT OWNS INPUT + PRESENTATION**
- keyboard/gamepad/touch input
- camera
- local UI
- animation/effects that do not establish authoritative state
- prediction where the server still validates the result

**SHARED OWNS CONTRACTS + CONFIG**
- immutable/shared constants
- types
- utility modules safe for both sides
- network message schemas

## Service placement

| Location | Good uses |
|---|---|
| `ServerScriptService` | authoritative systems and server entry points |
| `ServerStorage` | server-only templates/assets not meant to replicate |
| `ReplicatedStorage` | shared modules, remotes, replicated assets/contracts |
| `StarterPlayerScripts` | client controllers/input/camera |
| `StarterCharacterScripts` | per-character client/server behavior when appropriate |
| `StarterGui` | ScreenGuis and client presentation |
| `Workspace` | live world/physics objects; not a dumping ground for application logic |

## Script types

- `Script`: server execution unless RunContext deliberately says otherwise.
- `LocalScript`: client execution in supported containers.
- `ModuleScript`: reusable code; authority depends on who requires it.

## Small-game baseline

Prefer a few coherent modules over framework ceremony:

- `ServerScriptService/Server/Game.server.luau`
- `ServerScriptService/Server/Systems/...`
- `ReplicatedStorage/Shared/...`
- `ReplicatedStorage/Remotes/...`
- `StarterPlayer/StarterPlayerScripts/Client.client.luau`
- `StarterGui/...`

## Anti-patterns

- one 2,000-line Script owning every system
- authoritative currency in LocalScripts
- client tells server how much damage/reward to apply
- RemoteEvent per tiny implementation detail
- replicated secrets/server-only configs
- loops scanning all descendants every frame
- scripts sprinkled randomly through Workspace
- adding Knit/Matter/Fusion/etc. because they are popular rather than needed

Use architecture proportional to the game.
