#!/usr/bin/env python3
from __future__ import annotations
import argparse, re
from pathlib import Path

FORBIDDEN = re.compile(r"\bitemsRemove\b", re.I)
BEHAVIOR = re.compile(r"\b(?:Confidence|Aggression|Assistance|Morality)\b", re.I)

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("paths", nargs="+", type=Path)
    ap.add_argument("--allow-behavior-stats", action="store_true")
    args = ap.parse_args()
    errors = []
    for path in args.paths:
        parts = [p.casefold() for p in path.parts]
        try:
            idx = parts.index("skypatcher")
        except ValueError:
            errors.append(f"{path}: not under a SkyPatcher directory")
            continue
        if len(parts) <= idx + 2:
            errors.append(f"{path}: file is in SkyPatcher root; category folder required")
        text = path.read_text(encoding="utf-8-sig", errors="replace")
        if FORBIDDEN.search(text):
            errors.append(f"{path}: unsupported/unverified itemsRemove field")
        if BEHAVIOR.search(text) and not args.allow_behavior_stats:
            errors.append(f"{path}: behavior stats require explicit opt-in")
    for error in errors:
        print("FAIL:", error)
    print("RESULT:", "FAIL" if errors else "PASS")
    return 1 if errors else 0

if __name__ == "__main__":
    raise SystemExit(main())
