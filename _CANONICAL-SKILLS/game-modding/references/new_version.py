#!/usr/bin/env python3
"""Create a new immutable mod snapshot with a semantic version bump."""

from __future__ import annotations
import argparse
import datetime as dt
import re
import shutil
import sys
from pathlib import Path

SEMVER = re.compile(r"^(?P<major>0|[1-9]\d*)\.(?P<minor>0|[1-9]\d*)\.(?P<patch>0|[1-9]\d*)$")

def bump(version: str, kind: str) -> str:
    match = SEMVER.fullmatch(version)
    if not match:
        raise ValueError(f"Invalid semantic version: {version}")
    major, minor, patch = [int(match.group(x)) for x in ("major", "minor", "patch")]
    if kind == "major":
        return f"{major + 1}.0.0"
    if kind == "minor":
        return f"{major}.{minor + 1}.0"
    return f"{major}.{minor}.{patch + 1}"

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("project_root", type=Path)
    parser.add_argument("--bump", choices=("patch", "minor", "major"), default="patch")
    parser.add_argument("--ai", required=True)
    parser.add_argument("--summary", required=True)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    root = args.project_root.resolve()
    current_file = root / "CURRENT.txt"
    changelog = root / "CHANGELOG.md"
    ownership = root / "WORKSPACE_OWNERSHIP.md"

    for required in (current_file, changelog, ownership):
        if not required.is_file():
            raise FileNotFoundError(required)

    current_name = current_file.read_text(encoding="utf-8").strip()
    current_dir = root / current_name
    if not current_dir.is_dir():
        raise FileNotFoundError(current_dir)

    match = re.fullmatch(r"(?P<name>.+) (?P<version>\d+\.\d+\.\d+)", current_name)
    if not match:
        raise ValueError("CURRENT must contain '<Mod Name> X.Y.Z'")

    mod_name = match.group("name")
    old_version = match.group("version")
    new_version = bump(old_version, args.bump)
    new_name = f"{mod_name} {new_version}"
    new_dir = root / new_name
    if new_dir.exists():
        raise FileExistsError(new_dir)

    timestamp = dt.datetime.now(dt.timezone.utc).isoformat()
    entry = (
        f"\n## {new_version} - {timestamp}\n"
        f"- Parent: {old_version}\n"
        f"- AI: {args.ai}\n"
        f"- Planned change: {args.summary}\n"
        f"- Changed files: pending\n"
        f"- Validation: pending\n"
        f"- Runtime status: assistant-claimed\n"
        f"- Unresolved: pending\n"
    )

    if args.dry_run:
        print(f"Would copy {current_dir} -> {new_dir}")
        print(entry)
        return 0

    shutil.copytree(current_dir, new_dir, symlinks=True)
    current_file.write_text(new_name + "\n", encoding="utf-8")
    (new_dir / "VERSION.md").write_text(
        f"# {mod_name} {new_version}\n\n"
        f"- Parent: {old_version}\n"
        f"- Created: {timestamp}\n"
        f"- AI: {args.ai}\n"
        f"- Planned change: {args.summary}\n"
        f"- Previous snapshot untouched: YES\n",
        encoding="utf-8",
    )
    with changelog.open("a", encoding="utf-8", newline="\n") as handle:
        handle.write(entry)

    copied = sum(1 for path in new_dir.rglob("*") if path.is_file())
    print(f"Created: {new_dir}")
    print(f"Copied files: {copied}")
    print(f"CURRENT: {new_name}")
    print("Changelog entry: STARTED")
    return 0

if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
