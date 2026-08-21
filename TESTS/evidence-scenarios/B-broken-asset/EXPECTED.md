# B. A grey box is a failed request, not a CSS bug

## The defect

`assets/two.png` and `assets/three.png` do not exist; `assets/one.png` exists
but is not a PNG. `assets/manifest.json` does not exist, so the fetch rejects
and the caption stays on its loading placeholder ("counting…").

Everything renders as grey boxes and a stuck label. The CSS is fine. An agent
that guesses will adjust `object-fit`, `background`, or the grid.

## Pass

- reproduced it in a browser
- read the console / network panel (404s, and a JSON parse failure)
- named the actual cause: missing files, not styling
- noticed the loading placeholder was left behind on failure
- fixed the cause, and gave the fetch a failure path

## Fail

- changed CSS and re-declared it fixed
- "the images are probably not loading, try a different path" with no check
