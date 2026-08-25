# Headless browser verification of HTML/canvas artifacts (this PC)

Context: the user runs **Opera GX — there is no Chrome installed**. Several
browser-tooling paths fail on this machine; use the working path below.

## Failure modes (do not repeat)

1. **Playwright MCP (Hermes)** — configured for `channel: 'chrome'`; errors with
   `Chromium distribution 'chrome' is not found at %USERPROFILE%\AppData\Local\Google\Chrome\Application\chrome.exe`.
   No Chrome exists on this PC. Do NOT `npx playwright install chrome` — that
   pulls Google Chrome onto the machine.
2. **browser_exec (browser-use CLI harness)** — attaches to the user's REAL
   Chrome and opens `chrome://inspect/#remote-debugging`, which requires a human
   to tick "Allow remote debugging". Not usable for autonomous verification.
3. **vision_analyze** — USED TO fall back to an OpenRouter vision model and fail
   with HTTP 404 `All providers have been ignored`. As of Aug 2026 sessions it
   works again (returned detailed descriptions repeatedly). Still: verify pixel
   content programmatically in-page first; use vision_analyze only for
   aesthetics (and treat its verdicts skeptically — it loops on pareidolia and
   hallucinates details that don't exist).

## Working path: temp-dir playwright + headless chromium

```bash
PW="$LOCALAPPDATA/Temp/pwcheck"        # reusable; browsers live in the shared cache
mkdir -p "$PW" && cd "$PW" && npm init -y >/dev/null 2>&1
PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm i playwright --no-audit --no-fund
npx playwright install chromium        # downloads to %LOCALAPPDATA%\ms-playwright
```

npm 12 blocks postinstall scripts anyway, so the explicit
`npx playwright install chromium` is required. The browsers land in the shared
ms-playwright cache (also used by the playwright MCP).

Driver script pattern (plain node, `require('playwright')` from that dir):

```js
const { chromium } = require('playwright');
(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
  const errs = [];
  page.on('pageerror', e => errs.push('pageerror: ' + e.message));
  page.on('console', m => { if (m.type() === 'error') errs.push('console: ' + m.text()); });
  await page.goto('file:///%USERPROFILE%/Artifact.html'); // URL-encode spaces
  await page.waitForTimeout(1500);
  // read state twice ~450ms apart to prove an animation is live
  await page.screenshot({ path: '%USERPROFILE%/verify.png' });
  await browser.close();
})();
```

## Proving a canvas animation is live

Temporary debug-hook pattern: expose `window.__stageInfo = { t, positions }`
each frame in the rAF loop, read it twice via `page.evaluate`, compare
positions — moved = animating. **Remove the hook before final delivery** (it is
scaffolding, not part of the artifact).

## Pixel verification without vision (the important part)

In-page `ctx.getImageData` works — the canvas is same-origin and readable:

- Map logical → device coords: `DPR = canvas.width / innerWidth`;
  `s = min(W/BW, H/BH) * 0.98`; `ox,oy` centering; device px =
  `(ox + x*s) * DPR`.
- Window-average small regions (radius 8–14 px) rather than single pixels, to
  survive outlines/glints.
- **Pitfall (hit live this session): sampling STALE positions while the
  animation keeps running returns wrong colors** — the frame moves between
  state capture and sampling. Either temporarily freeze the animation, or scan
  a REGION for expected colors (e.g. sweep the airspace above the head for
  red/green/blue pixels) instead of trusting exact points.
- Add a `canvasNonBgPct` guard (fraction of pixels brighter than background)
  as a blank-canvas check.

## Opening results in the user's browser (Opera GX)

```bash
cmd //c start "" "%USERPROFILE%\AppData\Local\Programs\Opera GX\opera.exe" "file:///%USERPROFILE%/Artifact.html"
```

(git-bash: `//c` escapes `/c`; empty quoted title comes first.)

## Housekeeping

- Delete stray verification screenshots from the user's home dir before
  finishing; keep ONE screenshot to attach inline via `MEDIA:` path in the
  final reply so the user sees the result immediately.
- `$LOCALAPPDATA/Temp/pwcheck` can stay — it is reusable; the browser binaries
  live in the shared cache regardless.
