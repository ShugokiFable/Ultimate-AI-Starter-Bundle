#!/usr/bin/env python3
from __future__ import annotations
import argparse,pathlib,zipfile,tempfile,shutil,re
JUNK={".ds_store","thumbs.db","desktop.ini","meta.ini"}
BUILD_SUFFIX={".pyc",".ilk",".obj",".tmp",".bak"}
DEBUG_SUFFIX={".pdb"}
MANAGER_NAMES={"__folder_managed_by_vortex","__folder_managed_by_vortex.json"}
LOG_SUFFIX={".log",".dmp"}

def scan(root,*,allow_data_root,allow_debug_symbols,allow_logs):
    errors=[];warnings=[]
    files=[p for p in root.rglob("*") if p.is_file()]
    if (root/"Data").is_dir() and not allow_data_root:
        warnings.append("archive root contains Data; verify intended mod-manager root")
    for p in files:
        rel=p.relative_to(root)
        name=p.name.casefold()
        suffix=p.suffix.casefold()
        if name in JUNK or name in MANAGER_NAMES:
            errors.append(f"manager/junk metadata: {rel}")
        if name.endswith(".meta"):
            errors.append(f"mod-manager archive sidecar: {rel}")
        if suffix in BUILD_SUFFIX:
            errors.append(f"junk/build file: {rel}")
        if suffix in DEBUG_SUFFIX and not allow_debug_symbols:
            errors.append(f"debug symbol in public release: {rel}")
        if suffix in LOG_SUFFIX and not allow_logs:
            errors.append(f"runtime/development log in release: {rel}")
        if "__pycache__" in p.parts:
            errors.append(f"Python cache: {rel}")
        if any(part.casefold() in {".git",".vs","build","cmake-build-debug"} for part in rel.parts):
            errors.append(f"build/source directory in release: {rel}")
    if not files: errors.append("release tree is empty")
    return errors,warnings

def safe_extract(z,destination):
    base=destination.resolve()
    for info in z.infolist():
        target=(destination/info.filename).resolve()
        try:target.relative_to(base)
        except ValueError:raise ValueError(f"unsafe archive member: {info.filename}")
    z.extractall(destination)

def self_test():
    with tempfile.TemporaryDirectory() as td:
        r=pathlib.Path(td)
        (r/"good.ini").write_text("x=1")
        assert not scan(r,allow_data_root=True,allow_debug_symbols=False,allow_logs=False)[0]
        (r/"__folder_managed_by_vortex.json").write_text("{}")
        assert scan(r,allow_data_root=True,allow_debug_symbols=False,allow_logs=False)[0]
    print("SELF-TEST: PASS")

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("path",nargs="?")
    ap.add_argument("--allow-data-root",action="store_true")
    ap.add_argument("--allow-debug-symbols",action="store_true")
    ap.add_argument("--allow-logs",action="store_true")
    ap.add_argument("--self-test",action="store_true")
    a=ap.parse_args()
    if a.self_test:self_test();return
    p=pathlib.Path(a.path);temp=None
    try:
        if not p.exists():
            print(f"FAIL: missing path: {p}");raise SystemExit(1)
        if p.suffix.casefold()==".zip":
            temp=pathlib.Path(tempfile.mkdtemp(prefix="skyrim-release-"))
            with zipfile.ZipFile(p) as z:safe_extract(z,temp)
            root=temp
        else:root=p
        errors,warnings=scan(root,allow_data_root=a.allow_data_root,allow_debug_symbols=a.allow_debug_symbols,allow_logs=a.allow_logs)
        for x in warnings:print("WARN:",x)
        for x in errors:print("FAIL:",x)
        print("RESULT:","FAIL" if errors else "PASS")
        raise SystemExit(1 if errors else 0)
    except (zipfile.BadZipFile,ValueError) as e:
        print("FAIL:",e);raise SystemExit(1)
    finally:
        if temp:shutil.rmtree(temp,ignore_errors=True)
if __name__=="__main__":main()
