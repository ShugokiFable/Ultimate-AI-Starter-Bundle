# Roblox game-design intelligence for coding agents

Before systems, identify the loop:

**ACTION -> FEEDBACK -> REWARD/PROGRESS -> REASON TO REPEAT**

For every game, define:
- first action within ~30 seconds,
- first meaningful reward,
- first visible progression,
- failure/friction,
- next short-term goal.

## Weak-model failure

"Simulator" -> pets + rebirths + 8 currencies + shops + codes + quests before the
basic action is satisfying.

## Better

One action feels good -> one server-authoritative reward -> one upgrade changes the
action -> UI clearly communicates it -> then add retention/progression layers.

## Roblox presentation

Prioritize:
- readable spawn,
- obvious first objective,
- strong feedback (animation/VFX/SFX/UI),
- landmarks,
- consistent palette,
- scale and traversal appropriate to avatars,
- short time-to-fun.

Do not polish a broken loop. Do not ship a technically working graybox if the loop
is proven and the tools allow inexpensive polish.
