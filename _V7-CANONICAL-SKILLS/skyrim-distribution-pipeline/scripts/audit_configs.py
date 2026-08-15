#!/usr/bin/env python3
"""Conservative text-config audit for Skyrim runtime patch files.

It intentionally checks encoding, duplicate active lines, whitespace, and basic
assignment structure. It does not claim framework-semantic validation.
"""
from __future__ import annotations
import argparse, collections, pathlib, sys

EXTENSIONS = {'.ini', '.json', '.toml', '.yaml', '.yml'}

def audit(path: pathlib.Path):
    raw = path.read_bytes()
    problems = []
    if raw.startswith(b'\xef\xbb\xbf'):
        problems.append('UTF-8 BOM present; verify framework support')
    try:
        text = raw.decode('utf-8-sig')
    except UnicodeDecodeError as e:
        return [f'not UTF-8: {e}']
    if b'\r\n' in raw and b'\n' in raw.replace(b'\r\n', b''):
        problems.append('mixed newline styles')
    seen = collections.defaultdict(list)
    for no, original in enumerate(text.splitlines(), 1):
        line = original.strip()
        if not line or line.startswith((';','#','//')) or (line.startswith('[') and line.endswith(']')):
            continue
        normalized = ' '.join(line.split())
        seen[normalized].append(no)
        if '=' not in line and path.suffix.lower() == '.ini':
            problems.append(f'line {no}: active INI line has no =')
        if original.rstrip() != original:
            problems.append(f'line {no}: trailing whitespace')
    for line, numbers in seen.items():
        if len(numbers) > 1:
            problems.append(f'duplicate active line at {numbers}: {line[:160]}')
    return problems

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('paths', nargs='+')
    args = ap.parse_args()
    files = []
    for raw in args.paths:
        p = pathlib.Path(raw)
        if p.is_dir(): files.extend(f for f in p.rglob('*') if f.is_file() and f.suffix.lower() in EXTENSIONS)
        else: files.append(p)
    bad = False
    for p in sorted(set(files)):
        issues = audit(p)
        print(f'{p}: {"FAIL" if issues else "PASS"}')
        for issue in issues: print('  -', issue)
        bad |= bool(issues)
    print('RESULT:', 'FAIL' if bad else 'PASS')
    raise SystemExit(1 if bad else 0)
if __name__ == '__main__': main()
