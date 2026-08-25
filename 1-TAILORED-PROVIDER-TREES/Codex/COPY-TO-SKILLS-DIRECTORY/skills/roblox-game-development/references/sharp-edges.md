# Sharp edges (things that bite every agent at least once)

Hard-won, verified against live Studio + MCP sessions. Read before your
first build session.

## MCP tool pre-parser quirks

- **No `+=` / `-=` / `*=` in tool-call code strings.** The pre-parser
  rejects augmented assignment. Write `x = x + 1`.
- Attribute access on results is unreliable across wrappers - prefer
  explicit indexing/locals in executed Luau.
- `execute_luau` needs `datamodel_type` (Edit / Client / Server). Server
  truth requires Server context; Edit context runs in edit mode where
  Players don't exist.

## Instance / math traps

- `Model:PivotTo(CFrame)` moves the whole model; `Part.CFrame = ...` moves
  one part. Setting PrimaryPart CFrame on a model does NOT move the rest.
- `WaitForChild` infinite-yield = wrong name or missing instance. Fix the
  cause; don't nil-guard around it reflexively.
- Kill bricks / Touched: debounce or the event refires every physics step.
- `Humanoid.Died` vs `Humanoid.Health <= 0` polling: prefer the event.
- Character may not exist yet when the player joins - use
  `player.CharacterAdded`, not `player.Character` at connect time.

## Workflow traps

- Editing StarterGui at runtime does nothing for existing players - edit
  PlayerGui copies.
- Edit-mode `execute_luau` cannot see play-mode state and vice versa.
- Multiple Studio sessions: every tool takes `studio_id`. Get it from
  `list_roblox_studios` first; guessing targets the wrong place.
- Console output is cumulative - filter by timestamp/your run, don't
  re-read ancient errors and "fix" them again.

## Agent traps (the meta-failures)

- Declaring done when scripts exist but nothing was playtested.
- "Visually verified" without having inspected a screenshot.
- Building 15 systems before proving one loop.
- Trusting client-sent numbers because "it's just a prototype" - prototypes
  get published.
