#!/usr/bin/env python3
"""Deterministic UTF-8-safe release ZIP builder for Ultimate AI Starter Bundle.

Builds Core and Full-Offline archives from the working tree while excluding
.git, caches, venvs, __pycache__, developer state, and previous release output.
Each ZIP is CRC-tested, extracted under a path containing spaces + Unicode, and
hashed with SHA256 before success is reported.
"""
from __future__ import annotations
import argparse, hashlib, json, os, re, shutil, tempfile, zipfile
from pathlib import Path, PurePosixPath

FIXED_TIME=(2026,8,20,0,0,0)
# The archive prefix follows VERSION.txt. It was restated in four places, so a
# release bump could ship v7.8.0-named archives containing a 7.9.0 tree.
def _pack_version(root:Path)->str:
    return (root/'VERSION.txt').read_text(encoding='utf-8-sig').strip().lstrip('vV')
def _prefix(root:Path)->str:
    return 'Ultimate-AI-Starter-Bundle-v'+_pack_version(root)
EXCLUDE_PARTS={'.git','.worktrees','.venv','venv','__pycache__','node_modules','.pytest_cache','.mypy_cache','.ruff_cache','.tox','.nox','htmlcov','cache','dist','artifacts'}
EXCLUDE_SUFFIXES={'.pyc','.pyo','.log'}
EXCLUDE_NAMES={'INSTALLATION.json','.DS_Store','.coverage','coverage.xml','config.MAINTAINER.yaml'}
# Forge is not an offline payload any more. Its source lives in the tree at
# BUNDLED-TOOLS/skyrim-forge, so BOTH variants carry it without a special case,
# and there is no archive whose version could disagree with the installer.
FORGE_SOURCE=PurePosixPath('BUNDLED-TOOLS/skyrim-forge')
def _forge_version(root:Path)->str:
    text=(root/FORGE_SOURCE/'VERSION.txt').read_text(encoding='utf-8-sig')
    match=re.search(r'(?m)^Skyrim Forge\s+(\d+\.\d+\.\d+)\s*$',text)
    if not match: raise SystemExit(f'{FORGE_SOURCE}/VERSION.txt declares no version')
    return match.group(1)

def excluded(rel:Path)->bool:
    if any(part in EXCLUDE_PARTS for part in rel.parts): return True
    if rel.as_posix() == '.git': return True
    if rel.name in EXCLUDE_NAMES or rel.suffix.lower() in EXCLUDE_SUFFIXES: return True
    if rel.name.startswith('Ultimate-AI-Starter-Bundle-v') and rel.suffix.lower()=='.zip': return True
    return False

CORE_NOTE=(
    'Core release: the vendored third-party offline payloads are omitted and\n'
    'downloaded by the installer when absent. For network-free installation,\n'
    'use the Full-Offline archive.\n'
    '\n'
    'Skyrim Forge is NOT one of those payloads and is present in full: its\n'
    'source ships in BUNDLED-TOOLS/skyrim-forge and is built here, not\n'
    'downloaded.\n'
).encode('utf-8')

def files(root:Path, core:bool):
    for p in sorted(root.rglob('*'), key=lambda x:x.relative_to(root).as_posix().lower()):
        if not p.is_file(): continue
        rel=p.relative_to(root)
        if excluded(rel): continue
        # Core drops every vendored third-party payload; the installer's
        # BundledFirst online fallback fetches them. Forge is unaffected --
        # it is source in the tree, not an archive in offline/.
        if core and len(rel.parts)>=2 and rel.parts[0]=='BUNDLED-TOOLS' and rel.parts[1]=='offline':
            continue
        yield p,rel

def _row(rel:Path,data:bytes)->dict[str,object]:
    return {'path':rel.as_posix(),'size':len(data),'sha256':hashlib.sha256(data).hexdigest()}

def _core_offline_manifest_bytes(root:Path)->bytes:
    # BUNDLED-TOOLS/OFFLINE-MANIFEST.json inventories the vendored payloads.
    # Core carries one of them. Shipping the Full inventory unchanged made the
    # Core archive describe six files it does not contain -- and the release
    # contract run FROM the extracted Core failed on exactly that, while the
    # same suite passed on Full. Rewrite it to describe Core.
    m=json.loads((root/'BUNDLED-TOOLS'/'OFFLINE-MANIFEST.json').read_text(encoding='utf-8-sig'))
    m['assets']=[]
    m['variant']='Core'
    m['note']=('Core ships no vendored payloads; the installer downloads each component '
               'when absent, and the Full-Offline archive carries them all for '
               'network-free installation. Skyrim Forge is not listed here in either '
               'variant: it is source in BUNDLED-TOOLS/skyrim-forge, not a payload.')
    return (json.dumps(m,indent=2)+'\n').encode('utf-8')

def _core_overrides(root:Path)->dict[str,bytes]:
    """Files whose Core bytes differ from the source tree's."""
    return {'BUNDLED-TOOLS/OFFLINE-MANIFEST.json':_core_offline_manifest_bytes(root)}

def _core_manifest_bytes(root:Path)->bytes:
    # Core intentionally omits most offline payloads. Generate its manifest
    # from the exact bytes that the Core archive will contain instead of
    # copying the Full tree manifest and creating false MISSING failures.
    overrides=_core_overrides(root)
    rows=[]
    for p,rel in files(root,True):
        if rel.as_posix()=='MANIFEST.json':
            continue
        rows.append(_row(rel,overrides.get(rel.as_posix(),None) or p.read_bytes()))
    rows.append(_row(Path('README-CORE.txt'),CORE_NOTE))
    rows.sort(key=lambda r:str(r['path']))
    return (json.dumps(rows,indent=1)+'\n').encode('utf-8')

