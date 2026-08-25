# Roblox security and networking

Official baseline: **everything sent by a client is attacker-controlled**.

A RemoteEvent is a transport mechanism, not permission.

## Server validation layers

For any client-triggered state change, validate the layers that apply:

1. **Type** — correct primitive/table/Instance shape?
2. **Range** — sane numeric/string/table size?
3. **Context** — is this action possible right now?
4. **Permission/ownership** — does this player own/use the target?
5. **Spatial plausibility** — are they near the prompt/target if required?
6. **State transition** — is the requested transition legal?
7. **Rate** — can this be spammed?
8. **Server-derived value** — compute reward/damage/price server-side when possible.

## Bad

Client:
`RewardEvent:FireServer(1000000)`

Server:
`coins.Value += amount`

## Better model

Client:
`RewardEvent:FireServer(actionId)`

Server:
- verifies action exists,
- verifies player completed it,
- reads reward from server-owned config,
- applies reward once,
- records state/cooldown.

## RemoteEvent vs RemoteFunction

Use current docs when semantics matter.

General rule:
- Events are asynchronous notifications/requests.
- Functions are synchronous request/response and can create blocking/error coupling.
- Unreliable remotes are for high-frequency, non-critical data that may be dropped.

Never use an unreliable channel for authoritative purchases, inventory, or progression.

## Other exploitable boundaries

Do not focus only on remotes. Validate server effects triggered through:
- ProximityPrompt
- ClickDetector
- touched parts
- tools
- marketplace receipts
- teleport/admin commands
- trading systems
- physics ownership-sensitive mechanics

## Rate limiting

Rate-limit by action cost/risk, not one global magic number.

Store per-player timestamps/token buckets on the server.
Clean player state on `PlayerRemoving`.

## Creator Store models

Treat inserted scripts as untrusted code:
- inspect descendants,
- inspect Scripts/LocalScripts/ModuleScripts,
- inspect remotes,
- inspect require(assetId),
- delete unexplained behavior before shipping.

## Security completion check

Before calling a multiplayer feature complete:
- can a client award itself value?
- can it target another player's objects?
- can it send NaN/inf/huge strings/tables?
- can it replay the request?
- can it spam the request?
- can it skip required sequence/state?
