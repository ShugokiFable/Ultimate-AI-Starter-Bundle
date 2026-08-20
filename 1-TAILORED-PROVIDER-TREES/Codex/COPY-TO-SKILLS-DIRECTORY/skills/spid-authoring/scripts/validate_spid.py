#!/usr/bin/env python3
from __future__ import annotations
import argparse, re, sys
from pathlib import Path

TRAITS = set("MFUCSLTD")
PLUGIN_RE = re.compile(r"\b[\w .'-]+\.(?:esm|esp|esl)\b", re.I)
RAW_FORM_RE = re.compile(r"(?:0x)?[0-9A-F]{6,8}(?:~[\w .'-]+\.(?:esm|esp|esl))?", re.I)

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("paths", nargs="+", type=Path)
    args = ap.parse_args()
    errors = []
    for path in args.paths:
        if not path.name.lower().endswith("_distr.ini"):
            errors.append(f"{path}: filename must end in _DISTR.ini")
            continue
        for no, raw in enumerate(path.read_text(encoding="utf-8-sig", errors="replace").splitlines(), 1):
            line = raw.strip()
            if not line or line.startswith((";", "#", "[")):
                continue
            if "=" not in line:
                errors.append(f"{path}:{no}: active line has no '='")
                continue
            fields = line.split("=", 1)[1].split("|")
            # SPID layouts vary by record kind; only enforce universal silent-failure traps.
            for field in fields:
                token = field.strip()
                if "/" in token and re.fullmatch(r"[-A-Z/,]+", token, re.I):
                    errors.append(f"{path}:{no}: slash-style trait logic is forbidden: {token}")
                if re.fullmatch(r"[-A-Z,]+", token, re.I):
                    for part in token.split(","):
                        letter = part.lstrip("-")
                        if len(letter) == 1 and letter.isalpha() and letter.upper() not in TRAITS:
                            errors.append(f"{path}:{no}: unknown trait token {part}")
            # Heuristic warning promoted to error when a field literally labeled FormFilters is supplied in comments is impossible;
            # catch common malformed plugin/raw-form filter-only lines.
            if "FormFilters" in raw and (PLUGIN_RE.search(raw) or RAW_FORM_RE.search(raw)):
                errors.append(f"{path}:{no}: invalid FormFilters plugin/FormID pattern")
    for error in errors:
        print("FAIL:", error)
    print("RESULT:", "FAIL" if errors else "PASS")
    return 1 if errors else 0

if __name__ == "__main__":
    raise SystemExit(main())
