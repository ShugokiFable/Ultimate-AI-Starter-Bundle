from __future__ import annotations

import base64, csv, gzip, hashlib, io, os, stat, tarfile, tomllib, zipfile
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parent
EPOCH = int(os.environ.get("SOURCE_DATE_EPOCH", "1784764800"))
ZIP_TIME = (2026, 7, 26, 0, 0, 0)
EXCLUDED = {".git", ".venv", "venv", ".go-cache", "__pycache__", "dist", "build", ".pytest_cache", "REPORTS", "INSTALLATION.json"}
GENERATED_REPORTS = {"VALIDATION.json", "BUILD-RECEIPT.json", "MANIFEST.json", "SBOM.spdx.json", "CHECKSUMS-SHA256.txt"}


def project(): return tomllib.loads((ROOT / "pyproject.toml").read_text(encoding="utf-8"))["project"]
def dist_name(): return project()["name"].replace("-", "_")
def version(): return str(project()["version"])
def dist_info(): return f"{dist_name()}-{version()}.dist-info"

def metadata():
    p = project()
    rows = ["Metadata-Version: 2.4", f"Name: {p['name']}", f"Version: {p['version']}", f"Summary: {p['description']}", f"Requires-Python: {p['requires-python']}", "License-Expression: MIT", "Description-Content-Type: text/markdown"]
    return ("\n".join(rows) + "\n\n" + (ROOT / "README.md").read_text(encoding="utf-8") + "\n").encode()

# Derived from pyproject, never restated: the generator string is baked into
# every wheel and is invisible until it is wrong.
def wheel_text(): return f"Wheel-Version: 1.0\nGenerator: Skyrim Forge {version()} deterministic backend\nRoot-Is-Purelib: true\nTag: py3-none-any\n".encode()
def entry_points(): return b"[console_scripts]\nforge = skyrim_forge.cli:main\nskyrim-forge-mcp = skyrim_forge.mcp_server:serve\nskyrim-forge-gui = skyrim_forge.gui:run_gui\n"
def get_requires_for_build_wheel(config_settings=None): return []
def get_requires_for_build_sdist(config_settings=None): return []

def package_files():
    return sorted([p for p in (ROOT / "skyrim_forge").rglob("*") if p.is_file() and not p.is_symlink() and not any(x in EXCLUDED for x in p.relative_to(ROOT).parts) and p.suffix not in {".pyc", ".pyo"}], key=lambda p: p.relative_to(ROOT).as_posix().casefold())

def zinfo(name, executable=False):
    info = zipfile.ZipInfo(name, ZIP_TIME); info.compress_type = zipfile.ZIP_DEFLATED; info.create_system = 3; info.external_attr = ((0o100755 if executable else 0o100644) & 0xFFFF) << 16; info.flag_bits |= 0x800; return info

def digest(data): return "sha256=" + base64.urlsafe_b64encode(hashlib.sha256(data).digest()).rstrip(b"=").decode()

def prepare_metadata_for_build_wheel(metadata_directory, config_settings=None):
    target = Path(metadata_directory) / dist_info(); target.mkdir(parents=True)
    (target / "METADATA").write_bytes(metadata()); (target / "WHEEL").write_bytes(wheel_text()); (target / "entry_points.txt").write_bytes(entry_points())
    return target.name

def build_wheel(wheel_directory, config_settings=None, metadata_directory=None):
    target = Path(wheel_directory); target.mkdir(parents=True, exist_ok=True)
    name = f"{dist_name()}-{version()}-py3-none-any.whl"; output = target / name
    members = {p.relative_to(ROOT).as_posix(): (p.read_bytes(), bool(p.stat().st_mode & stat.S_IXUSR)) for p in package_files()}
    di = dist_info(); members[f"{di}/METADATA"]=(metadata(),False); members[f"{di}/WHEEL"]=(wheel_text(),False); members[f"{di}/entry_points.txt"]=(entry_points(),False); members[f"{di}/licenses/LICENSE"]=((ROOT/"LICENSE").read_bytes(),False)
    record = f"{di}/RECORD"; stream=io.StringIO(newline=""); writer=csv.writer(stream,lineterminator="\n")
    for path in sorted(members,key=str.casefold):
        data,_=members[path]; writer.writerow([path,digest(data),str(len(data))])
    writer.writerow([record,"",""]); members[record]=(stream.getvalue().encode(),False)
    with zipfile.ZipFile(output,"w",zipfile.ZIP_DEFLATED,compresslevel=9) as archive:
        for path in sorted(members,key=str.casefold):
            data,executable=members[path]; archive.writestr(zinfo(path,executable),data,compress_type=zipfile.ZIP_DEFLATED,compresslevel=9)
    return name

def sdist_files():
    result=[]
    for p in ROOT.rglob("*"):
        if p.is_file() and not p.is_symlink() and p.name not in GENERATED_REPORTS and not any(x in EXCLUDED or x.endswith(".egg-info") for x in p.relative_to(ROOT).parts) and p.suffix not in {".pyc", ".pyo"}:
            result.append(p)
    return sorted(result,key=lambda p:p.relative_to(ROOT).as_posix().casefold())

def build_sdist(sdist_directory, config_settings=None):
    target=Path(sdist_directory); target.mkdir(parents=True,exist_ok=True); name=f"{dist_name()}-{version()}.tar.gz"; output=target/name; prefix=f"{dist_name()}-{version()}"
    payload=io.BytesIO()
    with tarfile.open(fileobj=payload,mode="w",format=tarfile.PAX_FORMAT) as archive:
        for path in sdist_files():
            data=path.read_bytes(); info=tarfile.TarInfo((PurePosixPath(prefix)/path.relative_to(ROOT).as_posix()).as_posix()); info.size=len(data); info.mtime=EPOCH; info.uid=info.gid=0; info.uname=info.gname=""; info.mode=0o755 if path.stat().st_mode & stat.S_IXUSR else 0o644; archive.addfile(info,io.BytesIO(data))
    payload.seek(0)
    with output.open("wb") as raw:
        with gzip.GzipFile(filename="",mode="wb",fileobj=raw,mtime=EPOCH,compresslevel=9) as gz: gz.write(payload.getvalue())
    return name
