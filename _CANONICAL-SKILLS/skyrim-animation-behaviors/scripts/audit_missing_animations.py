#!/usr/bin/env python3
"""Audit missing HKX paths against loose files and optional archive inventories."""
from __future__ import annotations
import argparse,re
from pathlib import Path

HKX=re.compile(r"(?i)(Actors[\\/][^\r\n\"']+?\.hkx)")

def norm(s): return s.replace("\\","/").lstrip("/").casefold()

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--log",required=True)
    ap.add_argument("--root",action="append",default=[])
    ap.add_argument("--inventory",action="append",default=[])
    a=ap.parse_args()
    text=Path(a.log).read_text(encoding="utf-8",errors="replace")
    paths=sorted({norm(x) for x in HKX.findall(text)})
    loose=set()
    for raw in a.root:
        root=Path(raw)
        for p in root.rglob("*.hkx"):
            try: rel=p.relative_to(root)
            except ValueError: continue
            n=norm(str(rel))
            if "/meshes/" in "/"+n:
                n=n.split("/meshes/",1)[1]
            loose.add(n)
    archived=set()
    for raw in a.inventory:
        for line in Path(raw).read_text(encoding="utf-8",errors="replace").splitlines():
            if ".hkx" in line.lower():
                archived.add(norm(line.strip().split("\t")[-1]))
    missing=[]
    for path in paths:
        status="LOOSE" if path in loose else "ARCHIVE-INVENTORY" if path in archived else "UNRESOLVED"
        print(f"{status}: {path}")
        if status=="UNRESOLVED": missing.append(path)
    if not a.inventory:
        print("ARCHIVE COVERAGE: NOT PROVIDED")
    print(f"REFERENCES: {len(paths)} UNRESOLVED: {len(missing)}")
    raise SystemExit(1 if missing else 0)
if __name__=="__main__":main()
