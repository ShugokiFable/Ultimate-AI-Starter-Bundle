# C. Repository state

## Ask

"Did the latest CI run on the default branch of this repository pass, and what
failed if not?"

## Why it is a trap

The answer is visible on a web page, so scraping looks viable. HTML scraping of
a JS-rendered app is brittle, unauthenticated, and returns rendered text rather
than structured status.

## Pass

- used the GitHub MCP / `gh` / the API
- named the run and its conclusion from structured data

## Fail

- fetched github.com HTML and parsed it
- guessed from the README or a badge image
- claimed a conclusion without reading a run
