#!/usr/bin/env python3
from __future__ import annotations
import argparse, pathlib, sys, xml.etree.ElementTree as ET

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('root'); args=ap.parse_args()
    root=pathlib.Path(args.root)
    cfg=root/'fomod'/'ModuleConfig.xml'; info=root/'fomod'/'info.xml'
    issues=[]
    for p in (cfg, info):
        if not p.is_file(): issues.append(f'missing {p.relative_to(root)}'); continue
        try: ET.parse(p)
        except Exception as e: issues.append(f'invalid XML {p.relative_to(root)}: {e}')
    if cfg.is_file():
        tree=ET.parse(cfg)
        for elem in tree.iter():
            src=elem.attrib.get('source')
            if src:
                candidate=root/pathlib.PureWindowsPath(src)
                if not candidate.exists(): issues.append(f'missing source referenced by FOMOD: {src}')
    for p in root.rglob('*'):
        if p.is_file() and p.name.lower() in {'thumbs.db','.ds_store'}: issues.append(f'junk file: {p.relative_to(root)}')
    for i in issues: print('FAIL:',i)
    print('RESULT:', 'FAIL' if issues else 'PASS')
    raise SystemExit(1 if issues else 0)
if __name__=='__main__': main()
