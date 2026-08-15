#!/usr/bin/env python3
"""Audit BOS duplicate targets and parser-breaking transform whitespace."""
from __future__ import annotations
import argparse,re
from pathlib import Path
from collections import defaultdict
SECTIONS={"forms","references","transforms","properties"}
FUNC_WS=re.compile(r"\b(?:pos[RA]?|rot[RA]?|scaleA?|flagsC?|chance[SRL]?)\([^)]*\s+[^)]*\)",re.I)

def strip_comment(line):
    quote=None
    for i,ch in enumerate(line):
        if quote:
            if ch==quote: quote=None
        elif ch in {'\"',"'"}: quote=ch
        elif ch==';': return line[:i].rstrip()
    return line.rstrip()

def entries(path):
    section=None
    for no,raw in enumerate(path.read_text(encoding='utf-8-sig',errors='replace').splitlines(),1):
        line=strip_comment(raw.strip())
        if not line or line.startswith(('#','//')): continue
        if line.startswith('[') and line.endswith(']'):
            section=line[1:-1].split('|',1)[0].strip().casefold(); continue
        if section in SECTIONS:
            fields=[x.strip() for x in line.split('|')]
            if fields and fields[0]: yield section,fields,no,line

def property_field(section,fields):
    if section in {'forms','references'}: return fields[2] if len(fields)>2 else ''
    return fields[1] if len(fields)>1 else ''

def audit(root):
    files=sorted(root.rglob('*_SWAP.ini'),key=lambda p:(p.name.casefold(),str(p).casefold()))
    found=defaultdict(list); malformed=[]
    for p in files:
        for section,fields,no,line in entries(p):
            found[(section,fields[0].casefold())].append((p,no,line))
            prop=property_field(section,fields)
            if prop and FUNC_WS.search(prop): malformed.append((p,no,prop,line))
    conflicts={k:v for k,v in found.items() if len(v)>1}
    for p,no,prop,line in malformed:
        print(f'MALFORMED BOS TRANSFORM: {p}:{no}')
        print(f'  PROPERTY: {prop}')
        print('  REASON: whitespace inside a transform/property invocation splits tokens in the pinned BOS parser')
    for key,rows in sorted(conflicts.items()):
        print(f'TARGET: {key[0]} | {key[1]}')
        for p,no,line in rows: print(f'  {p.name}:{no}: {line}')
        print(f'  ALPHABETICAL WINNER CANDIDATE: {rows[-1][0].name}')
        print('  SEMANTIC VERDICT: UNRESOLVED')
    print(f'MALFORMED TRANSFORMS: {len(malformed)}')
    print(f'CONFLICT TARGETS: {len(conflicts)}')
    return 1 if malformed or conflicts else 0

def self_test():
    import tempfile
    with tempfile.TemporaryDirectory() as td:
        r=Path(td)
        (r/'Whitespace_SWAP.ini').write_text('[Transforms]\nRefA|rotR(147.9, 355.9, 82.7)\n')
        assert audit(r)==1
        (r/'Whitespace_SWAP.ini').write_text('[Transforms]\nRefA|rotR(147.9,355.9,82.7)\n')
        assert audit(r)==0
        (r/'A_SWAP.ini').write_text('[Transforms]\nRefB|rotR(0,0,90)\n')
        (r/'Z_SWAP.ini').write_text('[Transforms]\nRefB|rotR(0,0,45)\n')
        assert audit(r)==1
    print('SELF-TEST: PASS')

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('directory',nargs='?'); ap.add_argument('--self-test',action='store_true'); a=ap.parse_args()
    if a.self_test: self_test(); return
    if not a.directory: ap.error('directory is required unless --self-test is used')
    raise SystemExit(audit(Path(a.directory)))
if __name__=='__main__': main()
