"""Prove each fixture still exhibits the defect it was built to contain.

A benchmark that has quietly been repaired passes everything and measures
nothing. Scoring the agent is a judgement call; scoring the fixture is not.
"""
import io
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
failures = []


def check(name, ok, detail):
    print(("  ok   " if ok else "  FAIL ") + name + ("" if ok else " -- " + detail))
    if not ok:
        failures.append(name)


def read(*parts):
    with io.open(os.path.join(HERE, *parts), encoding="utf-8") as fh:
        return fh.read()


# A: the fixed header must still overlap the content, and the note must stay
# below AA contrast. Both are the defect; repairing either silently guts the
# scenario.
a = read("A-visual-defect", "index.html")
header_fixed = "position: fixed" in a
main_rule = re.search(r"main\s*\{([^}]*)\}", a)
main_body = main_rule.group(1) if main_rule else ""
check("A header still overlaps main",
      header_fixed and "padding-top" not in main_body and "margin-top" not in main_body,
      "main now clears the fixed header, so there is nothing to see")
check("A low-contrast note survives", "#9aa0aa" in a and "11px" in a,
      "the contrast defect was fixed in the fixture")

# B: the assets must still be missing/invalid.
assets = os.path.join(HERE, "B-broken-asset", "assets")
missing = [n for n in ("two.png", "three.png", "manifest.json")
           if not os.path.exists(os.path.join(assets, n))]
check("B assets are still missing", len(missing) == 3, "present: %r" % (missing,))
one = os.path.join(assets, "one.png")
with io.open(one, "rb") as fh:
    head = fh.read(8)
check("B one.png is still not a PNG", not head.startswith(b"\x89PNG"),
      "one.png became a real PNG")

# C and D: both must still crash, and only C must explain itself.
for scen, wants_log in (("C-crash-with-log", True), ("D-crash-no-log", False)):
    d = os.path.join(HERE, scen)
    proc = subprocess.run([sys.executable, os.path.join(d, "app.py")],
                          capture_output=True, text=True, cwd=d)
    check("%s still fails" % scen[0], proc.returncode != 0,
          "exit %d -- the fixture no longer reproduces" % proc.returncode)
    log = os.path.join(d, "app.log")
    if wants_log:
        has = os.path.exists(log) and "max_attempts" in read(scen, "app.log")
        check("C log still names the cause", has, "the log stopped explaining it")
    else:
        combined = (proc.stdout + proc.stderr)
        check("D still explains nothing", "max_attempts" not in combined,
              "the silent fixture now reveals the cause")

# C's config must still be the old shape, or neither C nor D fails for the
# reason they document.
for scen in ("C-crash-with-log", "D-crash-no-log"):
    cfg = json.loads(read(scen, "config.json"))
    check("%s config is still pre-1.3" % scen[0],
          "max_attempts" not in cfg.get("retry", {}),
          "the config was migrated, so the scenario is inert")

# Every scenario must still say how it is scored.
for name in sorted(os.listdir(HERE)):
    d = os.path.join(HERE, name)
    if not os.path.isdir(d) or name.startswith("."):
        continue
    has_rubric = any(os.path.exists(os.path.join(d, f))
                     for f in ("EXPECTED.md", "QUESTION.md"))
    check("%s has a rubric" % name, has_rubric, "no EXPECTED.md or QUESTION.md")

print()
if failures:
    print("EVIDENCE SCENARIOS: %d fixture(s) no longer test what they claim" % len(failures))
    sys.exit(1)
print("EVIDENCE SCENARIOS: fixtures intact")
