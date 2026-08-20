#!/usr/bin/env python3
"""Deterministic UTF-8-safe release ZIP builder for Ultimate AI Starter Bundle.

Builds Core and Full-Offline archives from the working tree while excluding
.git, caches, venvs, __pycache__, developer state, and previous release output.
Each ZIP is CRC-tested, extracted under a path containing spaces + Unicode, and
hashed with SHA256 before success is reported.
"""
from __future__ import annotations
import argparse, hashlib, json, os, shutil, tempfile, zipfile
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
EXCLUDE_NAMES={'INSTALLATION.json','.DS_Store','.coverage','coverage.xml'}
# Derived, never restated: whichever Skyrim-Forge-x.y.z.zip is in the tree is
# the required payload. 7.8.0 named it in four separate literals, so bumping
# Forge meant remembering all four.
def _required_forge(root:Path)->str:
    hits=sorted((root/'BUNDLED-TOOLS'/'offline').glob('Skyrim-Forge-*.zip'))
    if not hits: raise SystemExit('BUNDLED-TOOLS/offline/Skyrim-Forge-*.zip is missing; Core and Full both require it')
    return hits[-1].name

def excluded(rel:Path)->bool:
    if any(part in EXCLUDE_PARTS for part in rel.parts): return True
    if rel.as_posix() == '.git': return True
    if rel.name in EXCLUDE_NAMES or rel.suffix.lower() in EXCLUDE_SUFFIXES: return True
    if rel.name.startswith('Ultimate-AI-Starter-Bundle-v') and rel.suffix.lower()=='.zip': return True
    return False

CORE_NOTE=(
    'Core release: most vendored offline tool payloads are omitted.\n'
    'The required Forge compatibility payload is retained; other components\n'
    'are downloaded automatically when absent. For network-free installation, use\n'
    'the Full-Offline archive.\n'
).encode('utf-8')

def files(root:Path, core:bool):
    for p in sorted(root.rglob('*'), key=lambda x:x.relative_to(root).as_posix().lower()):
        if not p.is_file(): continue
        rel=p.relative_to(root)
        if excluded(rel): continue
        if core and len(rel.parts)>=2 and rel.parts[0]=='BUNDLED-TOOLS' and rel.parts[1]=='offline':
            # The required Forge payload is bundle-managed and not reconstructible
            # from the older public upstream release. Core keeps it; other payloads
            # can be fetched by the installer's BundledFirst online fallback.
            if rel.name != _required_forge(root):
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
    keep=_required_forge(root)
    m['assets']=[a for a in m.get('assets',[]) if a.get('file')==keep]
    m['variant']='Core'
    m['note']=('Core ships only the required Forge payload. Every other component is '
               'downloaded by the installer when absent; the Full-Offline archive '
               'carries them all for network-free installation.')
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

def _write(z:zipfile.ZipFile,prefix:str,rel:Path,data:bytes)->None:
    zi=zipfile.ZipInfo(str(PurePosixPath(prefix)/PurePosixPath(rel.as_posix())),FIXED_TIME)
    zi.compress_type=zipfile.ZIP_DEFLATED; zi.flag_bits |= 0x800
    zi.external_attr=(0o100644 & 0xFFFF)<<16
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
            # Both variants must carry a Forge payload. Check the EXTRACTED tree,
            # not the source: that is the copy the user actually receives.
            if not sorted((top/'BUNDLED-TOOLS'/'offline').glob('Skyrim-Forge-*.zip')):
                raise RuntimeError('extracted archive has no BUNDLED-TOOLS/offline/Skyrim-Forge-*.zip')
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
