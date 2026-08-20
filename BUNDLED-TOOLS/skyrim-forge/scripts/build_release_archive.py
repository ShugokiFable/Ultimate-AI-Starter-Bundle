from __future__ import annotations

import argparse, hashlib, os, re, stat, zipfile
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
# Derived, never restated: the archive prefix must follow the product version.
VERSION=re.search(r'^VERSION\s*=\s*"([^"]+)"',(ROOT/"skyrim_forge"/"version.py").read_text(encoding="utf-8"),re.M).group(1)
FIXED=(2026,7,26,0,0,0)
EXCLUDED={".git",".venv","venv",".go-cache","__pycache__","dist","build",".pytest_cache","REPORTS","INSTALLATION.json"}


def files():
    result=[]
    for p in ROOT.rglob("*"):
        if p.is_file() and not p.is_symlink() and not any(x in EXCLUDED or x.endswith(".egg-info") for x in p.relative_to(ROOT).parts) and p.suffix not in {".pyc",".pyo"}:
            result.append(p)
    return sorted(result,key=lambda p:p.relative_to(ROOT).as_posix().casefold())


def build(output: Path):
    output.parent.mkdir(parents=True,exist_ok=True); tmp=output.with_suffix(output.suffix+".tmp"); prefix=f"Skyrim-Forge-{VERSION}/"
    with zipfile.ZipFile(tmp,"w",zipfile.ZIP_DEFLATED,compresslevel=9) as z:
        for p in files():
            rel=prefix+p.relative_to(ROOT).as_posix(); info=zipfile.ZipInfo(rel,FIXED); info.create_system=3; info.external_attr=((0o100755 if p.stat().st_mode&stat.S_IXUSR else 0o100644)&0xFFFF)<<16; info.compress_type=zipfile.ZIP_DEFLATED; z.writestr(info,p.read_bytes(),compress_type=zipfile.ZIP_DEFLATED,compresslevel=9)
    with zipfile.ZipFile(tmp) as z:
        bad=z.testzip()
        if bad: raise RuntimeError(f"CRC failure: {bad}")
    os.replace(tmp,output); return hashlib.sha256(output.read_bytes()).hexdigest()


def main():
    ap=argparse.ArgumentParser(); ap.add_argument("output",nargs="?",default=str(ROOT.parent/f"Skyrim-Forge-{VERSION}-GITHUB-READY.zip")); a=ap.parse_args(); out=Path(a.output); print(build(out),out)
if __name__=="__main__":main()
