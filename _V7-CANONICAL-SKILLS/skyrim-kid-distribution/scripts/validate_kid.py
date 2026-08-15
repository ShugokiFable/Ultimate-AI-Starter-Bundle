#!/usr/bin/env python3
from __future__ import annotations
import argparse, re
from pathlib import Path

SIGNATURES = {
    "AACT","ACTI","ALCH","AMMO","ARMO","BOOK","CONT","FLOR","FURN","INGR",
    "KEYM","LIGH","MGEF","MISC","NPC_","SCRL","SLGM","SPEL","TACT","TREE","WEAP"
}
REMOVED_LONG_TYPE = re.compile(r"Keyword\s*=\s*[^|]+~[^|]+\|(?:OR|AND)\|", re.I)

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("paths", nargs="+", type=Path)
    args = ap.parse_args()
    errors = []
    for path in args.paths:
        if not path.name.lower().endswith("_kid.ini"):
            errors.append(f"{path}: filename must end in _KID.ini")
            continue
        for no, raw in enumerate(path.read_text(encoding="utf-8-sig", errors="replace").splitlines(), 1):
            line = raw.strip()
            if not line or line.startswith((";", "#", "[")):
                continue
            if REMOVED_LONG_TYPE.search(line):
                errors.append(f"{path}:{no}: removed long-type KID dialect")
            if "=" not in line:
                errors.append(f"{path}:{no}: active line has no '='")
                continue
            fields = [x.strip() for x in line.split("=", 1)[1].split("|")]
            sigs = [x for x in fields if re.fullmatch(r"[A-Z_]{4}", x)]
            for sig in sigs:
                if sig not in SIGNATURES:
                    errors.append(f"{path}:{no}: unknown record signature {sig}")
            if len(fields) < 3:
                errors.append(f"{path}:{no}: too few pipe fields")
    for error in errors:
        print("FAIL:", error)
    print("RESULT:", "FAIL" if errors else "PASS")
    return 1 if errors else 0

if __name__ == "__main__":
    raise SystemExit(main())
