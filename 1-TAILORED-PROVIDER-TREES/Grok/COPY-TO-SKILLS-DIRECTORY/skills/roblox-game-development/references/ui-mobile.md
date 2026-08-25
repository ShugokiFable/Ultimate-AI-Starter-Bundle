# Roblox UI, mobile, controller, and device verification

A Roblox UI is not complete because it looks good at one desktop resolution.

## Layout rules

Prefer:
- anchors/scale where appropriate,
- constraints/aspect ratios intentionally,
- padding/list/grid layout objects,
- readable contrast,
- safe-area aware placement,
- touch targets large enough to use,
- content hierarchy over decorative clutter.

Avoid:
- hardcoded pixel positions everywhere,
- tiny desktop-only buttons,
- text clipped at localization/scale changes,
- important HUD under platform chrome/notches,
- UI that requires hover.

## Input

Design actions around abstractions rather than only `MouseButton1Click`:
- touch,
- mouse/keyboard,
- gamepad where the game targets console/controller.

Use `ContextActionService` or other appropriate current APIs when input mapping matters.

## Roblox built-in skill accelerator

If the official Studio MCP exposes the `skill` capability, prefer Roblox's own
`rbx-device-simulator-lua` skill for form-factor checks.

Use it to test:
- phone portrait/landscape,
- tablet,
- PC,
- console/controller focus where applicable.

If that skill is not available externally, state the limitation and use the actual
device emulator/manual Studio tools that are available. Do not pretend a device test happened.

## Visual evidence

For a UI change:
1. open the UI in its real state,
2. capture screenshot,
3. inspect pixels if host vision exists,
4. test at least one small-screen form factor for meaningful UI,
5. fix clipping/overlap,
6. recapture final state.

Screenshot captured != screenshot inspected.
