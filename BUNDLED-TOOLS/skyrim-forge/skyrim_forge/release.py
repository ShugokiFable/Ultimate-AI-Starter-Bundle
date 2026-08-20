from __future__ import annotations

import os
import re
import stat
import zipfile
from pathlib import Path, PurePosixPath
from typing import Any

from .errors import SafetyError, ValidationError
from .fomod import validate_fomod
from .safety import require_approval, require_within, validate_filename
from .util import iter_files, sha256_file

BLOCKED_SUFFIXES = {".log", ".dmp", ".tmp", ".bak", ".pdb", ".ilk", ".obj", ".pyc"}
BLOCKED_NAMES = {"meta.ini", "desktop.ini", "thumbs.db", ".ds_store"}
FIXED_TIME = (2026, 7, 23, 0, 0, 0)
TEXT_SCAN_SUFFIXES = {".txt", ".md", ".ini", ".json", ".toml", ".yaml", ".yml", ".xml", ".psc", ".pas", ".py", ".ps1", ".bat"}
PRIVATE_WINDOWS_PATH = re.compile(r"[A-Za-z]:\\Users\\(?!YOU(?:\\|$)|<)", re.I)


def validate_release_tree(root: Path) -> dict[str, Any]:
    root = root.resolve(strict=True)
    if not root.is_dir():
        raise ValidationError("Release tree must be a directory")
    errors = []
    warnings = []
    files = []
    casefolded: dict[str, str] = {}
    for path in root.rglob("*"):
        rel = path.relative_to(root).as_posix()
        if path.is_symlink():
            errors.append(f"symlink is not allowed: {rel}")
            continue
        key = rel.casefold()
        if key in casefolded and casefolded[key] != rel:
            errors.append(f"case-colliding paths: {casefolded[key]} and {rel}")
        casefolded[key] = rel
        if path.is_file():
            if path.name.casefold() in BLOCKED_NAMES or path.suffix.casefold() in BLOCKED_SUFFIXES:
                errors.append(f"development or manager artifact: {rel}")
            if any(part in {"__pycache__", ".git", ".venv", "venv", "build", "dist"} for part in path.relative_to(root).parts):
                errors.append(f"development directory in release: {rel}")
            if path.suffix.casefold() in TEXT_SCAN_SUFFIXES and path.stat().st_size <= 16 * 1024 * 1024:
                text = path.read_text(encoding="utf-8-sig", errors="replace")
                if PRIVATE_WINDOWS_PATH.search(text):
                    errors.append(f"private Windows user path in release text: {rel}")
            files.append({"path": rel, "size": path.stat().st_size, "sha256": sha256_file(path)})
    fomod_dirs = [path for path in root.iterdir() if path.is_dir() and path.name.casefold() == "fomod"]
    fomod_report = None
    if fomod_dirs:
        fomod_report = validate_fomod(root, strict_coverage=True)
        errors.extend(f"FOMOD: {item}" for item in fomod_report["errors"])
        warnings.extend(f"FOMOD: {item}" for item in fomod_report["warnings"])
    return {
        "result": "PASS" if not errors else "FAIL",
        "root": str(root),
        "file_count": len(files),
        "errors": sorted(set(errors)),
        "warnings": warnings,
        "files": files,
        "fomod": fomod_report,
        "target": "private",
        "share_ready": False,
        "publication_status": "PRIVATE_ONLY",
        "evidence": "Release-tree hygiene only. This result is not Nexus/publication approval and must not be called share-ready. Gameplay and runtime behavior are not validated.",
    }


def build_release(root: Path, output: Path, workspace_root: Path, *, approved: bool) -> dict[str, Any]:
    require_approval(approved, "release archive creation")
    report = validate_release_tree(root)
    if report["result"] != "PASS":
        raise ValidationError(f"Release tree failed validation: {report['errors']}")
    output = require_within(output, workspace_root)
    validate_filename(output.name, {".zip"})
    if output.exists():
        raise SafetyError(f"Refusing to overwrite release archive: {output}")
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_name(f".{output.name}.forge.tmp")
    with zipfile.ZipFile(temporary, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in iter_files(root):
            rel = path.relative_to(root).as_posix()
            info = zipfile.ZipInfo(rel, FIXED_TIME)
            info.create_system = 3
            info.external_attr = ((0o100755 if os.access(path, os.X_OK) else 0o100644) & 0xFFFF) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, path.read_bytes(), compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
    with zipfile.ZipFile(temporary) as archive:
        bad = archive.testzip()
        if bad:
            temporary.unlink(missing_ok=True)
            raise ValidationError(f"ZIP CRC failure: {bad}")
    os.replace(temporary, output)
    return {
        "result": "PASS",
        "target": "private",
        "share_ready": False,
        "publication_status": "PRIVATE_ONLY",
        "output": str(output),
        "size": output.stat().st_size,
        "sha256": sha256_file(output),
        "file_count": report["file_count"],
        "evidence": "Deterministic private archive only. Use target=nexus with a validated publication plan for share-ready status.",
    }
