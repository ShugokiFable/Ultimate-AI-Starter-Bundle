"""Every declared copy of the pack version must agree with VERSION.txt.

The version is restated in files that cannot read each other: an installer
banner, a JSON catalog, two docs and a validation report. Restating is
unavoidable; drifting silently is not. v7.5.3 shipped with CATALOG.json still
declaring 6.8.0 -- seven minor versions behind -- because nothing checked.
"""
import io
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def read(rel):
    with io.open(os.path.join(ROOT, rel), encoding="utf-8-sig") as fh:
        return fh.read()


def main():
    version = read("VERSION.txt").strip()          # e.g. "v7.6.2"
    bare = version.lstrip("vV")                    # e.g. "7.6.2"
    print("VERSION.txt declares %s" % version)

    problems = []

    def check(rel, pattern, expected, label=None):
        try:
            text = read(rel)
        except OSError as exc:
            problems.append("%s: unreadable (%s)" % (rel, exc))
            return
        found = re.search(pattern, text, re.M)
        if not found:
            problems.append("%s: no version declaration matched %r" % (rel, pattern))
            return
        got = found.group(1)
        status = "ok" if got == expected else "MISMATCH"
        print("  %-8s %-34s %s" % (status, label or rel, got))
        if got != expected:
            problems.append("%s declares %s, expected %s" % (rel, got, expected))

    check("README.md", r"^# Ultimate AI Starter Bundle v([0-9]+\.[0-9]+\.[0-9]+)", bare)
    check("START-HERE.txt", r"^Ultimate AI Starter Bundle V([0-9]+\.[0-9]+\.[0-9]+)", bare)
    check("INSTALL-V7-AIO.ps1",
          r"Ultimate AI Starter Bundle v([0-9]+\.[0-9]+\.[0-9]+) - ALL-IN-ONE INSTALLER", bare,
          "INSTALL-V7-AIO.ps1 (banner)")
    check("INSTALL-V7-AIO.ps1", r"version = '([0-9]+\.[0-9]+\.[0-9]+)'", bare,
          "INSTALL-V7-AIO.ps1 (state)")
    # The two console titles are the first thing a fresh user sees. Nothing
    # checked them before 7.9.0, so both sat at v7.8.0 for the whole release.
    check("START-HERE.bat",
          r"^title Ultimate AI Starter Bundle v([0-9]+\.[0-9]+\.[0-9]+)", bare,
          "START-HERE.bat (title)")
    check("INSTALL-V7-AIO.bat",
          r"^title Ultimate AI Starter Bundle v([0-9]+\.[0-9]+\.[0-9]+)", bare,
          "INSTALL-V7-AIO.bat (title)")

    try:
        catalog = json.loads(read("BUNDLED-TOOLS/CATALOG.json"))
        got = catalog.get("pack_version")
        print("  %-8s %-34s %s" % ("ok" if got == bare else "MISMATCH",
                                   "BUNDLED-TOOLS/CATALOG.json", got))
        if got != bare:
            problems.append("CATALOG.json pack_version is %s, expected %s" % (got, bare))
    except Exception as exc:
        problems.append("CATALOG.json unreadable: %s" % exc)

    try:
        validation = json.loads(read("VALIDATION.json"))
        got = validation.get("version")
        print("  %-8s %-34s %s" % ("ok" if got == bare else "MISMATCH",
                                   "VALIDATION.json", got))
        if got != bare:
            problems.append("VALIDATION.json version is %s, expected %s" % (got, bare))
    except Exception as exc:
        problems.append("VALIDATION.json unreadable: %s" % exc)

    changelog = read("CHANGELOG.md")
    if not re.search(r"^## %s\b" % re.escape(bare), changelog, re.M):
        problems.append("CHANGELOG.md has no '## %s' section" % bare)
    else:
        print("  %-8s %-34s ## %s" % ("ok", "CHANGELOG.md", bare))

    history = os.path.join(ROOT, "docs", "history", "V%s-CHANGELOG.md" % bare)
    if not os.path.isfile(history):
        problems.append("docs/history/V%s-CHANGELOG.md is missing" % bare)
    else:
        print("  %-8s %-34s present" % ("ok", "docs/history/V%s-CHANGELOG.md" % bare))

    if problems:
        print("\nVersion drift:")
        for p in problems:
            print("  - %s" % p)
        return 1
    print("\nAll declared versions agree.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
