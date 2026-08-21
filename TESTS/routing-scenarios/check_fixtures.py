"""Prove each routing fixture still contains what it claims.

A and B are a matched pair: A's content must be reachable ONLY by rendering,
B's must be reachable WITHOUT it. If either drifts, the pair stops measuring
the distinction it exists for.
"""
import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
failures = []


def check(name, ok, detail=""):
    print(("  ok   " if ok else "  FAIL ") + name + ("" if ok else " -- " + detail))
    if not ok:
        failures.append(name)


def read(*parts):
    with io.open(os.path.join(HERE, *parts), encoding="utf-8") as fh:
        return fh.read()


def visible_text(html):
    """What a non-rendering fetch can actually see: markup minus script bodies."""
    return re.sub(r"(?is)<script.*?</script>", "", html)


# A: the payload must be invisible without executing JS.
a = read("A-js-shell", "index.html")
a_visible = visible_text(a)
hidden = ["Fabrikam", "907150", "Helios", "Q3 Revenue Review"]
leaked = [t for t in hidden if t in a_visible]
check("A payload is unreachable without rendering", not leaked,
      "visible in raw markup: %r" % (leaked,))
check("A still renders that payload via script",
      all(t in a for t in hidden) and "innerHTML" in a,
      "the fixture no longer injects the content it hides")

# B: the payload must be present WITHOUT executing anything.
b = read("B-static-page", "index.html")
b_visible = visible_text(b)
needed = ["Release Notes 4.2", "0.9s", "no migration step"]
absent = [t for t in needed if t not in b_visible]
check("B payload is readable with a plain fetch", not absent,
      "missing from raw markup: %r" % (absent,))
check("B needs no scripting at all", "<script" not in b.lower(),
      "a script crept into the static twin, collapsing the A/B contrast")

# Every scenario keeps a rubric with both verdicts.
for d in sorted(os.listdir(HERE)):
    full = os.path.join(HERE, d)
    if not os.path.isdir(full) or d.startswith("__"):
        continue
    q = os.path.join(full, "QUESTION.md")
    if not os.path.isfile(q):
        check("%s has a rubric" % d, False, "QUESTION.md missing")
        continue
    text = read(d, "QUESTION.md")
    check("%s rubric states pass and fail" % d,
          "## Pass" in text and "## Fail" in text,
          "a rubric with only one verdict cannot separate anything")

print("")
if failures:
    print("ROUTING SCENARIOS: %d fixture(s) no longer test what they claim" % len(failures))
    sys.exit(1)
print("ROUTING SCENARIOS: fixtures intact")
