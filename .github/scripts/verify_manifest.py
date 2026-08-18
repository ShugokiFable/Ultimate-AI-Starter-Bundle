"""Verify every file recorded in MANIFEST.json still hashes to the same bytes.

This repo sets `* -text` in .gitattributes so a checkout is byte-identical to
the released pack. That guarantee is what MANIFEST.json records, so it is worth
checking on every push rather than only at release time.
"""
import hashlib
import io
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    manifest_path = os.path.join(ROOT, "MANIFEST.json")
    if not os.path.isfile(manifest_path):
        print("MANIFEST.json not found")
        return 1

    data = json.load(io.open(manifest_path, encoding="utf-8"))
    entries = data["files"] if isinstance(data, dict) and "files" in data else data

    missing, mismatch, verified = [], [], 0
    for entry in entries:
        rel = entry["path"]
        full = os.path.join(ROOT, rel.replace("/", os.sep))
        if not os.path.isfile(full):
            missing.append(rel)
            continue
        if sha256(full) != entry.get("sha256"):
            mismatch.append(rel)
        else:
            verified += 1

    print("verified=%d missing=%d mismatch=%d total=%d"
          % (verified, len(missing), len(mismatch), len(entries)))
    for rel in missing[:20]:
        print("  MISSING  %s" % rel)
    for rel in mismatch[:20]:
        print("  MISMATCH %s" % rel)
    if len(missing) > 20 or len(mismatch) > 20:
        print("  ... truncated")

    if missing or mismatch:
        print("\nMANIFEST.json does not describe this tree. Regenerate with:")
        print("  python TOOLS/generate_manifest.py")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
