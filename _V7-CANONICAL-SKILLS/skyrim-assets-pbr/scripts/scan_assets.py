#!/usr/bin/env python3
from __future__ import annotations
import argparse, pathlib, collections
EXT={'.dds','.nif','.tri','.hkx','.bgsm','.bgem'}
def main():
    ap=argparse.ArgumentParser(); ap.add_argument('root'); args=ap.parse_args(); root=pathlib.Path(args.root)
    counts=collections.Counter(); dup=collections.defaultdict(list); issues=[]
    for p in root.rglob('*'):
        if p.is_file() and p.suffix.lower() in EXT:
            counts[p.suffix.lower()]+=1; dup[p.name.lower()].append(p.relative_to(root))
            if any(c.isupper() for c in str(p.relative_to(root))): issues.append(f'mixed-case path: {p.relative_to(root)}')
    print('COUNTS', dict(counts))
    for name,paths in dup.items():
        if len(paths)>1: print('DUPLICATE NAME',name,*(str(x) for x in paths),sep='\n  ')
    for i in issues: print('WARN:',i)
    print('RESULT: PASS')
if __name__=='__main__': main()
