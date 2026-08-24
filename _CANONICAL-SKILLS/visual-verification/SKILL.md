---
name: visual-verification
description: Use when creating, changing, debugging, or claiming completion of anything whose correctness includes how it LOOKS - a website, web or desktop UI, game, HUD, menu, rendered 3D scene, Blender/Unity/Godot output, generated image, icon, chart, responsive layout, gallery or preview. Also use on "make this UI better", "finish this app", "make it polished", "this button does nothing", "the preview is gray/blank", "fix the images", "it looks wrong/broken/ugly", or before saying a visual change is done.
---

# Visual Verification

## Core rule

**If appearance is part of the requirement, the rendered result is the evidence.**

Source code, DOM structure, CSS, a scene tree, a passing test suite and a clean
build are **not** proof that something looks right. They are proof that it was
described right. Those are different, and the gap between them is where almost
every "finished" UI that the user immediately calls broken lives.

## The loop

```
implement -> launch/render -> capture the actual output -> LOOK at it
   -> find defects -> fix -> render again -> look again -> only then done
```

The second look is not optional. See `verification-before-completion`: evidence
must come from the final state, so a screenshot taken before the last edit
proves nothing about what ships.

## First: can you actually see pixels?

"Look at the screenshot" is the easiest instruction in this pack to fake,
because the honest report and the fabricated one are the same sentence. These
are two different claims and only the second supports a completion claim:

```
a screenshot was captured        <- a file exists
the agent inspected the pixels   <- a model actually read the image
```

Settle it once per session, with a check that cannot be bluffed:

```powershell
TOOLS\Test-VisionCanary.ps1 -Word <word> -Shape <shape> -Color <colour>
```

Open `TOOLS\vision-canary\vision-canary.png` first and report what is in it. The
expected answer is stored only as a hash, so reading the repository is not a
substitute for looking.

**PASS** - inspect rendered output before every visual completion claim.

**FAIL** - that is an answer, not an error. Then:

- keep the screenshot as an artifact for the user or a capable agent;
- fall back to DOM / accessibility tree / computed styles / console / network /
  element geometry, which catch many of the defects below;
- say **"visual verification unavailable in this provider/session"** and name
  what remains unchecked. Never write "looks good" about pixels you did not see.

What each client can do changes with its version; test, do not assume. As
measured for this pack: Claude Code reads image files directly; `codex` and
`codex exec` accept `-i/--image`; grok, kimi and hermes showed no image-attach
flag in their `--help`. An MCP server that returns an image is only useful if
the client forwards it to the model - which the canary is how you find out.

## Getting the pixels

Cheapest sufficient route, in order. Do not turn on a browser stack to check a
README, and do not open a full browser when a render-to-file settles it.

| what | route |
|---|---|
| web page / app | the provider's own browser capability, else Playwright (CLI or MCP), screenshot to file |
| console errors, failed requests, computed layout | Chrome DevTools MCP - `web` profile |
| desktop app / EXE | launch it, screenshot the window, then close it and check it actually exited (`process-lifecycle-cleanup`) |
| Blender / Godot / Unity | render or capture through that engine's own capability - `engine-*` profiles |
| generated image or asset | open the file |

Capability profiles are per project and off by default; see
`capability-profiles`. Enable the one this task needs, not all of them.

## What to look for

AI-written UI fails in a small number of recognisable ways. Sweep for these
before anything subjective:

- overlapping or clipped elements; text overflowing its container
- content hidden behind a header, footer or fixed bar; off-screen controls
- broken, missing, wrong, stretched or low-resolution images
- blank or grey preview boxes; loading placeholders left behind
- unreadable contrast; text far too small
- modal, dropdown or tooltip positioned wrong; z-index/layering wrong
- horizontal scrollbar on the page body; layout collapse at mobile widths
- default browser or OS chrome showing where custom UI was intended
- controls that do not respond when actually clicked
- empty states that were never designed
- inconsistent spacing or visual hierarchy
- materially different from the reference design or what the user asked for

Then stop. This is a **closure** skill, not a design system: fix correctness,
usability, obvious polish defects and the user's stated requirements. Do not
drift into unbounded pixel-perfection.

## Interactions, not just appearance

A screenshot proves the first frame. If the requirement includes behaviour,
exercise it: click the control, submit the form, open the menu, resize to the
breakpoints that matter - then look again. Check the console for errors and the
network panel for failed requests when something is missing rather than ugly; a
grey box is usually a failed request, not a CSS bug, and guessing at CSS is how
that one gets fixed five times without being fixed. See `systematic-debugging`.

## Failed verification is the workflow working

Finding a defect is the point. Do not suppress it, do not weaken a check to make
it pass, and do not narrate a defect you have not fixed as if it were minor.
Observe, fix, render, look again.

## Report honestly

State which of these you did:

- rendered and inspected the actual output (say at what size/state)
- captured output but could not inspect it (say why; keep the artifact)
- verified structurally only - DOM/CSS/scene data (say what stays unverified)

"I checked the code and it should render correctly" is not any of the three.