# Any Linux ELF the tree ships, wherever it ships it. Naming one path missed
# skyrim_forge/bin/linux-x64/SkyrimForge.Native, which went out at 0644 while
# its sibling went out at 0755.
LINUX_EXECUTABLES=('linux-x64/SkyrimForge.Native',)
def _archive_mode(rel:Path)->int:
    # ZIPs created on Windows do not preserve POSIX execute bits. The merged
    # Forge tree carries published Linux helpers that repository validation
    # executes after extraction, so encode that portable contract explicitly.
    posix=rel.as_posix()
    if any(posix.endswith(suffix) for suffix in LINUX_EXECUTABLES):
        return 0o100755
    return 0o100644

def _write(z:zipfile.ZipFile,prefix:str,rel:Path,data:bytes)->None:
    zi=zipfile.ZipInfo(str(PurePosixPath(prefix)/PurePosixPath(rel.as_posix())),FIXED_TIME)
    zi.compress_type=zipfile.ZIP_DEFLATED; zi.flag_bits |= 0x800
    zi.create_system=3
    zi.external_attr=(_archive_mode(rel) & 0xFFFF)<<16
    z.writestr(zi,data,compress_type=zipfile.ZIP_DEFLATED,compresslevel=9)

def build(root:Path,out:Path,core:bool)->None:
    prefix=_prefix(root)
    core_manifest=_core_manifest_bytes(root) if core else None
    overrides=_core_overrides(root) if core else {}
    with zipfile.ZipFile(out,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as z:
        for p,rel in files(root,core):
            if core and rel.as_posix()=='MANIFEST.json':
                _write(z,prefix,rel,core_manifest)
            elif rel.as_posix() in overrides:
                _write(z,prefix,rel,overrides[rel.as_posix()])
            else:
                _write(z,prefix,rel,p.read_bytes())
        if core:
            _write(z,prefix,Path('README-CORE.txt'),CORE_NOTE)

def verify(path:Path,root:Path)->None:
    with zipfile.ZipFile(path) as z:
        bad=z.testzip()
        if bad: raise RuntimeError(f'ZIP CRC failure: {bad}')
        names=z.namelist()
        forbidden=('/.git/','/__pycache__/','/.venv/','/node_modules/')
        if any(any(x in '/'+n for x in forbidden) for n in names): raise RuntimeError('forbidden developer state in ZIP')
        with tempfile.TemporaryDirectory(prefix='UABS Unicode Ω Space ') as td:
            z.extractall(td)
            top=Path(td)/_prefix(root)
            for rel in ('START-HERE.bat','INSTALL-V7-AIO.ps1','BUNDLED-TOOLS/CATALOG.json','VERSION.txt'):
                if not (top/rel).is_file(): raise RuntimeError(f'extracted required file missing: {rel}')
            # Both variants must carry buildable Forge source. Check the EXTRACTED
            # tree, not the source: that is the copy the user actually receives.
            forge=top/FORGE_SOURCE
            for rel in ('VERSION.txt','Install-or-Update.ps1','skyrim_forge/__init__.py'):
                if not (forge/rel).is_file():
                    raise RuntimeError(f'extracted archive has no {FORGE_SOURCE}/{rel}')
            extracted=re.search(r'(?m)^Skyrim Forge\s+(\d+\.\d+\.\d+)\s*$',(forge/'VERSION.txt').read_text(encoding='utf-8-sig'))
            if not extracted or extracted.group(1)!=_forge_version(root):
                raise RuntimeError('extracted Forge source is not the version this tree ships')
            if (top/'VERSION.txt').read_text(encoding='utf-8-sig').strip().lstrip('vV')!=_pack_version(root):
                raise RuntimeError('extracted VERSION.txt does not match the archive name')
            manifest=top/'MANIFEST.json'
            if not manifest.is_file(): raise RuntimeError('extracted MANIFEST.json missing')
            rows=json.loads(manifest.read_text(encoding='utf-8'))
            rows=rows.get('files',[]) if isinstance(rows,dict) else rows
            for row in rows:
                rel=Path(str(row['path']))
                target=top/rel
                if not target.is_file(): raise RuntimeError(f'manifest missing after extraction: {rel.as_posix()}')
                data=target.read_bytes()
                if len(data)!=int(row.get('size',-1)) or hashlib.sha256(data).hexdigest()!=row.get('sha256'):
                    raise RuntimeError(f'manifest mismatch after extraction: {rel.as_posix()}')

def sha256(path:Path)->str:
    h=hashlib.sha256()
    with path.open('rb') as f:
        for b in iter(lambda:f.read(1024*1024),b''): h.update(b)
    return h.hexdigest()

def main()->int:
    ap=argparse.ArgumentParser(); ap.add_argument('--root',type=Path,default=Path(__file__).resolve().parent.parent); ap.add_argument('--outdir',type=Path,default=Path.cwd())
    mode=ap.add_mutually_exclusive_group(); mode.add_argument('--core-only',action='store_true'); mode.add_argument('--full-only',action='store_true')
    a=ap.parse_args(); root=a.root.resolve(); outdir=a.outdir.resolve(); outdir.mkdir(parents=True,exist_ok=True)
    outputs=[]
    variants=(('Core',True),) if a.core_only else ((('Full-Offline',False),) if a.full_only else (('Core',True),('Full-Offline',False)))
    for label,core in variants:
        out=outdir/f'{_prefix(root)}-{label}.zip'
        build(root,out,core); verify(out,root); digest=sha256(out); (out.with_suffix(out.suffix+'.sha256')).write_text(f'{digest}  {out.name}\n',encoding='ascii'); outputs.append((out,digest))
    for p,d in outputs: print(f'PASS {p.name} sha256={d} bytes={p.stat().st_size}')
    return 0
if __name__=='__main__': raise SystemExit(main())
