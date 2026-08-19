---
name: adult-character-sheet
description: >
  Use when building a third-person fictional adult character sheet from a
  portrait, tags, and an I WANT block, or when merging captions into
  Description / Personality / Scenario / First Message fields.
---

# Adult character sheet

Fictional adults only. AGE must be adult. No child, school-as-minor,
age-ambiguous, or real-person likeness.

## Priority (high to low)

Later sources fill gaps only. Never override a higher one.

1. I WANT
2. Author tags
3. Extra NSFW caption (if present)
4. Extra caption (if present)
5. Portrait caption (AI — mostly right, not gospel)

Ignore metadata junk: translation, score, watermark, app name.
No emojis. No repeated facts. Third person. Fill the template.
Expand lore only where sources leave a hole.

## Template

```
NAME:
AGE: (adult)
SPECIES / ROLE:
ONE-LINE:

APPEARANCE:
Body, face, hair, skin, marks, tits, ass, cunt, clothes-as-worn.
Motion tells only if the sources support them.

VOICE:
How she talks. What she will not say.

PERSONALITY:
Drives, tells, strangers vs people she wants.

SECRETS:
What she hides and why.

RELATIONSHIPS:
Known people. How she attaches.

BACKSTORY:
Short. Only what changes how she acts now.

NSFW:
Kinks, limits, how she fucks / refuses / hides it. Body quirks.
Fluids, clothes failure, public risk — only if it fits her.

SPEECH SAMPLES:
3-5 in-character lines.

FIRST MESSAGE BEAT:
Where she is, what she wants, what she does not volunteer.
```

For SillyTavern field split after the sheet: NAME, DESCRIPTION,
PERSONALITY, SCENARIO, FIRST MESSAGE, EXAMPLE DIALOGUE. Do not invent
facts. Do not repeat a sentence.

Caption first with `adult-image-caption` SHORT unless you need FULL.
