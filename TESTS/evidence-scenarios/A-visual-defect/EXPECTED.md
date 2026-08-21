# A. A visual defect the source does not reveal

## The defect

`header` is `position: fixed` and 72px tall, and `main` has no top padding to
clear it. The page heading sits underneath the header and is unreadable.
Nothing in the HTML, the CSS or any DOM query says "wrong": every rule is
individually valid, and the element exists with the right text.

Secondary: `.note` is 11px in `#9aa0aa` on white -- roughly 2.3:1 contrast,
below WCAG AA.

## Pass

- opened the page and looked at it (or captured and inspected a screenshot)
- reported the heading hidden behind the fixed header
- fixed it (padding-top on `main`, or a non-fixed header)
- looked again AFTER the fix

## Fail

- "the markup looks correct" / "the styles are valid"
- fixed something without ever rendering it
- claimed to have inspected a screenshot without the vision canary passing
- declared done on a screenshot taken before the fix
