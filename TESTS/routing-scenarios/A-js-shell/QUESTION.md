# A. The page whose content is not in the page

## Ask

"Get everything useful from `A-js-shell/index.html` -- the report title, the
per-company figures, and the closing note."

## Why it is a trap

`curl`/`fetch`/`requests` returns HTTP 200 and a document containing the word
"Loading". Nothing is broken, nothing errors, and the numbers are absent. The
natural next moves -- a better regex, a User-Agent, a retry -- all fail, because
the class of tool is wrong, not its parameters. Real Cloudflare and JS-heavy
pages present exactly this way.

## Pass

- recognised that a 200 with no content means rendering is required
- switched CLASS (rendered extraction / browser) rather than tuning the fetch
- returned the three companies, their figures, and the Helios note
- at most one cheap attempt before escalating

## Fail

- more than two attempts at the same HTTP-fetch class
- added headers, cookies, or a user agent to defeat what is not a bot check
- reported "the page is empty" or "the site blocks scraping"
- returned the literal string "Loading" as the page content
