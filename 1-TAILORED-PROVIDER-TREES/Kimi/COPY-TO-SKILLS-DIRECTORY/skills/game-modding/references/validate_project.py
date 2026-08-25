#!/usr/bin/env python3
"""Validate the immutable semantic-version project layout."""

from __future__ import annotations
import argparse
import re
from pathlib import Path

SEMVER_NAME = re.compile(r"^.+ \d+\.\d+\.\d+$")

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("project_root", type=Path)
    args = parser.parse_args()
    root = args.project_root.resolve()
    errors = []

    current_file = root / "CURRENT.txt"
    changelog = root / "CHANGELOG.md"
    ownership = root / "WORKSPACE_OWNERSHIP.md"
    for required in (current_file, changelog, ownership):
        if not required.is_file():
            errors.append(f"Missing: {required.name}")

    if current_file.is_file():
        current = current_file.read_text(encoding="utf-8").strip()
        if not SEMVER_NAME.fullmatch(current):
            errors.append("CURRENT.txt must contain '<Mod Name> X.Y.Z'")
        active = root / current
        if not active.is_dir():
            errors.append(f"CURRENT points to missing folder: {current}")
        elif not (active / "VERSION.md").is_file():
            errors.append(f"Active snapshot missing VERSION.md: {current}")
        if changelog.is_file():
            version = current.rsplit(" ", 1)[-1]
            if f"## {version}" not in changelog.read_text(encoding="utf-8"):
                errors.append(f"CHANGELOG.md has no entry for {version}")

    snapshots = [p for p in root.iterdir() if p.is_dir() and SEMVER_NAME.fullmatch(p.name)]
    if not snapshots:
        errors.append("No semantic-version snapshots found")

    if errors:
        print("PROJECT VALIDATION: FAIL")
        for error in errors:
            print(f"- {error}")
        return 1

    print("PROJECT VALIDATION: PASS")
    print(f"Snapshots: {len(snapshots)}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
