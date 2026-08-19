#!/usr/bin/env python3
"""Verify pinned framework truth and production-path regression fixtures."""
from __future__ import annotations
from pathlib import Path
import json,subprocess,sys,re,tempfile
ROOT=Path(__file__).resolve().parents[2]
findings=[]
spid=(ROOT/'skyrim-spid-distribution'/'SKILL.md').read_text(encoding='utf-8')
kid=(ROOT/'skyrim-kid-distribution'/'SKILL.md').read_text(encoding='utf-8')
linter=ROOT/'skyrim-distr-kid-validation'/'scripts'/'lint_framework_configs.py'
bos_auditor=ROOT/'skyrim-base-object-swapper'/'scripts'/'audit_bos_configs.py'
lock=json.loads((ROOT/'skyrim-frameworks-index'/'references'/'FRAMEWORK-SOURCE-LOCK.json').read_text(encoding='utf-8'))
for token in ['ExclusiveGroup','DeathItem','GlobalLinkedFinalDeathOutfit','There is no `Weapon` distribution key','The parser splits TraitFilters on `/`','`65/`','`18!` is valid']:
    if token not in spid: findings.append(f'SPID skill missing truth token: {token}')
for token in ['ordinary usable `Keyword` row needs','Record signatures','ExclusiveGroup']:
    if token not in kid: findings.append(f'KID skill missing truth token: {token}')
for pattern in [r'slash traits? (?:are )?forbidden',r'TraitFilters? (?:combine|separate|split) with comma',r'(?:use|write|generate)\s+`?Weapon\s*=']:
    rx=re.compile(pattern,re.I)
    for p in ROOT.rglob('*.md'):
        text=p.read_text(encoding='utf-8',errors='ignore'); m=rx.search(text)
        if m and 'historical' not in text[max(0,m.start()-120):m.start()].lower(): findings.append(f'stale SPID wording: {p}')
for name,expected in [('spid','e5ef32b99ecb277778644f4deae0ac04851ca614'),('kid','895df224d4964dc9723460038eb533bfff06d860')]:
    if lock.get(name,{}).get('source_commit')!=expected: findings.append(f'{name.upper()} source lock mismatch')
for script in [linter,bos_auditor,ROOT/'skyrim-runtime-log-forensics'/'scripts'/'analyze_runtime_logs.py',ROOT/'skyrim-container-distribution'/'scripts'/'lint_cdf_json.py']:
    proc=subprocess.run([sys.executable,str(script),'--self-test'],text=True,capture_output=True)
    if proc.returncode: findings.append(f'{script.name} self-test failed:\n{proc.stdout}{proc.stderr}')
# Production-path fixtures, not helper-only assertions.
with tempfile.TemporaryDirectory() as td:
    r=Path(td)
    good={
      'Special_DISTR.ini':'ExclusiveGroup = RMB|0x800~A.esp,0x801~A.esp ; published-style comment\nDeathItem = 0x900~A.esp|ActorTypeNPC||||1|100 ; published-style comment\n',
      'Types_KID.ini':'Keyword = MyKeyword|Weapon|*Sword||100 ; comment\nExclusiveGroup = Weapons|MyKeyword,OtherKeyword\n',
    }
    bad={
      'Whitespace_SWAP.ini':'[Transforms]\nRefA|rotR(147.9, 355.9, 82.7)\n',
      'Signature_KID.ini':'Keyword = MyKeyword|WEAP|*Sword||100\n',
    }
    for name,text in good.items():
        p=r/name;p.write_text(text);proc=subprocess.run([sys.executable,str(linter),str(p)],text=True,capture_output=True)
        if proc.returncode: findings.append(f'production good fixture rejected: {name}\n{proc.stdout}{proc.stderr}')
    p=r/'Whitespace_SWAP.ini';p.write_text(bad[p.name]);proc=subprocess.run([sys.executable,str(bos_auditor),str(r)],text=True,capture_output=True)
    if proc.returncode==0 or 'MALFORMED BOS TRANSFORM' not in proc.stdout: findings.append('production BOS whitespace fixture was not detected by audit_bos_configs.py')
    p=r/'Signature_KID.ini';p.write_text(bad[p.name]);proc=subprocess.run([sys.executable,str(linter),str(p)],text=True,capture_output=True)
    if proc.returncode==0: findings.append('production KID signature fixture was not rejected')
if findings:
    print('FRAMEWORK TRUTH LOCK: FAIL')
    for f in findings: print('FAIL:',f)
    raise SystemExit(1)
print('FRAMEWORK TRUTH LOCK: PASS')
